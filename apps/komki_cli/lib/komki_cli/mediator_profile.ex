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
    * den eigenen Kanal binden (#143): den Unix-Socket
      `<base>/run/mediator.sock` (binden, annehmen, 0600, alten entfernen)
      und die Token-Datei `<base>/run/mediator.token` lesen; die Variante
      `{:tcp, port}` bleibt fuer Tests und Altinstanzen generierbar,
    * `network-outbound` nur auf die Connector-Sockets
      `<base>/run/connectors/<id>.sock` (alle Manifest-IDs, damit der Text
      nicht vom Vault-Schalter abhaengt) und Lesen der zugehoerigen
      Token-Dateien `<id>.token` (`KomkiConnector.Token`).

  Kein Netz-Outbound sonst, kein process-exec fuer Connectoren (Seatbelt
  laesst sich nicht verschachteln; `komki up` startet die Connectoren).
  """

  alias KomkiCli.{Channel, Config, ConnectorProfile, EscriptProfile, Mediator}
  alias KomkiConnector.{Manifest, Token}
  alias Seatbelt.SBPL

  @type listen :: {:tcp, pos_integer()} | {:unix, String.t()}

  @doc "Profilpfad neben dem pi-Profil."
  @spec path(Config.t()) :: String.t()
  def path(%Config{} = cfg), do: Path.join(Path.dirname(cfg.profile_path), "mediator.sb")

  @doc "Socket-Pfad des Kanals (CONTRACT.md §2, #143; Quelle `KomkiCli.Channel`)."
  @spec socket_path(Config.t()) :: String.t()
  def socket_path(%Config{} = cfg), do: Channel.socket_path(cfg)

  defp token_path(cfg), do: Channel.token_path(cfg)

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
        EscriptProfile.runtime_for(cfg, binary) ++
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

    documents = Path.join(data, "documents")
    go = Path.join(data, "go")

    [
      "; Raum lesen (registry.json, room.json). Die Dokumente liest der",
      "; Dokument-Connector (Ticket #169); hier nur Metadaten fuer die",
      "; Erstprovisionierung, keine Inhalte.",
      "(allow file-read* (literal " <>
        SBPL.quote!(data) <>
        ") (literal " <>
        SBPL.quote!(Path.join(data, "registry.json")) <>
        ") (literal " <> SBPL.quote!(Path.join(data, "room.json")) <> "))",
      "(allow file-read-metadata (subpath " <> SBPL.quote!(documents) <> "))",
      "(allow file-read* (subpath " <>
        SBPL.quote!(journal) <> ") (subpath " <> SBPL.quote!(go) <> "))",
      "; Journal: anhaengen und uappnd setzen (Ticket #139)",
      "(allow file-write* (subpath " <> SBPL.quote!(journal) <> "))",
      "(allow process-exec (literal \"/usr/bin/chflags\"))",
      "(allow file-read* (literal \"/usr/bin/chflags\"))",
      "; Erstprovisionierung beim ersten Start (Templates.provision!/1)",
      "(allow file-write* (literal " <>
        SBPL.quote!(data) <>
        ") (literal " <>
        SBPL.quote!(Path.join(data, "registry.json")) <>
        ") (literal " <> SBPL.quote!(Path.join(data, "room.json")) <> "))",
      "(allow file-write* (subpath " <> SBPL.quote!(documents) <> "))",
      "; GO-Anfragen und Offenlegungsstand (Ticket #98)",
      "(allow file-write* (subpath " <> SBPL.quote!(go) <> "))"
    ]
  end

  # Altform: Loopback-TCP auf einem Port (vor #143).
  defp listen_rules(_cfg, {:tcp, port}) do
    [
      "; Kanal pi -> Vermittler: Loopback-TCP (Altform vor #143)",
      "(allow network-bind (local ip \"localhost:" <> Integer.to_string(port) <> "\"))",
      "(allow network-inbound (local ip))"
    ]
  end

  # #143: Unix-Socket unter <base>/run mit Bearer-Token-Datei.
  defp listen_rules(cfg, {:unix, socket}) do
    ["; Kanal pi -> Vermittler: Unix-Socket (CONTRACT.md §8), Token nur lesen"] ++
      ConnectorProfile.socket_bind_rules(socket) ++
      [
        "(allow network-inbound (local unix-socket (path-literal " <> SBPL.quote!(socket) <> ")))",
        "(allow file-read* (literal " <> SBPL.quote!(token_path(cfg)) <> "))"
      ]
  end

  defp listen_paths({:tcp, _port}, _cfg), do: []
  defp listen_paths({:unix, socket}, cfg), do: [socket, token_path(cfg)]

  defp connector_rules(sockets) do
    ["; Connector-Sockets (Frame-Protokoll, CONTRACT.md §3) — einziges Outbound, Token nur lesen"] ++
      Enum.flat_map(sockets, fn socket ->
        [
          "(allow network-outbound (remote unix-socket (path-literal " <>
            SBPL.quote!(socket) <> ")))",
          "(allow file-read* (literal " <> SBPL.quote!(Token.for_socket(socket)) <> "))"
        ]
      end)
  end

  defp mediator_bin!(%Config{mediator_bin: bin}) when is_binary(bin), do: bin

  defp mediator_bin!(_cfg),
    do: raise(ArgumentError, "komki-mediator nicht entdeckt ('make komki', dann 'komki setup')")
end
