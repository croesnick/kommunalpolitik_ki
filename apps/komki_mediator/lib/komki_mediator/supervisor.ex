defmodule KomkiMediator.Supervisor do
  @moduledoc """
  Supervisor der Vermittlungs-App in bewusster Kinderordnung und
  `:one_for_all`-Strategie (fail-closed): stirbt der Journal-Writer,
  stirbt die Vermittlung mit — die Auditkette wird nie laufend
  abgedunkelt.

  Reihenfolge:
  1. Journal (PDR-Writer, Datei bleibt offen)
  2. Env (Gamma-Stand + Raum + Journal-Anbindung)
  3. anubis MCP-Server (Registry/Session-Maschinerie, KEIN eigener
     Listener — der HTTP-Port ist Punkt 4)
  4. Bandit-Listener (nur loopback)
  """

  use Supervisor

  def start_link({journal_path, gamma, room, port}) do
    Supervisor.start_link(__MODULE__, {journal_path, gamma, room, port}, name: __MODULE__)
  end

  @impl Supervisor
  def init({journal_path, gamma, room, port}) do
    children = [
      {KomkiMediator.Journal, journal_path},
      {KomkiMediator.Env, %{gamma: gamma, room: room, journal: KomkiMediator.Journal}},
      # start: true ist bewusst explizit: die Registry/Session-Maschinerie
      # von anubis 1.6 bindet fuer :streamable_http selbst keinen Socket
      # (der Plug ist der einzige Zugang) — mit start: false waere die
      # Registrierung :ignore und der Plug wuerde eine leere Maschinerie
      # an finden.
      {KomkiMediator.Server, transport: {:streamable_http, start: true}},
      {Bandit, plug: KomkiMediator.HTTP, scheme: :http, ip: {127, 0, 0, 1}, port: port}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
