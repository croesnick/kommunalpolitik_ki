defmodule Ratsprojekte.Projects.NextStep do
  @moduledoc "The one next step of a project: what, who, by when. It goes into the briefing."

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.Text

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:text, :string)
    field(:assignee, :string)
    field(:due_on, :date)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step, attrs) do
    step
    |> cast(attrs, [:text, :assignee, :due_on])
    |> Text.clean_fields([:text, :assignee])
    |> validate_required([:text])
    |> validate_length(:text, max: 300)
    |> validate_length(:assignee, max: 80)
  end
end
