defmodule RatsprojekteWeb.HubTest do
  use ExUnit.Case, async: true

  alias Ratsprojekte.Projects.{NextStep, Project, TimelineEntry}
  alias RatsprojekteWeb.Hub

  @today ~D[2026-11-12]

  defp project(step, last_on \\ @today) do
    %Project{
      next_step: step,
      timeline: [%TimelineEntry{on: last_on}],
      opinions: [],
      facts: [],
      variants: [],
      motions: []
    }
  end

  test "deadline: overdue, within seven days, or nothing" do
    due = &project(%NextStep{text: "x", due_on: Date.add(@today, &1)})

    assert Hub.deadline(due.(-1), @today) == {:overdue, "Überfällig"}
    assert Hub.deadline(due.(0), @today) == {:soon, "Heute"}
    assert Hub.deadline(due.(1), @today) == {:soon, "Morgen"}
    assert Hub.deadline(due.(7), @today) == {:soon, "In 7 Tagen"}
    assert Hub.deadline(due.(8), @today) == nil
    assert Hub.deadline(%{due.(-1) | disposition: :resting}, @today) == nil
  end

  test "a project lies only if nothing happened and nothing is agreed" do
    old = Date.add(@today, -35)

    assert Hub.lying_weeks(project(nil, old), @today) == 5
    assert Hub.lying_weeks(project(%NextStep{text: "x"}, old), @today) == 5

    assert Hub.lying_weeks(project(%NextStep{text: "x", due_on: ~D[2027-01-01]}, old), @today) ==
             nil

    assert Hub.lying_weeks(project(nil, Date.add(@today, -10)), @today) == nil
  end

  test "the editor is „Du“ on screen" do
    assert Hub.assignee("ich") == "Du"
    assert Hub.assignee("Selin") == "Selin"
    assert Hub.mine?(project(%NextStep{text: "x", assignee: "ich"}))
  end

  test "the checklist locks nothing and says what is open" do
    items = Hub.maturity(project(nil))
    assert {"Noch kein Antrag begonnen", :open} in items
    assert {"Keine Varianten, bei einfachen Anträgen in Ordnung", :hint} in items
    assert {"Keine Festlegung der Fraktion eingetragen", :hint} in items
  end
end
