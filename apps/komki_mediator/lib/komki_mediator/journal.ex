defmodule KomkiMediator.Journal do
  @moduledoc """
  Getrennter Journal-Writer (R.4.4): NUR dieser Prozess beruehrt die
  PDR-Journal-Datei. Tool-Handler und Gate schreiben nichts selbst — die
  Datensaetze laufen synchron als `append` durch diesen Prozess.

  Die Datei wird einmal beim Start geoeffnet (Append-Modus) und bleibt
  offen; jeder Datensatz ist ein kanonisches JSON-Dokument
  (`KomkiPolicy.JSON.canonical`, mehrzeilig eingerueckt) mit genau einem
  finalen Newline und wird mit `:file.sync` festgehalten. Trotz der
  Endung `.jsonl` ist die Datei kein zeilenweises JSONL: Die Datensaetze
  stehen direkt hintereinander, jeder beginnt mit einer Zeile `{`. So
  bleibt jeder Datensatz byte-identisch mit seiner kanonischen Form
  (Re-Kanonisieren liefert dieselben Bytes, Ticket #133).
  Schreibfehler sind fatal: der Prozess stoppt, die `:one_for_all`-Strategie
  des Mediator-Supervisors stoppt dadurch die ganze Vermittlung — die
  Auditkette wird nie still abgedunkelt, waehrend weiter vermittelt wird.
  """

  use GenServer

  @typedoc "Fehlergrund beim Oeffnen der Journal-Datei."
  @type open_error() :: {:journal_open, term()}

  @doc "Startet den Journal-Writer unter dem Modulnamen auf dem gegebenen Pfad."
  @spec start_link(Path.t()) :: {:ok, pid()} | {:error, open_error()}
  def start_link(path) do
    GenServer.start_link(__MODULE__, path, name: __MODULE__)
  end

  @doc """
  Haengt einen PDR-Datensatz synchron an die Journal-Datei an. Rueckgabe
  :ok heisst: geschrieben und gesynct. Stirbt der Journal-Prozess, wird
  der Aufrufender mit einem Exit geworfen (fail-closed).
  """
  @spec append(GenServer.server(), map()) :: :ok
  def append(journal, record) do
    GenServer.call(journal, {:append, record})
  end

  @impl GenServer
  def init(path) do
    File.mkdir_p!(Path.dirname(path))

    case File.open(path, [:append, :binary]) do
      {:ok, fd} -> {:ok, %{fd: fd}}
      {:error, reason} -> {:stop, {:journal_open, reason}}
    end
  end

  @impl GenServer
  def handle_call({:append, record}, _from, state) do
    # Fail-closed im Schreibweg: ein nicht-vollzogener Sync stoppt den
    # Prozess — die :one_for_all-Strategie des Mediator-Supervisors
    # stoppt die Vermittlung, die Auditkette dunkelt nie ab.
    line = KomkiPolicy.JSON.canonical(record)
    :ok = IO.binwrite(state.fd, line)
    :ok = :file.sync(state.fd)
    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, %{fd: fd}), do: File.close(fd)
end
