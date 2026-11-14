defmodule RatsprojekteWeb.ProjectLiveTest do
  use RatsprojekteWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ratsprojekte.Projects

  setup %{conn: conn} do
    {:ok, project} = Projects.create_project(%{title: "Radweg Bahnhofstraße"})
    {:ok, view, _html} = live(conn, ~p"/projekte/#{project.slug}")
    %{view: view, slug: project.slug}
  end

  defp open(view, selector), do: view |> element(selector) |> render_click()

  test "an unknown slug leads back to the overview", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/projekte/gibt-es-nicht")
  end

  test "„Neuer Eintrag“ records the event and shows it in the timeline", %{view: view, slug: slug} do
    open(view, "#neuer-eintrag")

    view
    |> form("#eintrag",
      event: %{by: "board", text: "Vorstand findet das gut", in_briefing: "true"}
    )
    |> render_submit()

    assert has_element?(view, "#verlauf li", "Vorstand findet das gut")
    assert has_element?(view, "#meinungsbild", "Vorstand findet das gut")
    assert [%{circle: :board}] = Projects.get_project!(slug).opinions
  end

  test "a phase button opens the main flow with that phase", %{view: view} do
    open(view, ~s(#phasen button[phx-value-phase="drafting"]))
    assert has_element?(view, ~s(#eintrag option[value="drafting"][selected]))

    view |> form("#eintrag", event: %{text: "Fraktion will weiter"}) |> render_submit()
    assert has_element?(view, "#phasen .jetzt", "Ausarbeitung")

    assert has_element?(
             view,
             "#verlauf li.entscheidung",
             "Idee → Ausarbeitung: Fraktion will weiter"
           )
  end

  test "a private note can go into the briefing and back", %{view: view} do
    open(view, "#neuer-eintrag")
    view |> form("#eintrag", event: %{text: "Telefonat", in_briefing: "false"}) |> render_submit()
    assert has_element?(view, "#verlauf li", "nur für mich")

    view |> element("#verlauf button", "in den Stand") |> render_click()
    refute has_element?(view, "#verlauf li .badge", "nur für mich")
  end

  test "the next step can be changed on its own", %{view: view} do
    open(view, ~s(#naechster-schritt button))

    view
    |> form("#schritt", step: %{text: "Ortstermin", assignee: "ich", due_on: "2026-12-01"})
    |> render_submit()

    assert has_element?(view, "#naechster-schritt", "Ortstermin")
    assert has_element?(view, "#naechster-schritt", "Du")
  end

  test "a motion carries status and outcome in the same main flow", %{view: view, slug: slug} do
    open(view, ~s(#phasen button[phx-value-phase="at_council"]))
    view |> form("#eintrag", event: %{text: "Antrag kommt"}) |> render_submit()

    open(view, ~s(#antraege button[phx-value-dialog="motion"]))

    view
    |> form("#antrag-neu",
      motion: %{title: "Radweg mit Förderung", motion_text: "Die Stadt plant …"}
    )
    |> render_submit()

    [motion] = Projects.get_project!(slug).motions
    open(view, "#antrag-#{motion.id} button")

    view
    |> form("#antrag-eintrag",
      event: %{
        status: "deliberated",
        outcome: "adopted",
        by: "council",
        text: "Stadtrat stimmt zu",
        phase: "implementation"
      }
    )
    |> render_submit()

    assert has_element?(view, "#antrag-#{motion.id} .badge", "Angenommen")
    assert has_element?(view, "#phasen .jetzt", "Umsetzung")
    assert Projects.get_project!(slug).motions |> hd() |> Map.get(:status) == :deliberated
  end

  test "facts, variants and cross references go through their dialogs", %{view: view} do
    refute has_element?(view, "#varianten")
    open(view, ~s(#phasen button[phx-value-phase="drafting"]))
    view |> form("#eintrag", event: %{text: "Ausarbeiten"}) |> render_submit()

    open(view, ~s(#fakten button))

    view
    |> form("#fakt",
      fact: %{statement: "Zwei Bauabschnitte", citation: "RIS, TOP 1", fetched_on: "2026-11-02"}
    )
    |> render_submit()

    assert has_element?(view, "#fakten", "geprüft")

    open(view, ~s(#varianten button))

    view
    |> form("#variante", variant: %{title: "Schutzstreifen", legal_basis: "StVO § 45"})
    |> render_submit()

    assert has_element?(view, "#variante-A", "StVO § 45")

    open(view, ~s(#variante-A button[phx-value-status="chosen"]))
    view |> form("#variante-entscheiden", decision: %{reason: "günstiger"}) |> render_submit()
    assert has_element?(view, "#variante-A .badge", "gewählt")

    open(view, ~s(#querverweise button[phx-value-dialog="cross_reference"]))

    view
    |> form("#querverweis", reference: %{kind: "vault", target: "Notiz Radweg"})
    |> render_submit()

    assert has_element?(view, "#querverweise", "Notiz Radweg")
    assert has_element?(view, "#verlauf li .badge", "nur für mich")
  end

  test "filing away and resuming", %{view: view} do
    open(view, ~s(button[phx-value-dialog="dispose"]))

    view
    |> form("#ablegen", decision: %{disposition: "resting", reason: "Haushalt"})
    |> render_submit()

    assert has_element?(view, "#abgelegt", "Ruht")

    open(view, ~s(#abgelegt button))
    view |> form("#wieder", decision: %{reason: "Förderung"}) |> render_submit()
    refute has_element?(view, "#abgelegt")
  end

  test "Escape closes a dialog without saving", %{view: view} do
    open(view, "#neuer-eintrag")
    render_keydown(view, "close", %{"key" => "Escape"})
    refute has_element?(view, "#eintrag")
  end
end
