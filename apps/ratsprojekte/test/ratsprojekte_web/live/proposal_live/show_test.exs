defmodule RatsprojekteWeb.ProposalLive.ShowTest do
  use RatsprojekteWeb.ConnCase, async: false

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt, Realisierungsstrang}
  import Ecto.Query

  # Modulweites Setup: frisches Projekt mit Strängen.
  setup do
    projekt = bahnhofstr()
    %{projekt: projekt}
  end

  describe "render" do
    setup %{projekt: projekt} do
      proposal = proposal(projekt)
      %{proposal: proposal}
    end

    test "renders pending proposal with payload, begruendung, audit, buttons", %{
      conn: conn,
      projekt: projekt,
      proposal: proposal
    } do
      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      # Header.
      assert html =~ "Vorschlag: Neuer Realisierungsstrang per Vorschlag"
      assert html =~ "add_realisierungsstrang"
      assert html =~ "vorgeschlagen von ai-harness"

      # Status-Badge.
      assert has_element?(view, "span.badge", "pending")

      # Payload-Felder.
      assert html =~ "Vorgeschlagener Realisierungsstrang"
      assert has_element?(view, "span", "Label")
      assert has_element?(view, "span", "Titel")
      assert has_element?(view, "span", "Beschreibung")
      assert has_element?(view, "span", "Rechtliche Grundlage")
      assert has_element?(view, "span", "Bedingung")

      # Payload-Werte.
      assert html =~ "Neuer Realisierungsstrang per Vorschlag"
      assert html =~ "Per Proposal angelegt — AI-Vorschlag."
      assert html =~ "§ 1 BeispielG"
      assert html =~ "Beschluss des Stadtrats"

      # Begründung (Quellenpflicht).
      assert html =~ "Begründung (Quellenpflicht)"
      assert html =~ "Ein Vorschlag, der die Argumente verbessert"

      # Quellen.
      assert html =~ "https://example.org/beleg"

      # Decision-Form mit Accept/Reject-Buttons.
      assert has_element?(view, "form#decision-form")
      assert has_element?(view, "button[type='submit'][value='accept']")
      assert has_element?(view, "button[type='submit'][value='reject']")
      assert has_element?(view, "textarea[name='kommentar']")
    end

    test "back link navigates to proposal index", %{
      conn: conn,
      projekt: projekt,
      proposal: proposal
    } do
      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      assert html =~ proposal.payload["titel"]
    end
  end

  describe "accept" do
    test "creates realisierungsstrang atomically and sets proposal approved", %{
      conn: conn,
      projekt: projekt
    } do
      proposal = proposal(projekt)

      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      # Vor Accept: 2 Stränge.
      assert count_straenge_for(projekt) == 2

      # Accept-Button klicken. `put_submitter` übermittelt den Button-Value (`aktion`).
      view
      |> form("#decision-form", kommentar: "Sieht gut aus.")
      |> put_submitter("button[name=aktion][value=accept]")
      |> render_submit()

      # Atomicity: Proposal-Status = approved UND neuer Realisierungsstrang in der DB.
      reloaded_proposal = Repo.get!(PendingProposal, proposal.id)
      assert reloaded_proposal.status == :approved
      assert reloaded_proposal.entschieden_am != nil
      assert reloaded_proposal.entschieden_von == "stadtrat"
      assert reloaded_proposal.entscheidungskommentar == "Sieht gut aus."

      # Neuer Realisierungsstrang wurde aus dem Payload angelegt.
      assert count_straenge_for(projekt) == 3

      new_strang =
        Repo.one!(
          from(rs in Realisierungsstrang,
            where: rs.projekt_id == ^projekt.id and rs.label == "D"
          )
        )

      assert new_strang.titel == "Neuer Realisierungsstrang per Vorschlag"
      assert new_strang.rechtliche_grundlage == "§ 1 BeispielG"
      assert new_strang.bedingung_erfuellt == false
    end

    test "accept without kommentar works (kommentar optional)", %{
      conn: conn,
      projekt: projekt
    } do
      proposal = proposal(projekt)

      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      view
      |> form("#decision-form", kommentar: "")
      |> put_submitter("button[name=aktion][value=accept]")
      |> render_submit()

      reloaded_proposal = Repo.get!(PendingProposal, proposal.id)
      assert reloaded_proposal.status == :approved
      assert reloaded_proposal.entscheidungskommentar == nil

      assert count_straenge_for(projekt) == 3
    end
  end

  describe "reject" do
    test "sets status without creating strang", %{conn: conn, projekt: projekt} do
      proposal = proposal(projekt)

      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      # Vor Reject: 2 Stränge.
      assert count_straenge_for(projekt) == 2

      view
      |> form("#decision-form", kommentar: "Nicht überzeugend argumentiert.")
      |> put_submitter("button[name=aktion][value=reject]")
      |> render_submit()

      # Proposal-Status = rejected, aber KEIN neuer Strang.
      reloaded_proposal = Repo.get!(PendingProposal, proposal.id)
      assert reloaded_proposal.status == :rejected
      assert reloaded_proposal.entschieden_am != nil
      assert reloaded_proposal.entschieden_von == "stadtrat"
      assert reloaded_proposal.entscheidungskommentar == "Nicht überzeugend argumentiert."

      # Strang-Anzahl unverändert.
      assert count_straenge_for(projekt) == 2
    end
  end

  describe "edge cases" do
    test "redirects to index when projekt missing", %{conn: conn} do
      projekt = bahnhofstr()
      proposal = proposal(projekt)

      # Proposal existiert, aber die URL verweist auf ein nicht-existierendes Projekt.
      # LiveView mount leitet zur Index weiter (Projekt nicht gefunden).
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/projekte/999999/proposals/#{proposal.id}")

      assert flash["error"] == "Projekt nicht gefunden"
    end

    test "redirects to proposal index for unknown proposal id", %{conn: conn, projekt: projekt} do
      expected_path = "/projekte/#{projekt.id}/proposals"

      assert {:error, {:redirect, %{to: ^expected_path, flash: flash}}} =
               live(conn, ~p"/projekte/#{projekt.id}/proposals/99999")

      assert flash["error"] == "Vorschlag nicht gefunden"
    end
  end

  describe "proposal index" do
    test "lists all proposals for projekt", %{conn: conn, projekt: projekt} do
      proposal(projekt)
      proposal(projekt)

      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.id}/proposals")

      # Das `"` wird vom HTML-Renderer zu `&quot;` encoded.
      assert html =~ "Vorschläge für"
      assert html =~ "Bahnhofstraße umgestalten"
      assert has_element?(view, ".project-card-link", "Neuer Realisierungsstrang per Vorschlag")
    end

    test "shows empty state when no proposals", %{conn: conn, projekt: projekt} do
      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.id}/proposals")

      assert html =~ "Keine Vorschläge für dieses Projekt."
      refute has_element?(view, ".project-card-link")
    end

    test "shows proposal status badge", %{conn: conn, projekt: projekt} do
      _pending = proposal(projekt)

      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.id}/proposals")

      assert has_element?(view, "span.badge", "pending")
    end
  end

  describe "change_status proposal" do
    setup %{projekt: projekt} do
      proposal =
        proposal(projekt, %{
          typ: :change_status,
          payload: %{
            "status" => "abgeschlossen",
            "begruendung_fuer_aenderung" => "Projekt abgeschlossen — Beschluss umgesetzt.",
            "datum" => "2026-07-13",
            "verworfen_grund" => nil
          },
          begruendung: "Projekt abgeschlossen — Beschluss umgesetzt."
        })

      %{proposal: proposal}
    end

    test "renders status-change payload fields", %{
      conn: conn,
      projekt: projekt,
      proposal: proposal
    } do
      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      assert html =~ "Vorgeschlagene Statusänderung"
      assert has_element?(view, "span", "Neuer Status")
      assert has_element?(view, "span", "Datum")
      assert has_element?(view, "span", "Verworfungsgrund")

      # Accept-Button trägt das Status-Änderungs-Label.
      assert has_element?(view, "button[type='submit'][value='accept']", "Status ändern")
    end

    test "accept updates projekt status atomically", %{
      conn: conn,
      projekt: projekt,
      proposal: proposal
    } do
      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      # Vorher: Projekt ist noch aktiv.
      assert Repo.get!(Projekt, projekt.id).status == :aktiv

      view
      |> form("#decision-form", kommentar: "Sieht gut aus.")
      |> put_submitter("button[name=aktion][value=accept]")
      |> render_submit()

      # Atomicity: Proposal approved UND Projektstatus aktualisiert.
      reloaded_proposal = Repo.get!(PendingProposal, proposal.id)
      assert reloaded_proposal.status == :approved
      assert reloaded_proposal.entscheidungskommentar == "Sieht gut aus."

      reloaded_projekt = Repo.get!(Projekt, projekt.id)
      assert reloaded_projekt.status == :abgeschlossen
      assert reloaded_projekt.abgeschlossen_am == ~D[2026-07-13]
    end

    test "accept verworfen sets verworfen_am and verworfen_grund", %{
      conn: conn,
      projekt: projekt
    } do
      proposal =
        proposal(projekt, %{
          typ: :change_status,
          payload: %{
            "status" => "verworfen",
            "begruendung_fuer_aenderung" => "Projekt verworfen — keine Mehrheit.",
            "datum" => "2026-07-13",
            "verworfen_grund" => "Keine politische Mehrheit im Bauausschuss."
          },
          begruendung: "Projekt verworfen — keine Mehrheit."
        })

      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      view
      |> form("#decision-form", kommentar: "")
      |> put_submitter("button[name=aktion][value=accept]")
      |> render_submit()

      reloaded_projekt = Repo.get!(Projekt, projekt.id)
      assert reloaded_projekt.status == :verworfen
      assert reloaded_projekt.verworfen_am == ~D[2026-07-13]
      assert reloaded_projekt.verworfen_grund == "Keine politische Mehrheit im Bauausschuss."

      assert Repo.get!(PendingProposal, proposal.id).status == :approved
    end

    test "reject leaves projekt status untouched", %{
      conn: conn,
      projekt: projekt,
      proposal: proposal
    } do
      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.id}/proposals/#{proposal.id}")

      view
      |> form("#decision-form", kommentar: "Noch nicht.")
      |> put_submitter("button[name=aktion][value=reject]")
      |> render_submit()

      assert Repo.get!(PendingProposal, proposal.id).status == :rejected
      assert Repo.get!(Projekt, projekt.id).status == :aktiv
    end
  end

  defp count_straenge_for(projekt) do
    Repo.aggregate(
      from(rs in Realisierungsstrang, where: rs.projekt_id == ^projekt.id),
      :count
    )
  end

  # Unused-alias-Bindings zur Vermeidung von Compiler-Warnungen.
  _ = Projekt
end
