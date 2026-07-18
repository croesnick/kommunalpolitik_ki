defmodule Ratsinfo.Store do
  @moduledoc """
  Lokale Persistenz für RIS-Daten via Ecto + SQLite3.

  Speichert Sitzungen, TOPs, Textblöcke und Dokument-Metadaten.
  Bietet Volltextsuche (FTS5) über alle extrahierten Texte.

  ## FTS5-Konfiguration

  Die Volltextsuche läuft über eine SQLite-FTS5-virtual-table (`texte`),
  angelegt in der initialen Migration mit dem Tokenizer
  `unicode61 remove_diacritics 2` (siehe
  `priv/repo/migrations/20250711000001_initial_schema.exs`).

  ### Tokenizer-Verhalten

  - `unicode61` normalisiert Nicht-ASCII-Zeichen gemäß Unicode-Regeln.
  - `remove_diacritics 2` entfernt Diakritika so aggressiv wie möglich:
    `ä/ö/ü` werden zu `a/o/u` normalisiert, ebenso `é/è/ê` → `e`.
  - **ß bleibt erhalten** (keine Auflösung zu `ss`). Eine Suche nach "Straße"
    findet also nicht "Strasse" und umgekehrt.

  ### Query-Builder (`build_fts_query/2`)

  Jeder Suchterm wird über `quote_fts_term/1` in doppelte Anführungszeichen
  gesetzt und mit `*` suffixt: `"Müll"*`. Das hat zwei Effekte:

  1. **Quoting** — FTS5-Sonderzeichen (`OR`, `AND`, `NOT`, `*`, `(`, `)`)
     werden nicht als Operatoren interpretiert. Eine Suche nach dem Wort
     `OR` findet auch wirklich das Wort `OR` und wirft keinen SQL-Error.
  2. **Präfix-Matching** — `"Müll"*` findet `Müll` und Komposita wie
     `Müllabfuhr`, `Mülltonne`. Ohne `*` matcht FTS5 nur exakte Token.

  Boolesche Verknüpfung der Terme (Default `:or`, siehe `search/2`):

      Modus      Query "Bahnhofstraße Verkehr"
      ---------  ----------------------------------
      :or        "Bahnhofstraße"* OR "Verkehr"*
      :and       "Bahnhofstraße"* AND "Verkehr"*
      :phrase    "Bahnhofstraße Verkehr"*

  ### Limitationen

  - **Kein echtes deutsches Stemming.** `unicode61` ist kein Stemmer — es
    normalisiert nur Zeichen, leitet aber keine Wortstämme ab. "Bezahlen"
    findet nicht "Bezahlung", "Haus" nicht "Häuser". `remove_diacritics 2`
    glättet zwar Umlaute, löst aber keine Flexionsformen auf.
  - **Keine Fuzzy-Suche** (Levenshtein etc.) — FTS5 bietet das nicht an.
  - **ß vs. ss** — siehe oben; ggf. Such-Query mit beiden Varianten stellen.

  ### Mögliche Erweiterung: `trigram`-Tokenizer

  SQLite bietet den `trigram`-Tokenizer, der Substring- und Fuzzy-Matches
    ermöglicht (findet "Müll" in "Müllabfuhr" auch ohne `*`, toleriert
    Tippfehler). Er wurde evaluiert, aber **nicht umgesetzt**:

  - Höherer Index-Size-Aufwand (Trigramm pro Token statt Token selbst).
  - Breaking-Change an der `texte`-Tabelle (Migration mit Rebuild).
  - Substring-Suche ist über das bestehende `*`-Präfix-Matching bereits
    für die häufigsten Use Cases (Komposita) abgedeckt.

  Falls Stemming später gebraucht wird, ist der realistischere Weg ein
  eigener Tokenizer via ICU oder portugiesische/portable Stemmer-Lib,
  nicht `trigram`. Beides out-of-scope für den MVP.
  """

  alias Ratsinfo.Repo
  alias Ratsinfo.Schemas.{Dokument, Sitzung, Textblock, TOP}
  import Ecto.Query

  @doc "Repo starten und Migrationen ausführen (für CLI-Nutzung)"
  @spec init() :: :ok | {:error, term()}
  def init do
    case Repo.open() do
      {:ok, _pid} ->
        migrate()
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Migrationen ausführen"
  def migrate do
    Ecto.Migrator.run(Repo, migrations_path(), :up, all: true)
  end

  defp migrations_path do
    Application.app_dir(:ratsinfo, "priv/repo/migrations")
  end

  @doc "Sitzung aus API-Response speichern (upsert)"
  @spec save_sitzung(map()) :: {:ok, Sitzung.t()} | {:error, Ecto.Changeset.t()}
  def save_sitzung(api_response) do
    attrs = %{
      id: api_response["id"],
      name: api_response["name"],
      gremium: api_response["committeename"],
      datum: api_response["meetingdate"],
      ort: api_response["locationname"],
      status: api_response["state"] || 0,
      client_id: api_response["clientid"],
      client_name: api_response["clientname"],
      raw_json: Jason.encode!(api_response)
    }

    %Sitzung{}
    |> Sitzung.changeset(attrs)
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: :id
    )
  end

  @doc "TOPs aus API-Response speichern"
  @spec save_tops(integer(), [map()]) :: :ok
  def save_tops(sitzung_id, tops) do
    Enum.each(tops, fn top ->
      attrs = %{
        id: top["id"],
        sitzung_id: sitzung_id,
        nummer: top["numbering"],
        titel: top["name"],
        restricted: top["restricted"] || false,
        raw_json: Jason.encode!(top)
      }

      %TOP{}
      |> TOP.changeset(attrs)
      |> Repo.insert(
        on_conflict: :replace_all,
        conflict_target: :id
      )
    end)

    :ok
  end

  @doc "Dokumente aus API-Response speichern"
  @spec save_dokumente(String.t(), integer(), [map()]) :: :ok
  def save_dokumente(top_id, sitzung_id, dokumente) do
    Enum.each(dokumente, fn doc ->
      attrs = %{
        id: doc["id"],
        top_id: top_id,
        sitzung_id: sitzung_id,
        name: doc["name"],
        fileext: doc["fileext"],
        downloaded: false
      }

      %Dokument{}
      |> Dokument.changeset(attrs)
      |> Repo.insert(
        on_conflict: :replace_all,
        conflict_target: :id
      )
    end)

    :ok
  end

  @doc "Textblöcke für Volltextsuche indexieren"
  @spec save_textbloecke(String.t(), integer(), [map()]) :: :ok
  def save_textbloecke(top_id, sitzung_id, textbloecke) do
    # Alte Textblöcke für diesen TOP löschen
    Repo.delete_all(from(t in Textblock, where: t.top_id == ^top_id))

    Enum.each(textbloecke, fn tb ->
      caption = tb["caption"] || ""
      content = decode_content(tb["content"] || "")
      id = "#{top_id}-#{caption}"

      # FTS5 unterstützt kein UPSERT — plain SQL insert
      Repo.query!(
        "INSERT INTO texte (id, top_id, caption, content, sitzung_id) VALUES (?, ?, ?, ?, ?)",
        [id, top_id, caption, content, sitzung_id]
      )
    end)

    :ok
  end

  @doc "Lokale Volltextsuche über gespeicherte Textblöcke"
  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    mode = Keyword.get(opts, :mode, :or)
    fts_query = build_fts_query(query, mode)

    sql = """
    SELECT t.id as top_id, t.titel, t.nummer, t.sitzung_id, s.name as sitzung_name,
           s.datum, s.gremium, tx.caption,
           snippet(texte, 3, '>>>', '<<<', '...', 20) as snippet
    FROM texte tx
    JOIN tops t ON tx.top_id = t.id
    JOIN sitzungen s ON t.sitzung_id = s.id
    WHERE texte MATCH ?
    ORDER BY rank
    LIMIT ?
    """

    case Repo.query(sql, [fts_query, limit]) do
      {:ok, %{rows: rows}} ->
        results =
          Enum.map(rows, fn [
                              top_id,
                              titel,
                              nummer,
                              sitzung_id,
                              sitzung_name,
                              datum,
                              gremium,
                              caption,
                              snippet
                            ] ->
            %{
              top_id: top_id,
              titel: titel,
              nummer: nummer,
              sitzung_id: sitzung_id,
              sitzung_name: sitzung_name,
              datum: datum,
              gremium: gremium,
              caption: caption,
              snippet: snippet
            }
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Alle gespeicherten Sitzungen auflisten"
  @spec list_sitzungen() :: [Sitzung.t()]
  def list_sitzungen do
    Repo.all(from(s in Sitzung, order_by: [desc: s.datum]))
  end

  @doc "Sitzung abrufen"
  @spec get_sitzung(integer()) :: Sitzung.t() | nil
  def get_sitzung(id) do
    Repo.get(Sitzung, id)
  end

  @doc "TOPs einer Sitzung abrufen"
  @spec list_tops(integer()) :: [TOP.t()]
  def list_tops(sitzung_id) do
    Repo.all(from(t in TOP, where: t.sitzung_id == ^sitzung_id, order_by: t.nummer))
  end

  @doc "Einzelnen TOP anhand seiner ID abrufen"
  @spec get_top(String.t()) :: TOP.t() | nil
  def get_top(top_id) do
    Repo.get(TOP, top_id)
  end

  @doc """
  Textblöcke eines TOPs abrufen.

  Greift direkt via SQL auf die FTS5-virtual-table `texte` zu, da `Textblock`
  ein FTS5-virtual-table-Schema ist und kein reguläres Repo.find über Ecto
  erlaubt. Liefert Maps mit `:caption` und `:content`, sortiert nach `caption`.

  Option B aus Issue #50: kein neues Schema, direktes SQL. Das passt zur
  Unix-Prinzip-Vorgabe (FTS5 bleibt intern im Store, nach außen Maps).
  """
  @spec list_textbloecke(String.t()) :: [map()]
  def list_textbloecke(top_id) do
    sql = """
    SELECT caption, content FROM texte
    WHERE top_id = ?
    ORDER BY caption
    """

    case Repo.query(sql, [top_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [caption, content] ->
          %{caption: caption, content: content}
        end)

      {:error, _} ->
        []
    end
  end

  @doc "Dokumente eines TOPs abrufen"
  @spec list_dokumente(String.t()) :: [Dokument.t()]
  def list_dokumente(top_id) do
    Repo.all(from(d in Dokument, where: d.top_id == ^top_id))
  end

  @doc "Einzelnes Dokument abrufen"
  @spec get_dokument(String.t()) :: Dokument.t() | nil
  def get_dokument(doc_id) do
    Repo.get(Dokument, doc_id)
  end

  @doc "Dokument als heruntergeladen markieren"
  @spec mark_downloaded(String.t(), String.t()) :: {:ok, Dokument.t()} | {:error, term()}
  def mark_downloaded(doc_id, local_path) do
    doc = Repo.get(Dokument, doc_id)

    doc
    |> Dokument.changeset(%{downloaded: true, lokaler_pfad: local_path})
    |> Repo.update()
  end

  @doc "Statistik über gespeicherte Daten"
  @spec stats() :: map()
  def stats do
    %{
      sitzungen: Repo.aggregate(Sitzung, :count),
      tops: Repo.aggregate(TOP, :count),
      dokumente: Repo.aggregate(Dokument, :count),
      texte: Repo.aggregate(Textblock, :count)
    }
  end

  # --- Helpers ---

  # FTS5-Query bauen: jeden Term quoten, Präfix-Matching aktivieren (`*`),
  # mehrere Terme mit dem gewählten Modus verknüpfen.
  #
  # Beispiele (`:or`):
  #   "Gansbichl"         → `"Gansbichl"*`
  #   "Wasserschutzgebiet" → `"Wasserschutzgebiet"*`
  #   "Bahnhofstraße Verkehr" → `"Bahnhofstraße"* OR "Verkehr"*`
  #
  # Beispiele (`:and`):
  #   "Bahnhofstraße Verkehr" → `"Bahnhofstraße"* AND "Verkehr"*`
  #
  # Beispiele (`:phrase`):
  #   "Bahnhofstraße Verkehr" → `"Bahnhofstraße Verkehr"*`
  #
  # Präfix-Matching (`*` nach gequotetem Term) findet "Gansbichl" in
  # "Gansbichlstraße". Ohne `*` würde FTS5 nur exakte Token-Matches finden.
  # Quoting verhindert, dass FTS5-Sonderzeichen (OR, AND, NOT, *, etc.)
  # als Operatoren interpretiert werden.
  defp build_fts_query(query, mode)

  defp build_fts_query(query, :or) when is_binary(query) do
    query
    |> String.split()
    |> Enum.map_join(" OR ", &quote_fts_term/1)
  end

  defp build_fts_query(query, :and) when is_binary(query) do
    query
    |> String.split()
    |> Enum.map_join(" AND ", &quote_fts_term/1)
  end

  defp build_fts_query(query, :phrase) when is_binary(query) do
    quote_fts_term(query)
  end

  defp build_fts_query(_, _), do: ""

  defp quote_fts_term(term) do
    # Doppelte Quotes im Term escapen (FTS5: "" inside quoted string = literal ")
    escaped = String.replace(term, "\"", "\"\"")
    "\"#{escaped}\"*"
  end

  defp decode_content(content) when is_binary(content) and byte_size(content) > 0 do
    case Base.decode64(content) do
      {:ok, decoded} -> strip_html(decoded)
      :error -> strip_html(content)
    end
  end

  defp decode_content(_), do: ""

  defp strip_html(html) do
    html
    |> HtmlEntities.decode()
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
