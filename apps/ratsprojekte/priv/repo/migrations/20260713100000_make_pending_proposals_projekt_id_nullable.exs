defmodule Ratsprojekte.Repo.Migrations.MakePendingProposalsProjektIdNullable do
  use Ecto.Migration

  # SQLite3 unterstützt kein ALTER COLUMN. Deshalb Tabelle neu aufbauen:
  # 1. foreign_keys off (während Rebuild)
  # 2. neue Tabelle mit nullable projekt_id + on_delete: :nilify_all
  # 3. Daten kopieren
  # 4. alte Tabelle droppen, neue umbenennen
  # 5. Indizes neu anlegen
  @table :pending_proposals
  @new_table :pending_proposals_new

  def up do
    execute("PRAGMA foreign_keys = OFF")

    execute("""
    CREATE TABLE #{@new_table} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      typ VARCHAR NOT NULL,
      payload JSON NOT NULL,
      begruendung TEXT NOT NULL,
      quellen TEXT,
      projekt_id BIGINT REFERENCES projekte(id) ON DELETE SET NULL,
      vorgeschlagen_von VARCHAR DEFAULT 'ai-harness' NOT NULL,
      vorgeschlagen_am DATETIME NOT NULL,
      status VARCHAR DEFAULT 'pending' NOT NULL,
      entschieden_am DATETIME,
      entschieden_von VARCHAR,
      entscheidungskommentar TEXT,
      inserted_at DATETIME NOT NULL,
      updated_at DATETIME NOT NULL
    )
    """)

    execute("""
    INSERT INTO #{@new_table}
    (id, typ, payload, begruendung, quellen, projekt_id,
     vorgeschlagen_von, vorgeschlagen_am, status,
     entschieden_am, entschieden_von, entscheidungskommentar,
     inserted_at, updated_at)
    SELECT id, typ, payload, begruendung, quellen, projekt_id,
           vorgeschlagen_von, vorgeschlagen_am, status,
           entschieden_am, entschieden_von, entscheidungskommentar,
           inserted_at, updated_at
    FROM #{@table}
    """)

    execute("DROP TABLE #{@table}")
    execute("ALTER TABLE #{@new_table} RENAME TO #{@table}")

    create(index(@table, [:projekt_id]))
    create(index(@table, [:status]))

    execute("PRAGMA foreign_key_check")
    execute("PRAGMA foreign_keys = ON")
  end

  def down do
    # Kann nicht sicher reversed werden, wenn bereits add_projekt-Vorschlaege
    # ohne projekt_id existieren.
    raise "Cannot reverse: projekt_id was made nullable for add_projekt proposals"
  end
end
