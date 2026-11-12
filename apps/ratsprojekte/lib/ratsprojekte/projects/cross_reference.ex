defmodule Ratsprojekte.Projects.CrossReference do
  @moduledoc """
  A cross reference („Querverweis“) to the vault, a filing („Ablage“) or
  a komki room; for a room only its identifier. Cross references stay in
  the work view and never go into the briefing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.{Labels, Text}
  alias Ratsprojekte.Projects.Project

  @type t :: %__MODULE__{}

  schema "cross_references" do
    belongs_to(:project, Project)
    field(:kind, Ecto.Enum, values: Labels.keys(Labels.cross_reference_kinds()))
    field(:target, :string)

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(reference, attrs) do
    reference
    |> cast(attrs, [:kind, :target])
    |> Text.clean_fields([:target])
    |> validate_required([:kind, :target])
    |> validate_length(:target, max: 500)
  end
end
