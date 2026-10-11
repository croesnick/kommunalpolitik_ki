defmodule Ratsinfo.Repo.Migrations.InitialSchema do
  use Ecto.Migration

  def up do
    create table(:sitzungen, primary_key: false) do
      add :id, :integer, primary_key: true
      add :name, :string, null: false
      add :gremium, :string
      add :datum, :string
      add :ort, :string
      add :status, :integer, default: 0
      add :client_id, :integer
      add :client_name, :string
      add :raw_json, :string
      add :synced_at, :utc_datetime
    end

    create table(:tops, primary_key: false) do
      add :id, :string, primary_key: true
      add :sitzung_id, :integer, null: false
      add :nummer, :string
      add :titel, :string
      add :restricted, :boolean, default: false
      add :raw_json, :string
    end

    create table(:dokumente, primary_key: false) do
      add :id, :string, primary_key: true
      add :top_id, :string, null: false
      add :sitzung_id, :integer
      add :name, :string
      add :fileext, :string
      add :lokaler_pfad, :string
      add :downloaded, :boolean, default: false
    end

    # FTS5 virtual table for full-text search
    # This is raw SQL because Ecto doesn't support virtual tables natively
    execute """
    CREATE VIRTUAL TABLE texte USING fts5(
      id,
      top_id,
      caption,
      content,
      sitzung_id UNINDEXED,
      tokenize='unicode61 remove_diacritics 2'
    )
    """

    create index(:tops, [:sitzung_id])
    create index(:dokumente, [:top_id])
    create index(:dokumente, [:sitzung_id])
  end

  def down do
    drop table(:sitzungen)
    drop table(:tops)
    drop table(:dokumente)
    execute "DROP TABLE IF EXISTS texte"
  end
end
