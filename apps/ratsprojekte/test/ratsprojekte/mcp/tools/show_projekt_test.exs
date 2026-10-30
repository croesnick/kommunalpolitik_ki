defmodule Ratsprojekte.MCP.Tools.ShowProjektTest do
  @moduledoc """
  Lesendes MCP-Tool `show_projekt` gibt die strukturierte RIS-Referenz der
  Sitzungs-Quellen aus (Ticket #32) — das ist die Schnittstelle, über die
  der ratsprojekte-Connector (#277) Beschlussnachverfolgung bestreitet.
  """

  use Ratsprojekte.DataCase, async: false

  alias Anubis.Server.Frame
  alias Ratsprojekte.MCP.Tools.ShowProjekt

  import Ratsprojekte.Fixtures

  describe "execute/2" do
    test "outputs ris reference fields of quellen (#32)" do
      projekt = freibad()

      quelle(projekt, %{
        typ: :sitzung,
        titel: "Stadtratssitzung 05.11.2026",
        url: "https://example.org/ris/sitzung/4711",
        ris_sitzung_id: "4711",
        ris_top: "7",
        beschluss_nr: "2026/034"
      })

      assert {:reply, response, _frame} = ShowProjekt.execute(%{slug: projekt.slug}, Frame.new())
      refute response.isError

      [%{"type" => "text", "text" => json}] = response.content
      body = Jason.decode!(json)

      sitzung =
        Enum.find(body["projekt_quellen"], &(&1["ris_sitzung_id"] == "4711")) ||
          flunk("Sitzungs-Quelle mit RIS-Referenz fehlt in der Ausgabe")

      assert sitzung["ris_top"] == "7"
      assert sitzung["beschluss_nr"] == "2026/034"

      # Quellen ohne Referenz führen die Felder als nil mit.
      ohne =
        Enum.find(body["projekt_quellen"], &(&1["ris_sitzung_id"] == nil)) ||
          flunk("Quelle ohne RIS-Referenz fehlt in der Ausgabe")

      assert ohne["ris_top"] == nil
      assert ohne["beschluss_nr"] == nil
    end

    test "outputs the antragsreife fields of the projekt (#22, #37)" do
      projekt =
        freibad(%{
          beschlussvorschlag:
            "Der Stadtrat beschließt, an allen Freibad-Kassen Kartenzahlung einzuführen.",
          adressat: "Stadtrat",
          value_proposition:
            "Bargeldanteil im Bäderbetrieb sinkt, Wartezeiten an den Kassen werden messbar kürzer.",
          success_metrics:
            "Bargeldanteil im Bäderbetrieb unter 30 Prozent, Wartezeit pro Gast unter drei Minuten."
        })

      assert {:reply, response, _frame} = ShowProjekt.execute(%{slug: projekt.slug}, Frame.new())
      refute response.isError

      [%{"type" => "text", "text" => json}] = response.content
      body = Jason.decode!(json)

      assert body["beschlussvorschlag"] =~ "Kartenzahlung"
      assert body["adressat"] == "Stadtrat"
      assert body["value_proposition"] =~ "Bargeldanteil"
      assert body["success_metrics"] =~ "30 Prozent"
    end

    test "unknown projekt slug returns an error" do
      assert {:reply, response, _frame} =
               ShowProjekt.execute(%{slug: "gibt-es-nicht"}, Frame.new())

      assert response.isError
    end
  end
end
