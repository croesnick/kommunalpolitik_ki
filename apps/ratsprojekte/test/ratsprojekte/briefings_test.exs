defmodule Ratsprojekte.BriefingsTest do
  use Ratsprojekte.DataCase, async: false

  alias Ratsprojekte.{Briefings, Projects, Settings, Surveys}
  alias Ratsprojekte.Projects.TimelineEntry

  @on ~D[2026-11-03]

  defp idea(title, attrs \\ %{}) do
    {:ok, project} =
      Projects.create_project(
        Map.merge(%{title: title, origin: "Bürgersprechstunde", on: @on}, attrs)
      )

    project
  end

  defp event(project, attrs) do
    {:ok, project} = Projects.record_event(project, Map.merge(%{on: @on}, attrs))
    project
  end

  # Everything so far counts as older than an issue a minute ago; what
  # follows is new. Timestamps have whole seconds.
  defp issue_a_minute_ago do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    Repo.update_all(TimelineEntry, set: [inserted_at: DateTime.add(now, -120)])
    {:ok, issued} = Briefings.issue("<article>Stand</article>", DateTime.add(now, -60))
    issued
  end

  defp news_texts(briefing),
    do: for({_title, entries} <- briefing.news, entry <- entries, do: entry.text)

  describe "what goes into the briefing" do
    test "private entries, cross references and the origin stay in the hub, counted" do
      project = idea("Bürgerbus")
      event(project, %{text: "Selin ist skeptisch", in_briefing: false})
      event(project, %{text: "Fraktion dafür", by: "fraction"})
      Projects.add_cross_reference(project, %{kind: "vault", target: "Notizen/Bus.md"})

      briefing = Briefings.preview()
      [{"Idee", [paper]}] = briefing.groups

      assert paper.notes == []
      assert [%{circle: "Fraktion", statement: "Fraktion dafür"}] = paper.opinions
      refute inspect(briefing) =~ "Selin"
      refute inspect(briefing) =~ "Bürgersprechstunde"
      refute inspect(briefing) =~ "Notizen/Bus.md"
      assert briefing.withheld == %{notes: 1, cross_references: 1, origins: 1}
    end

    test "„Wer ist dran“ names the editor, „Redaktion“ while no name is entered" do
      event(idea("Bänke"), %{text: "x", step_text: "Standorte prüfen", step_assignee: "ich"})
      event(idea("Solar"), %{text: "x", step_text: "Statik", step_assignee: "Selin"})
      event(idea("Bus"), %{text: "x", step_text: "Fahrplan"})

      assert [{"Noch niemand", _}, {"Redaktion", [%{title: "Bänke"}]}, {"Selin", _}] =
               Enum.sort(Briefings.preview().due)

      {:ok, "Miriam Haas"} = Settings.set_editor_name(%{"name" => "Miriam Haas"})
      briefing = Briefings.preview()

      assert briefing.editor == "Miriam Haas"

      assert {"Miriam Haas", [%{text: "Standorte prüfen"}]} =
               List.keyfind(briefing.due, "Miriam Haas", 0)

      assert {"Noch niemand", _} = List.last(briefing.due)
    end

    test "early projects say which circles have not been heard" do
      event(idea("Bänke"), %{text: "dafür", by: "board"})
      [{_, [paper]}] = Briefings.preview().groups
      assert paper.not_heard == ["Fraktion", "Basis"]
    end

    test "filed projects stand apart, the latest decision with the project" do
      {:ok, _} =
        Projects.dispose(idea("Bücherei"), %{disposition: "resting", reason: "später"})

      event(idea("Bus"), %{text: "weiter", phase: :drafting, by: "fraction"})

      briefing = Briefings.preview()
      assert briefing.filed == [{"Bücherei", "Ruht"}]
      [{"Ausarbeitung", [paper]}] = briefing.groups
      assert paper.decision.text == "Idee → Ausarbeitung: weiter"
      assert paper.decision.by == "Fraktion"
    end
  end

  describe "„Neu seit“" do
    test "the first briefing has none" do
      idea("Bus")
      assert Briefings.preview().since == nil
      assert Briefings.preview().news == []
    end

    test "after an issue only substance entered since then, never private" do
      project = idea("Bus")
      issued = issue_a_minute_ago()

      project
      |> event(%{text: "Korrektur: Der Bus fährt nur werktags.", by: "fraction"})
      |> event(%{text: "nur für mich", in_briefing: false})
      |> Projects.add_fact(%{
        statement: "Kostet 40 000 €",
        citation: "Angebot S. 2",
        fetched_on: @on
      })

      briefing = Briefings.preview()
      assert briefing.since == {:issued, issued.issued_at}
      assert news_texts(briefing) == ["Korrektur: Der Bus fährt nur werktags."]
      assert [{"Bus", [%{by: "Fraktion"}]}] = briefing.news
    end

    test "the review counts from a chosen day by when it happened" do
      project = idea("Bus")
      issue_a_minute_ago()
      event(project, %{text: "Basis gefragt", on: ~D[2026-10-01]})
      event(project, %{text: "Vorstand dafür", by: "board", on: ~D[2026-11-05]})

      briefing = Briefings.review(~D[2026-11-01])
      assert briefing.since == {:day, ~D[2026-11-01]}
      assert news_texts(briefing) == ["Idee aufgenommen", "Vorstand dafür"]
    end
  end

  describe "issued briefings" do
    test "keep the document and the time, newest first" do
      {:ok, first} = Briefings.issue("<p>eins</p>", ~U[2026-11-01 18:00:00Z])
      {:ok, second} = Briefings.issue("<p>zwei</p>", ~U[2026-11-08 18:42:10Z])

      assert Enum.map(Briefings.list_issued(), & &1.id) == [second.id, first.id]
      assert Briefings.last_issued_at() == ~U[2026-11-08 18:42:10Z]
      assert Briefings.get_issued(first.id).html == "<p>eins</p>"
    end
  end

  test "fresh survey results come with their rows in the order of the ideas" do
    a = idea("Trinkbrunnen")
    b = idea("Sitzbänke")

    {:ok, survey} =
      Surveys.open_survey(
        %{
          title: "Herbst",
          question: "Was sollen wir verfolgen?",
          circle: "base",
          due_on: ~D[2026-11-30]
        },
        [b.slug, a.slug]
      )

    {:ok, survey} = Surveys.confirm_upload(survey, @on)
    [first, second] = survey.topics

    rows =
      for topic <- [first, second] do
        slug = Enum.find([a, b], &(&1.id == topic.project_id)).slug

        %{
          topic_id: topic.topic_id,
          tally: [0, 1, 2, 3, 4],
          arguments: [%{stance: "for", text: "Gut für Kinder"}],
          assign: {:project, slug}
        }
      end

    {:ok, _} = Surveys.record_return(survey, ~U[2026-11-10 12:00:00Z], rows, close: true)

    [result] = Briefings.preview().surveys
    assert result.circle == "Basis"

    assert Enum.map(result.rows, & &1.title) ==
             Enum.map(survey.topics, &Enum.find([a, b], fn p -> p.id == &1.project_id end).title)

    assert [%{"stance" => "for"}] = hd(result.rows).arguments
  end
end
