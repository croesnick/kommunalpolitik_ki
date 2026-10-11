defmodule Ratsprojekte.Schemas.Vorbedingung do
  use Ecto.Schema
  import Ecto.Changeset

  schema "vorbedingungen" do
    field(:text, :string)
    field(:erfuellt, :boolean, default: false)
    field(:rechtliche_grundlage, :string)
    field(:typ, Ecto.Enum, values: [:rechtlich, :wissen_fehlt], default: :rechtlich)
    field(:position, :integer, default: 0)

    belongs_to(:realisierungsstrang, Ratsprojekte.Schemas.Realisierungsstrang)

    timestamps(type: :utc_datetime)
  end

  def changeset(vorbedingung, attrs) do
    vorbedingung
    |> cast(attrs, [
      :text,
      :erfuellt,
      :rechtliche_grundlage,
      :typ,
      :position,
      :realisierungsstrang_id
    ])
    |> validate_required([:text, :realisierungsstrang_id])
  end
end
