defmodule Ratsprojekte.Projects.Value do
  @moduledoc "Benefit and success of a project („Nutzen und Erfolg“): a checklist item, no lock."

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.Text

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:proposition, :string)
    field(:success_metrics, :string)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(value, attrs) do
    value
    |> cast(attrs, [:proposition, :success_metrics])
    |> Text.clean_fields([:proposition, :success_metrics])
    |> validate_length(:proposition, max: 2000)
    |> validate_length(:success_metrics, max: 2000)
  end
end
