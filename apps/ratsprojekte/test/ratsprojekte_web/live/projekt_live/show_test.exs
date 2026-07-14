defmodule RatsprojekteWeb.ProjektLive.ShowTest do
  use RatsprojekteWeb.ConnCase, async: false

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  import Ecto.Query

  describe "render" do
    setup do
      projekt = bahnhofstr()
      {:ok, projekt: projekt}
    end

    test "renders project with straenge, vorbedingungen, schritte, quellen", %{
      conn: conn,
      projekt: projekt
    } do
      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.id}")

      assert html =~ "Bahnhofstraße umgestalten"
      assert html =~ "Boulevard Bahnhofstraße — Tempo 30, Begrünung, Sitzgelegenheiten."

      # Stränge A und B.
      assert has_element?(view, "span.strang-title", "Westtangente als Ortsumgehung bauen")
      assert has_element?(view, "span.strang-title", "Direkte Umstufung ohne Ortsumgehung")

      # ODER-Separator zwischen Strängen.
      assert has_element?(view, ".oder-separator", "— ODER —")

      # Vorbedingungen mit ✓ (erfüllt) und ⚠ (offen).
      assert has_element?(
               view,
               ".vorbedingung.vorb-unmet",
               "Westtangente muss als OU im Sinne des Art. 13f BayFAG qualifizieren"
             )

      assert has_element?(
               view,
               ".vorbedingung.vorb-met",
               "Verkehrsrückgang muss mit Daten belegt werden"
             )

      # Rechtliche Grundlage als Legal-Badge.
      assert has_element?(view, ".legal-badge.legal-unmet", "Art. 13f BayFAG")
      assert has_element?(view, ".legal-badge.legal-met", "Art. 7 BayStrWG")

      # Schritte.
      assert has_element?(view, ".schritt", "Verkehrsgutachten erstellen")
      assert has_element?(view, ".schritt", "VEP-Daten aufbereiten")

      # Strang-Quellen.
      assert has_element?(view, ".source-item", "Art. 13f BayFAG — Sonderbaulast-Modell")

      # Strang-Bedingung + Status.
      assert has_element?(view, ".strang-bedingung")
      assert has_element?(view, ".strang-status")
    end

    test "shows status and prio badge", %{conn: conn, projekt: projekt} do
      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.id}")

      assert has_element?(view, "span.badge", "aktiv")
      assert has_element?(view, "span.badge", "hoch")
    end

    test "strang_status counts vorbedingungen correctly", %{conn: conn, projekt: projekt} do
      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.id}")

      # Strang A: 2 Vorbedingungen, beide offen.
      # Strang B: 1 Vorbedingung, erfüllt.
      assert html =~ "0 ✓"
      assert html =~ "1 ✓"
      assert html =~ "2 von 2 Vorbedingungen offen"
      assert html =~ "Alle Vorbedingungen erfüllt"
    end

    test "renders projekt title", %{conn: conn, projekt: projekt} do
      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.id}")

      assert html =~ projekt.titel
    end
  end

  describe "unknown projekt" do
    test "redirects to index with flash for unknown id", %{conn: conn} do
      # LiveView mount leitet direkt zur Index weiter, wenn das Projekt nicht existiert.
      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/projekte/99999")
      assert flash["error"] == "Projekt nicht gefunden"
    end
  end

  describe "pending proposals link" do
    test "link appears when pending proposals exist", %{conn: conn} do
      projekt = bahnhofstr()
      proposal(projekt)

      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.id}")

      assert html =~ "Offene Vorschläge (1)"

      assert has_element?(
               view,
               "a[href='/projekte/#{projekt.id}/proposals']",
               "Offene Vorschläge (1)"
             )
    end

    test "link always visible (browse rejected/approved too), muted when no pending", %{
      conn: conn
    } do
      projekt = bahnhofstr()

      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.id}")

      # Link ist immer sichtbar — auch ohne offene Vorschläge, damit der Stadtrat
      # historische (approved/rejected) Vorschläge durchsuchen kann.
      assert has_element?(
               view,
               "a[href='/projekte/#{projekt.id}/proposals']",
               "🤖 Vorschläge"
             )

      # Ohne offene Vorschläge wird kein Count gerendert.
      refute html =~ "Offene Vorschläge"
    end

    test "link count increases with multiple pending proposals", %{conn: conn} do
      projekt = bahnhofstr()
      proposal(projekt)
      proposal(projekt)
      proposal(projekt)

      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.id}")

      assert html =~ "Offene Vorschläge (3)"
    end

    test "approved/rejected proposals not counted as pending", %{conn: conn} do
      projekt = bahnhofstr()

      _approved =
        proposal(projekt, %{
          status: :approved,
          entschieden_am: DateTime.truncate(DateTime.utc_now(), :second),
          entschieden_von: "stadtrat"
        })

      _rejected =
        proposal(projekt, %{
          status: :rejected,
          entschieden_am: DateTime.truncate(DateTime.utc_now(), :second),
          entschieden_von: "stadtrat"
        })

      _pending = proposal(projekt)

      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.id}")

      assert html =~ "Offene Vorschläge (1)"
    end
  end

  # Referenzen werden nicht gehalten — nur, um unused-alias-Warnungen zu vermeiden.
  _ = Projekt
  _ = Repo
  _ = from(p in "projekte")
end
