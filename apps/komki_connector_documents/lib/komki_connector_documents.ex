defmodule KomkiConnectorDocuments do
  @moduledoc """
  Documents connector (version `komki-documents/1`, ticket #169): reads the
  room documents `<documents_dir>/<document_id>.md` and, since #290,
  `<documents_dir>/<document_id>.pdf` for `admit_document`.

  The connector decides nothing. The mediator has already decided via the
  object labels from `room.json` whether a document may enter the context;
  the connector is only called after a permit, so the mediator itself needs
  no read access to the documents.

  Path hardening: `document_id` matches the manifest pattern `^[a-z0-9-]+$`
  (no separators, no `..`), and the file itself must not be a symlink.
  Markdown wins over a PDF of the same name; intake keeps a single format
  per object ID, so both never coexist in a room.

  PDFs are rendered by `KomkiConnectorDocuments.Pdf` (license and NIF
  origin are documented there). Its NIF cannot load in an escript; the
  read then fails with a clear error until #288 settles the program form.

  State: `%{dir: <documents_dir>}`.
  """

  @behaviour Sidecar.Server

  alias KomkiConnectorDocuments.Pdf

  @max_bytes 1_048_576

  # ex_pdfium parses the whole file in memory in the connector process
  # (no memory limit in the profile); 64 MiB covers scanned council papers.
  @max_pdf_file_bytes 64 * 1024 * 1024

  @impl true
  def manifest, do: KomkiConnector.Manifest.sidecar!("documents")

  @impl true
  def init(dir) when is_binary(dir) do
    if File.dir?(dir),
      do: {:ok, %{dir: dir}},
      else: {:error, "--documents-dir ist kein Verzeichnis"}
  end

  def init(_), do: {:error, "--documents-dir fehlt"}

  @impl true
  def handle_op("read", %{"document_id" => document_id}, _context, state) do
    with {:ok, format, stat} <- resolve(state.dir, document_id),
         {:ok, content} <- read(format, stat) do
      {:ok, %{"document_id" => document_id, "content" => content}}
    end
  end

  # Markdown first, then PDF; a non-regular entry (symlink, directory)
  # stops the lookup instead of falling through.
  defp resolve(dir, document_id) do
    Enum.find_value([md: ".md", pdf: ".pdf"], {:error, "not-found", "Dokument nicht gefunden"}, fn
      {format, ext} ->
        path = Path.join(dir, document_id <> ext)

        case File.lstat(path) do
          {:ok, %File.Stat{type: :regular, size: size}} ->
            {:ok, format, %{path: path, size: size}}

          {:ok, %File.Stat{}} ->
            {:error, "forbidden-path", "kein regulaeres Dokument"}

          {:error, _} ->
            nil
        end
    end)
  end

  defp read(:md, %{size: size}) when size > @max_bytes,
    do: {:error, "too-large", "Dokument groesser als 1 MiB"}

  defp read(:md, %{path: path}), do: {:ok, File.read!(path)}

  defp read(:pdf, %{size: size}) when size > @max_pdf_file_bytes,
    do: {:error, "too-large", "PDF-Datei groesser als 64 MiB"}

  defp read(:pdf, %{path: path}), do: Pdf.render(path)
end
