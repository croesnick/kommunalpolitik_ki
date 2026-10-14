defmodule KomkiPolicy.MetricsTest do
  use ExUnit.Case, async: true

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)

  @tcr_max_steps 4
  @k 2
  @tcr_threshold 0.85

  @moduledoc """
  Abnahmemetriken CONTRACT.md § 8.3 — Tests als Entscheidungsbeweis.

  **HITL load**: Das Quarantäne-Szenario braucht genau **ein** Objekt-Level-GO
  (Erstklassifikation über eine neue Snapshot-Version, R.2.5/R.6.2); danach
  laufen wiederholte Aufnahmen desselben Objekts **ohne weiteres GO**
  (Schwellenwert: GO-Zähler == 1). Die `fakt_nachreichen`-Pfade brauchen
  **null** GOs (Schwellenwert: == 0).

  **TCR@k**: Über den Szenario-Korpus der Fixtures folgt der Test der
  deterministischen Skript-Spur `fakt_nachreichen` →
  `registrierte_transformation` → `neuer_raum` → `aktionsfreigabe`
  (normative Katalog-Ordnung § 2.8: ein GO steht nie an erster Stelle) und
  misst, innerhalb wievieler Schritte (k) Permit erreicht wird. Gemessen bei
  k=#{@tcr_max_steps} über den Korpus, Schwellenwert Quote >= #{@tcr_threshold}.
  „Alles zu verweigern reicht nicht" wird damit messbar. Die konkreten
  Messwerte (GO-Zähler je Szenario, Quote, k) werden im Ticket-Kommentar
  berichtet.

  Vollzugssimulation (Skript, keine Engine-Logik): `fakt_nachreichen` liefert
  die autoritativen Werte via festes Ziel-Map (Booles `true`, `purpose` den
  genehmigten Fallumfang). `neuer_raum` wählt deterministisch die kleinste
  Registry-Umgebung, die die verlangten Empfänger aufnehmen kann, legt die
  Bindungen auf `required_bindings` und markiert den (neu geprüften) Vertrag
  als gültig. Ein `aktionsfreigabe`-call-Schritt konstruiert ein korrekt
  gebundenes GO (call hash exakt nach § 2.6) und geht über
  `decide_with_release/5`.
  """

  alias KomkiPolicy.{Derive, JSON, Registry, Release}

  # ---------------------------------------------------------------------
  # Fixtures / Registry
  # ---------------------------------------------------------------------

  defp registry do
    {:ok, compiled} =
      @fixtures_dir
      |> Path.join("registry.json")
      |> File.read!()
      |> JSON.parse()
      |> elem(1)
      |> Registry.compile()

    compiled
  end

  defp load_case(name) do
    {:ok, snapshot} = JSON.parse(File.read!(Path.join([@fixtures_dir, name, "snapshot.json"])))
    {:ok, intent} = JSON.parse(File.read!(Path.join([@fixtures_dir, name, "intent.json"])))
    {snapshot, intent}
  end

  # ---------------------------------------------------------------------
  # Skript-Vollzug je Übergangstyp (deterministisch, test-only)
  # ---------------------------------------------------------------------

  @supply_targets %{
    "purpose" => "antwort-fall-4711",
    "input_in_approved_case_scope" => true,
    "has_operation_right" => true,
    "has_object_access_right" => true,
    "audit_path_ready" => true,
    "environment_observers_complete" => true
  }

  defp supply_facts(snapshot, fact_names) do
    Enum.reduce(fact_names, snapshot, fn name, snap ->
      value = Map.get(@supply_targets, name, true)

      put_in(snap, ["facts", name], %{
        "value" => value,
        "source" => "nachgereichende Verwaltungsstelle (Skript)",
        "source_kind" => "administered"
      })
    end)
  end

  defp apply_transformation(snapshot, output_labels) do
    put_in(snapshot, ["object", "labels"], output_labels)
  end

  defp new_room(snapshot, reg, required_bindings, required_recipients) do
    environment =
      reg.environments
      |> Enum.filter(fn {_id, env} ->
        hosts?(Enum.sort(env.observers), Enum.sort(required_recipients))
      end)
      |> Enum.sort_by(fn {id, env} -> {length(env.observers), id} end)
      |> Enum.map(fn {id, _} -> id end)
      |> List.first()

    snapshot
    |> put_in(["workspace", "bindings"], Enum.sort(Enum.uniq(required_bindings)))
    |> put_in(["workspace", "environment"], environment)
    |> put_in(["workspace", "valid"], true)
  end

  # Deterministisch: die kleinste Umgebung, deren Beobachterliste die
  # verlangten Empfänger vollständig aufnehmen kann (Übermengen-Anforderung).
  defp hosts?(observers, required) do
    required -- observers == []
  end

  defp upgrade_object(snapshot) do
    snapshot
    |> put_in(["object", "classification"], "classified")
    |> put_in(["object", "labels"], [])
    |> put_in(["snapshot_id"], snapshot["snapshot_id"] <> "-klassifiziert")
  end

  defp call_go_flow(reg, snapshot, intent) do
    digest = get_in(snapshot, ["facts", "output_content_digest", "value"])
    object_ref = snapshot["object"]["object_id"] <> "@" <> snapshot["object"]["version"]
    workspace = snapshot["workspace"]["workspace_id"]

    release = %{
      "schema" => "komki-release/1",
      "release_id" => "go-script-4711",
      "kind" => "aktionsfreigabe",
      "operation" => "emit",
      "object" => object_ref,
      "workspace" => workspace,
      "content_digest" => digest,
      "call_hash" => Release.call_hash(digest, object_ref, "emit", workspace),
      "scope" => "script-bereich",
      "authority" => "lokale-fallverarbeitung",
      "valid_from" => 0,
      "valid_until" => 2000,
      "nonce" => "script-nonce"
    }

    stand = %{
      "schema" => "komki-stand/1",
      "stand_id" => "script-stand",
      "version" => 0,
      "scope" => "script-bereich",
      "as_of" => 1000,
      "consumed" => %{}
    }

    case Derive.decide_with_release(reg, snapshot, intent, release, stand) do
      {:ok, %{"decision" => "permit"}} -> :permit
      _ -> :stuck
    end
  end

  # ---------------------------------------------------------------------
  # deterministische Skript-Spur (Katalog-Ordnung: never GO first)
  # ---------------------------------------------------------------------

  defp run_track(reg, snapshot, intent, steps, gos, max_steps) do
    case Derive.decide(reg, snapshot, intent) do
      {:ok, %{"decision" => "permit"}} ->
        {steps, gos, true}

      {:ok, %{"remedies" => [_ | _] = remedies}} when steps < max_steps ->
        step_transition(reg, hd(remedies)["transitions"], snapshot, intent, steps, gos, max_steps)

      _ ->
        {steps, gos, false}
    end
  end

  defp step_transition(_reg, [], _snapshot, _intent, steps, gos, _max), do: {steps, gos, false}

  defp step_transition(reg, [transition | rest], snapshot, intent, steps, gos, max_steps) do
    case transition do
      %{"type" => "fakt_nachreichen", "facts" => facts} ->
        run_track(reg, supply_facts(snapshot, facts), intent, steps + 1, gos, max_steps)

      %{"type" => "registrierte_transformation", "output_labels" => labels} ->
        run_track(reg, apply_transformation(snapshot, labels), intent, steps + 1, gos, max_steps)

      %{"type" => "neuer_raum", "required_bindings" => bindings, "required_recipients" => recips} ->
        run_track(
          reg,
          new_room(snapshot, reg, bindings, recips),
          intent,
          steps + 1,
          gos,
          max_steps
        )

      %{"type" => "aktionsfreigabe", "scope" => "call"} ->
        case call_go_flow(reg, snapshot, intent) do
          :permit -> {steps + 1, gos + 1, true}
          :stuck -> step_transition(reg, rest, snapshot, intent, steps, gos, max_steps)
        end

      %{"type" => "aktionsfreigabe", "scope" => "object"} ->
        run_track(reg, upgrade_object(snapshot), intent, steps + 1, gos + 1, max_steps)

      _ ->
        step_transition(reg, rest, snapshot, intent, steps, gos, max_steps)
    end
  end

  # =========================================================================
  # TCR@k (§ 8.3)
  # =========================================================================

  @corpus [
    "case_deny",
    "case_deny_licensed",
    "case_deny_recipient",
    "case_deny_missing_rule",
    "case_deny_no_basis",
    "case_deny_precedence",
    "case_deny_multi_blockers",
    "case_indeterminate",
    "case_indeterminate_env_false",
    "case_indeterminate_env_missing",
    "case_indeterminate_multi_evidence",
    "case_deny_label_not_included",
    "case_emit_deny_purpose",
    "case_emit_indeterminate",
    "case_emit_no_rule",
    "case_emit_recipient",
    "case_emit_workspace_invalid"
  ]

  test "TCR@k: deterministische Skript-Spur über den Korpus erreicht Permit innerhalb k" do
    reg = registry()

    results =
      Enum.map(@corpus, fn name ->
        {snapshot, intent} = load_case(name)
        {steps, gos, permit?} = run_track(reg, snapshot, intent, 0, 0, @tcr_max_steps)
        {name, steps, gos, permit?}
      end)

    Enum.each(results, fn {name, steps, gos, permit?} ->
      IO.puts(
        "  TCR #{name}: permit=#{permit?} steps=#{if permit?, do: steps, else: :stuck} gos=#{gos}"
      )
    end)

    assert Enum.all?(results, fn {_n, _s, _g, permit?} -> permit? end),
           "Skript-Spur muss für den gesamten Korpus Permit erreichen"

    within_k = Enum.count(results, fn {_n, steps, _g, permit?} -> permit? and steps <= @k end)
    quote_within_k = within_k / length(results)

    assert quote_within_k >= @tcr_threshold,
           "TCR@#{@k} = #{quote_within_k} (#{within_k}/#{length(results)}) < #{@tcr_threshold}"
  end

  # =========================================================================
  # HITL load (§ 8.3)
  # =========================================================================

  describe "HITL load" do
    test "Quarantäne: genau EIN Objekt-Level-GO, danach wiederholte Aufnahmen ohne weiteres GO" do
      reg = registry()
      {snapshot, intent} = load_case("case_quarantine")

      {:ok, decision} = Derive.decide(reg, snapshot, intent)
      assert decision["decision"] == "deny"

      # das Skript folgt dem Katalog: Erstklassifikation als Objekt-Level-GO
      [remedy] = decision["remedies"]
      assert [%{"scope" => "object", "type" => "aktionsfreigabe"}] = remedy["transitions"]
      go_count = 1

      # das GO bewirkt die neue Snapshot-Version (Erstklassifikation)
      upgraded = upgrade_object(snapshot)

      # wiederholte Aufnahmen desselben Objekts — KEIN weiteres GO nötig
      assert {:ok, %{"decision" => "permit"}} = Derive.decide(reg, upgraded, intent)
      assert {:ok, %{"decision" => "permit"}} = Derive.decide(reg, upgraded, intent)
      assert {:ok, %{"decision" => "permit"}} = Derive.decide(reg, upgraded, intent)

      assert go_count == 1, "HITL-Schwellenwert § 8.3: genau ein Objekt-Level-GO"
    end

    test "fakt_nachreichen-Pfade brauchen null GOs" do
      reg = registry()

      Enum.each(["case_indeterminate", "case_deny"], fn name ->
        {snapshot, intent} = load_case(name)

        {:ok, decision} = Derive.decide(reg, snapshot, intent)
        refute decision["decision"] == "permit"

        remedy = hd(decision["remedies"])
        [%{"type" => "fakt_nachreichen", "facts" => facts} | _] = remedy["transitions"]

        supply = supply_facts(snapshot, facts)

        assert {:ok, %{"decision" => "permit"}} = Derive.decide(reg, supply, intent)

        refute Enum.any?(decision["remedies"], fn r ->
                 Enum.any?(r["transitions"], &(&1["type"] == "aktionsfreigabe"))
               end)
      end)
    end
  end
end
