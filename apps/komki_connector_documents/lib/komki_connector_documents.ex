defmodule KomkiConnectorDocuments do
  @moduledoc """
  Dokument-Connector (Fassung `komki-documents/1`, Ticket #169): liest die
  Raumdokumente `<documents_dir>/<document_id>.md` fuer `admit_document`.

  Der Connector entscheidet nichts. Ob ein Dokument in den Kontext darf,
  hat der Vermittler vorher ueber die Objekt-Labels aus `room.json`
  entschieden; gerufen wird der Connector erst nach einem permit. Damit
  braucht der Vermittler keinen Lesezugriff auf die Dokumente mehr.

  Pfadhaertung: `document_id` erfuellt das Manifest-Pattern `^[a-z0-9-]+$`
  (keine Pfadtrenner, kein `..`); die Datei selbst darf kein Symlink sein.

  Zustand: `%{dir: <documents_dir>}`.
  """

  @behaviour KomkiConnector.Server

  @max_bytes 1_048_576

  @impl true
  def manifest_id, do: "documents"

  @impl true
  def init(dir) when is_binary(dir) do
    if File.dir?(dir),
      do: {:ok, %{dir: dir}},
      else: {:error, "--documents-dir ist kein Verzeichnis"}
  end

  def init(_), do: {:error, "--documents-dir fehlt"}

  @impl true
  def handle_op("read", %{"document_id" => document_id}, _context, state) do
    path = Path.join(state.dir, document_id <> ".md")

    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} when size <= @max_bytes ->
        {:ok, %{"document_id" => document_id, "content" => File.read!(path)}}

      {:ok, %File.Stat{type: :regular}} ->
        {:error, "too-large", "Dokument groesser als 1 MiB"}

      {:ok, %File.Stat{}} ->
        {:error, "forbidden-path", "kein regulaeres Dokument"}

      {:error, _} ->
        {:error, "not-found", "Dokument nicht gefunden"}
    end
  end
end
