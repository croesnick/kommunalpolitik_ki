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
        titel: "Klima-Konzept Buchloe",
        slug: "klima-konzept-buchloe",
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
      assert proposal.payload["slug"] == "klima-konzept-buchloe"
      assert proposal.payload["titel"] == "Klima-Konzept Buchloe"
      assert proposal.status == :pending

      # Kein echtes Projekt wurde angelegt.
      refute Repo.exists?(from(p in Projekt, where: p.slug == "klima-konzept-buchloe"))
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
      projekt = bahnhofstr()
      %{projekt: projekt, slug: projekt.slug}
    end

    test "returns clear error before GO and does not insert a proposal", %{slug: slug} do
      params = [
        titel: "Duplikat Bahnhofstraße",
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

  defp parse_json_body(response) do
    [%{"type" => "text", "text" => json}] = response.content
    Jason.decode!(json)
  end

  defp error_text(response) do
    [%{"type" => "text", "text" => text}] = response.content
    text
  end
end
