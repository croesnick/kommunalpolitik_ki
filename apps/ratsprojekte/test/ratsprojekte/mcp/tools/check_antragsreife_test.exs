defmodule Ratsprojekte.MCP.Tools.CheckAntragsreifeTest do
  @moduledoc """
  Hard Gates der Antragsreife (Tickets #22, #37).

  `freibad/1` liefert ein Projekt, bei dem alle übrigen Hard Gates passieren
  (Quelle mit URL+Abrufdatum, erfüllter Strang) — nur die Feld-Gates
  (`adressat`, `beschlussvorschlag`, `value_proposition`, `success_metrics`)
  schlagen fehl, bis sie gesetzt sind.
  """

  use Ratsprojekte.DataCase, async: false

  alias Anubis.Server.Frame
  alias Ratsprojekte.MCP.Tools.CheckAntragsreife

  import Ratsprojekte.Fixtures

  @beschlossene_attrs %{
    beschlussvorschlag:
      "Der Stadtrat beschließt, an allen Freibad-Kassen Kartenzahlung einzuführen.",
    adressat: "Stadtrat",
    value_proposition:
      "Bargeldanteil im Bäderbetrieb sinkt, Wartezeiten an den Kassen werden messbar kürzer.",
    success_metrics:
      "Bargeldanteil im Bäderbetrieb unter 30 Prozent, Wartezeit pro Gast unter drei Minuten."
  }

  describe "hard gates" do
    test "VP+SM gates fail without the fields (#37)" do
      projekt = freibad()

      assert {"fail", _} = gate(projekt.slug, :value_proposition_vorhanden)
      assert {"fail", _} = gate(projekt.slug, :success_metrics_vorhanden)
      assert body(projekt.slug)["empfehlung"] == "nicht_antragsreif"
    end

    test "VP+SM gates pass with both fields set (#37)" do
      projekt = freibad(@beschlossene_attrs)

      assert {"pass", _} = gate(projekt.slug, :value_proposition_vorhanden)
      assert {"pass", _} = gate(projekt.slug, :success_metrics_vorhanden)
    end

    test "alle hard gates pass → empfehlung antragsreif" do
      projekt = freibad(@beschlossene_attrs)

      assert Enum.all?(body(projekt.slug)["hard_gates"], &(&1["status"] == "pass"))
      assert body(projekt.slug)["empfehlung"] == "antragsreif"
    end

    test "adressat + beschlussvorschlag gates (#22)" do
      projekt = freibad()

      assert {"fail", _} = gate(projekt.slug, :adressat_gesetzt)
      assert {"fail", _} = gate(projekt.slug, :beschlussvorschlag_konkret)

      gesetzt =
        freibad(
          Map.merge(Map.take(@beschlossene_attrs, [:adressat, :beschlussvorschlag]), %{
            slug: "freibad-kartenzahlung-test-gesetzt"
          })
        )

      assert {"pass", _} = gate(gesetzt.slug, :adressat_gesetzt)
      assert {"pass", _} = gate(gesetzt.slug, :beschlussvorschlag_konkret)
    end

    test "stufe fraktion ändert die Kriterien nicht, nur die Empfehlung" do
      projekt = freibad()

      report = body(projekt.slug, "fraktion")

      assert Enum.map(report["hard_gates"], & &1["kriterium"]) ==
               Enum.map(body(projekt.slug)["hard_gates"], & &1["kriterium"])

      assert report["empfehlung"] == "nicht_fraktionsreif"
    end

    test "unknown projekt slug returns an error" do
      assert {:reply, response, _frame} =
               CheckAntragsreife.execute(%{slug: "gibt-es-nicht", stufe: "stadtrat"}, Frame.new())

      assert response.isError
    end
  end

  # --- Helpers ---

  defp gate(slug, kriterium) do
    entry =
      Enum.find(body(slug)["hard_gates"], &(&1["kriterium"] == Atom.to_string(kriterium))) ||
        flunk("Hard Gate #{kriterium} fehlt im Report")

    {entry["status"], entry["detail"]}
  end

  defp body(slug, stufe \\ "stadtrat") do
    assert {:reply, response, _frame} =
             CheckAntragsreife.execute(%{slug: slug, stufe: stufe}, Frame.new())

    refute response.isError

    [%{"type" => "text", "text" => json}] = response.content
    Jason.decode!(json)
  end
end
