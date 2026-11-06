defmodule Ratsprojekte.MCP.Tools.ProposeProjektTest do
  use Ratsprojekte.DataCase, async: false

  alias Anubis.Server.Frame
  alias Ratsprojekte.MCP.Tools.ProposeProjekt
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}

  import Ecto.Query
  import Ratsprojekte.Fixtures

  describe "execute/2 with new slug" do
    test "creates a pending add_projekt proposal" do
      params = [
        titel: "Klima-Konzept Beispielstadt",
        slug: "klima-konzept-beispielstadt",
        beschreibung: "Ein kommunales Klimaschutz-Konzept.",
        prioritaet: "hoch",
        begruendung: "Klimaschutz ist kommunalpolitisch dringend geboten.",
        quellen: "https://example.org/klima"
      ]

      assert {:reply, response, _frame} = ProposeProjekt.execute(params, Frame.new())
      refute response.isError

      body = parse_json_body(response)
      assert body["typ"] == "add_projekt"
      assert body["status"] == "pending"
      assert body["hinweis"] =~ "GO-Prinzip"
      assert body["review_url"] =~ "/proposals/"

      proposal = Repo.get!(PendingProposal, body["id"])
      assert proposal.typ == :add_projekt
      assert proposal.payload["slug"] == "klima-konzept-beispielstadt"
      assert proposal.payload["titel"] == "Klima-Konzept Beispielstadt"
      assert proposal.status == :pending

      # Kein echtes Projekt wurde angelegt.
      refute Repo.exists?(from(p in Projekt, where: p.slug == "klima-konzept-beispielstadt"))
    end

    test "works without explicit slug (slug nil skips collision check)" do
      params = [
        titel: "Ohne Slug Projekt",
        begruendung: "Ein Projekt ohne expliziten Slug-Vorschlag."
      ]

      assert {:reply, response, _frame} = ProposeProjekt.execute(params, Frame.new())
      refute response.isError
    end
  end

  describe "execute/2 with existing slug" do
    setup do
      projekt = marktplatz()
      %{projekt: projekt, slug: projekt.slug}
    end

    test "returns clear error before GO and does not insert a proposal", %{slug: slug} do
      params = [
        titel: "Duplikat Marktplatz",
        slug: slug,
        beschreibung: "Sollte abgelehnt werden wegen Slug-Kollision.",
        prioritaet: "mittel",
        begruendung: "Dieses Proposal muss wegen existierendem Slug abgelehnt werden."
      ]

      assert {:reply, response, _frame} = ProposeProjekt.execute(params, Frame.new())

      assert response.isError
      assert error_text(response) =~ slug
      assert error_text(response) =~ "propose_projekt_update"
      assert error_text(response) =~ "propose_realisierungsstrang"

      # Es wird KEIN PendingProposal eingetragen — die Früh-Erkennung greift
      # vor dem Insert.
      count =
        Repo.aggregate(
          from(pp in PendingProposal, where: pp.typ == :add_projekt),
          :count
        )

      assert count == 0
    end

    test "different slug still succeeds after a kolliding call failed", %{slug: slug} do
      kollision_params = [
        titel: "Kollision",
        slug: slug,
        begruendung: "Sollte sofort fehlschlagen, nicht erst beim Accept."
      ]

      assert {:reply, response, _frame} = ProposeProjekt.execute(kollision_params, Frame.new())
      assert response.isError

      ok_params = [
        titel: "Neues Projekt",
        slug: "neues-einmaliges-projekt",
        begruendung: "Funktioniert, weil der Slug noch nicht existiert."
      ]

      assert {:reply, response2, _frame} = ProposeProjekt.execute(ok_params, Frame.new())
      refute response2.isError
    end
  end

  describe "execute/2 with value proposition and success metrics (#37)" do
    alias Ratsprojekte.MCP.Tools.DecideProposal

    @vp "Bargeldanteil im Bäderbetrieb sinkt, Wartezeiten an den Kassen werden messbar kürzer."
    @sm "Bargeldanteil im Bäderbetrieb unter 30 Prozent, Wartezeit pro Gast unter drei Minuten."

    test "proposal carries VP+SM; GO creates the projekt with both fields" do
      params = [
        titel: "Freibad Kartenzahlung",
        slug: "freibad-kartenzahlung-via-proposal",
        value_proposition: @vp,
        success_metrics: @sm,
        begruendung: "Bargeldloser Betrieb reduziert Ausfallzeiten an den Kassen."
      ]

      assert {:reply, response, _frame} = ProposeProjekt.execute(params, Frame.new())
      refute response.isError

      body = parse_json_body(response)
      proposal = Repo.get!(PendingProposal, body["id"])
      assert proposal.payload["value_proposition"] == @vp
      assert proposal.payload["success_metrics"] == @sm

      # Noch kein Projekt — erst das GO legt es an.
      refute Repo.exists?(
               from(p in Projekt, where: p.slug == "freibad-kartenzahlung-via-proposal")
             )

      assert {:reply, go_response, _frame} =
               DecideProposal.execute(
                 [proposal_id: proposal.id, aktion: "accept", kommentar: "GO im Chat"],
                 Frame.new()
               )

      refute go_response.isError

      projekt =
        Repo.one!(from(p in Projekt, where: p.slug == "freibad-kartenzahlung-via-proposal"))

      assert projekt.value_proposition == @vp
      assert projekt.success_metrics == @sm
    end

    test "GO on a pure 'Digitalisierung von X' VP succeeds — the gate warns, no changeset veto" do
      alias Ratsprojekte.MCP.Tools.CheckAntragsreife

      params = [
        titel: "Freibad Kartenzahlung",
        slug: "freibad-kartenzahlung-rein",
        value_proposition: "Digitalisierung von Freibad-Kassen und Getränkeautomaten.",
        success_metrics: @sm,
        begruendung: "Bargeldloser Betrieb reduziert Ausfallzeiten an den Kassen."
      ]

      assert {:reply, response, _frame} = ProposeProjekt.execute(params, Frame.new())
      refute response.isError

      body = parse_json_body(response)
      proposal = Repo.get!(PendingProposal, body["id"])

      # Das GO des Stadtrats gilt — die reine Form ist Gate-Warnung (Soft-Gate-
      # Terrain des AI-Harness), kein Changeset-Veto am GO.
      assert {:reply, go_response, _frame} =
               DecideProposal.execute(
                 [proposal_id: proposal.id, aktion: "accept", kommentar: "GO im Chat"],
                 Frame.new()
               )

      refute go_response.isError

      assert Repo.get!(PendingProposal, proposal.id).status == :approved

      assert {:reply, check_response, _frame} =
               CheckAntragsreife.execute(
                 %{slug: "freibad-kartenzahlung-rein", stufe: "stadtrat"},
                 Frame.new()
               )

      refute check_response.isError

      [%{"type" => "text", "text" => check_json}] = check_response.content

      vp_gate =
        Enum.find(
          Jason.decode!(check_json)["hard_gates"],
          &(&1["kriterium"] == "value_proposition_vorhanden")
        )

      assert vp_gate["status"] == "warn"
    end
  end

  defp parse_json_body(response) do
    [%{"type" => "text", "text" => json}] = response.content
    Jason.decode!(json)
  end

  defp error_text(response) do
    [%{"type" => "text", "text" => text}] = response.content
    text
  end
end
