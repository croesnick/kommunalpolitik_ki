defmodule Ratsprojekte.Schemas.Realisierungsstrang do
  use Ecto.Schema
  import Ecto.Changeset

  schema "realisierungsstraenge" do
    field(:label, :string)
    field(:titel, :string)
    field(:beschreibung, :string)
    field(:rechtliche_grundlage, :string)
    field(:bedingung, :string)
    field(:bedingung_erfuellt, :boolean, default: false)
    field(:position, :integer, default: 0)

    belongs_to(:projekt, Ratsprojekte.Schemas.Projekt)
    has_many(:vorbedingungen, Ratsprojekte.Schemas.Vorbedingung)
    has_many(:schritte, Ratsprojekte.Schemas.Schritt)
    has_many(:quellen, Ratsprojekte.Schemas.Quelle)

    timestamps(type: :utc_datetime)
  end

  def changeset(strang, attrs) do
    strang
    |> cast(attrs, [
      :label,
      :titel,
      :beschreibung,
      :rechtliche_grundlage,
      :bedingung,
      :bedingung_erfuellt,
      :position,
      :projekt_id
    ])
    |> validate_required([:titel, :projekt_id])
  end
end
