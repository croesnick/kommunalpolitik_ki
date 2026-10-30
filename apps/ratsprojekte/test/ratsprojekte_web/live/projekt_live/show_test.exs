defmodule RatsprojekteWeb.ProjektLive.ShowTest do
  use RatsprojekteWeb.ConnCase, async: false

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  import Ecto.Query

  describe "render" do
    setup do
      projekt = marktplatz()
      {:ok, projekt: projekt}
    end

    test "renders project with straenge, vorbedingungen, schritte, quellen", %{
      conn: conn,
      projekt: projekt
    } do
      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      assert html =~ "Marktplatz umgestalten"
      assert html =~ "Marktplatz aufwerten — Aufenthaltsqualität, Begrünung, Sitzgelegenheiten."

      # Stränge A und B.
      assert has_element?(view, "span.strang-title", "Über Städtebauförderung")
      assert has_element?(view, "span.strang-title", "Über Eigenleistung")

      # ODER-Separator zwischen Strängen.
      assert has_element?(view, ".oder-separator", "— ODER —")

      # Vorbedingungen mit ✓ (erfüllt) und ⚠ (offen).
      assert has_element?(
               view,
               ".vorbedingung.vorb-unmet",
               "Erneuerungsgebiet muss förmlich festgelegt sein"
             )

      assert has_element?(
               view,
               ".vorbedingung.vorb-met",
               "Haushaltsmittel müssen eingeplant sein"
             )

      # Rechtliche Grundlage als Legal-Badge.
      assert has_element?(view, ".legal-badge.legal-unmet", "§ 136 BauGB")
      assert has_element?(view, ".legal-badge.legal-met", "Art. 61 BayGO")

      # Schritte.
      assert has_element?(view, ".schritt", "Gebietsfestlegung vorbereiten")
      assert has_element?(view, ".schritt", "Haushaltsantrag vorbereiten")

      # Strang-Quellen.
      assert has_element?(view, ".source-item", "Städtebauförderungsrichtlinien — Zuschussmodul")

      # Strang-Bedingung + Status.
      assert has_element?(view, ".strang-bedingung")
      assert has_element?(view, ".strang-status")
    end

    test "shows status and prio badge", %{conn: conn, projekt: projekt} do
      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.slug}")

      assert has_element?(view, "span.badge", "aktiv")
      assert has_element?(view, "span.badge", "hoch")
    end

    test "strang_status counts vorbedingungen correctly", %{conn: conn, projekt: projekt} do
      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      # Strang A: 2 Vorbedingungen, beide offen.
      # Strang B: 1 Vorbedingung, erfüllt.
      assert html =~ "0 ✓"
      assert html =~ "1 ✓"
      assert html =~ "2 von 2 Vorbedingungen offen"
      assert html =~ "Alle Vorbedingungen erfüllt"
    end

    test "renders projekt title", %{conn: conn, projekt: projekt} do
      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

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
      projekt = marktplatz()
      proposal(projekt)

      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      assert html =~ "Offene Vorschläge (1)"

      assert has_element?(
               view,
               "a[href='/projekte/#{projekt.slug}/proposals']",
               "Offene Vorschläge (1)"
             )
    end

    test "link always visible (browse rejected/approved too), muted when no pending", %{
      conn: conn
    } do
      projekt = marktplatz()

      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      # Link ist immer sichtbar — auch ohne offene Vorschläge, damit der Stadtrat
      # historische (approved/rejected) Vorschläge durchsuchen kann.
      assert has_element?(
               view,
               "a[href='/projekte/#{projekt.slug}/proposals']",
               "🤖 Vorschläge"
             )

      # Ohne offene Vorschläge wird kein Count gerendert.
      refute html =~ "Offene Vorschläge"
    end

    test "link count increases with multiple pending proposals", %{conn: conn} do
      projekt = marktplatz()
      proposal(projekt)
      proposal(projekt)
      proposal(projekt)

      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      assert html =~ "Offene Vorschläge (3)"
    end

    test "approved/rejected proposals not counted as pending", %{conn: conn} do
      projekt = marktplatz()

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

      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      assert html =~ "Offene Vorschläge (1)"
    end
  end

  describe "ziel & messung (value proposition / success metrics)" do
    test "renders VP and SM when set (#37)", %{conn: conn} do
      projekt =
        freibad(%{
          value_proposition:
            "Bargeldanteil im Bäderbetrieb sinkt, Wartezeiten an den Kassen werden messbar kürzer.",
          success_metrics:
            "Bargeldanteil im Bäderbetrieb unter 30 Prozent, Wartezeit pro Gast unter drei Minuten."
        })

      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      assert html =~ "Ziel &amp; Messung"
      assert has_element?(view, "span.payload-row-label", "Value Proposition:")
      assert has_element?(view, "span.payload-row-label", "Success Metrics:")
      assert html =~ "Bargeldanteil im Bäderbetrieb unter 30 Prozent"
    end

    test "renders nothing when both fields are unset", %{conn: conn} do
      projekt = freibad()

      {:ok, _view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      refute html =~ "Ziel &amp; Messung"
      refute html =~ "Value Proposition"
    end
  end

  describe "ris referenz an sitzungs-quellen (#32)" do
    test "renders the reference as link into the ris when url is set", %{conn: conn} do
      projekt = freibad()

      quelle(projekt, %{
        typ: :sitzung,
        titel: "Stadtratssitzung 05.11.2026",
        url: "https://example.org/ris/sitzung/4711",
        ris_sitzung_id: "4711",
        ris_top: "7",
        beschluss_nr: "2026/034"
      })

      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      assert has_element?(
               view,
               ".source-ris a[href='https://example.org/ris/sitzung/4711']",
               "🏛 RIS: Sitzung 4711 · TOP 7 · Beschluss 2026/034"
             )

      assert html =~ "Beschluss 2026/034"
    end

    test "renders the reference as plain text when url is unset", %{conn: conn} do
      projekt = freibad()

      quelle(projekt, %{
        typ: :sitzung,
        titel: "Stadtratssitzung 05.11.2026",
        ris_sitzung_id: "4711",
        ris_top: "7"
      })

      {:ok, view, html} = live(conn, ~p"/projekte/#{projekt.slug}")

      assert has_element?(view, ".source-ris", "🏛 RIS: Sitzung 4711 · TOP 7")
      refute has_element?(view, ".source-ris a")
      assert html =~ "Sitzung 4711"
    end

    test "renders no ris badge for quellen without reference", %{conn: conn} do
      projekt = marktplatz()

      {:ok, view, _html} = live(conn, ~p"/projekte/#{projekt.slug}")

      refute has_element?(view, ".source-ris")
    end
  end

  # Referenzen werden nicht gehalten — nur, um unused-alias-Warnungen zu vermeiden.
  _ = Projekt
  _ = Repo
  _ = from(p in "projekte")
end
