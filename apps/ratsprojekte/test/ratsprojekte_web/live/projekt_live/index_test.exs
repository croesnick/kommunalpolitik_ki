defmodule RatsprojekteWeb.ProjektLive.IndexTest do
  use RatsprojekteWeb.ConnCase, async: false

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{Projekt, Realisierungsstrang}
  import Ecto.Query

  setup do
    seed_all()
    :ok
  end

  describe "render" do
    test "renders all projects", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Stadtrats-Projekte Buchloe"
      assert has_element?(view, "h2", "Bahnhofstraße umgestalten")
      assert has_element?(view, "h2", "Westtangente prüfen")
      assert has_element?(view, "h2", "Freibad Digitalisierung")
      assert has_element?(view, "h2", "Gennachpark / Moorpark")
    end

    test "renders verworfen badge with red style", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Badge bekommt die verworfen-spezifische Modifier-Klasse — die
      # konkreten Farben leben in app.css als Design-Tokens.
      badge =
        view
        |> element("span.badge", "verworfen")
        |> render()

      assert badge =~ "badge-verworfen"
    end
  end

  describe "status filter via URL" do
    test "filter verworfen shows only verworfen projects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?status=verworfen")

      assert has_element?(view, "h2", "Westtangente prüfen")
      refute has_element?(view, "h2", "Bahnhofstraße umgestalten")
      refute has_element?(view, "h2", "Freibad Digitalisierung")
      refute has_element?(view, "h2", "Gennachpark / Moorpark")

      # Genau eine Projekt-Karte (`.project-card`).
      assert count_cards(render(view)) == 1
    end

    test "filter aktiv shows only aktiv projects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?status=aktiv")

      assert has_element?(view, "h2", "Bahnhofstraße umgestalten")
      refute has_element?(view, "h2", "Westtangente prüfen")
      refute has_element?(view, "h2", "Freibad Digitalisierung")
      refute has_element?(view, "h2", "Gennachpark / Moorpark")
    end

    test "filter idee shows only idee projects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?status=idee")

      assert has_element?(view, "h2", "Freibad Digitalisierung")
      refute has_element?(view, "h2", "Bahnhofstraße umgestalten")
    end

    test "filter abgeschlossen shows only abgeschlossen projects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?status=abgeschlossen")

      assert has_element?(view, "h2", "Gennachpark / Moorpark")
      refute has_element?(view, "h2", "Bahnhofstraße umgestalten")
    end
  end

  describe "blockiert filter via URL" do
    test "blockiert=true shows only projects without fulfilled strang", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?blockiert=true")

      # Bahnhofstraße hat Strang B (erfüllt) → NICHT blockiert.
      refute has_element?(view, "h2", "Bahnhofstraße umgestalten")

      # Westtangente, Freibad, Gennachpark haben keinen erfüllten Strang → blockiert.
      assert has_element?(view, "h2", "Westtangente prüfen")
      assert has_element?(view, "h2", "Freibad Digitalisierung")
      assert has_element?(view, "h2", "Gennachpark / Moorpark")
    end
  end

  describe "status + seit filter via URL" do
    test "status=verworfen + seit filtern nach verworfen_am", %{conn: conn} do
      # Westtangente wurde am 2025-03-15 verworfen.
      # seit=2025-04-01 → kein Treffer.
      {:ok, view_leer, _html} = live(conn, ~p"/?status=verworfen&seit=2025-04-01")
      refute has_element?(view_leer, "h2", "Westtangente prüfen")

      # seit=2025-01-01 → Treffer.
      {:ok, view_voll, _html} = live(conn, ~p"/?status=verworfen&seit=2025-01-01")
      assert has_element?(view_voll, "h2", "Westtangente prüfen")
    end

    test "status=abgeschlossen + seit filtern nach abgeschlossen_am", %{conn: conn} do
      # Gennachpark abgeschlossen am 2025-02-01.
      {:ok, view_leer, _html} = live(conn, ~p"/?status=abgeschlossen&seit=2025-03-01")
      refute has_element?(view_leer, "h2", "Gennachpark / Moorpark")

      {:ok, view_voll, _html} = live(conn, ~p"/?status=abgeschlossen&seit=2025-01-01")
      assert has_element?(view_voll, "h2", "Gennachpark / Moorpark")
    end
  end

  describe "filter form patches URL" do
    test "render_change :filter patches URL and updates list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_change(view, :filter, %{
        "filter" => %{"status" => "verworfen", "seit" => "", "blockiert" => "false"}
      })

      assert_patch(view, ~p"/?status=verworfen")

      # Liste aktualisiert sich auf verworfen.
      assert has_element?(view, "h2", "Westtangente prüfen")
      refute has_element?(view, "h2", "Bahnhofstraße umgestalten")
    end

    test "render_change :filter with blockiert checked patches blockiert=true", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_change(view, :filter, %{
        "filter" => %{"status" => "", "seit" => "", "blockiert" => "true"}
      })

      assert_patch(view, ~p"/?blockiert=true")

      refute has_element?(view, "h2", "Bahnhofstraße umgestalten")
      assert has_element?(view, "h2", "Westtangente prüfen")
    end

    test "render_change :filter without any value patches to root", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?status=verworfen")

      render_change(view, :filter, %{
        "filter" => %{"status" => "", "seit" => "", "blockiert" => "false"}
      })

      # Reset → alle Projekte sichtbar.
      assert_patch(view, ~p"/")
      assert has_element?(view, "h2", "Bahnhofstraße umgestalten")
      assert has_element?(view, "h2", "Westtangente prüfen")
    end
  end

  # Smoke-Test, dass die Stream-Tuple-Destructuring in der Render-Function stabil ist.
  test "stream iteration renders all four project cards once", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert count_cards(html) == 4
  end

  # Referenzen werden nicht gehalten — nur, um unused-alias-Warnungen zu vermeiden.
  _ = Projekt
  _ = Realisierungsstrang
  _ = Repo
  _ = from(p in "projekte")

  defp count_cards(html) when is_binary(html) do
    # `.project-card` erscheint als `class="project-card"` im gerenderten HTML.
    parts = String.split(html, "class=\"project-card\"")
    length(parts) - 1
  end

  defp count_cards(%Phoenix.LiveViewTest.View{} = view) do
    count_cards(render(view))
  end
end
