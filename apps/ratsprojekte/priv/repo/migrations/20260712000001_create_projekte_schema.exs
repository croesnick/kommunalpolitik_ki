defmodule Ratsprojekte.Repo.Migrations.CreateProjekteSchema do
  use Ecto.Migration

  def change do
    create table(:projekte) do
      add(:titel, :string, null: false)
      add(:beschreibung, :text)
      add(:status, :string, default: "idee", null: false)
      add(:prioritaet, :string, default: "mittel", null: false)

      timestamps(type: :utc_datetime)
    end

    create table(:blocker) do
      add(:titel, :string, null: false)
      add(:beschreibung, :text)
      add(:typ, :string, null: false)
      add(:status, :string, default: "offen", null: false)
      add(:projekt_id, references(:projekte, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:blocker, [:projekt_id]))

    create table(:blocker_dependencies, primary_key: false) do
      add(:blocker_id, references(:blocker, on_delete: :delete_all),
        null: false,
        primary_key: true
      )

      add(:depends_on_blocker_id, references(:blocker, on_delete: :delete_all),
        null: false,
        primary_key: true
      )
    end

    create(index(:blocker_dependencies, [:blocker_id]))
    create(index(:blocker_dependencies, [:depends_on_blocker_id]))

    create table(:quellen) do
      add(:typ, :string, null: false)
      add(:titel, :string, null: false)
      add(:url, :string)
      add(:paragraf, :string)
      add(:abrufdatum, :date)
      add(:projekt_id, references(:projekte, on_delete: :delete_all))
      add(:blocker_id, references(:blocker, on_delete: :delete_all))

      timestamps(type: :utc_datetime)
    end

    create(index(:quellen, [:projekt_id]))
    create(index(:quellen, [:blocker_id]))
  end
end
