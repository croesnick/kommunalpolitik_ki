defmodule Ratsprojekte.Schemas.Blocker do
  use Ecto.Schema
  import Ecto.Changeset

  schema "blocker" do
    field(:titel, :string)
    field(:beschreibung, :string)

    field(:typ, Ecto.Enum,
      values: [:rechtlich, :finanziell, :politisch, :organisatorisch, :infrastruktur]
    )

    field(:status, Ecto.Enum, values: [:offen, :in_arbeit, :geloest], default: :offen)

    belongs_to(:projekt, Ratsprojekte.Schemas.Projekt)
    has_many(:quellen, Ratsprojekte.Schemas.Quelle)

    many_to_many(:depends_on, __MODULE__,
      join_through: "blocker_dependencies",
      join_keys: [blocker_id: :id, depends_on_blocker_id: :id]
    )

    many_to_many(:blocks, __MODULE__,
      join_through: "blocker_dependencies",
      join_keys: [depends_on_blocker_id: :id, blocker_id: :id]
    )

    timestamps(type: :utc_datetime)
  end

  def changeset(blocker, attrs) do
    blocker
    |> cast(attrs, [:titel, :beschreibung, :typ, :status, :projekt_id])
    |> validate_required([:titel, :typ, :projekt_id])
  end
end
