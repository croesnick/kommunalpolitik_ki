defmodule RatsprojekteWeb.BriefingLiveTest do
  use RatsprojekteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ratsprojekte.{Briefings, Projects, Repo}
  alias Ratsprojekte.Briefings.IssuedBriefing
  alias Ratsprojekte.Projects.TimelineEntry

  defp project(title, attrs) do
    {:ok, project} = Projects.create_project(%{title: title, origin: "Sprechstunde"})
    {:ok, project} = Projects.record_event(project, attrs)
    project
  end

  test "the preview shows the paper and what stays here", %{conn: conn} do
    project("Bürgerbus", %{text: "Selin ist skeptisch", in_briefing: false})

    project("Solar", %{
      text: "Fraktion dafür",
      by: "fraction",
      step_text: "Statik klären",
      step_due_on: Date.add(Projects.today(), -3)
    })

    {:ok, view, _html} = live(conn, ~p"/stand")

    assert has_element?(view, "#papier #wer-ist-dran", "Statik klären")
    refute has_element?(view, "#papier", "Selin")
    refute has_element?(view, "#papier", "Sprechstunde")
    refute has_element?(view, "#papier", "Überfällig")
    assert has_element?(view, "#bleibt-hier", "1 Notiz nur für dich")
    assert has_element?(view, "#bleibt-hier", "Herkunft von 2 Projekten")
    assert has_element?(view, "#abgelaufen", "Eine Frist")
    assert has_element?(view, "#papier", "gepflegt von Redaktion")
    refute has_element?(view, "#drucken")
    refute has_element?(view, "#neu-seit")
  end

  test "issuing stores exactly the document, which never changes afterwards", %{conn: conn} do
    project = project("Solar", %{text: "Fraktion dafür", by: "fraction"})

    {:ok, view, _html} = live(conn, ~p"/stand")
    view |> element("#ausgeben") |> render_click()

    [issued] = Repo.all(IssuedBriefing)
    assert_patch(view, ~p"/stand/#{issued.id}")
    assert has_element?(view, "#ausgegeben #papier", "Fraktion dafür")
    assert has_element?(view, "#ausgegeben", "Uhr")
    assert has_element?(view, "#drucken")
    assert has_element?(view, "#bisher-ausgegeben a", "Uhr")

    # Later changes reach the next briefing, never the issued one.
    # Timestamps have whole seconds: what was there counts as older.
    Repo.update_all(TimelineEntry, set: [inserted_at: DateTime.add(issued.issued_at, -60)])
    Projects.record_event(project, %{text: "Vorstand auch", by: "board"})

    {:ok, issued_view, _html} = live(conn, ~p"/stand/#{issued.id}")
    refute has_element?(issued_view, "#papier", "Vorstand auch")

    {:ok, preview, _html} = live(conn, ~p"/stand")
    assert has_element?(preview, "#neu-seit", "Vorstand auch")
    refute has_element?(preview, "#neu-seit", "Fraktion dafür")
  end

  test "an unknown issued briefing leads back to the preview", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/stand"}}} = live(conn, ~p"/stand/999")
  end

  test "the review starts from a chosen day and stores nothing", %{conn: conn} do
    project("Solar", %{text: "Alte Sache", on: ~D[2026-01-10]})
    project("Bus", %{text: "Neue Sache", on: ~D[2026-03-05]})

    {:ok, view, _html} = live(conn, ~p"/stand")
    view |> element("#rueckblick-form") |> render_change(%{"ab" => "2026-03-01"})

    assert_patch(view, ~p"/stand?ab=2026-03-01")
    assert has_element?(view, "#papier", "Rückblick · nicht ausgegeben")
    assert has_element?(view, "#neu-seit", "Seit 01.03.2026")
    assert has_element?(view, "#neu-seit", "Neue Sache")
    refute has_element?(view, "#neu-seit", "Alte Sache")
    refute has_element?(view, "#ausgeben")
    assert Briefings.list_issued() == []
  end

  test "the editor enters a name once, the paper shows it instead of „ich“", %{conn: conn} do
    project("Bänke", %{text: "x", step_text: "Standorte prüfen", step_assignee: "ich"})

    {:ok, view, _html} = live(conn, ~p"/stand")
    assert has_element?(view, "#wer-ist-dran", "Redaktion")

    view |> form("#redaktion-form", redaktion: %{name: "Miriam Haas"}) |> render_submit()

    assert has_element?(view, "#wer-ist-dran", "Miriam Haas")
    assert has_element?(view, "#papier", "gepflegt von Miriam Haas")
    refute has_element?(view, "#wer-ist-dran th", ~r/^\s*ich\s*$/)
  end
end
