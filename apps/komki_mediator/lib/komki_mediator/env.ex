defmodule KomkiMediator.Env do
  @moduledoc """
  Vermittlungs-Umgebung: haelt den geladenen Gamma-Stand, den Raum und die
  Journal-Anbindung bereit. Die MCP-Tools holen die Umgebung einmal je
  Aufruf und reichen sie an das Gate durch — Tests starten eine
  konfigurierte Instanz und erzeugen so definierten Nachlauf.
  """

  use GenServer

  @doc "Startet die benannte Umgebung."
  @spec start_link(map()) :: {:ok, pid()}
  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @doc "Holt die aktuelle Umgebung (gamma, room, journal)."
  @spec fetch() :: map()
  def fetch do
    GenServer.call(__MODULE__, :fetch)
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:fetch, _from, state), do: {:reply, state, state}
end
