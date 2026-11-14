defmodule Ratsprojekte.Briefings do
  @moduledoc """
  The briefing („Stand“, ADR 0004): the version of the hub that Fraktion
  and Vorstand get. Page 1 carries the overview and „Wer ist dran“, then
  „Neu seit“ with substance only, then fresh survey results, then all
  active projects to look things up.

  What stays in the hub never reaches the briefing: private entries
  („Nur ich“), cross references, the origin of a project, and the
  timeline lines the hub writes about its own bookkeeping. Deadlines
  stand neutral as dates; only the preview points to expired ones.

  „Stand ausgeben“ stores exactly the rendered document with its time
  (`issue/2`); it never changes. From then on „Neu seit“ counts. A
  review („Rückblick“) uses the same version from a chosen day and is
  never stored.
  """

  import Ecto.Query, only: [from: 2]

  alias Ratsprojekte.Briefings.IssuedBriefing
  alias Ratsprojekte.{Labels, Projects, Repo, Settings, Surveys}
  alias Ratsprojekte.Projects.{NextStep, Project}

  @typedoc "From when „Neu seit“ counts: none, the last issued briefing, or a chosen day."
  @type since :: nil | {:issued, DateTime.t()} | {:day, Date.t()}

  # Substance: new ideas, entries and decisions with phase changes, and
  # the state of motions. Facts, variants and the hub's own bookkeeping
  # stand further down with the project.
  @news_kinds [:created, :note, :opinion, :decision, :motion]

  # The circles a project in an early phase should have heard.
  @early_phases [:idea, :opinion_forming]
  @heard_circles [:fraction, :board, :base]

  @editor_fallback "Redaktion"
  @nobody "Noch niemand"

  ## Composing

  @doc "The briefing as it would go out now: „Neu seit“ counts from the last issued one."
  @spec preview() :: map()
  def preview do
    since = if issued_at = last_issued_at(), do: {:issued, issued_at}
    compose(since)
  end

  @doc "The review from `day` on, in the same version, never stored."
  @spec review(Date.t()) :: map()
  def review(day), do: compose({:day, day})

  defp compose(since),
    do: build(Projects.list_projects(), Surveys.list_surveys(), since, Settings.editor_name())

  @doc """
  Builds the briefing from loaded projects and surveys. Pure: the same
  input gives the same briefing.
  """
  @spec build([Project.t()], [Surveys.Survey.t()], since(), String.t() | nil) :: map()
  def build(projects, surveys, since, editor_name) do
    editor = editor_name || @editor_fallback
    active = Enum.reject(projects, & &1.disposition)
    fresh = Enum.filter(surveys, &(&1.results_as_of && fresh?(since, &1)))
    fresh_ids = MapSet.new(fresh, & &1.id)
    running = Enum.filter(surveys, &(&1.status == :running))

    %{
      since: since,
      editor: editor,
      phases:
        for(
          {phase, name} <- Labels.phases(),
          do: {name, Enum.count(active, &(&1.phase == phase))}
        ),
      due: due(active, editor),
      news: news(projects, since, editor),
      surveys: Enum.map(fresh, &survey_result(&1, projects)),
      groups: groups(active, running, fresh_ids, editor),
      filed:
        for(
          p <- projects,
          p.disposition,
          do: {p.title, Labels.name(Labels.dispositions(), p.disposition)}
        ),
      withheld: withheld(projects)
    }
  end

  # „Wer ist dran“: one group per person, the editor by name, steps by deadline.
  defp due(active, editor) do
    active
    |> Enum.filter(& &1.next_step)
    |> Enum.map(fn p ->
      %{
        who: assignee(p.next_step.assignee, editor),
        title: p.title,
        text: p.next_step.text,
        due_on: p.next_step.due_on
      }
    end)
    |> Enum.group_by(& &1.who)
    |> Enum.sort_by(fn {who, _} -> {who == @nobody, who} end)
    |> Enum.map(fn {who, steps} -> {who, Enum.sort_by(steps, &due_key/1)} end)
  end

  defp due_key(%{due_on: nil, title: title}), do: {1, ~D[0000-01-01], title}
  defp due_key(%{due_on: due, title: title}), do: {0, due, title}

  defp assignee(name, editor) do
    cond do
      name in [nil, ""] -> @nobody
      NextStep.editor?(name) -> editor
      true -> name
    end
  end

  defp news(_projects, nil, _editor), do: []

  defp news(projects, since, editor) do
    for project <- projects,
        entries = Enum.filter(project.timeline, &(news?(&1) and new?(since, &1))),
        entries != [] do
      {project.title, Enum.map(entries, &%{on: &1.on, text: &1.text, by: actor(&1.by, editor)})}
    end
  end

  defp news?(entry), do: entry.in_briefing and entry.kind in @news_kinds

  # Timestamps have whole seconds. An entry from the second of the issue
  # counts as new: shown twice is better than never shown as new.
  defp new?({:issued, at}, entry), do: DateTime.compare(entry.inserted_at, at) != :lt
  defp new?({:day, day}, entry), do: Date.compare(entry.on, day) != :lt

  defp fresh?(nil, _survey), do: true
  defp fresh?({:issued, at}, survey), do: DateTime.compare(survey.updated_at, at) != :lt
  defp fresh?({:day, day}, survey), do: Date.compare(local_date(survey.updated_at), day) != :lt

  defp actor(nil, _editor), do: nil
  defp actor(:editor, editor), do: editor
  defp actor(by, _editor), do: Labels.name(Labels.actors(), by)

  # Results in the order of the ideas, never sorted by approval (ADR 0004).
  defp survey_result(survey, projects) do
    by_id = Map.new(projects, &{&1.id, &1})

    rows =
      for %{project_id: id} <- survey.topics,
          project = by_id[id],
          opinion = project && Enum.find(project.opinions, &(&1.survey_id == survey.id)),
          opinion != nil,
          do: %{
            title: project.title,
            tally: opinion.tally,
            statement: opinion.statement,
            arguments: opinion.arguments || []
          }

    %{
      title: survey.title,
      question: survey.question,
      circle: Labels.name(Labels.circles(), survey.circle),
      as_of: local_date(survey.results_as_of),
      rows: rows
    }
  end

  defp groups(active, running, fresh_ids, editor) do
    for {phase, name} <- Labels.phases(),
        projects = Enum.filter(active, &(&1.phase == phase)),
        projects != [] do
      {name, Enum.map(projects, &project(&1, running, fresh_ids, editor))}
    end
  end

  defp project(p, running, fresh_ids, editor) do
    shown = Enum.filter(p.timeline, & &1.in_briefing)
    decision = shown |> Enum.filter(&(&1.kind == :decision)) |> List.last()

    %{
      title: p.title,
      short: p.short,
      survey:
        Enum.find_value(
          running,
          &(Enum.any?(&1.topics, fn t -> t.project_id == p.id end) && &1.title)
        ),
      decision:
        decision && %{on: decision.on, text: decision.text, by: actor(decision.by, editor)},
      opinions: opinions(p, fresh_ids),
      not_heard: not_heard(p),
      chosen: Enum.find_value(p.variants, &(&1.status == :chosen && "#{&1.label}: #{&1.title}")),
      facts: Enum.map(p.facts, &Map.take(&1, [:statement, :citation, :verified])),
      motions: Enum.map(p.motions, &motion/1),
      notes: for(e <- shown, e.kind == :note, do: e.text)
    }
  end

  # The latest opinion of each circle; a tally shown above with its survey is not repeated.
  defp opinions(p, fresh_ids) do
    for {circle, name} <- Labels.circles(),
        opinion = latest_opinion(p, circle),
        opinion != nil do
      %{
        circle: name,
        on: opinion.on,
        statement: opinion.statement,
        tally: opinion.tally,
        tally_above: opinion.survey_id in fresh_ids
      }
    end
  end

  defp latest_opinion(p, circle) do
    p.opinions
    |> Enum.filter(&(&1.circle == circle))
    |> Enum.max_by(&{Date.to_gregorian_days(&1.on), &1.id}, fn -> nil end)
  end

  defp not_heard(%Project{phase: phase} = p) when phase in @early_phases do
    for {circle, name} <- Labels.circles(),
        circle in @heard_circles,
        !latest_opinion(p, circle),
        do: name
  end

  defp not_heard(_project), do: []

  defp motion(m) do
    state =
      if m.outcome,
        do: Labels.name(Labels.outcomes(), m.outcome),
        else: Labels.name(Labels.motion_statuses(), m.status)

    %{
      kind: Labels.name(Labels.motion_kinds(), m.kind),
      title: m.title,
      state: state,
      report_due_on: m.report_due_on
    }
  end

  # What stays in the hub, counted for the preview only.
  defp withheld(projects) do
    %{
      notes:
        Enum.sum_by(projects, fn p ->
          Enum.count(p.timeline, &(&1.kind == :note and !&1.in_briefing))
        end),
      cross_references: Enum.sum_by(projects, &length(&1.cross_references)),
      origins: Enum.count(projects, &(&1.origin not in [nil, ""]))
    }
  end

  ## Issued briefings

  @doc "Issued briefings, newest first, without their documents."
  @spec list_issued() :: [IssuedBriefing.t()]
  def list_issued do
    Repo.all(
      from(b in IssuedBriefing,
        order_by: [desc: b.issued_at, desc: b.id],
        select: struct(b, [:id, :issued_at])
      )
    )
  end

  @doc "The issued briefing with this id, or nil."
  @spec get_issued(integer() | String.t()) :: IssuedBriefing.t() | nil
  def get_issued(id), do: Repo.get(IssuedBriefing, id)

  @doc "When the last briefing went out, or nil."
  @spec last_issued_at() :: DateTime.t() | nil
  def last_issued_at do
    Repo.one(
      from(b in IssuedBriefing,
        order_by: [desc: b.issued_at, desc: b.id],
        limit: 1,
        select: b.issued_at
      )
    )
  end

  @doc """
  Stores the rendered document `html` as issued at `issued_at`. It stays
  retrievable and never changes; from then on „Neu seit“ counts.
  """
  @spec issue(String.t(), DateTime.t()) ::
          {:ok, IssuedBriefing.t()} | {:error, Ecto.Changeset.t()}
  def issue(html, issued_at) do
    Repo.insert(%IssuedBriefing{issued_at: DateTime.truncate(issued_at, :second), html: html})
  end

  ## Time

  @doc "A UTC time as local wall-clock time."
  @spec local(DateTime.t()) :: NaiveDateTime.t()
  def local(%DateTime{} = at) do
    at
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.universal_time_to_local_time()
    |> NaiveDateTime.from_erl!()
  end

  defp local_date(at), do: at |> local() |> NaiveDateTime.to_date()
end
