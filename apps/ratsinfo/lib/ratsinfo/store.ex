defmodule Ratsinfo.Store do
  @moduledoc """
  Lokale SQLite-Persistenz für RIS-Daten.

  Speichert Sitzungen, TOPs, Textblöcke und Dokument-Metadaten.
  Bietet Volltextsuche (FTS5) über alle extrahierten Texte.

  Schema:
  - sitzungen: id, name, gremium, datum, ort, status, client_id, client_name, raw_json
  - tops: id, sitzung_id, nummer, titel, restricted, raw_json
  - dokumente: id, top_id, name, fileext, lokaler_pfad, downloaded
  - texte: id, top_id, caption, content (FTS5-virtual-table für Volltextsuche)
  """

  alias Exqlite.Basic

  @db_path_default Path.join(System.user_home!(), ".local/share/ratsinfo/ratsinfo.db")

  @doc "Standard-Datenbankpfad"
  def db_path, do: @db_path_default

  @doc "Datenbank öffnen/erstellen und Schema migrieren"
  @spec open(String.t()) :: {:ok, Exqlite.Connection.t()} | {:error, term()}
  def open(path \\ db_path()) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    case Basic.connect(path) do
      {:ok, conn} ->
        migrate(conn)
        {:ok, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Schema erstellen (idempotent)"
  def migrate(conn) do
    statements = [
      """
      CREATE TABLE IF NOT EXISTS sitzungen (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        gremium TEXT,
        datum TEXT,
        ort TEXT,
        status INTEGER DEFAULT 0,
        client_id INTEGER,
        client_name TEXT,
        raw_json TEXT,
        synced_at TEXT DEFAULT (datetime('now'))
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS tops (
        id TEXT PRIMARY KEY,
        sitzung_id INTEGER NOT NULL,
        nummer TEXT,
        titel TEXT,
        restricted INTEGER DEFAULT 0,
        raw_json TEXT,
        FOREIGN KEY (sitzung_id) REFERENCES sitzungen(id)
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS dokumente (
        id TEXT PRIMARY KEY,
        top_id TEXT,
        sitzung_id INTEGER,
        name TEXT,
        fileext TEXT,
        lokaler_pfad TEXT,
        downloaded INTEGER DEFAULT 0,
        FOREIGN KEY (top_id) REFERENCES tops(id)
      )
      """,
      """
      CREATE VIRTUAL TABLE IF NOT EXISTS texte USING fts5(
        top_id,
        caption,
        content,
        sitzung_id UNINDEXED,
        tokenize='unicode61 remove_diacritics 2'
      )
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_tops_sitzung ON tops(sitzung_id)
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_dokumente_top ON dokumente(top_id)
      """,
      """
      CREATE INDEX IF NOT EXISTS idx_dokumente_sitzung ON dokumente(sitzung_id)
      """
    ]

    Enum.each(statements, fn sql ->
      {:ok, _} = Basic.exec(conn, sql)
    end)

    :ok
  end

  @doc "Sitzung speichern (upsert)"
  @spec save_sitzung(Exqlite.Connection.t(), map()) :: :ok | {:error, term()}
  def save_sitzung(conn, sitzung) do
    id = sitzung["id"]
    name = sitzung["name"]
    gremium = sitzung["committeename"]
    datum = sitzung["meetingdate"]
    ort = sitzung["locationname"]
    status = sitzung["state"] || 0
    client_id = sitzung["clientid"]
    client_name = sitzung["clientname"]
    raw = Jason.encode!(sitzung)

    sql = """
    INSERT INTO sitzungen (id, name, gremium, datum, ort, status, client_id, client_name, raw_json, synced_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(id) DO UPDATE SET
      name = excluded.name,
      gremium = excluded.gremium,
      datum = excluded.datum,
      ort = excluded.ort,
      status = excluded.status,
      client_id = excluded.client_id,
      client_name = excluded.client_name,
      raw_json = excluded.raw_json,
      synced_at = datetime('now')
    """

    {:ok, _} = Basic.exec(conn, sql, [id, name, gremium, datum, ort, status, client_id, client_name, raw])
    :ok
  end

  @doc "TOPs einer Sitzung speichern"
  @spec save_tops(Exqlite.Connection.t(), integer(), [map()]) :: :ok
  def save_tops(conn, sitzung_id, tops) do
    Enum.each(tops, fn top ->
      id = top["id"]
      nummer = top["numbering"]
      titel = top["name"]
      restricted = if(top["restricted"], do: 1, else: 0)
      raw = Jason.encode!(top)

      sql = """
      INSERT INTO tops (id, sitzung_id, nummer, titel, restricted, raw_json)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        nummer = excluded.nummer,
        titel = excluded.titel,
        restricted = excluded.restricted,
        raw_json = excluded.raw_json
      """

      {:ok, _} = Basic.exec(conn, sql, [id, sitzung_id, nummer, titel, restricted, raw])
    end)

    :ok
  end

  @doc "Dokumente eines TOPs speichern"
  @spec save_dokumente(Exqlite.Connection.t(), String.t(), integer(), [map()]) :: :ok
  def save_dokumente(conn, top_id, sitzung_id, dokumente) do
    Enum.each(dokumente, fn doc ->
      id = doc["id"]
      name = doc["name"]
      fileext = doc["fileext"]

      sql = """
      INSERT INTO dokumente (id, top_id, sitzung_id, name, fileext, downloaded)
      VALUES (?, ?, ?, ?, ?, 0)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        fileext = excluded.fileext
      """

      {:ok, _} = Basic.exec(conn, sql, [id, top_id, sitzung_id, name, fileext])
    end)

    :ok
  end

  @doc "Textblöcke eines TOPs für Volltextsuche indexieren"
  @spec save_textbloecke(Exqlite.Connection.t(), String.t(), integer(), [map()]) :: :ok
  def save_textbloecke(conn, top_id, sitzung_id, textbloecke) do
    # Alte Textblöcke für diesen TOP löschen (FTS5 hat kein ON CONFLICT)
    {:ok, _} = Basic.exec(conn, "DELETE FROM texte WHERE top_id = ?", [top_id])

    Enum.each(textbloecke, fn tb ->
      caption = tb["caption"] || ""
      content = decode_content(tb["content"] || "")
      fts_id = "#{top_id}-#{caption}"

      sql = """
      INSERT INTO texte (top_id, caption, content, sitzung_id)
      VALUES (?, ?, ?, ?)
      """

      {:ok, _} = Basic.exec(conn, sql, [top_id, caption, content, sitzung_id])
    end)

    :ok
  end

  @doc "Lokale Volltextsuche über gespeicherte Textblöcke"
  @spec search(Exqlite.Connection.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(conn, query, _opts \\ []) do
    sql = """
    SELECT t.titel, t.nummer, t.sitzung_id, s.name as sitzung_name, s.datum, s.gremium,
           text.caption, snippet(texte, 2, '>>>', '<<<', '...', 20) as snippet
    FROM texte
    JOIN tops t ON texte.top_id = t.id
    JOIN sitzungen s ON t.sitzung_id = s.id
    WHERE texte MATCH ?
    ORDER BY rank
    LIMIT 50
    """

    case Basic.exec(conn, sql, [query]) do
      {:ok, _} ->
        {:ok, rows} = Basic.all(conn)
        {:ok, Enum.map(rows, &row_to_search_result/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Alle gespeicherten Sitzungen auflisten"
  @spec list_sitzungen(Exqlite.Connection.t()) :: {:ok, [map()]}
  def list_sitzungen(conn) do
    sql = """
    SELECT id, name, gremium, datum, ort, client_name, synced_at
    FROM sitzungen
    ORDER BY datum DESC
    """

    {:ok, _} = Basic.exec(conn, sql)
    {:ok, rows} = Basic.all(conn)
    {:ok, Enum.map(rows, &row_to_sitzung/1)}
  end

  @doc "Sitzungsdetails abrufen (aus lokaler DB)"
  @spec get_sitzung(Exqlite.Connection.t(), integer()) :: {:ok, map()} | {:error, :not_found}
  def get_sitzung(conn, id) do
    sql = """
    SELECT s.id, s.name, s.gremium, s.datum, s.ort, s.client_name, s.raw_json
    FROM sitzungen s
    WHERE s.id = ?
    """

    {:ok, _} = Basic.exec(conn, sql, [id])

    case Basic.all(conn) do
      {:ok, [row | _]} -> {:ok, row_to_sitzung_detail(row)}
      {:ok, []} -> {:error, :not_found}
    end
  end

  @doc "TOPs einer Sitzung abrufen (aus lokaler DB)"
  @spec list_tops(Exqlite.Connection.t(), integer()) :: {:ok, [map()]}
  def list_tops(conn, sitzung_id) do
    sql = """
    SELECT id, sitzung_id, nummer, titel, restricted
    FROM tops
    WHERE sitzung_id = ?
    ORDER BY CAST(nummer AS REAL)
    """

    {:ok, _} = Basic.exec(conn, sql, [sitzung_id])
    {:ok, rows} = Basic.all(conn)
    {:ok, Enum.map(rows, &row_to_top/1)}
  end

  @doc "Markiere Dokument als heruntergeladen"
  @spec mark_downloaded(Exqlite.Connection.t(), String.t(), String.t()) :: :ok
  def mark_downloaded(conn, doc_id, local_path) do
    {:ok, _} = Basic.exec(
      conn,
      "UPDATE dokumente SET downloaded = 1, lokaler_pfad = ? WHERE id = ?",
      [local_path, doc_id]
    )
    :ok
  end

  @doc "Anzahl gespeicherter Datensätze"
  @spec stats(Exqlite.Connection.t()) :: map()
  def stats(conn) do
    {:ok, _} = Basic.exec(conn, "SELECT COUNT(*) FROM sitzungen")
    {:ok, [[sitzungen]]} = Basic.all(conn)

    {:ok, _} = Basic.exec(conn, "SELECT COUNT(*) FROM tops")
    {:ok, [[tops]]} = Basic.all(conn)

    {:ok, _} = Basic.exec(conn, "SELECT COUNT(*) FROM dokumente")
    {:ok, [[dokumente]]} = Basic.all(conn)

    {:ok, _} = Basic.exec(conn, "SELECT COUNT(*) FROM texte")
    {:ok, [[texte]]} = Basic.all(conn)

    %{sitzungen: sitzungen, tops: tops, dokumente: dokumente, texte: texte}
  end

  # --- Helpers ---

  # Content kann base64-codiertes HTML sein (aus der API)
  defp decode_content(content) when is_binary(content) and byte_size(content) > 0 do
    case Base.decode64(content) do
      {:ok, decoded} -> strip_html(decoded)
      :error -> strip_html(content)
    end
  end

  defp decode_content(_), do: ""

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp row_to_search_result([titel, nummer, sitzung_id, sitzung_name, datum, gremium, caption, snippet]) do
    %{
      titel: titel,
      nummer: nummer,
      sitzung_id: sitzung_id,
      sitzung_name: sitzung_name,
      datum: datum,
      gremium: gremium,
      caption: caption,
      snippet: snippet
    }
  end

  defp row_to_sitzung([id, name, gremium, datum, ort, client_name, synced_at]) do
    %{id: id, name: name, gremium: gremium, datum: datum, ort: ort, client_name: client_name, synced_at: synced_at}
  end

  defp row_to_sitzung_detail([id, name, gremium, datum, ort, client_name, raw_json]) do
    %{id: id, name: name, gremium: gremium, datum: datum, ort: ort, client_name: client_name, raw: raw_json}
  end

  defp row_to_top([id, sitzung_id, nummer, titel, restricted]) do
    %{id: id, sitzung_id: sitzung_id, nummer: nummer, titel: titel, restricted: restricted == 1}
  end
end
