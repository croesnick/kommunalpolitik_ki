defmodule Ratsprojekte.Projects.Project do
  @moduledoc """
  A Ratsprojekt (ADR 0004): phase, next step and disposition, with its
  timeline, opinions, facts, variants, motions and cross references.
  Phases change freely; a reason in the timeline replaces a lock in code.
  The slug („Kurzname“) is the stable contract with the vault.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.{Labels, Text}

  alias Ratsprojekte.Projects.{
    CrossReference,
    Fact,
    Motion,
    NextStep,
    Opinion,
    TimelineEntry,
    Value,
    Variant
  }

  @type t :: %__MODULE__{}

  schema "projects" do
    field(:slug, :string)
    field(:title, :string)
    field(:short, :string)
    field(:origin, :string)
    field(:phase, Ecto.Enum, values: Labels.keys(Labels.phases()), default: :idea)
    field(:disposition, Ecto.Enum, values: Labels.keys(Labels.dispositions()))
    field(:disposed_on, :date)

    embeds_one(:next_step, NextStep, on_replace: :delete)
    embeds_one(:value, Value, on_replace: :update)

    has_many(:timeline, TimelineEntry, preload_order: [asc: :id])
    has_many(:opinions, Opinion, preload_order: [asc: :on, asc: :id])
    has_many(:facts, Fact, preload_order: [asc: :id])
    has_many(:variants, Variant, preload_order: [asc: :label])
    has_many(:motions, Motion, preload_order: [asc: :id])
    has_many(:cross_references, CrossReference, preload_order: [asc: :id])

    timestamps(type: :utc_datetime)
  end

  @doc "Title, short text, origin and slug of a new or edited project."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:title, :short, :origin, :slug])
    |> Text.clean_fields([:title, :short, :origin, :slug])
    |> validate_required([:title, :slug])
    |> validate_length(:title, max: 140)
    |> validate_length(:short, max: 500)
    |> validate_length(:slug, max: 80)
    |> validate_format(:slug, Text.slug_format(),
      message: "nur Kleinbuchstaben, Ziffern und Bindestriche"
    )
    |> unique_constraint(:slug, message: "ist schon vergeben")
  end
end
