defmodule Ratsprojekte.Surveys.SurveyTopic do
  @moduledoc """
  A topic of a survey: its opaque `topic_id` and where it leads. Topics
  from the package lead to the project they came from; a topic someone
  proposed on the platform is assigned once (new idea, existing project
  or `ignored`), and the hub remembers that by its identifier.
  """

  use Ecto.Schema

  alias Ratsprojekte.Projects.Project
  alias Ratsprojekte.Surveys.Survey

  @type t :: %__MODULE__{}

  schema "survey_topics" do
    belongs_to(:survey, Survey)
    belongs_to(:project, Project)
    field(:topic_id, :string)
    field(:ignored, :boolean, default: false)

    timestamps(type: :utc_datetime)
  end
end
