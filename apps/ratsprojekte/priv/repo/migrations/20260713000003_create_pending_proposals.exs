defmodule Ratsprojekte.Repo.Migrations.CreatePendingProposals do
  use Ecto.Migration

  def change do
    create table(:pending_proposals) do
      # Was wird vorgeschlagen?
      add(:typ, :string, null: false)
      add(:payload, :map, null: false)
      add(:begruendung, :text, null: false)
      add(:quellen, :text)

      # Fuer welches Projekt?
      add(:projekt_id, references(:projekte, on_delete: :delete_all), null: false)

      # Audit-Trail
      add(:vorgeschlagen_von, :string, default: "ai-harness", null: false)
      add(:vorgeschlagen_am, :utc_datetime, null: false)
      add(:status, :string, default: "pending", null: false)
      add(:entschieden_am, :utc_datetime)
      add(:entschieden_von, :string)
      add(:entscheidungskommentar, :text)

      timestamps(type: :utc_datetime)
    end

    create(index(:pending_proposals, [:projekt_id]))
    create(index(:pending_proposals, [:status]))
  end
end
