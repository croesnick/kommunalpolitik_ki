defmodule Ratsprojekte.Schemas.Quelle do
  use Ecto.Schema
  import Ecto.Changeset

  schema "quellen" do
    field(:typ, Ecto.Enum, values: [:sitzung, :foerderprogramm, :gesetz, :url, :zeitungsartikel])
    field(:titel, :string)
    field(:url, :string)
    field(:paragraf, :string)
    field(:abrufdatum, :date)

    belongs_to(:projekt, Ratsprojekte.Schemas.Projekt)
    belongs_to(:realisierungsstrang, Ratsprojekte.Schemas.Realisierungsstrang)

    timestamps(type: :utc_datetime)
  end

  def changeset(quelle, attrs) do
    quelle
    |> cast(attrs, [
      :typ,
      :titel,
      :url,
      :paragraf,
      :abrufdatum,
      :projekt_id,
      :realisierungsstrang_id
    ])
    |> validate_required([:typ, :titel])
  end
end
