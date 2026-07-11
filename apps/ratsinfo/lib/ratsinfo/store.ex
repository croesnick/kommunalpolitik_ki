defmodule Ratsinfo.Store do
  @moduledoc """
  Lokale Persistenz für RIS-Daten via Ecto + SQLite3.

  Speichert Sitzungen, TOPs, Textblöcke und Dokument-Metadaten.
  Bietet Volltextsuche (FTS5) über alle extrahierten Texte.
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

    sql = """
    SELECT t.titel, t.nummer, t.sitzung_id, s.name as sitzung_name,
           s.datum, s.gremium, tx.caption,
           snippet(texte, 3, '>>>', '<<<', '...', 20) as snippet
    FROM texte tx
    JOIN tops t ON tx.top_id = t.id
    JOIN sitzungen s ON t.sitzung_id = s.id
    WHERE texte MATCH ?
    ORDER BY rank
    LIMIT ?
    """

    case Repo.query(sql, [query, limit]) do
      {:ok, %{rows: rows}} ->
        results =
          Enum.map(rows, fn [
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

  @doc "Dokumente eines TOPs abrufen"
  @spec list_dokumente(String.t()) :: [Dokument.t()]
  def list_dokumente(top_id) do
    Repo.all(from(d in Dokument, where: d.top_id == ^top_id))
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
end
