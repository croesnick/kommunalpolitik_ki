defmodule Ratsprojekte.Schemas.Schritt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "schritte" do
    field(:text, :string)
    field(:frist, :date)
    field(:position, :integer, default: 0)

    belongs_to(:realisierungsstrang, Ratsprojekte.Schemas.Realisierungsstrang)

    timestamps(type: :utc_datetime)
  end

  def changeset(schritt, attrs) do
    schritt
    |> cast(attrs, [:text, :frist, :position, :realisierungsstrang_id])
    |> validate_required([:text, :realisierungsstrang_id])
  end
end
