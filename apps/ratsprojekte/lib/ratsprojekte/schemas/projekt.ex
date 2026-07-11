defmodule Ratsprojekte.Schemas.Projekt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projekte" do
    field(:titel, :string)
    field(:beschreibung, :string)
    field(:status, Ecto.Enum, values: [:idee, :aktiv, :blockiert, :abgeschlossen], default: :idee)
    field(:prioritaet, Ecto.Enum, values: [:hoch, :mittel, :niedrig], default: :mittel)

    has_many(:blocker, Ratsprojekte.Schemas.Blocker)
    has_many(:quellen, Ratsprojekte.Schemas.Quelle, where: [blocker_id: nil])

    timestamps(type: :utc_datetime)
  end

  def changeset(projekt, attrs) do
    projekt
    |> cast(attrs, [:titel, :beschreibung, :status, :prioritaet])
    |> validate_required([:titel])
  end
end
