defmodule Ratsprojekte.Projects.Prerequisite do
  @moduledoc "A prerequisite („Vorbedingung“) of a variant: legal basis or knowledge, met or not."

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.{Labels, Text}

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:text, :string)
    field(:kind, Ecto.Enum, values: Labels.keys(Labels.prerequisite_kinds()), default: :knowledge)
    field(:met, :boolean, default: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(prerequisite, attrs) do
    prerequisite
    |> cast(attrs, [:text, :kind, :met])
    |> Text.clean_fields([:text])
    |> validate_required([:text, :kind])
    |> validate_length(:text, max: 500)
  end
end
