defmodule Ratsprojekte.Repo.Migrations.CreateBriefings do
  use Ecto.Migration

  # The issued briefing („ausgegebener Stand“, #438) keeps exactly the
  # document that went out, as rendered HTML; it never changes. Settings
  # hold single values such as the editor's name.
  def change do
    create table(:issued_briefings) do
      add(:issued_at, :utc_datetime, null: false)
      add(:html, :text, null: false)
    end

    create(index(:issued_briefings, [:issued_at]))

    create table(:settings, primary_key: false) do
      add(:key, :string, primary_key: true)
      add(:value, :text, null: false)

      timestamps(type: :utc_datetime)
    end
  end
end
