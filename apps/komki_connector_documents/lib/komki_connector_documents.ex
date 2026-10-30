defmodule KomkiConnectorDocuments do
  @moduledoc """
  Dokument-Connector (Fassung `komki-documents/1`, Ticket #169): liest die
  Raumdokumente `<documents_dir>/<document_id>.md` und seit #290 auch
  `<documents_dir>/<document_id>.pdf` fuer `admit_document`.

  Der Connector entscheidet nichts. Ob ein Dokument in den Kontext darf,
  hat der Vermittler vorher ueber die Objekt-Labels aus `room.json`
  entschieden; gerufen wird der Connector erst nach einem permit. Damit
  braucht der Vermittler keinen Lesezugriff auf die Dokumente mehr.

  Pfadhaertung: `document_id` erfuellt das Manifest-Pattern `^[a-z0-9-]+$`
  (keine Pfadtrenner, kein `..`); die Datei selbst darf kein Symlink sein.
  Bei gleichem Namen gewinnen Markdown-Dateien vor PDFs — die Aufnahme
  vergibt eine Objekt-ID je Inhalt (R.2.1), beide Formen derselben ID
  koennen darum nicht als Objekte im Raum liegen.

  PDFs liest `KomkiConnectorDocuments.Pdf`: Text je Seite mit
  Seitenanker, dazu die Highlights mit Kommentar und markiertem Text;
  Lizenz und Herkunft des NIF stehen im Moduledoc dort. Die PDF-Form
  braucht einen NIF, der im Escript-Kontext nicht ladbar ist — die
  Antwort ist dann ein klarer Fehler, die Programmform entscheidet #288.

  Zustand: `%{dir: <documents_dir>}`.
  """

  @behaviour Sidecar.Server

  alias KomkiConnectorDocuments.Pdf

  @max_bytes 1_048_576

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
    case resolve(state.dir, document_id) do
      {:md, file} -> read_markdown(document_id, file)
      {:pdf, file} -> read_pdf(document_id, file)
      {:error, code, detail} -> {:error, code, detail}
    end
  end

  # Markdown zuerst, dann PDF; ein Treffer ungleicher Art (Symlink,
  # Verzeichnis) gewinnt vor dem Weitersehen.
  defp resolve(dir, document_id) do
    case take(dir, document_id, ".md") do
      :missing -> take_or_missing(dir, document_id, ".pdf", :pdf)
      {:ok, file} -> {:md, file}
      {:error, _code, _detail} = error -> error
    end
  end

  defp take_or_missing(dir, document_id, ext, kind) do
    case take(dir, document_id, ext) do
      :missing -> {:error, "not-found", "Dokument nicht gefunden"}
      {:ok, file} -> {kind, file}
      {:error, _code, _detail} = error -> error
    end
  end

  defp take(dir, document_id, ext) do
    path = Path.join(dir, document_id <> ext)

    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} -> {:ok, %{path: path, size: size}}
      {:ok, %File.Stat{}} -> {:error, "forbidden-path", "kein regulaeres Dokument"}
      {:error, _} -> :missing
    end
  end

  defp read_markdown(document_id, %{path: path, size: size}) do
    if size > @max_bytes,
      do: {:error, "too-large", "Dokument groesser als 1 MiB"},
      else: {:ok, %{"document_id" => document_id, "content" => File.read!(path)}}
  end

  defp read_pdf(document_id, %{path: path}) do
    case Pdf.render(path) do
      {:ok, content} -> {:ok, %{"document_id" => document_id, "content" => content}}
      {:error, code, detail} -> {:error, code, detail}
    end
  end
end
