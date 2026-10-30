defmodule KomkiPolicy.DeriveTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KomkiPolicy.{Calculus, Derive, JSON, Registry}

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)

  # ======================================================================
  # Fixtures-Kontext
  # ======================================================================

  defp fixture(path) do
    @fixtures_dir
    |> Path.join(path)
    |> File.read!()
    |> JSON.parse()
    |> elem(1)
  end

  defp registry do
    {:ok, compiled} = Registry.compile(fixture("registry.json"))
    compiled
  end

  defp case_dirs do
    Enum.sort(Path.wildcard(Path.join(@fixtures_dir, "case_*")))
  end

  # ======================================================================
  # Derive-Orakel: alle case_*/expected_decision.json
  # ======================================================================

  describe "Derive-Orakel (case_*-Verzeichnisse)" do
    test "jede erwartete Decision stimmt in der kanonischen §6-Form (proof key je Fall gepint) ueberein" do
      reg = registry()

      Enum.each(case_dirs(), fn dir ->
        name = Path.basename(dir)
        {:ok, snapshot} = JSON.parse(File.read!(Path.join(dir, "snapshot.json")))
        {:ok, intent} = JSON.parse(File.read!(Path.join(dir, "intent.json")))

        result =
          if File.exists?(Path.join(dir, "release.json")) do
            {:ok, rel} = JSON.parse(File.read!(Path.join(dir, "release.json")))
            {:ok, std} = JSON.parse(File.read!(Path.join(dir, "stand.json")))

            Derive.decide_with_release(reg, snapshot, intent, rel, std)
          else
            Derive.decide(reg, snapshot, intent)
          end

        case result do
          {:ok, decision} ->
            oracle_path = Path.join(dir, "expected_decision.json")
            assert File.exists?(oracle_path), "#{name} liefert eine Decision ohne Decision-orakel"
            {:ok, oracle} = JSON.parse(File.read!(oracle_path))
            assert_maps_equal_ignoring_proof(decision, oracle, name)

          {:unsupported, info} ->
            oracle_path = Path.join(dir, "expected_result.json")
            assert File.exists?(oracle_path), "#{name} ist unsupported ohne expected_result"
            {:ok, oracle} = JSON.parse(File.read!(oracle_path))
            assert info == oracle, name
        end
      end)
    end
  end

  defp assert_maps_equal_ignoring_proof(computed, oracle, name) do
    left = Map.delete(computed, "proof")
    right = Map.delete(oracle, "proof")

    assert JSON.canonical(left) == JSON.canonical(right), "decision mismatch: #{name}"
  end

  describe "Beweiskopplung case_permit (§ 8, RFC A.7)" do
    test "derive-Proof ist byte-identisch mit case_permit/proof_valid.json" do
      reg = registry()

      {:ok, snapshot} =
        JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/snapshot.json")))

      {:ok, intent} = JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/intent.json")))
      {:ok, decision} = Derive.decide(reg, snapshot, intent)

      oracle = fixture("case_permit/proof_valid.json")
      refute is_nil(decision["proof"])

      assert JSON.canonical(decision["proof"]) == JSON.canonical(oracle)
    end

    test "deny/indeterminate-Entscheidungen tragen niemals einen Beweis" do
      reg = registry()

      decision_dirs =
        Enum.filter(case_dirs(), &File.exists?(Path.join(&1, "expected_decision.json")))

      Enum.each(decision_dirs, fn dir ->
        oracle =
          fixture(Path.relative_to(Path.join(dir, "expected_decision.json"), @fixtures_dir))

        if oracle["decision"] != "permit" do
          {:ok, snapshot} = JSON.parse(File.read!(Path.join(dir, "snapshot.json")))
          {:ok, intent} = JSON.parse(File.read!(Path.join(dir, "intent.json")))
          {:ok, decision} = Derive.decide(reg, snapshot, intent)
          assert is_nil(decision["proof"]), Path.basename(dir)
        end
      end)
    end
  end

  describe "Validierungs-Orakel (negative Eingaben, keine Decisions)" do
    test "snapshot_unknown_binding_ref.json -> unknown_binding_reference" do
      reg = registry()
      snapshot = fixture("invalid/snapshot_unknown_binding_ref.json")
      intent = fixture("case_permit/intent.json")

      assert {:error, %{code: :unknown_binding_reference, path: path}} =
               Derive.decide(reg, snapshot, intent)

      assert String.contains?(path, "$.workspace.bindings")
    end

    test "intent_version_mismatch.json -> intent_snapshot_mismatch (minimal kohärenter Kontext)" do
      reg = registry()
      snapshot = fixture("case_permit/snapshot.json")
      intent = fixture("invalid/intent_version_mismatch.json")

      assert {:error, %{code: :intent_snapshot_mismatch}} = Derive.decide(reg, snapshot, intent)
    end

    test "Strukturfehler sind Eingabefehler und keine Decisions" do
      reg = registry()

      case Derive.decide(reg, %{"schema" => "platzhalter"}, fixture("case_permit/intent.json")) do
        {:error, %{code: _}} -> assert true
        other -> flunk("expected an input error, got: #{inspect(other)}")
      end
    end
  end

  describe "Determinismus (§ 4.4)" do
    test "zwei Aufrufe mit identischen Eingaben erzeugen byte-identische kanonische Ausgaben" do
      reg = registry()

      Enum.each(case_dirs(), fn dir ->
        {:ok, snapshot} = JSON.parse(File.read!(Path.join(dir, "snapshot.json")))
        {:ok, intent} = JSON.parse(File.read!(Path.join(dir, "intent.json")))
        first = Derive.decide(reg, snapshot, intent)
        second = Derive.decide(reg, snapshot, intent)

        assert first == second, Path.basename(dir)

        assert canonical_result(first) == canonical_result(second), Path.basename(dir)
      end)
    end

    defp canonical_result({:ok, decision}), do: JSON.canonical(decision)
    defp canonical_result({:unsupported, info}), do: JSON.canonical(info)
    defp canonical_result({:error, error}), do: JSON.canonical(error)
  end

  # ======================================================================
  # emit (§ 4.5): Eingabepflichten, Zuordnung, Opazität
  # ======================================================================

  describe "emit-Eingabepflichten (§ 4.5)" do
    test "Snapshot ohne output_content_digest -> Eingabefehler emit_digest_missing (Exit 2, keine Decision)" do
      reg = registry()
      snapshot = fixture("invalid/emit_digest_missing_snapshot.json")
      intent = fixture("invalid/emit_digest_missing_intent.json")

      assert {:error, %{code: :emit_digest_missing}} = Derive.decide(reg, snapshot, intent)
    end

    test "quarantine-Objekt bei emit -> Eingabefehler (kein object_quarantine auf emit)" do
      reg = registry()

      snapshot =
        put_in(
          fixture("case_emit_permit/snapshot.json"),
          ["object", "classification"],
          "quarantine"
        )

      intent = fixture("case_emit_permit/intent.json")

      assert {:error, %{code: :emit_object_not_classified}} = Derive.decide(reg, snapshot, intent)
    end
  end

  describe "emit-Zuordnung λ(y) := B_W (R.5.5)" do
    test "Permit trägt assigned_label = B_W und content_digest-Echo (§ 2.4, § 4.5)" do
      reg = registry()

      {:ok, decision} =
        Derive.decide(
          reg,
          fixture("case_emit_permit/snapshot.json"),
          fixture("case_emit_permit/intent.json")
        )

      assert decision["decision"] == "permit"
      assert decision["assigned_label"] == ["buergerfall-4711@1"]

      digest =
        fixture("case_emit_permit/snapshot.json")["facts"]["output_content_digest"]["value"]

      assert decision["content_digest"] == digest
    end

    test "opaque case: zwei Snapshots, identisch bis auf den Digest — beide permit, Entscheidungen identisch modulo content_digest" do
      reg = registry()
      dir = Path.join(@fixtures_dir, "case_emit_opaque")

      {:ok, snapshot_a} = JSON.parse(File.read!(Path.join(dir, "snapshot.json")))
      {:ok, snapshot_b} = JSON.parse(File.read!(Path.join(dir, "snapshot_alt.json")))
      {:ok, intent} = JSON.parse(File.read!(Path.join(dir, "intent.json")))

      {:ok, d_a} = Derive.decide(reg, snapshot_a, intent)
      {:ok, d_b} = Derive.decide(reg, snapshot_b, intent)

      assert d_a["decision"] == "permit"
      assert d_b["decision"] == "permit"
      assert d_a["content_digest"] != d_b["content_digest"]

      # Entscheidungen identisch modulo content_digest und snapshot_ref
      # (die Snapshot-Id ist im Snapshot-Datensatz, unvermeidlich verschieden)
      strip = fn d ->
        d
        |> Map.delete("content_digest")
        |> Map.delete("snapshot_ref")
        |> Map.delete("proof")
      end

      assert Map.get(strip.(d_a), "assigned_label") == ["buergerfall-4711@1"]
      assert JSON.canonical(strip.(d_a)) == JSON.canonical(strip.(d_b))
    end

    property "keine Eingabe kann assigned_label beeinflussen: Digest-Variation ändert die Zuordnung nicht" do
      check all(
              digest <- StreamData.string(~c"0123456789abcdef", min_length: 64, max_length: 64),
              initial_seed: 20_261_014,
              max_runs: 50
            ) do
        reg = registry()

        snapshot =
          put_in(
            fixture("case_emit_permit/snapshot.json"),
            ["facts", "output_content_digest"],
            %{"value" => digest, "source" => "test", "source_kind" => "test"}
          )

        intent = fixture("case_emit_permit/intent.json")
        {:ok, decision} = Derive.decide(reg, snapshot, intent)

        assert decision["assigned_label"] == ["buergerfall-4711@1"]
      end
    end
  end

  describe "required_premises Regel-Dispatch (§ 5 Schritt 3 Basis)" do
    test "admit: neun feste Prämissen in Ordnung; emit: sieben (+ label_assignment, ohne not_quarantine/label_inclusion)" do
      admit = Derive.required_premises("admit")
      emit = Derive.required_premises("emit")

      assert Enum.count(admit) == 9
      assert Enum.count(emit) == 7
      assert "label_assignment" in emit
      refute "label_assignment" in admit
      refute "not_quarantine" in emit
      refute "has_object_access_right" in emit
      refute "label_inclusion" in emit
    end
  end

  # ======================================================================
  # Gate-2-Remediation: Basisfakten-Typ-Pin (§ 4.2)
  # ======================================================================

  defp type_pinned_registry do
    {:ok, term} = JSON.parse(File.read!(Path.join(@fixtures_dir, "registry.json")))

    {:ok, compiled} =
      Registry.compile(put_in(term, ["fact_fields", "environment_observers_complete"], "integer"))

    compiled
  end

  defp with_fact(snapshot_path, name, value) do
    {:ok, snapshot} = JSON.parse(File.read!(Path.join(@fixtures_dir, snapshot_path)))

    fact = %{"value" => value, "source" => "test-verwaltung", "source_kind" => "test"}
    put_in(snapshot, ["facts", name], fact)
  end

  describe "Basisfakten-Typ-Pin (§ 4.2, A1)" do
    test "Registry-Redeclaration als integer wird nicht uebernommen (value 0 -> invalid_fact_value)" do
      reg = type_pinned_registry()
      snapshot = with_fact("case_permit/snapshot.json", "environment_observers_complete", 0)
      intent = fixture("case_permit/intent.json")

      assert {:error,
              %{code: :invalid_fact_value, path: "$.facts.environment_observers_complete.value"}} =
               Derive.decide(reg, snapshot, intent)
    end

    test "Basisfakt ohne Redeclaration bleibt boolean (value 0 -> invalid_fact_value)" do
      reg = registry()
      snapshot = with_fact("case_permit/snapshot.json", "has_operation_right", 0)
      intent = fixture("case_permit/intent.json")

      assert {:error, %{code: :invalid_fact_value, path: "$.facts.has_operation_right.value"}} =
               Derive.decide(reg, snapshot, intent)
    end
  end

  # ======================================================================
  # Gate-2-Remediation: Nicht-Listen-Guard (A2)
  # ======================================================================

  describe "Nicht-Listen-Guard fuer Referenzlisten (A2)" do
    test "fehlender workspace.bindings-Schluessel ist strukturierter Fehler, kein Crash" do
      reg = registry()

      {:ok, snapshot} =
        JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/snapshot.json")))

      broken = Map.delete(snapshot["workspace"], "bindings")
      snapshot = put_in(snapshot, ["workspace"], broken)
      intent = fixture("case_permit/intent.json")

      assert {:error, %{code: :invalid_reference_list, path: "$.workspace.bindings"}} =
               Derive.decide(reg, snapshot, intent)
    end

    test "bindings: 42 / bindings: null / fehlende labels sind je strukturierte Fehler" do
      reg = registry()
      intent = fixture("case_permit/intent.json")

      sw42 = with_bindings(42)
      assert {:error, %{code: :invalid_reference_list}} = Derive.decide(reg, sw42, intent)

      swnull = with_bindings(nil)
      assert {:error, %{code: :invalid_reference_list}} = Derive.decide(reg, swnull, intent)

      {:ok, snapshot_no_labels} =
        JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/snapshot.json")))

      snapshot_no_labels =
        put_in(snapshot_no_labels, ["object"], Map.delete(snapshot_no_labels["object"], "labels"))

      assert {:error, %{code: :invalid_reference_list, path: "$.object.labels"}} =
               Derive.decide(reg, snapshot_no_labels, intent)
    end
  end

  defp with_bindings(value) do
    {:ok, snapshot} =
      JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/snapshot.json")))

    put_in(snapshot, ["workspace", "bindings"], value)
  end

  # ======================================================================
  # MIN-5: ungepinnte Fehlercodes (konstruierte Minimal-Inputs)
  # ======================================================================

  describe "ungepinnte Eingabefehlercodes (MIN-5)" do
    test "unsortierte workspace.bindings -> unsorted_references" do
      reg = registry()
      snapshot = with_bindings(["lizenz-namensnennung@1", "buergerfall-4711@1"])
      intent = fixture("case_deny_licensed/intent.json")

      assert {:error, %{code: :unsorted_references, path: "$.workspace.bindings"}} =
               Derive.decide(reg, snapshot, intent)
    end

    test "fremde registry_ref -> registry_ref_mismatch" do
      reg = registry()

      {:ok, snapshot} =
        JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/snapshot.json")))

      snapshot = put_in(snapshot, ["registry_ref"], "anderes-reg")
      intent = fixture("case_permit/intent.json")

      assert {:error, %{code: :registry_ref_mismatch, path: "$.registry_ref"}} =
               Derive.decide(reg, snapshot, intent)
    end

    test "unbekannte Umgebung -> unknown_environment" do
      reg = registry()

      {:ok, snapshot} =
        JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/snapshot.json")))

      snapshot = put_in(snapshot, ["workspace", "environment"], "phantom-umgebung@1")
      intent = fixture("case_permit/intent.json")

      assert {:error, %{code: :unknown_environment, path: "$.workspace.environment"}} =
               Derive.decide(reg, snapshot, intent)
    end
  end

  # ======================================================================
  # C11: Kalkuel-Extraktion (R_G, r_G, l-Subset)
  # ======================================================================

  describe "KomkiPolicy.Calculus" do
    test "allowed_recipients: Durchschnitt der readers; leeres Prueflabel = ganzer Beobachterraum" do
      reg = registry()

      assert ["lokale-fallverarbeitung", "nutzende-person"] =
               Calculus.allowed_recipients(reg, ["buergerfall-4711@1"])

      assert ["eigene-rz-analyse", "lokale-fallverarbeitung", "nutzende-person", "webdienst-x"] =
               Calculus.allowed_recipients(reg, [])
    end

    test "actual_recipients und labels_subset?" do
      reg = registry()

      assert ["nutzende-person", "webdienst-x"] =
               Calculus.actual_recipients(reg, "recherche-webdienst@1")

      assert Calculus.labels_subset?(["lizenz-namensnennung@1"], [
               "buergerfall-4711@1",
               "lizenz-namensnennung@1"
             ])

      refute Calculus.labels_subset?(["buergerfall-4711@1"], [])
    end
  end

  # ======================================================================
  # C12: Required-Set-Konstante (§ 4.3 <-> § 5 Schritt 3)
  # ======================================================================

  describe "required_premises (C12)" do
    test "Reihenfolge entspricht exakt dem Referenz-Baum case_permit/proof_valid.json" do
      proof = fixture("case_permit/proof_valid.json")
      premises = Map.fetch!(proof, "premises")

      oracle_names = premises |> Enum.map(&Map.fetch!(&1, "name")) |> Enum.uniq()

      assert Derive.required_premises() == oracle_names
    end
  end

  describe "store (§ 4.7)" do
    test "ein GO für emit passt nicht auf store desselben Objekts (Operation im call_hash)" do
      dir = Path.join(@fixtures_dir, "case_release_store_permit")
      {:ok, snapshot} = JSON.parse(File.read!(Path.join(dir, "snapshot.json")))
      {:ok, intent} = JSON.parse(File.read!(Path.join(dir, "intent.json")))
      {:ok, stand} = JSON.parse(File.read!(Path.join(dir, "stand.json")))

      {:ok, emit_go} =
        JSON.parse(File.read!(Path.join(@fixtures_dir, "case_release_permit/release.json")))

      assert {:ok, %{"decision" => "deny", "blockers" => [%{"code" => "release_call_mismatch"}]}} =
               Derive.decide_with_release(
                 registry(),
                 snapshot,
                 intent,
                 Map.put(emit_go, "operation", "store"),
                 stand
               )
    end

    test "ohne store-Regel: deny mit call-GO im Katalog, nach neuer_raum" do
      dir = Path.join(@fixtures_dir, "case_store_no_rule")
      {:ok, snapshot} = JSON.parse(File.read!(Path.join(dir, "snapshot.json")))
      {:ok, intent} = JSON.parse(File.read!(Path.join(dir, "intent.json")))

      assert {:ok, %{"decision" => "deny", "remedies" => [%{"transitions" => transitions}]}} =
               Derive.decide(registry(), snapshot, intent)

      assert Enum.map(transitions, & &1["type"]) == ["neuer_raum", "aktionsfreigabe"]
    end

    test "transfer bleibt unsupported" do
      assert length(Derive.required_premises("store")) == 7
      assert %{"result" => "unsupported"} = Derive.unsupported_info("transfer")
    end
  end
end
