defmodule KomkiMediator.GoStand do
  @moduledoc """
  Offenlegungsstand `komki-stand/1` des Vermittlers (Ticket #98, CONTRACT
  §2.7): der Mini-Ledger der verbrauchten GO-Noncen. Die Engine fuehrt
  keinen Stand (§9, B.8), der Vermittler ist der Vollzug.

  * `current/0` liefert den Stand mit `as_of` = jetzt (Unix-Sekunden, die
    logische Zeit der Frische-Fenster).
  * `advance/1` committet den Verbrauch ueber `KomkiPolicy.Stand.advance/2`
    (Compare-and-Swap ueber die Version) und schreibt den neuen Stand nach
    `<go_dir>/stand.json`, bevor die Antwort kommt. Scheitert das
    Schreiben, gilt die Nonce als nicht committet: keine Wirkung.

  Der Prozess serialisiert alle Uebergaenge; zwei Ausfuehrungen desselben
  GOs verliert genau eine (`nonce_already_consumed`).
  """

  use GenServer

  alias KomkiPolicy.{JSON, Stand}

  @stand_id "go-stand"

  @doc "Startet den Stand fuer `%{dir: go_dir, scope: scope}`."
  @spec start_link(%{dir: Path.t(), scope: String.t()}) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Aktueller Stand (JSON-Datensatz) mit `as_of` = jetzt."
  @spec current() :: map()
  def current, do: GenServer.call(__MODULE__, :current)

  @doc "Committet einen Verbrauchs-Vorschlag (`release`-Objekt der Permit-Entscheidung)."
  @spec advance(map()) :: {:ok, map()} | {:refused, map()} | {:error, term()}
  def advance(proposal), do: GenServer.call(__MODULE__, {:advance, proposal})

  @doc "Pfad der Stand-Datei unter dem GO-Verzeichnis."
  @spec path(Path.t()) :: Path.t()
  def path(dir), do: Path.join(dir, "stand.json")

  @impl GenServer
  def init(%{dir: dir, scope: scope}) do
    File.mkdir_p!(dir)
    {:ok, %{dir: dir, stand: load(path(dir), scope)}}
  end

  @impl GenServer
  def handle_call(:current, _from, state), do: {:reply, now(state.stand), state}

  def handle_call({:advance, proposal}, _from, state) do
    with {:ok, next} <- Stand.advance(now(state.stand), proposal),
         record = Stand.to_record(next),
         :ok <- persist(state.dir, record) do
      {:reply, {:ok, record}, %{state | stand: record}}
    else
      {:refused, refusal} -> {:reply, {:refused, refusal}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # Ein vorhandener Stand gilt nur fuer denselben Geltungsbereich; ein
  # fremder oder kaputter Stand bricht den Start ab (fail-closed), statt
  # verbrauchte Noncen still zu vergessen.
  defp load(file, scope) do
    case File.read(file) do
      {:ok, content} ->
        {:ok, term} = JSON.parse(content)
        {:ok, stand} = Stand.validate(term)
        if stand.scope != scope, do: raise("stand.json: fremder scope #{stand.scope}")
        Stand.to_record(stand)

      {:error, :enoent} ->
        %{
          "schema" => "komki-stand/1",
          "stand_id" => @stand_id,
          "version" => 0,
          "scope" => scope,
          "as_of" => 0,
          "consumed" => %{}
        }
    end
  end

  defp now(stand), do: Map.put(stand, "as_of", System.os_time(:second))

  defp persist(dir, record) do
    tmp = path(dir) <> ".tmp"

    with :ok <- File.write(tmp, JSON.canonical(record)) do
      File.rename(tmp, path(dir))
    end
  end
end
