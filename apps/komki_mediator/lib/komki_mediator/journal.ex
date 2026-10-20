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

  Manipulationsnachweis (Ticket #139, RFC 0003 R.11.4):

    * **Hash-Kette.** Der Writer ergaenzt jeden Datensatz um `seq` (Position
      in der Datei, ab 0) und `prev_hash` (SHA-256 der Bytes des
      Vorgaengers; beim ersten Datensatz `@genesis`). Beim Start liest er
      die bestehende Datei und setzt die Kette fort; eine nicht kanonische
      oder gebrochene Datei verhindert den Start (fail-closed). `verify/1`
      prueft die Kette. Aeltere Datensaetze ohne Kettenfelder (vor #139)
      sind nur als Praefix zulaessig.
    * **Append-only durch das Betriebssystem.** Mit `append_only: true`
      setzt der Writer beim Start `chflags uappnd`: Anhaengen bleibt
      moeglich, Ueberschreiben, Kuerzen und Loeschen nicht. Der Eigentuemer
      kann das Flag entfernen; die Kette macht Aenderungen dann trotzdem
      sichtbar, nur Kuerzung am Ende und vollstaendige Neuberechnung nicht.
      Dagegen helfen erst Kontrollpunkte ausserhalb der Datei (offen in #139).
  """

  use GenServer

  alias KomkiMediator.Hash
  alias KomkiPolicy.JSON

  @genesis "sha256:" <> String.duplicate("0", 64)

  @typedoc "Fehlergrund beim Start des Writers."
  @type start_error() ::
          {:journal_open, term()} | {:journal_corrupt, map()} | {:journal_flag, String.t()}

  @typedoc "Ergebnis der Kettenpruefung."
  @type verify_result() ::
          {:ok,
           %{
             records: non_neg_integer(),
             chained: non_neg_integer(),
             legacy: non_neg_integer(),
             head_hash: String.t()
           }}
          | {:error, %{index: non_neg_integer(), reason: String.t()}}

  @doc "Hash-Anker vor dem ersten Datensatz."
  @spec genesis() :: String.t()
  def genesis, do: @genesis

  @doc """
  Startet den Journal-Writer unter dem Modulnamen. `opts`:
  `append_only: true` setzt `chflags uappnd` auf die Datei.
  """
  @spec start_link(Path.t() | {Path.t(), keyword()}) :: {:ok, pid()} | {:error, start_error()}
  def start_link({path, opts}),
    do: GenServer.start_link(__MODULE__, {path, opts}, name: __MODULE__)

  def start_link(path), do: start_link({path, []})

  @doc """
  Haengt einen PDR-Datensatz synchron an die Journal-Datei an. Rueckgabe
  :ok heisst: geschrieben und gesynct. Stirbt der Journal-Prozess, wird
  der Aufrufender mit einem Exit geworfen (fail-closed).
  """
  @spec append(GenServer.server(), map()) :: :ok
  def append(journal, record) do
    GenServer.call(journal, {:append, record})
  end

  @doc """
  Zerlegt den Dateiinhalt in die Bytes der einzelnen Datensaetze. Eine
  Zeile `}` ohne Einrueckung kommt im kanonischen Text nur am Ende eines
  Datensatzes vor (innere Klammern sind eingerueckt, Strings enthalten
  keine rohen Zeilenumbrueche).
  """
  @spec split_records(binary()) :: [binary()]
  def split_records(""), do: []

  def split_records(content) do
    # Ein unvollstaendiges Ende (abgebrochener Schreibvorgang, Kuerzung
    # mitten im Datensatz) bleibt roh und faellt in der Pruefung durch,
    # statt durch das angehaengte "}" scheinbar vollstaendig zu werden.
    {complete, [tail]} = content |> String.split("\n}\n") |> Enum.split(-1)
    records = Enum.map(complete, &(&1 <> "\n}\n"))
    if tail == "", do: records, else: records ++ [tail]
  end

  @doc """
  Prueft Kanonizitaet und Hash-Kette eines Journal-Inhalts. Liefert die
  Anzahl der Datensaetze und den Kopf-Hash (Hash des letzten Datensatzes,
  Basis fuer Kontrollpunkte).
  """
  @spec verify(binary()) :: verify_result()
  def verify(content) when is_binary(content) do
    content
    |> split_records()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{prev: @genesis, chained: 0, legacy: 0}}, &verify_step/2)
    |> case do
      {:ok, acc} ->
        {:ok,
         %{
           records: acc.chained + acc.legacy,
           chained: acc.chained,
           legacy: acc.legacy,
           head_hash: acc.prev
         }}

      {:error, _} = error ->
        error
    end
  end

  defp verify_step({bytes, index}, {:ok, acc}) do
    case check_record(bytes, index, acc) do
      {:ok, acc} -> {:cont, {:ok, %{acc | prev: Hash.sha256_hex(bytes)}}}
      {:error, reason} -> {:halt, {:error, %{index: index, reason: reason}}}
    end
  end

  defp check_record(bytes, index, acc) do
    with {:ok, record} <- parse(bytes),
         :ok <- canonical(record, bytes) do
      check_chain(record, index, acc)
    end
  end

  defp parse(bytes) do
    case JSON.parse(bytes) do
      {:ok, record} when is_map(record) -> {:ok, record}
      _ -> {:error, "kein JSON-Objekt"}
    end
  end

  defp canonical(record, bytes) do
    if JSON.canonical(record) == bytes, do: :ok, else: {:error, "nicht kanonisch"}
  end

  # Kettenfelder per Map.fetch statt Pattern-Match: KomkiPolicy.JSON
  # typisiert Objekte als %{}, Dialyzer verwirft sonst den Schluessel-Match.
  defp check_chain(record, index, acc) do
    case {Map.fetch(record, "seq"), Map.fetch(record, "prev_hash")} do
      {{:ok, seq}, {:ok, prev}} -> check_link(seq, prev, index, acc)
      _ when acc.chained == 0 -> {:ok, %{acc | legacy: acc.legacy + 1}}
      _ -> {:error, "Datensatz ohne Kettenfelder nach Beginn der Kette"}
    end
  end

  defp check_link(seq, prev, index, acc) do
    cond do
      seq != index -> {:error, "seq " <> inspect(seq) <> " an Position " <> to_string(index)}
      prev != acc.prev -> {:error, "prev_hash passt nicht zum Vorgaenger"}
      true -> {:ok, %{acc | chained: acc.chained + 1}}
    end
  end

  @impl GenServer
  def init({path, opts}) do
    File.mkdir_p!(Path.dirname(path))

    with {:ok, head} <- read_head(path),
         {:ok, fd} <- open(path),
         :ok <- maybe_append_only(path, Keyword.get(opts, :append_only, false)) do
      {:ok, %{fd: fd, seq: head.records, prev_hash: head.head_hash}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp read_head(path) do
    content =
      case File.read(path) do
        {:ok, content} -> content
        {:error, :enoent} -> ""
        {:error, reason} -> {:error, reason}
      end

    with content when is_binary(content) <- content,
         {:ok, head} <- verify(content) do
      {:ok, head}
    else
      {:error, %{} = detail} -> {:error, {:journal_corrupt, detail}}
      {:error, reason} -> {:error, {:journal_open, reason}}
    end
  end

  defp open(path) do
    case File.open(path, [:append, :binary]) do
      {:ok, fd} -> {:ok, fd}
      {:error, reason} -> {:error, {:journal_open, reason}}
    end
  end

  defp maybe_append_only(_path, false), do: :ok

  defp maybe_append_only(path, true) do
    case System.cmd("/usr/bin/chflags", ["uappnd", path], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _} -> {:error, {:journal_flag, String.trim(out)}}
    end
  end

  @impl GenServer
  def handle_call({:append, record}, _from, state) do
    # Fail-closed im Schreibweg: ein nicht-vollzogener Sync stoppt den
    # Prozess — die :one_for_all-Strategie des Mediator-Supervisors
    # stoppt die Vermittlung, die Auditkette dunkelt nie ab.
    bytes =
      record
      |> Map.merge(%{"seq" => state.seq, "prev_hash" => state.prev_hash})
      |> JSON.canonical()

    :ok = IO.binwrite(state.fd, bytes)
    :ok = :file.sync(state.fd)
    {:reply, :ok, %{state | seq: state.seq + 1, prev_hash: Hash.sha256_hex(bytes)}}
  end

  @impl GenServer
  def terminate(_reason, %{fd: fd}), do: File.close(fd)
end
