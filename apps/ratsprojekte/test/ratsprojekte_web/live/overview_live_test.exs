defmodule RatsprojekteWeb.OverviewLiveTest do
  use RatsprojekteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ratsprojekte.Projects

  defp project(title, attrs \\ %{}) do
    {:ok, project} = Projects.create_project(%{title: title})

    {:ok, project} =
      if attrs == %{}, do: {:ok, project}, else: Projects.record_event(project, attrs)

    project
  end

  test "an empty hub says how to start", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#leer")
  end

  test "cards sit in the column of their phase, filed ones below", %{conn: conn} do
    project("Bürgerbus", %{text: "weiter", phase: :drafting})
    filed = project("Bücherei")
    Projects.dispose(filed, %{disposition: "resting", reason: "später"})

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#spalte-drafting #karte-buergerbus")
    refute has_element?(view, "#brett #karte-buecherei")
    assert has_element?(view, "#abgelegt", "Bücherei")
  end

  test "„Du bist dran“ shows the editor's next steps only", %{conn: conn} do
    project("Mitfahrbänke", %{text: "x", step_text: "Beispiel anschauen", step_assignee: "ich"})
    project("Solar", %{text: "x", step_text: "Statik", step_assignee: "Selin"})

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#karte-mitfahrbaenke", "Beispiel anschauen · Du")

    view |> element("#filter button", "Du bist dran") |> render_click()
    assert has_element?(view, "#karte-mitfahrbaenke")
    refute has_element?(view, "#karte-solar")
  end

  test "an overdue step needs attention", %{conn: conn} do
    project("Solar", %{
      text: "x",
      step_text: "Statik",
      step_due_on: Date.add(Projects.today(), -1)
    })

    project("Bänke")

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#karte-solar .badge", "Überfällig")

    view |> element("#filter button", "Braucht Aufmerksamkeit") |> render_click()
    refute has_element?(view, "#karte-baenke")
  end

  describe "the main flow from the overview" do
    test "one dialog per project: text, readers, phase and step", %{conn: conn} do
      project("Schulstraße")
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#eintragen-schulstrasse") |> render_click()
      assert has_element?(view, "#eintrag #sichtbarkeit")

      view
      |> form("#eintrag",
        event: %{
          by: "council",
          text: "Bauausschuss stimmt zu",
          in_briefing: "true",
          phase: "at_council",
          step_text: "Sitzung vorbereiten",
          step_assignee: "du"
        }
      )
      |> render_submit()

      refute has_element?(view, "#eintrag")

      assert has_element?(
               view,
               "#spalte-at_council #karte-schulstrasse",
               "Sitzung vorbereiten · Du"
             )

      project = Projects.get_project!("schulstrasse")
      assert Enum.any?(project.timeline, &(&1.text == "Idee → Im Rat: Bauausschuss stimmt zu"))
      assert project.next_step.assignee == "ich"
    end

    test "without text it says what is missing, in German", %{conn: conn} do
      project("Schulstraße")
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#eintragen-schulstrasse") |> render_click()

      html = view |> form("#eintrag", event: %{text: ""}) |> render_submit()
      assert html =~ "Bitte ausfüllen"
      assert has_element?(view, "#eintrag")
    end

    test "„Nur ich“ as the speaker makes the entry private", %{conn: conn} do
      project("Schulstraße")
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#eintragen-schulstrasse") |> render_click()

      view |> form("#eintrag", event: %{by: "editor"}) |> render_change()
      assert has_element?(view, ~s(#sichtbarkeit input[value="false"][checked]))
    end
  end

  test "„Neue Idee“ suggests the short name and opens the project", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?neu")

    html =
      view
      |> form("#neue-idee-form", project: %{title: "Trinkbrunnen am Markt"})
      |> render_change()

    assert html =~ ~s(value="trinkbrunnen-am-markt")

    {:error, {:live_redirect, %{to: to}}} =
      view
      |> form("#neue-idee-form",
        project: %{title: "Trinkbrunnen am Markt", slug: "trinkbrunnen-am-markt"}
      )
      |> render_submit()

    assert to == ~p"/projekte/trinkbrunnen-am-markt"
  end

  test "no route lets a machine decide a proposal in the hub (ADR 0004)" do
    paths = Enum.map(RatsprojekteWeb.Router.__routes__(), & &1.path)
    refute Enum.any?(paths, &(&1 =~ ~r/decide|proposal|vorschlag|entscheid/i))
  end
end
