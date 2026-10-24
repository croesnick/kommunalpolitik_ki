defmodule KomkiMediator.Env do
  @moduledoc """
  Vermittlungs-Umgebung: haelt den geladenen Gamma-Stand, den Raum und die
  Journal-Anbindung bereit, dazu `connectors_dir` (Verzeichnis der
  Connector-Sockets) und optional `session_id` (Zuordnung im PDR). Die MCP-Tools holen die Umgebung einmal je
  Aufruf und reichen sie an das Gate durch — Tests starten eine
  konfigurierte Instanz und erzeugen so definierten Nachlauf.
  """

  use GenServer

  @doc "Startet die benannte Umgebung."
  @spec start_link(map()) :: {:ok, pid()}
  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @doc "Holt die aktuelle Umgebung (gamma, room, journal, connectors_dir, session_id)."
  @spec fetch() :: map()
  def fetch do
    GenServer.call(__MODULE__, :fetch)
  end

  @doc """
  Umgebung fuer EINEN Toolaufruf: `fetch/0` plus `:session_id` aus dem
  anubis-Frame (Ticket #143). Der HTTP-Guard prueft `X-Komki-Session` und legt
  den Wert (oder nil) in `conn.assigns.komki_session`; anubis uebernimmt die
  Assigns je Anfrage in `frame.assigns`. Das Gate schreibt `env.session_id` in
  den PDR.

  Jedes MCP-Tool holt seine Umgebung ueber diese Funktion, nicht ueber
  `fetch/0` — auch kuenftige Connector-Tools:

      def execute(params, frame) do
        env = Env.for_call(frame)
        response = Gate.call(env, "tool_name", params, executor)
        ...
  """
  @spec for_call(%{:assigns => map(), optional(atom()) => term()}) :: map()
  def for_call(%{assigns: assigns}) do
    Map.put(fetch(), :session_id, Map.get(assigns, :komki_session))
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:fetch, _from, state), do: {:reply, state, state}
end
