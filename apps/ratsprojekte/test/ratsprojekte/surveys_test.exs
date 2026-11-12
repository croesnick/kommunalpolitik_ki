defmodule Ratsprojekte.SurveysTest do
  use Ratsprojekte.DataCase, async: false

  alias Ratsprojekte.{Projects, Surveys}

  setup do
    {:ok, a} = Projects.create_project(%{title: "Mitfahrbänke"})
    {:ok, b} = Projects.create_project(%{title: "Bürgerbus"})

    {:ok, survey} =
      Surveys.open_survey(
        %{
          title: "Herbst",
          question: "Sollen wir das angehen?",
          circle: "base",
          due_on: ~D[2026-11-30]
        },
        [a.slug, b.slug]
      )

    %{a: a, b: b, survey: survey}
  end

  test "open_survey/2 bundles projects under opaque identifiers", %{survey: survey, a: a} do
    assert survey.status == :preparing
    assert survey.public_id =~ ~r/\A[A-Za-z0-9_-]{1,64}\z/
    assert length(survey.topics) == 2
    refute Enum.any?(survey.topics, &String.contains?(&1.topic_id, a.slug))
  end

  test "confirm_upload/2 lets it run and notes it in each project", %{survey: survey, a: a} do
    {:ok, survey} = Surveys.confirm_upload(survey, ~D[2026-11-04])
    assert survey.status == :running

    assert Enum.any?(
             Projects.get_project!(a.slug).timeline,
             &(&1.kind == :survey and &1.text =~ "läuft bis 30.11.2026")
           )
  end

  test "record_return/4 assigns rows, replaces with newer and refuses older", ctx do
    %{survey: survey, a: a, b: b} = ctx
    [ta, tb] = Enum.map(survey.topics, & &1.topic_id)
    first = ~U[2026-11-10 10:00:00Z]

    rows = [
      %{
        topic_id: ta,
        tally: [0, 1, 2, 3, 4],
        arguments: [%{"stance" => "for", "text" => "gut\u{200B}"}],
        assign: {:project, a.slug}
      },
      %{topic_id: tb, tally: [1, 1, 1, 1, 1], assign: {:project, b.slug}},
      %{topic_id: "neu-1", tally: [0, 0, 0, 2, 5], assign: {:new, %{"title" => "Trinkbrunnen"}}},
      %{topic_id: "neu-2", tally: [9, 0, 0, 0, 0], assign: :ignore}
    ]

    {:ok, survey} = Surveys.record_return(survey, first, rows)

    [opinion] = Projects.get_project!(a.slug).opinions
    assert opinion.tally == [0, 1, 2, 3, 4]
    assert opinion.circle == :base
    assert opinion.arguments == [%{"stance" => "for", "text" => "gut"}]

    new = Projects.get_project!("trinkbrunnen")
    assert new.origin == "Basis (Befragung „Herbst“)"
    assert Enum.find(survey.topics, &(&1.topic_id == "neu-2")).ignored

    {:ok, _} =
      Surveys.record_return(
        survey,
        ~U[2026-11-12 10:00:00Z],
        [Map.put(hd(rows), :tally, [0, 0, 0, 0, 9])],
        close: true
      )

    assert [%{tally: [0, 0, 0, 0, 9]}] = Projects.get_project!(a.slug).opinions

    assert {:error, :older} =
             Surveys.record_return(Surveys.get_survey!(survey.public_id), first, rows)

    assert Surveys.get_survey!(survey.public_id).status == :answered
  end
end
