defmodule KomkiMediator.RemedyTest do
  use ExUnit.Case, async: true

  alias KomkiMediator.{Gamma, Remedy, TestHelpers}
  alias KomkiPolicy.JSON

  setup do
    base = TestHelpers.provisioned_base()
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))
    %{gamma: gamma}
  end

  test "deny-Blocker binding_condition_false ergibt provide_fact auf dem Feld", %{gamma: gamma} do
    decision = %{
      "decision" => "deny",
      "blockers" => [
        %{
          "code" => "binding_condition_false",
          "binding" => "doc-vertraulich@1",
          "condition" => "purpose"
        }
      ]
    }

    remedies = Remedy.from_decision(decision, gamma)

    assert remedies == [
             %{
               "type" => "provide_fact",
               "clears" => "purpose",
               "relaxation_authorities" => []
             }
           ]
  end

  test "indeterminate missing_fact ergibt provide_fact auf dem Fakt und faehrt die Relaxationsbefugnis hoch",
       %{
         gamma: gamma
       } do
    decision = %{
      "decision" => "indeterminate",
      "missing_evidence" => [
        %{
          "code" => "missing_fact",
          "fact" => "vertraulich_freigabe",
          "binding" => "doc-pending-freigabe@1"
        }
      ]
    }

    remedies = Remedy.from_decision(decision, gamma)

    assert remedies == [
             %{
               "type" => "provide_fact",
               "clears" => "vertraulich_freigabe",
               "relaxation_authorities" => ["nutzende-person"]
             }
           ]
  end

  test "relaxation_authorities stammen aus dem rohen Registry-Term", %{gamma: gamma} do
    assert gamma.term["bindings"]["doc-pending-freigabe@1"]["relaxation_authorities"] == [
             "nutzende-person"
           ]

    # Die kompilierte Form trgt sie bewusst nicht.
    refute Map.has_key?(
             gamma.compiled.bindings["doc-pending-freigabe@1"],
             "relaxation_authorities"
           )
  end

  test "Ordnung ist deterministisch: byteweise nach {type, clears}", %{gamma: gamma} do
    decision = %{
      "decision" => "deny",
      "blockers" => [
        %{"code" => "workspace_invalid", "binding" => nil},
        %{"code" => "missing_operation_rule", "binding" => "b2"}
      ]
    }

    remedies = Remedy.from_decision(decision, gamma)
    expected = Enum.sort_by(remedies, &{&1["type"], &1["clears"]})

    assert remedies == expected
    assert Enum.map(remedies, & &1["type"]) == ["register_operation_rule", "repair_workspace"]
  end

  test "unbekannte Eintraege filtern sich heraus, ohne zu crashen", %{gamma: gamma} do
    decision = %{
      "decision" => "deny",
      "blockers" => [%{"code" => "irgendetwas_fremdes"}]
    }

    assert Remedy.from_decision(decision, gamma) == []
  end

  test "recipients_unproven ergibt provide_recipient_proof", %{gamma: gamma} do
    decision = %{
      "decision" => "indeterminate",
      "missing_evidence" => [
        %{
          "code" => "recipients_unproven",
          "fact" => "environment_observers_complete",
          "binding" => nil
        }
      ]
    }

    remedies = Remedy.from_decision(decision, gamma)

    assert Enum.map(remedies, &{&1["type"], &1["clears"]}) == [
             {"provide_recipient_proof", "environment_observers_complete"}
           ]

    assert JSON.canonical(remedies) == JSON.canonical(remedies)
  end
end
