defmodule Ratsprojekte.Repo.Migrations.ReworkToRealisierungsstraenge do
  use Ecto.Migration

  def up do
    # Drop old tables
    drop_if_exists(table(:blocker_dependencies))
    drop_if_exists(table(:quellen))
    drop_if_exists(table(:blocker))

    # Realisierungsstränge
    create table(:realisierungsstraenge) do
      add(:label, :string)
      add(:titel, :string, null: false)
      add(:beschreibung, :text)
      add(:rechtliche_grundlage, :string)
      add(:bedingung, :text)
      add(:bedingung_erfuellt, :boolean, default: false, null: false)
      add(:position, :integer, default: 0)
      add(:projekt_id, references(:projekte, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:realisierungsstraenge, [:projekt_id]))

    # Vorbedingungen
    create table(:vorbedingungen) do
      add(:text, :string, null: false)
      add(:erfuellt, :boolean, default: false, null: false)
      add(:rechtliche_grundlage, :string)
      add(:position, :integer, default: 0)

      add(:realisierungsstrang_id, references(:realisierungsstraenge, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime)
    end

    create(index(:vorbedingungen, [:realisierungsstrang_id]))

    # Schritte
    create table(:schritte) do
      add(:text, :string, null: false)
      add(:frist, :date)
      add(:position, :integer, default: 0)

      add(:realisierungsstrang_id, references(:realisierungsstraenge, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime)
    end

    create(index(:schritte, [:realisierungsstrang_id]))

    # Quellen (new schema with realisierungsstrang_id)
    create table(:quellen) do
      add(:typ, :string, null: false)
      add(:titel, :string, null: false)
      add(:url, :string)
      add(:paragraf, :string)
      add(:abrufdatum, :date)
      add(:projekt_id, references(:projekte, on_delete: :delete_all))
      add(:realisierungsstrang_id, references(:realisierungsstraenge, on_delete: :delete_all))

      timestamps(type: :utc_datetime)
    end

    create(index(:quellen, [:projekt_id]))
    create(index(:quellen, [:realisierungsstrang_id]))
  end

  def down do
    drop_if_exists(table(:quellen))
    drop_if_exists(table(:schritte))
    drop_if_exists(table(:vorbedingungen))
    drop_if_exists(table(:realisierungsstraenge))
  end
end
