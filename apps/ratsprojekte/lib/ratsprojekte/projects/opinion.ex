defmodule Ratsprojekte.Projects.Opinion do
  @moduledoc """
  An opinion („Meinungsbild“) of one circle on a project: date, one
  sentence, optionally a tally over five levels from „klar dagegen“ to
  „klar dafür“, and from a survey the arguments verbatim. The hub forms
  no total and no ranking.

  `statement` is what a person in the hub wrote; `arguments` are foreign
  text from a survey return and never leave for machines (ADR 0004).
  """

  use Ecto.Schema

  alias Ratsprojekte.Labels
  alias Ratsprojekte.Projects.Project
  alias Ratsprojekte.Surveys.Survey

  @type t :: %__MODULE__{}

  schema "opinions" do
    belongs_to(:project, Project)
    belongs_to(:survey, Survey)
    field(:on, :date)
    field(:circle, Ecto.Enum, values: Labels.keys(Labels.circles()))
    field(:question, :string)
    field(:statement, :string)
    field(:tally, {:array, :integer})
    field(:arguments, {:array, :map}, default: [])

    timestamps(type: :utc_datetime)
  end
end
