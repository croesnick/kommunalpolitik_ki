defmodule KomkiPolicy.RemediesTest do
  use ExUnit.Case, async: true

  alias KomkiPolicy.{Calculus, Context, JSON, Registry, Remedies}

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)

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

  defp test_ctx(bindings, object_labels, env_id) do
    reg = registry()

    %{
      rule: :admit,
      object_labels: object_labels,
      checked: bindings,
      rho: Calculus.actual_recipients(reg, env_id),
      object_ref: "obj-x@v1",
      call_hash: nil
    }
  end

  defp finding(code), do: %{"code" => code, "binding" => nil, "condition" => nil}

  defp transition_type(remedy), do: Enum.map(remedy["transitions"], &Map.fetch!(&1, "type"))

  test "Ordnungs-Invariante: aktionsfreigabe steht nie an erster Stelle (admit)" do
    reg = registry()
    ctx = test_ctx(["buergerfall-4711@1"], [], "lokale-fallverarbeitung@1")

    [remedy] =
      Remedies.catalog(reg, ctx, :admit, [
        %{
          "code" => "binding_condition_false",
          "binding" => "buergerfall-4711@1",
          "condition" => "input_in_approved_case_scope"
        }
      ])

    assert transition_type(remedy) == ["fakt_nachreichen", "neuer_raum"]
  end

  test "Ordnungs-Invariante (emit call-GO): fakt < neuer_raum < aktionsfreigabe" do
    reg = registry()

    ctx = %{
      test_ctx(["buergerfall-4711@1"], [], "lokale-fallverarbeitung@1")
      | rule: :emit,
        call_hash: "beef"
    }

    [remedy] =
      Remedies.catalog(reg, ctx, :emit, [
        %{"code" => "basis_right_false", "binding" => nil, "condition" => "has_operation_right"}
      ])

    assert transition_type(remedy) == ["fakt_nachreichen", "neuer_raum", "aktionsfreigabe"]
  end

  test "Anwendbarkeitstabelle admit: GO-Einträge erscheinen nie (bewusste Lücke § 9)" do
    reg = registry()
    ctx = test_ctx([], [], "lokale-fallverarbeitung@1")

    codes = [
      "object_quarantine",
      "workspace_invalid",
      "basis_right_false",
      "audit_path_not_ready",
      "label_not_included",
      "recipient_not_allowed",
      "missing_operation_rule",
      "binding_condition_false"
    ]

    Enum.each(codes, fn code ->
      [remedy] = Remedies.catalog(reg, ctx, :admit, [finding(code)])

      # admit-Fälle führen keinen call-GO-Eintrag (bewusste Lücke, § 8/§ 9);
      # object_quarantine ist die Ausnahme mit objekt-scope-GO (Erstklassifikation).
      case code do
        "object_quarantine" ->
          assert [%{"type" => "aktionsfreigabe", "scope" => "object"}] =
                   remedy["transitions"]

        _ ->
          types = transition_type(remedy)
          refute "aktionsfreigabe" in types, code
          assert types != [], code
      end
    end)
  end

  test "Anwendbarkeitstabelle emit: aktionsfreigabe (call) nur bei den fünf weichen Blockern" do
    reg = registry()

    ctx = %{
      test_ctx(["buergerfall-4711@1"], [], "lokale-fallverarbeitung@1")
      | rule: :emit,
        call_hash: "beef"
    }

    call_go_codes = [
      "basis_right_false",
      "audit_path_not_ready",
      "recipient_not_allowed",
      "missing_operation_rule",
      "binding_condition_false"
    ]

    Enum.each(call_go_codes, fn code ->
      [remedy] = Remedies.catalog(reg, ctx, :emit, [finding(code)])
      types = transition_type(remedy)

      assert "aktionsfreigabe" in types, code
      assert hd(types) != "aktionsfreigabe", code
    end)

    [ws_remedy] = Remedies.catalog(reg, ctx, :emit, [finding("workspace_invalid")])
    refute "aktionsfreigabe" in transition_type(ws_remedy)
  end

  test "indeterminate (missing_fact/recipients_unproven): nie aktionsfreigabe, auch bei emit" do
    reg = registry()

    ctx = %{
      test_ctx(["buergerfall-4711@1"], [], "lokale-fallverarbeitung@1")
      | rule: :emit,
        call_hash: "beef"
    }

    Enum.each(["missing_fact", "recipients_unproven"], fn code ->
      evidence = %{"code" => code, "fact" => "environment_observers_complete", "binding" => nil}
      [remedy] = Remedies.catalog(reg, ctx, :emit, [evidence])
      types = transition_type(remedy)

      refute "aktionsfreigabe" in types

      assert types == ["fakt_nachreichen", "neuer_raum"]
    end)
  end

  test "object_quarantine -> nur objekt-scope-GO (Erstklassifikation R.2.5)" do
    reg = registry()
    ctx = test_ctx([], [], "lokale-fallverarbeitung@1")

    [remedy] = Remedies.catalog(reg, ctx, :admit, [finding("object_quarantine")])

    assert [%{"type" => "aktionsfreigabe", "scope" => "object", "object" => "obj-x@v1"}] =
             remedy["transitions"]
  end

  test "registrierte Transformation erscheint nur, wenn input ⊆ λ(x) und output ⊆ B_W" do
    reg = registry()

    ctx =
      test_ctx(["buergerfall-4711@1"], ["lizenz-namensnennung@1"], "lokale-fallverarbeitung@1")

    [remedy] = Remedies.catalog(reg, ctx, :admit, [finding("label_not_included")])

    assert Enum.any?(remedy["transitions"], fn t ->
             Map.fetch!(t, "type") == "registrierte_transformation" and
               Map.fetch!(t, "transformation") == "presse-auszug@1"
           end)

    # input [lizenz] ⊄ λ([]): Transformation erscheint hier NICHT
    ctx2 = test_ctx(["buergerfall-4711@1"], [], "lokale-fallverarbeitung@1")
    [remedy2] = Remedies.catalog(reg, ctx2, :admit, [finding("label_not_included")])

    refute Enum.any?(remedy2["transitions"], &(&1["type"] == "registrierte_transformation"))
  end

  test "Freigabe-Zweig: je Release-Blocker ein call-GO mit NEU berechnetem korrektem call_hash" do
    reg = registry()

    ctx = %{
      rule: :release,
      object_labels: [],
      checked: ["buergerfall-4711@1"],
      rho: ["nutzende-person"],
      object_ref: "obj-a@v1",
      call_hash: "korrekt-berechnet"
    }

    [remedy] = Remedies.catalog(reg, ctx, :release, [finding("release_call_mismatch")])

    assert [
             %{
               "type" => "aktionsfreigabe",
               "scope" => "call",
               "call_hash" => "korrekt-berechnet"
             }
           ] = remedy["transitions"]

    # workspace_invalid bleibt unüberbrückbar: neuer_raum, required_bindings [] (emit-Regeltyp)
    [ws_remedy] = Remedies.catalog(reg, ctx, :release, [finding("workspace_invalid")])

    assert [%{"type" => "neuer_raum", "required_bindings" => []}] = ws_remedy["transitions"]
  end

  test "Der Katalog erzeugt keine Autorität: `remedies` wird von keiner Eingabe akzeptiert (§ 2.8)" do
    intent =
      Map.put(
        elem(JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/intent.json"))), 1),
        "remedies",
        []
      )

    assert {:error, %{code: :unknown_field}} = Context.validate_intent(intent)
  end

  test "fakt_nachreichen ohne benennbares Feld (condition: null, Literal-Regel) entfällt (Befund 10)" do
    reg = registry()
    ctx = test_ctx(["buergerfall-4711@1"], [], "lokale-fallverarbeitung@1")

    finding = %{
      "code" => "binding_condition_false",
      "binding" => "buergerfall-4711@1",
      "condition" => nil
    }

    [remedy] = Remedies.catalog(reg, ctx, :admit, [finding])

    assert [%{"type" => "neuer_raum"}] = remedy["transitions"]
    refute Enum.any?(remedy["transitions"], &(&1["type"] == "fakt_nachreichen"))

    # emit: gleiche Regel, aber call-GO bleibt — Katalog nicht leer
    emit_ctx = %{ctx | rule: :emit, call_hash: "korrekt-berechnet"}
    [emit_remedy] = Remedies.catalog(reg, emit_ctx, :emit, [finding])

    assert Enum.map(emit_remedy["transitions"], &Map.fetch!(&1, "type")) == [
             "neuer_raum",
             "aktionsfreigabe"
           ]

    refute Enum.any?(emit_remedy["transitions"], &(&1["type"] == "fakt_nachreichen"))
  end
end
