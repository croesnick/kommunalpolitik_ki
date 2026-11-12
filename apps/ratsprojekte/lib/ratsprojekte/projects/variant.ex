defmodule Ratsprojekte.Projects.Variant do
  @moduledoc """
  A variant („Variante“): an alternative to the same goal, with
  prerequisites and the status open, chosen or rejected with a reason.
  It replaces the former Realisierungsstrang; its legal basis became a
  prerequisite of kind `:legal`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.{Labels, Text}
  alias Ratsprojekte.Projects.{Prerequisite, Project}

  @type t :: %__MODULE__{}

  schema "variants" do
    belongs_to(:project, Project)
    field(:label, :string)
    field(:title, :string)
    field(:description, :string)
    field(:status, Ecto.Enum, values: Labels.keys(Labels.variant_statuses()), default: :open)
    field(:reason, :string)
    embeds_many(:prerequisites, Prerequisite, on_replace: :delete)

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(variant, attrs) do
    variant
    |> cast(attrs, [:label, :title, :description])
    |> Text.clean_fields([:label, :title, :description])
    |> cast_embed(:prerequisites)
    |> validate_required([:label, :title])
    |> validate_length(:label, max: 3)
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> unique_constraint([:project_id, :label], message: "gibt es schon")
  end
end
