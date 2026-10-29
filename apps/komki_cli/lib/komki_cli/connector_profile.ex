defmodule KomkiCli.ConnectorProfile do
  @moduledoc """
  Seatbelt-Profile fuer Connectoren und den Egress-Proxy (Ticket #146),
  generiert aus `KomkiConnector.Manifest` und der config.json.

  **Connector** (`connector-<id>.sb`): Grundschicht `KomkiCli.EscriptProfile`,
  dazu genau

    * Binden des eigenen Sockets `<base>/run/connectors/<id>.sock`,
    * Log `<base>/tmp/connector-<id>.log`,
    * Netz nur `localhost:<egress-port>` (bzw. `localhost:<mock-port>` im
      RIS-Mock-Betrieb), und nur, wenn das Manifest `egress_hosts` hat,
    * Dateisystem nur nach `fs` des Manifests (`{vault_dir}` lesen,
      `{vault_dir}/komki-test` schreiben, `{documents_dir}` lesen).

  Kein Home, kein `~/.ssh`, kein DNS: Ein Connector kennt nur Loopback.

  **Egress** (`egress.sb`): Grundschicht, Log, `network-bind` auf die
  Egress-Ports, Outbound `*:443` und DNS. Seatbelt filtert Outbound nicht
  nach Host (`host must be * or localhost`); die Host-Allowlist erzwingt der
  Proxy selbst (CONTRACT.md §9). Er ist der einzige Prozess mit `*:443`.
  """

  alias KomkiCli.{Config, Connectors, EscriptProfile}
  alias KomkiConnector.Manifest
  alias Seatbelt.SBPL

  @doc "Profiltext eines Connectors."
  @spec connector(Config.t(), Manifest.t()) :: String.t()
  def connector(%Config{} = cfg, manifest) do
    binary = Connectors.binary!(cfg, manifest.id)
    root = EscriptProfile.erlang_root!(cfg)
    socket = Manifest.socket_path(cfg.base_dir, manifest.id)
    log = Connectors.log_path(cfg, manifest.id)
    fs = fs_paths(cfg, manifest)

    EscriptProfile.render(
      EscriptProfile.header([
        "Connector-Profil " <> manifest.id <> " (" <> manifest.fassung <> ", Ticket #146).",
        "Generiert aus KomkiConnector.Manifest und config.json; feste Eingaben -> byte-identischer Text."
      ]) ++
        EscriptProfile.runtime_for(cfg, binary) ++
        EscriptProfile.log_rules(log) ++
        socket_bind_rules(socket) ++
        connector_net_rules(Connectors.upstream(cfg, manifest)) ++
        fs_rules(fs) ++
        EscriptProfile.meta_ancestors([root, binary, socket, log] ++ Enum.map(fs, &elem(&1, 0))) ++
        [
          "; Bewusst NICHT erlaubt: Netz ausser dem einen Loopback-Port, DNS, Home-Verzeichnis,",
          "; Schreiben ausserhalb von Socket, Log und den fs-Pfaden des Manifests."
        ]
    )
  end

  @doc "Profiltext des Egress-Proxys."
  @spec egress(Config.t()) :: String.t()
  def egress(%Config{} = cfg) do
    binary = Connectors.egress_binary!(cfg)
    root = EscriptProfile.erlang_root!(cfg)
    log = Connectors.egress_log_path(cfg)

    EscriptProfile.render(
      EscriptProfile.header([
        "Egress-Profil (komki-egress, Ticket #146): einziger Prozess mit Outbound *:443.",
        "Generiert aus KomkiConnector.Manifest und config.json; feste Eingaben -> byte-identischer Text."
      ]) ++
        EscriptProfile.runtime_for(cfg, binary) ++
        EscriptProfile.log_rules(log) ++
        egress_bind_rules(Connectors.egress_ports(cfg)) ++
        egress_out_rules() ++
        EscriptProfile.meta_ancestors([root, binary, log]) ++
        [
          "; Seatbelt filtert Outbound nicht nach Host (host must be * or localhost); die",
          "; Host-Allowlist je Port erzwingt komki-egress selbst (CONTRACT.md §9)."
        ]
    )
  end

  @doc "Socket binden: network-bind plus Anlegen, chmod 0600 und Entfernen der Datei."
  @spec socket_bind_rules(String.t()) :: [String.t()]
  def socket_bind_rules(socket) do
    [
      "; eigener Unix-Socket (binden, 0600 setzen, alten Socket entfernen)",
      "(allow network-bind (local unix-socket (path-literal " <> SBPL.quote!(socket) <> ")))",
      "(allow file-read* file-write* (literal " <> SBPL.quote!(socket) <> "))"
    ]
  end

  defp connector_net_rules(:none), do: ["; kein Netz (Manifest ohne egress_hosts)"]

  defp connector_net_rules({:proxy, port}) do
    [
      "; Netz: nur der eigene Egress-Proxy-Port auf Loopback",
      "(allow network-outbound (remote tcp \"localhost:" <> Integer.to_string(port) <> "\"))",
      "; TLS-Wurzeln fuer den Tunnel: /etc/ssl/cert.pem (public_key:cacerts_load/1).",
      "; cacerts_get/0 startet /usr/bin/security und bleibt verweigert.",
      "(allow file-read* (literal \"/private/etc/ssl/cert.pem\"))",
      "(allow file-read-metadata (literal \"/private/etc/ssl\"))"
    ]
  end

  defp connector_net_rules({:direct, port}) do
    [
      "; Netz: Mock-Betrieb, nur der Mock-Port auf Loopback (kein Proxy, CONTRACT.md §9)",
      "(allow network-outbound (remote tcp \"localhost:" <> Integer.to_string(port) <> "\"))"
    ]
  end

  defp fs_paths(cfg, manifest) do
    Enum.map(manifest.fs, fn {pattern, mode} ->
      path =
        if String.contains?(pattern, "{vault_dir}"),
          do: String.replace(pattern, "{vault_dir}", vault_dir!(cfg)),
          else: String.replace(pattern, "{documents_dir}", KomkiCli.Connectors.documents_dir(cfg))

      {path, mode}
    end)
  end

  defp fs_rules([]), do: []

  defp fs_rules(fs) do
    ["; Dateisystem nach Manifest (fs)"] ++
      Enum.map(fs, fn
        {path, :read} -> "(allow file-read* (subpath " <> SBPL.quote!(path) <> "))"
        {path, :write} -> "(allow file-read* file-write* (subpath " <> SBPL.quote!(path) <> "))"
      end)
  end

  defp egress_bind_rules(ports) do
    ["; Egress-Ports: je Connector ein Loopback-Port"] ++
      Enum.map(ports, fn {port, _id, _hosts} ->
        "(allow network-bind (local ip \"localhost:" <> Integer.to_string(port) <> "\"))"
      end) ++ ["(allow network-inbound (local ip))"]
  end

  defp egress_out_rules do
    [
      "; Outbound: nur Port 443 (CONNECT-Ziele), Host-Pruefung im Proxy",
      "(allow network-outbound (remote tcp \"*:443\"))",
      "; DNS ueber inet_gethost (getaddrinfo -> mDNSResponder-Socket, /etc/hosts,",
      "; Routing-Sonde); inet_gethost signalisiert seine Worker-Kinder",
      "(allow network-outbound (remote unix-socket (path-literal \"/private/var/run/mDNSResponder\")))",
      "(allow file-read* (literal \"/private/etc/hosts\"))",
      "(allow sysctl-read (sysctl-name \"net.routetable.0.0.3.0\"))",
      "(allow signal (target children))"
    ]
  end

  defp vault_dir!(%Config{vault_dir: dir}) when is_binary(dir), do: dir

  defp vault_dir!(_cfg),
    do: raise(ArgumentError, "vault_dir nicht gesetzt — Vault-Connector ist abgeschaltet")
end
