defmodule KomkiCli.Channel do
  @moduledoc """
  Kanal pi → Vermittler (Ticket #143, CONTRACT §2 und §8): Laufzeitverzeichnis,
  Token, Session-ID und das stdio-Relay.

      <base>/run/                 0700, angelegt von `komki up`
      <base>/run/mediator.sock    Vermittler (Bandit, HTTP), Rechte 0600
      <base>/run/mediator.token   32 Byte Zufall als Hex, 0600, neu bei jedem
                                  Kaltstart durch `komki up`; ein geplanter
                                  Neustart (neues Γ, neue Raumdokumente)
                                  behaelt es (Ticket #216)

  Das Token steht nie in argv: der Vermittler liest es per `--token-file`,
  pi bekommt es ueber die Umgebung (`KOMKI_MEDIATOR_TOKEN`) und reicht es
  ueber die `env`-Felder der mcp.json (`${KOMKI_MEDIATOR_TOKEN}`) an das
  Relay weiter. Die mcp.json selbst enthaelt kein Token.

  `komki-relay.js` (Quelle: `priv/komki-relay.js`, zur Compile-Zeit
  eingebettet) liegt unter `<pi-home>/.pi/agent/` und wird vor jedem pi-Start
  neu geschrieben: Das pi-Home ist fuer den Agenten schreibbar, ein
  veraendertes Relay ueberlebt so keinen Lauf.
  """

  alias KomkiCli.Config

  @relay_source Path.expand("../../priv/komki-relay.js", __DIR__)
  @external_resource @relay_source
  @relay_js File.read!(@relay_source)

  # macOS: sun_path hat 104 Byte inklusive Nullbyte.
  @max_socket_bytes 103

  @spec run_dir(Config.t()) :: String.t()
  def run_dir(%Config{} = cfg), do: Path.join(cfg.base_dir, "run")

  @spec socket_path(Config.t()) :: String.t()
  def socket_path(%Config{} = cfg), do: Path.join(run_dir(cfg), "mediator.sock")

  @spec token_path(Config.t()) :: String.t()
  def token_path(%Config{} = cfg), do: Path.join(run_dir(cfg), "mediator.token")

  @spec relay_path(Config.t()) :: String.t()
  def relay_path(%Config{} = cfg), do: Path.join([cfg.pi_home, ".pi", "agent", "komki-relay.js"])

  @doc "Prüft die macOS-Grenze für Unix-Socket-Pfade (103 Byte)."
  @spec check_socket_path(Config.t()) :: :ok | {:error, String.t()}
  def check_socket_path(%Config{} = cfg) do
    path = socket_path(cfg)

    if byte_size(path) <= @max_socket_bytes,
      do: :ok,
      else:
        {:error,
         "Socket-Pfad zu lang (" <>
           to_string(byte_size(path)) <> " > 103 Byte): " <> path <> " — kürzere Basis wählen"}
  end

  @doc "Legt `<base>/run` (0700) an und schreibt ein neues Token (0600)."
  @spec write_token!(Config.t()) :: :ok
  def write_token!(%Config{} = cfg) do
    dir = run_dir(cfg)
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)

    path = token_path(cfg)
    _ = File.rm(path)
    File.write!(path, "")
    File.chmod!(path, 0o600)
    File.write!(path, Base.encode16(:crypto.strong_rand_bytes(32), case: :lower))
  end

  @doc "Liest das Token; der Fehler nennt den Pfad, nie den Inhalt."
  @spec read_token(Config.t()) :: {:ok, String.t()} | {:error, String.t()}
  def read_token(%Config{} = cfg) do
    path = token_path(cfg)

    case File.read(path) do
      {:ok, token} ->
        if Regex.match?(~r/\A[0-9a-f]{64}\z/, token),
          do: {:ok, token},
          else: {:error, "ungültiges Token in " <> path <> " — 'komki down' und 'komki up'"}

      {:error, reason} ->
        {:error,
         "Token fehlt (" <>
           path <> ": " <> List.to_string(:file.format_error(reason)) <> ") — 'komki up' zuerst"}
    end
  end

  @doc "Neue Session-ID für einen pi-Start (`ses-` plus 16 Hex-Zeichen)."
  @spec new_session_id() :: String.t()
  def new_session_id, do: "ses-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  @doc """
  Umgebung fuer einen pi-Start: Token aus der Datei und eine neue
  Session-ID. Schreibt das Relay frisch ins pi-Home.
  """
  @spec prepare_pi(Config.t()) :: {:ok, %{String.t() => String.t()}} | {:error, String.t()}
  def prepare_pi(%Config{} = cfg) do
    with {:ok, token} <- read_token(cfg) do
      write_relay!(cfg)
      {:ok, %{"KOMKI_MEDIATOR_TOKEN" => token, "KOMKI_SESSION_ID" => new_session_id()}}
    end
  end

  @doc "Schreibt `komki-relay.js` ins pi-Home (idempotent)."
  @spec write_relay!(Config.t()) :: :ok
  def write_relay!(%Config{} = cfg) do
    path = relay_path(cfg)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, @relay_js)
  end

  @doc "Inhalt des eingebetteten Relays (für Tests)."
  @spec relay_js() :: String.t()
  def relay_js, do: @relay_js
end
