defmodule Ratsprojekte.Schemas.ProjektTest do
  @moduledoc """
  Changeset-Validierung der Antragsreife-Felder (Ticket #37).

  Value Proposition und Success Metrics sind optionale Spalten — gesetzt
  werden sie per Proposal + GO —, aber wenn sie gesetzt sind, müssen sie
  konkret sein: Mindestlänge und kein reines „Digitalisierung von X“.
  """

  use Ratsprojekte.DataCase, async: false

  alias Ratsprojekte.Schemas.Projekt

  @valid_vp "Bargeldanteil im Bäderbetrieb sinkt, Wartezeiten an den Kassen werden messbar kürzer."
  @valid_sm "Bargeldanteil im Bäderbetrieb unter 30 Prozent, Wartezeit pro Gast unter drei Minuten."

  describe "value_proposition" do
    test "accepts a concrete value proposition" do
      changeset = changeset_with(%{value_proposition: @valid_vp})
      assert changeset.valid?
    end

    test "rejects a value proposition of 20 characters or fewer" do
      changeset = changeset_with(%{value_proposition: "Zu kurz als VP."})
      assert "should be at least 21 character(s)" in errors_on(changeset).value_proposition
    end

    test "rejects a pure 'Digitalisierung von X' value proposition despite length" do
      changeset =
        changeset_with(%{
          value_proposition: "Digitalisierung von Freibad-Kassen und Getränkeautomaten."
        })

      assert "darf kein reines „Digitalisierung von X“ sein — es muss das konkrete Problem nennen" in errors_on(
               changeset
             ).value_proposition
    end

    test "accepts a value proposition that starts with Digitalisierung but names a concrete change" do
      changeset =
        changeset_with(%{
          value_proposition:
            "Digitalisierung der Kassen reduziert die Wartezeit pro Gast um 40 Prozent."
        })

      assert changeset.valid?
    end

    test "stays optional: nil passes the changeset" do
      changeset = changeset_with(%{value_proposition: nil})
      assert changeset.valid?
    end
  end

  describe "success_metrics" do
    test "accepts a measurable success metric" do
      changeset = changeset_with(%{success_metrics: @valid_sm})
      assert changeset.valid?
    end

    test "rejects success metrics of 10 characters or fewer" do
      changeset = changeset_with(%{success_metrics: "Zu kurz."})
      assert "should be at least 11 character(s)" in errors_on(changeset).success_metrics
    end

    test "stays optional: nil passes the changeset" do
      changeset = changeset_with(%{success_metrics: nil})
      assert changeset.valid?
    end
  end

  defp changeset_with(attrs) do
    Projekt.changeset(%Projekt{}, Map.merge(base_attrs(), attrs))
  end

  defp base_attrs do
    %{titel: "Freibad: Kartenzahlung einführen", slug: "freibad-kartenzahlung-test"}
  end
end
