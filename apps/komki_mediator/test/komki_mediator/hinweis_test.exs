defmodule KomkiMediator.HinweisTest do
  # Ticket #417: which denial is "nothing transmitted". Only store without a
  # GO way qualifies; emit and transfer keep their form from before (#354).
  use ExUnit.Case, async: true

  alias KomkiMediator.Hinweis

  defp remedy(code, transitions), do: %{"code" => code, "transitions" => transitions}

  @room %{"type" => "neuer_raum", "required_bindings" => [], "required_recipients" => ["x"]}
  @call_go %{"type" => "aktionsfreigabe", "scope" => "call", "call_hash" => "abc"}

  test "store, Empfänger außerhalb, kein GO im Katalog: nicht übertragen" do
    remedies = [
      remedy("recipient_not_allowed", [@room]),
      remedy("missing_operation_rule", [@room])
    ]

    assert Hinweis.not_transmitted?("store", remedies)
  end

  test "store ohne Empfängerbefund: bisherige Form" do
    refute Hinweis.not_transmitted?("store", [remedy("missing_operation_rule", [@room, @call_go])])
  end

  # Neither path reaches workspace_invalid through ConnectorGate (the
  # mediator's snapshot is always valid), so the engine-shaped remedies are
  # given here: no call GO, recipient_not_allowed among the findings.
  for rule <- ["emit", "transfer"] do
    test "#{rule} mit recipient_not_allowed und workspace_invalid: bisherige Form" do
      remedies = [
        remedy("workspace_invalid", [@room]),
        remedy("recipient_not_allowed", [@room])
      ]

      refute Hinweis.not_transmitted?(unquote(rule), remedies)
    end
  end

  test "admit (Gate 2): bisherige Form" do
    refute Hinweis.not_transmitted?("admit", [remedy("recipient_not_allowed", [@room])])
  end
end
