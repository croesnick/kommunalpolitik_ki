defmodule Ratsprojekte.Surveys.Survey do
  @moduledoc """
  A survey („Befragung“): one question to one circle about several
  projects, with a deadline. It is the handover point to a participation
  platform (`docs/schnittstellen/befragung.md`): `public_id` is the
  opaque identifier the platform only returns, never the slug. It runs
  only once the editor confirmed the upload, and stays as a results page
  afterwards. Deadline and status stay in the hub, never in a file.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.{Labels, Text}
  alias Ratsprojekte.Surveys.SurveyTopic

  @type t :: %__MODULE__{}

  schema "surveys" do
    field(:public_id, :string)
    field(:title, :string)
    field(:question, :string)
    field(:circle, Ecto.Enum, values: Labels.keys(Labels.circles()), default: :base)
    field(:due_on, :date)
    field(:status, Ecto.Enum, values: Labels.keys(Labels.survey_statuses()), default: :preparing)
    field(:running_since, :date)
    field(:results_as_of, :utc_datetime)
    has_many(:topics, SurveyTopic, preload_order: [asc: :id])

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(survey, attrs) do
    survey
    |> cast(attrs, [:title, :question, :circle, :due_on])
    |> Text.clean_fields([:title, :question])
    |> validate_required([:title, :question, :circle, :due_on])
    |> validate_length(:title, max: 140)
    |> validate_length(:question, max: 500)
  end
end
