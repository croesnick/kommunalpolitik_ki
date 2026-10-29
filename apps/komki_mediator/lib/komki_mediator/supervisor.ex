defmodule KomkiMediator.Supervisor do
  @moduledoc """
  Supervisor der Vermittlungs-App in bewusster Kinderordnung und
  `:one_for_all`-Strategie (fail-closed): stirbt der Journal-Writer,
  stirbt die Vermittlung mit — die Auditkette wird nie laufend
  abgedunkelt.

  Reihenfolge:
  1. Journal (PDR-Writer, Datei bleibt offen)
  1a. GoStand (Offenlegungsstand der GO-Noncen, nur mit GO-Konfiguration;
      Ticket #98)
  2. Env (Gamma-Stand + Raum + Journal-Anbindung)
  3. anubis MCP-Server (Registry/Session-Maschinerie, KEIN eigener
     Listener — der HTTP-Port ist Punkt 4)
  4. Bandit-Listener auf dem Unix-Socket (Ticket #143, kein TCP)

  Der Listener-Start (`start_listener/2`) raeumt eine verwaiste
  Socket-Datei weg, bindet und setzt die Rechte der Socket-Datei auf
  `0600`. Ob ein anderer Vermittler den Socket noch bedient, prueft der
  Escript vor dem Start (`KomkiMediator.CLI`). Das Laufzeitverzeichnis
  (`0700`) legt `komki up` an; es schliesst das kurze Fenster zwischen
  Bind und chmod.
  """

  use Supervisor

  @typedoc """
  Socket-Zugang: Socket-Pfad und Socket-Token (CONTRACT §8), optional das Verzeichnis
  der Connector-Sockets (CONTRACT §2; fehlt es, sind Connector-Aufrufe
  Connector-Fehler).
  """
  @type channel() :: %{
          required(:socket) => Path.t(),
          required(:token) => String.t(),
          optional(:connectors_dir) => Path.t(),
          optional(:go) => KomkiMediator.Go.config()
        }

  def start_link({journal_path, gamma, room, channel}) do
    Supervisor.start_link(__MODULE__, {journal_path, gamma, room, channel}, name: __MODULE__)
  end

  @doc "Startet Bandit auf dem Unix-Socket und setzt die Socket-Rechte auf 0600."
  @spec start_listener(Path.t(), String.t()) :: Supervisor.on_start()
  def start_listener(socket, token) do
    _ = File.rm(socket)

    with {:ok, pid} <-
           Bandit.start_link(
             plug: {KomkiMediator.HTTP, token: token},
             scheme: :http,
             ip: {:local, socket},
             port: 0
           ) do
      :ok = File.chmod(socket, 0o600)
      {:ok, pid}
    end
  end

  @impl Supervisor
  def init({journal_path, gamma, room, %{socket: socket, token: token} = channel}) do
    env = %{
      gamma: gamma,
      room: room,
      journal: KomkiMediator.Journal,
      connectors_dir: Map.get(channel, :connectors_dir),
      go: Map.get(channel, :go)
    }

    # Der Offenlegungsstand der GO-Noncen (Ticket #98) gehoert zum Raum.
    go_stand =
      case env.go do
        %{dir: dir} -> [{KomkiMediator.GoStand, %{dir: dir, scope: "go-" <> room.workspace_id}}]
        nil -> []
      end

    children =
      [{KomkiMediator.Journal, journal_path}] ++
        go_stand ++
        [
          {KomkiMediator.Env, env},
          # start: true ist bewusst explizit: die Registry/Session-Maschinerie
          # von anubis 1.6 bindet fuer :streamable_http selbst keinen Socket
          # (der Plug ist der einzige Zugang) — mit start: false waere die
          # Registrierung :ignore und der Plug wuerde eine leere Maschinerie
          # an finden.
          {KomkiMediator.Server, transport: {:streamable_http, start: true}},
          %{
            id: :listener,
            start: {__MODULE__, :start_listener, [socket, token]},
            type: :supervisor
          }
        ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
