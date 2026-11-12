defmodule Ratsprojekte.Surveys do
  @moduledoc """
  Surveys („Befragungen“): open one for several projects, confirm the
  upload, assign a return. Reading and writing the files of
  `docs/schnittstellen/befragung.md` is not part of this context; it
  takes the rows already read.
  """

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Ratsprojekte.{Projects, Repo, Text}
  alias Ratsprojekte.Projects.{Opinion, Project, TimelineEntry}
  alias Ratsprojekte.Surveys.{Survey, SurveyTopic}

  @type row :: %{
          required(:topic_id) => String.t(),
          required(:tally) => [non_neg_integer()],
          optional(:arguments) => [map()],
          required(:assign) => {:project, String.t()} | {:new, map()} | :ignore
        }

  @doc "All surveys, newest first."
  @spec list_surveys() :: [Survey.t()]
  def list_surveys do
    Repo.all(from(s in Survey, order_by: [desc: s.id], preload: [topics: :project]))
  end

  @doc "The survey with this identifier."
  @spec get_survey!(String.t()) :: Survey.t()
  def get_survey!(public_id),
    do: Survey |> Repo.get_by!(public_id: public_id) |> Repo.preload(topics: :project)

  @doc "Changeset for the form of a new survey."
  @spec change_survey(map()) :: Ecto.Changeset.t()
  def change_survey(attrs \\ %{}), do: Survey.changeset(%Survey{}, attrs)

  @doc "Opens a survey in preparation for the projects with these slugs, one topic each."
  @spec open_survey(map(), [String.t()]) :: {:ok, Survey.t()} | {:error, Ecto.Changeset.t()}
  def open_survey(attrs, slugs) do
    projects = Repo.all(from(p in Project, where: p.slug in ^slugs))

    Multi.new()
    |> Multi.insert(:survey, Survey.changeset(%Survey{public_id: identifier()}, attrs))
    |> Multi.run(:topics, fn repo, %{survey: survey} ->
      {:ok, Enum.map(projects, &repo.insert!(topic(survey, &1.id)))}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{survey: survey}} -> {:ok, get_survey!(survey.public_id)}
      {:error, _step, changeset, _done} -> {:error, changeset}
    end
  end

  @doc "The editor uploaded the package: the survey runs, each project notes it."
  @spec confirm_upload(Survey.t(), Date.t()) :: {:ok, Survey.t()}
  def confirm_upload(%Survey{status: :preparing} = survey, on \\ Projects.today()) do
    text =
      "In die Befragung „#{survey.title}“ gegeben, läuft bis #{Projects.german_date(survey.due_on)}"

    Repo.transaction(fn ->
      Repo.update!(Ecto.Changeset.change(survey, status: :running, running_since: on))

      for %SurveyTopic{project_id: id} when not is_nil(id) <- survey.topics,
          do: Repo.insert!(%TimelineEntry{project_id: id, kind: :survey, text: text, on: on})
    end)

    {:ok, get_survey!(survey.public_id)}
  end

  @doc """
  Assigns a return: each row is a topic with its tally and arguments and
  where it goes (`{:project, slug}`, `{:new, project_attrs}`, `:ignore`).
  A return older than the last one is refused; the newer one replaces
  the opinion of the same survey. `close: true` ends the survey.
  """
  @spec record_return(Survey.t(), DateTime.t(), [row()], keyword()) ::
          {:ok, Survey.t()} | {:error, :older | Ecto.Changeset.t()}
  def record_return(survey, as_of, rows, opts \\ []) do
    on = Keyword.get(opts, :on, Projects.today())

    status = if Keyword.get(opts, :close, false), do: :answered, else: survey.status

    with :ok <- newer(survey, as_of),
         {:ok, _} <-
           Repo.transaction(fn ->
             Enum.each(rows, &assign(survey, &1, on))
             as_of = DateTime.truncate(as_of, :second)
             Repo.update!(Ecto.Changeset.change(survey, results_as_of: as_of, status: status))
           end) do
      {:ok, get_survey!(survey.public_id)}
    end
  end

  defp newer(%Survey{results_as_of: nil}, _as_of), do: :ok

  defp newer(survey, as_of),
    do: if(DateTime.compare(as_of, survey.results_as_of) == :lt, do: {:error, :older}, else: :ok)

  defp assign(survey, %{assign: :ignore, topic_id: topic_id}, _on),
    do: remember(survey, topic_id, nil, true)

  defp assign(survey, %{assign: {:new, attrs}} = row, on) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put_new("origin", "Basis (Befragung „#{survey.title}“)")

    case Projects.create_project(Map.put(attrs, "on", on)) do
      {:ok, project} -> answer(survey, project, row, on)
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp assign(survey, %{assign: {:project, slug}} = row, on),
    do: answer(survey, Projects.get_project!(slug), row, on)

  defp answer(survey, project, row, on) do
    remember(survey, row.topic_id, project.id, false)
    arguments = row |> Map.get(:arguments, []) |> Enum.map(&clean_argument/1)

    case Repo.get_by(Opinion, survey_id: survey.id, project_id: project.id) do
      nil ->
        Repo.insert!(%Opinion{
          project_id: project.id,
          survey_id: survey.id,
          circle: survey.circle,
          question: survey.question,
          on: on,
          tally: row.tally,
          arguments: arguments
        })

      opinion ->
        Repo.update!(
          Ecto.Changeset.change(opinion, tally: row.tally, arguments: arguments, on: on)
        )
    end

    Repo.insert!(%TimelineEntry{
      project_id: project.id,
      kind: :return,
      text: "Rücklauf aus der Befragung „#{survey.title}“: #{Enum.sum(row.tally)} Personen",
      on: on
    })
  end

  # Arguments are free text too: stored without invisible characters.
  defp clean_argument(argument) do
    Map.new(argument, fn
      {k, v} when is_binary(v) -> {to_string(k), Text.clean(v)}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp remember(survey, topic_id, project_id, ignored) do
    case Repo.get_by(SurveyTopic, survey_id: survey.id, topic_id: topic_id) do
      nil ->
        Repo.insert!(%{topic(survey, project_id) | topic_id: topic_id, ignored: ignored})

      topic ->
        Repo.update!(Ecto.Changeset.change(topic, project_id: project_id, ignored: ignored))
    end
  end

  defp topic(survey, project_id),
    do: %SurveyTopic{survey_id: survey.id, project_id: project_id, topic_id: identifier()}

  # Opaque: 1 to 64 characters from A–Z, a–z, 0–9, _ and - (befragung.md).
  defp identifier, do: Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
end
