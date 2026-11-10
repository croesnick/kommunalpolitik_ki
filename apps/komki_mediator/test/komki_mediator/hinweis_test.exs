defmodule KomkiMediator.HinweisTest do
  # Ticket #417: which note a denial carries for the model. Only store gets
  # :not_transmitted; emit and transfer keep the note from before (#354).
  use ExUnit.Case, async: true

  alias KomkiMediator.Hinweis

  defp remedy(code, transitions), do: %{"code" => code, "transitions" => transitions}

  @room %{"type" => "neuer_raum", "required_bindings" => [], "required_recipients" => ["x"]}
  @call_go %{"type" => "aktionsfreigabe", "scope" => "call", "call_hash" => "abc"}

  test "store, Empfänger außerhalb, kein GO im Katalog: nur „nicht übertragen“" do
    remedies = [
      remedy("recipient_not_allowed", [@room]),
      remedy("missing_operation_rule", [@room])
    ]

    assert Hinweis.for_denial("store", remedies) == Hinweis.text(:not_transmitted)
  end

  test "store ohne Empfängerbefund: der bisherige Hinweis" do
    remedies = [remedy("missing_operation_rule", [@room, @call_go])]

    assert Hinweis.for_denial("store", remedies) == Hinweis.text(:deny)
  end

  # Neither path reaches workspace_invalid through ConnectorGate (the
  # mediator's snapshot is always valid), so the engine-shaped remedies are
  # given here: no call GO, recipient_not_allowed among the findings.
  for rule <- ["emit", "transfer"] do
    test "#{rule} mit recipient_not_allowed und workspace_invalid: wie bisher" do
      remedies = [
        remedy("workspace_invalid", [@room]),
        remedy("recipient_not_allowed", [@room])
      ]

      assert Hinweis.for_denial(unquote(rule), remedies) == Hinweis.text(:deny)
    end
  end

  test "admit (Gate 2): wie bisher" do
    assert Hinweis.for_denial("admit", [remedy("recipient_not_allowed", [@room])]) ==
             Hinweis.text(:deny)
  end
end
