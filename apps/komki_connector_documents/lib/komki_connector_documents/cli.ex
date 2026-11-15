defmodule KomkiConnectorDocuments.CLI do
  @moduledoc """
  Escript-Einstieg `komki-connector-documents` (CONTRACT.md §4):

      komki-connector-documents --socket <pfad> --documents-dir <pfad>
      komki-connector-documents --nif-check

  Liest zuerst die Credentials von stdin (eine JSON-Zeile, hier `{}`),
  bindet dann den Socket und bedient Anfragen, bis SIGTERM kommt. Log
  auf stderr, ohne Payloads. Bei Fehlern: Meldung auf stderr, Exit 1.

  Zweite Programmform (CONTRACT.md §4, #288): Der Bootstrap bringt das
  physische ex_pdfium-Verzeichnis auf den Code-Pfad, bevor irgendein
  ExPdfium-Modul laedt — im Escript-Archiv waere `priv/` gezippt und
  `dlopen` scheitert mit `errno=20`. `--nif-check` laedt pdfium und
  beendet sich mit dem Ergebnis (Exit 0/1), ohne Socket zu binden;
  `komki doctor` ruft es unter dem Profil der Instanz auf.
  """

  alias KomkiConnector.{Launch, Nif}
  alias Sidecar.Server

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    log_to_stderr()
    # Die NIF-Anwendung kommt aus dem eigenen Manifest (CONTRACT.md §5): kein
    # zweiter Ort, an dem ex_pdfium stehen koennte.
    Nif.bootstrap(program_path(), KomkiConnectorDocuments.manifest().nif)

    case parse(argv) do
      {:ok, :nif_check} -> run_nif_check()
      {:ok, socket, dir} -> serve(socket, dir)
      {:error, message} -> fail(message)
    end
  end

  # CONTRACT.md §4: Credentials von stdin, dann Socket binden und bedienen,
  # bis SIGTERM. `Launch.run/4` blockt im Erfolg; nur Fehler kehren zurueck.
  @spec serve(String.t(), String.t()) :: no_return()
  defp serve(socket, dir) do
    case Server.read_credentials() do
      {:ok, creds} -> launch(socket, dir, creds)
      {:error, message} -> fail(message)
    end
  end

  @spec launch(String.t(), String.t(), map()) :: no_return()
  defp launch(socket, dir, creds) do
    case Launch.run(KomkiConnectorDocuments, socket, dir, creds) do
      {:error, reason} -> fail(to_string_reason(reason))
    end
  end

  @doc """
  NIF-Selbstpruefung der zweiten Programmform (#288): pdfium laden und
  das Ergebnis liefern, ohne halt (`main/1` gibt es aus und beendet).
  `{:ok, version}` heisst: Verkettung und Initialisierung stehen (Phase 0
  von ex_pdfium), jede PDF-Lesung kann starten.
  """
  @spec nif_check() :: {:ok, String.t()} | {:error, String.t()}
  def nif_check do
    case ExPdfium.pdfium_version() do
      version when is_binary(version) ->
        {:ok, version}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp parse(argv) do
    case OptionParser.parse(argv,
           strict: [socket: :string, documents_dir: :string, nif_check: :boolean]
         ) do
      {opts, [], []} -> parsed(opts)
      _ -> usage()
    end
  end

  defp parsed(opts) do
    if opts[:nif_check] do
      {:ok, :nif_check}
    else
      socket_and_dir(opts)
    end
  end

  defp socket_and_dir(opts) do
    with {:ok, socket} <- required(opts, :socket, "--socket"),
         {:ok, dir} <- required(opts, :documents_dir, "--documents-dir") do
      {:ok, socket, dir}
    end
  end

  defp usage,
    do:
      {:error,
       "Aufruf: komki-connector-documents --socket <pfad> --documents-dir <pfad> | --nif-check"}

  # NIF-Selbstpruefung fuer den Doctor (Aufruf: --nif-check): eine Zeile
  # auf stdout bei Erfolg, stderr bei Fehlschlag, Exit 0/1. Die Zeilen sind
  # ASCII (Rollen laufen mit LANG=C).
  @spec run_nif_check() :: no_return()
  defp run_nif_check do
    case nif_check() do
      {:ok, version} ->
        IO.puts("pdfium ok (" <> version <> ")")
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "pdfium fehlt: " <> reason)
        System.halt(1)
    end
  end

  # Laufendes Programm; Kanonisierung (Symlinks wie ~/.local/bin/komki)
  # uebernimmt KomkiConnector.Nif. `:escript.script_name/0` gibt es nur
  # im Escript; im Mix-Kontext (Tests), im Release und unter der
  # Burrito-Einzeldatei laedt die NIF ohnehin vom korrekten Pfad —
  # Bootstrap wird No-Op.
  defp program_path do
    to_string(:escript.script_name())
  rescue
    _ -> nil
  end

  defp required(opts, key, flag) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when value != "" -> {:ok, value}
      _ -> {:error, "#{flag} fehlt"}
    end
  end

  defp to_string_reason(reason) when is_binary(reason), do: reason
  defp to_string_reason(reason), do: inspect(reason)

  # CONTRACT.md §4: Log auf stderr (komki up leitet es in die Logdatei um).
  defp log_to_stderr do
    _ = :logger.remove_handler(:default)

    _ =
      :logger.add_handler(:default, :logger_std_h, %{
        config: %{type: :standard_error},
        # Ohne explizite Filter setzt OTP fuer die ID :default nur
        # otp/sasl-Domains durch — Elixir-Logs gingen verloren.
        filter_default: :log,
        filters: [],
        formatter: Logger.default_formatter()
      })

    :ok
  end

  @spec fail(String.t()) :: no_return()
  defp fail(message) do
    IO.puts(:stderr, "komki-connector-documents: " <> message)
    System.halt(1)
  end
end
