defmodule KomkiCli.MediatorProfile do
  @moduledoc """
  Seatbelt-Profil des Vermittlers (Ticket #137, gebaut in #146):
  `<base>/profile/mediator.sb`, deny default mit der Escript-Grundschicht
  `KomkiCli.EscriptProfile`, dazu genau

    * Raum lesen (`<base>/mediator`: registry.json, room.json, documents),
    * Journal schreiben (`<base>/mediator/journal`, inklusive
      `chflags uappnd` ueber `/usr/bin/chflags`, Ticket #139),
    * Erstprovisionierung: registry.json, room.json und documents/ anlegen
      (`KomkiMediator.Templates.provision!/1` schreibt sie beim ersten Start),
    * Log schreiben,
    * den eigenen Kanal binden: heute Loopback-TCP auf `mediator_port`,
      Ziel (#143) der Unix-Socket `<base>/run/mediator.sock` mit Token-Datei,
    * `network-outbound` nur auf die Connector-Sockets
      `<base>/run/connectors/<id>.sock` (alle Manifest-IDs, damit der Text
      nicht vom Vault-Schalter abhaengt).

  Kein Netz-Outbound sonst, kein process-exec fuer Connectoren (Seatbelt
  laesst sich nicht verschachteln; `komki up` startet die Connectoren).
  """

  alias KomkiCli.{Config, ConnectorProfile, EscriptProfile, Mediator}
  alias KomkiConnector.Manifest

  @type listen :: {:tcp, pos_integer()} | {:unix, String.t()}

  @doc "Profilpfad neben dem pi-Profil."
  @spec path(Config.t()) :: String.t()
  def path(%Config{} = cfg), do: Path.join(Path.dirname(cfg.profile_path), "mediator.sb")

  @doc "Socket- und Token-Pfad des Ziel-Kanals (CONTRACT.md §2, #143)."
  @spec socket_path(Config.t()) :: String.t()
  def socket_path(%Config{} = cfg), do: Path.join([cfg.base_dir, "run", "mediator.sock"])

  @spec token_path(Config.t()) :: String.t()
  def token_path(%Config{} = cfg), do: Path.join([cfg.base_dir, "run", "mediator.token"])

  @doc "Profiltext fuer den Kanal `listen`."
  @spec generate(Config.t(), listen()) :: String.t()
  def generate(%Config{} = cfg, listen) do
    binary = mediator_bin!(cfg)
    root = EscriptProfile.erlang_root!(cfg)
    data = Path.join(cfg.base_dir, "mediator")
    log = Mediator.log_path(cfg)
    sockets = Enum.map(Manifest.ids(), &Manifest.socket_path(cfg.base_dir, &1))

    EscriptProfile.render(
      EscriptProfile.header([
        "Vermittler-Profil (komki-mediator, Tickets #137/#146): kein Netz-Outbound,",
        "nur die Connector-Sockets. Feste Eingaben -> byte-identischer Text."
      ]) ++
        EscriptProfile.runtime(root, binary) ++
        EscriptProfile.log_rules(log) ++
        data_rules(data) ++
        listen_rules(cfg, listen) ++
        connector_rules(sockets) ++
        EscriptProfile.meta_ancestors([root, binary, log, data] ++ listen_paths(listen, cfg)) ++
        [
          "; Bewusst NICHT erlaubt: Netz-Auswaerts ausser den Connector-Sockets, process-exec",
          "; ausser Runtime und chflags, Schreiben ausserhalb von Journal, Provisionierung und Log."
        ]
    )
  end

  defp data_rules(data) do
    journal = Path.join(data, "journal")

    [
      "; Raum lesen (registry.json, room.json, documents)",
      "(allow file-read* (subpath \"" <> data <> "\"))",
      "; Journal: anhaengen und uappnd setzen (Ticket #139)",
      "(allow file-write* (subpath \"" <> journal <> "\"))",
      "(allow process-exec (literal \"/usr/bin/chflags\"))",
      "(allow file-read* (literal \"/usr/bin/chflags\"))",
      "; Erstprovisionierung beim ersten Start (Templates.provision!/1)",
      "(allow file-write* (literal \"" <>
        data <>
        "\") (literal \"" <>
        Path.join(data, "registry.json") <>
        "\") (literal \"" <> Path.join(data, "room.json") <> "\"))",
      "(allow file-write* (subpath \"" <> Path.join(data, "documents") <> "\"))"
    ]
  end

  # Heute (bis #143): Loopback-TCP auf dem Vermittler-Port.
  defp listen_rules(_cfg, {:tcp, port}) do
    [
      "; Kanal pi -> Vermittler: Loopback-TCP (bis #143)",
      "(allow network-bind (local ip \"localhost:" <> Integer.to_string(port) <> "\"))",
      "(allow network-inbound (local ip))"
    ]
  end

  # Ziel (#143): Unix-Socket unter <base>/run mit Bearer-Token-Datei.
  defp listen_rules(cfg, {:unix, socket}) do
    ["; Kanal pi -> Vermittler: Unix-Socket (CONTRACT.md §8)"] ++
      ConnectorProfile.socket_bind_rules(socket) ++
      ["(allow file-read* (literal \"" <> token_path(cfg) <> "\"))"]
  end

  defp listen_paths({:tcp, _port}, _cfg), do: []
  defp listen_paths({:unix, socket}, cfg), do: [socket, token_path(cfg)]

  defp connector_rules(sockets) do
    ["; Connector-Sockets (Frame-Protokoll, CONTRACT.md §3) — einziges Outbound"] ++
      Enum.map(sockets, fn socket ->
        "(allow network-outbound (remote unix-socket (path-literal \"" <> socket <> "\")))"
      end)
  end

  defp mediator_bin!(%Config{mediator_bin: bin}) when is_binary(bin), do: bin

  defp mediator_bin!(_cfg),
    do: raise(ArgumentError, "komki-mediator nicht entdeckt (mix escript.build, init --force)")
end
