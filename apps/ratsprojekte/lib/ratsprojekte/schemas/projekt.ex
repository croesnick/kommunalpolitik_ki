defmodule Ratsprojekte.Schemas.Projekt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projekte" do
    field(:titel, :string)
    field(:beschreibung, :string)
    field(:status, Ecto.Enum, values: [:idee, :aktiv, :abgeschlossen], default: :idee)
    field(:prioritaet, Ecto.Enum, values: [:hoch, :mittel, :niedrig], default: :mittel)
    field(:beschlussvorschlag, :string)
    field(:adressat, :string)

    has_many(:realisierungsstraenge, Ratsprojekte.Schemas.Realisierungsstrang)
    has_many(:quellen, Ratsprojekte.Schemas.Quelle, where: [realisierungsstrang_id: nil])

    timestamps(type: :utc_datetime)
  end

  def changeset(projekt, attrs) do
    projekt
    |> cast(attrs, [:titel, :beschreibung, :status, :prioritaet, :beschlussvorschlag, :adressat])
    |> validate_required([:titel])
  end
end
