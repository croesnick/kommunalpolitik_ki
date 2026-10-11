defmodule Ratsprojekte.Repo.Migrations.AddProjectLifecycleFields do
  use Ecto.Migration

  def change do
    alter table(:projekte) do
      add(:abgeschlossen_am, :date)
      add(:verworfen_am, :date)
      add(:verworfen_grund, :text)
    end

    alter table(:vorbedingungen) do
      add(:typ, :string, default: "rechtlich", null: false)
    end
  end
end
