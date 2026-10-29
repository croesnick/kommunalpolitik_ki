defmodule KomkiCli.Connectors do
  @moduledoc """
  Lebenszyklus von Egress-Proxy und Connectoren (Ticket #146,
  CONTRACT.md §2/§4/§9). `komki up` startet beide, jeweils ueber
  `sandbox-exec -f <eigenes Profil>` — Seatbelt laesst sich nicht
  verschachteln, ein gesandboxter Vermittler koennte sie nicht starten.

  Reihenfolge (in `KomkiCli.Steps`): llama → egress → Connectoren →
  Vermittler; `down` rueckwaerts.

    * **Egress** startet nur, wenn ein aktiver Connector ueber den Proxy
      geht. stdin: `{"ports": {"<port>": ["host:443", ...]}}` aus Manifesten
      und `egress_ports`.
    * **Connector**: `escript <binary> --socket <base>/run/connectors/<id>.sock
      [--proxy 127.0.0.1:<port>] [--base-url <url>] [--vault-dir <pfad>]`.
      stdin: genau eine JSON-Zeile mit den Credentials aus dem
      Schluesselbund (`{}` ohne Credentials oder wenn einer fehlt), danach
      schliesst komki stdin. Der Wert steht nie in argv, Umgebung oder Log.
    * Bereit ist ein Connector, wenn die reservierte Operation `ping` die
      Fassung des Manifests liefert; der Egress, wenn sein erster Port
      Verbindungen annimmt.

  pidfiles unter `<base>/tmp/` mit Identitaetscheck ueber die
  ps-Kommandozeile (`KomkiCli.Proc`), Logs unter `<base>/tmp/`.
  `<base>/run` und `<base>/run/connectors` mit `0700`.
  """

  alias KomkiCli.{Config, ConnectorProfile, Proc, Profile, Secrets}
  alias KomkiConnector.{Launch, Manifest, Text}
  alias Sidecar.{Client, Token}

  @ready_timeout_ms 15_000
  @egress_marker "komki-egress"

  @type state :: {:running, pos_integer()} | :stopped | :disabled | {:error, String.t()}
  @type up_state ::
          {:started, pos_integer()}
          | {:started, pos_integer(), [String.t()]}
          | {:already, pos_integer()}
  @type down_state :: :ok | :no_pidfile | {:stale, String.t()}

  # ===========================================================================
  # Pfade
  # ===========================================================================

  @spec run_dir(Config.t()) :: String.t()
  def run_dir(cfg), do: KomkiCli.Channel.run_dir(cfg)

  @spec connectors_dir(Config.t()) :: String.t()
  def connectors_dir(cfg), do: Path.join([cfg.base_dir, "run", "connectors"])

  @spec log_path(Config.t(), String.t()) :: String.t()
  def log_path(cfg, id), do: Path.join([cfg.base_dir, "tmp", "connector-" <> id <> ".log"])

  @spec pidfile(Config.t(), String.t()) :: String.t()
  def pidfile(cfg, id), do: Path.join([cfg.base_dir, "tmp", "connector-" <> id <> ".pid"])

  @spec profile_path(Config.t(), String.t()) :: String.t()
  def profile_path(cfg, id),
    do: Path.join(Path.dirname(cfg.profile_path), "connector-" <> id <> ".sb")

  @spec egress_log_path(Config.t()) :: String.t()
  def egress_log_path(cfg), do: Path.join([cfg.base_dir, "tmp", "egress.log"])

  @spec egress_pidfile(Config.t()) :: String.t()
  def egress_pidfile(cfg), do: Path.join([cfg.base_dir, "tmp", "komki-egress.pid"])

  @spec egress_profile_path(Config.t()) :: String.t()
  def egress_profile_path(cfg), do: Path.join(Path.dirname(cfg.profile_path), "egress.sb")

  @doc "Längster Socket-Pfad der Instanz (Grenze 103 Byte, CONTRACT.md §2)."
  @spec longest_socket(String.t()) :: String.t()
  def longest_socket(base) do
    Enum.max_by(
      [
        Path.join([base, "run", "mediator.sock"])
        | Enum.map(Manifest.ids(), &Manifest.socket_path(base, &1))
      ],
      &byte_size/1
    )
  end

  @max_socket_bytes 103

  @doc "Socket-Pfade der Basis passen in sun_path (103 Byte)?"
  @spec socket_length(String.t()) :: :ok | {:error, String.t()}
  def socket_length(base) do
    longest = longest_socket(base)

    if byte_size(longest) <= @max_socket_bytes do
      :ok
    else
      {:error,
       "Socket-Pfad zu lang (" <>
         Integer.to_string(byte_size(longest)) <>
         " > " <> Integer.to_string(@max_socket_bytes) <> " Byte): " <> longest}
    end
  end

  # ===========================================================================
  # Auswahl und Argumente (rein)
  # ===========================================================================

  @doc "Aktive Connectoren: alle Manifeste, Vault nur mit gesetztem vault_dir."
  @spec enabled(Config.t()) :: [Manifest.t()]
  def enabled(%Config{} = cfg) do
    Enum.filter(Manifest.all(), fn manifest ->
      manifest.id != "vault" or is_binary(cfg.vault_dir)
    end)
  end

  @doc "Raumdokumente des Vermittlers, die der Dokument-Connector liest (Ticket #169)."
  @spec documents_dir(Config.t()) :: Path.t()
  def documents_dir(%Config{base_dir: base}), do: Path.join([base, "mediator", "documents"])

  @doc """
  Netzweg eines Connectors: `:none` (keine egress_hosts), `{:proxy, port}`
  oder im RIS-Mock-Betrieb `{:direct, mock_port}`.
  """
  @spec upstream(Config.t(), Manifest.t()) ::
          :none | {:proxy, pos_integer()} | {:direct, pos_integer()}
  def upstream(%Config{} = cfg, manifest) do
    cond do
      manifest.egress_hosts == [] -> :none
      manifest.id == "ris" and Config.ris_mock?(cfg) -> {:direct, cfg.ris_mock_port}
      true -> {:proxy, egress_port!(cfg, manifest.id)}
    end
  end

  defp egress_port!(cfg, id) do
    case Map.fetch(cfg.egress_ports, id) do
      {:ok, port} -> port
      :error -> raise ArgumentError, "egress_ports: kein Port für Connector " <> id
    end
  end

  @doc "Egress-Ports der aktiven Proxy-Connectoren: `[{port, id, hosts}]`, nach Port sortiert."
  @spec egress_ports(Config.t()) :: [{pos_integer(), String.t(), [String.t()]}]
  def egress_ports(%Config{} = cfg) do
    cfg
    |> enabled()
    |> Enum.flat_map(fn manifest ->
      case upstream(cfg, manifest) do
        {:proxy, port} -> [{port, manifest.id, manifest.egress_hosts}]
        _ -> []
      end
    end)
    |> Enum.sort()
  end

  @spec egress_needed?(Config.t()) :: boolean()
  def egress_needed?(cfg), do: egress_ports(cfg) != []

  @doc """
  stdin des Egress-Proxys (CONTRACT.md §9, Format von komki-egress):
  `{"ports": {"<port>": {"connector": "<id>", "allow": ["host:443"]}}}`.
  """
  @spec egress_stdin(Config.t()) :: String.t()
  def egress_stdin(cfg) do
    ports =
      Map.new(egress_ports(cfg), fn {port, id, hosts} ->
        {Integer.to_string(port), %{"connector" => id, "allow" => hosts}}
      end)

    JSON.encode!(%{"ports" => ports}) <> "\n"
  end

  @doc "Argumente nach dem Binary (CONTRACT.md §4). Enthält nie Credentials."
  @spec connector_args(Config.t(), Manifest.t()) :: [String.t()]
  def connector_args(%Config{} = cfg, manifest) do
    ["--socket", Manifest.socket_path(cfg.base_dir, manifest.id)] ++
      proxy_args(upstream(cfg, manifest)) ++
      base_url_args(cfg, manifest) ++
      fs_args(cfg, manifest)
  end

  defp proxy_args({:proxy, port}), do: ["--proxy", "127.0.0.1:" <> Integer.to_string(port)]
  defp proxy_args(_), do: []

  defp base_url_args(cfg, %{id: "ris"}), do: ["--base-url", Config.ris_url(cfg)]
  defp base_url_args(_cfg, _manifest), do: []

  defp fs_args(cfg, %{id: "vault"}), do: ["--vault-dir", cfg.vault_dir]
  defp fs_args(cfg, %{id: "documents"}), do: ["--documents-dir", documents_dir(cfg)]
  defp fs_args(_cfg, _manifest), do: []

  @doc """
  Credentials-Zeile fuer stdin: das Connector-Token unter
  `KomkiConnector.Launch.credential_key/0` und `{"<NAME>": "<wert>"}` aus `fetch`
  (Default `Secrets.reveal/1`: Siegel aus dem Schluesselbund, per Secure
  Enclave geoeffnet). Fehlt ein Wert, bleibt er weg; Name und Fehlergrund
  der fehlenden kommen als zweites Element zurueck (nie Werte).
  """
  @spec credentials_line(
          Manifest.t(),
          String.t(),
          (String.t() -> {:ok, String.t()} | {:error, term()})
        ) ::
          {String.t(), [{String.t(), term()}]}
  def credentials_line(manifest, token, fetch \\ &Secrets.reveal/1) do
    {found, missing} =
      manifest.credentials
      |> Enum.sort()
      |> Enum.reduce({%{Launch.credential_key() => token}, []}, fn {name, service},
                                                                   {found, missing} ->
        case fetch.(service) do
          {:ok, value} -> {Map.put(found, name, value), missing}
          {:error, error} -> {found, missing ++ [{name, error}]}
        end
      end)

    {JSON.encode!(found) <> "\n", missing}
  end

  @spec binary!(Config.t(), String.t()) :: String.t()
  def binary!(%Config{} = cfg, id) do
    case binary(cfg, id) do
      bin when is_binary(bin) -> bin
      _ -> raise ArgumentError, missing_binary(Manifest.fetch!(id).binary)
    end
  end

  @doc """
  Programm eines Connectors: der Eintrag in `connector_bins`, sonst das
  Multicall-Programm `komki`, das alle Rollen enthaelt (eine Instanz aus der
  Zeit vor einem neuen Connector kennt dessen Eintrag noch nicht, #169).
  """
  @spec binary(Config.t(), String.t()) :: String.t() | nil
  def binary(%Config{} = cfg, id), do: Map.get(cfg.connector_bins, id) || cfg.komki_bin

  @spec egress_binary!(Config.t()) :: String.t()
  def egress_binary!(%Config{egress_bin: bin}) when is_binary(bin), do: bin
  def egress_binary!(_cfg), do: raise(ArgumentError, missing_binary(@egress_marker))

  @doc "Hinweistext für ein fehlendes Escript."
  @spec missing_binary(String.t()) :: String.t()
  def missing_binary(name),
    do:
      name <>
        " nicht gefunden — in PATH oder <base>/bin ablegen ('komki setup' entdeckt neu)"

  # ===========================================================================
  # Profile
  # ===========================================================================

  @doc "Zu schreibende Profile: `[{name, pfad, generator}]` für Egress (falls nötig) und aktive Connectoren."
  @spec profiles(Config.t()) :: [{String.t(), String.t(), (-> String.t())}]
  def profiles(%Config{} = cfg) do
    egress =
      if egress_needed?(cfg),
        do: [{"egress profile", egress_profile_path(cfg), fn -> ConnectorProfile.egress(cfg) end}],
        else: []

    egress ++
      Enum.map(enabled(cfg), fn manifest ->
        {"connector-" <> manifest.id <> " profile", profile_path(cfg, manifest.id),
         fn -> ConnectorProfile.connector(cfg, manifest) end}
      end)
  end

  # ===========================================================================
  # Lebenszyklus
  # ===========================================================================

  @doc """
  Startet Egress (falls noetig) und alle aktiven Connectoren in dieser
  Reihenfolge. Bricht beim ersten Fehler ab (bereits gestartete laufen
  weiter; `komki down` raeumt auf).
  """
  @spec up(Config.t(), keyword()) :: {:ok, [{String.t(), up_state()}]} | {:error, String.t()}
  def up(%Config{} = cfg, opts \\ []) do
    fetch = Keyword.get(opts, :fetch, &Secrets.reveal/1)
    ensure_run_dirs!(cfg)

    steps =
      Enum.map(start_order(cfg), fn
        "egress" -> :egress
        "connector-" <> id -> {:connector, Manifest.fetch!(id)}
      end)

    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      case start(cfg, step, fetch) do
        {:ok, entry} -> {:cont, {:ok, acc ++ [entry]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Startreihenfolge: Egress (falls nötig), dann die aktiven Connectoren in Manifest-Reihenfolge."
  @spec start_order(Config.t()) :: [String.t()]
  def start_order(cfg) do
    if(egress_needed?(cfg), do: ["egress"], else: []) ++
      Enum.map(enabled(cfg), &("connector-" <> &1.id))
  end

  @doc "Stoppreihenfolge von `down/1`: Connectoren rückwärts (alle, idempotent), dann Egress."
  @spec stop_order() :: [String.t()]
  def stop_order do
    Enum.map(Enum.reverse(Manifest.ids()), &("connector-" <> &1)) ++ ["egress"]
  end

  @doc """
  `<base>/run` und `<base>/run/connectors` mit 0700 anlegen, dazu den
  Dokumentordner des Raums: Der Dokument-Connector startet vor dem
  Vermittler, der den Ordner sonst erst beim ersten Start befuellt.
  """
  @spec ensure_run_dirs!(Config.t()) :: :ok
  def ensure_run_dirs!(cfg) do
    for dir <- [run_dir(cfg), connectors_dir(cfg)] do
      File.mkdir_p!(dir)
      File.chmod!(dir, 0o700)
    end

    File.mkdir_p!(documents_dir(cfg))
    :ok
  end

  # Laeuft die Komponente schon, bleibt alles unberuehrt: Profil und Socket
  # werden nur vor einem echten Start vorbereitet. Frueher loeschte jedes
  # `up` den Socket eines laufenden Connectors, der danach als "running"
  # galt, aber unerreichbar war (enoent), etwa in `komki session` nach `run`.
  defp start(cfg, step, fetch) do
    comp = component_for(cfg, step)

    case alive(comp) do
      {:ok, pid} -> keep_or_restart(cfg, step, comp, pid, fetch)
      :none -> start_fresh(cfg, step, comp, fetch)
    end
  end

  # Ein laufender Connector ohne Tokendatei stammt aus einer komki-Version
  # vor den Connector-Tokens (oder hat sein Token verloren); der Vermittler
  # erreicht ihn nicht mehr. Er wird neu gestartet statt als laufend zu gelten.
  defp keep_or_restart(cfg, {:connector, _} = step, comp, pid, fetch) do
    if File.exists?(Token.for_socket(comp.socket)) do
      {:ok, {comp.name, {:already, pid}}}
    else
      _ = stop(comp)
      start_fresh(cfg, step, comp, fetch)
    end
  end

  defp keep_or_restart(_cfg, _step, comp, pid, _fetch), do: {:ok, {comp.name, {:already, pid}}}

  defp component_for(cfg, :egress), do: egress_component(cfg)
  defp component_for(cfg, {:connector, manifest}), do: connector_component(cfg, manifest.id)

  defp start_fresh(cfg, :egress, comp, _fetch) do
    Profile.write!(egress_profile_path(cfg), ConnectorProfile.egress(cfg))

    launch(cfg, comp, egress_binary!(cfg), [], egress_profile_path(cfg), egress_stdin(cfg), fn ->
      egress_ready(cfg)
    end)
  end

  defp start_fresh(cfg, {:connector, manifest}, comp, fetch) do
    Profile.write!(profile_path(cfg, manifest.id), ConnectorProfile.connector(cfg, manifest))
    File.rm(comp.socket)
    # Capability-Token je Start (Sidecar.Token): Datei fuer den
    # Vermittler, derselbe Wert in der stdin-Zeile fuer den Connector.
    token = Token.provision!(comp.socket)
    {line, missing} = credentials_line(manifest, token, fetch)

    cfg
    |> launch(
      comp,
      binary!(cfg, manifest.id),
      connector_args(cfg, manifest),
      profile_path(cfg, manifest.id),
      line,
      fn -> ping(cfg, manifest) end
    )
    |> with_warnings(credential_warnings(manifest, missing))
  end

  # Ein nicht gesetzter Schluessel ist eine Wahl (der Doctor meldet ihn);
  # ein verweigertes oder unversiegeltes Geheimnis meldet `up` sichtbar.
  defp credential_warnings(manifest, missing) do
    for {name, error} <- missing, error != :missing do
      Secrets.describe(Map.fetch!(manifest.credentials, name), error) <>
        " — " <> manifest.id <> " startet ohne " <> name
    end
  end

  defp with_warnings({:ok, {name, {:started, pid}}}, [_ | _] = warnings),
    do: {:ok, {name, {:started, pid, warnings}}}

  defp with_warnings(result, _warnings), do: result

  defp launch(cfg, comp, binary, args, profile, input, ready) do
    case alive(comp) do
      {:ok, pid} ->
        {:ok, {comp.name, {:already, pid}}}

      :none ->
        # Multicall (Ticket #179): der Rollenname (= marker) vor den Argumenten
        role = KomkiCli.Roles.prefix(cfg, binary, comp.marker)
        line = spawn_line(cfg, profile, binary, role ++ args, comp.log)

        with {:ok, pid} <- Proc.spawn_detached(line, input, "/") do
          File.write!(comp.pidfile, Integer.to_string(pid) <> "\n")
          await(comp, pid, ready)
        end
    end
  end

  @doc """
  Spawn-Zeile eines gesandboxten Escripts mit durchgereichtem stdin (rein,
  testbar): `nohup env -i … sandbox-exec -f <profil> <escript> <binary>
  <args> 0<&0 > <log> 2>&1 & echo $!`.
  """
  @spec spawn_line(Config.t(), String.t(), String.t(), [String.t()], String.t()) :: String.t()
  def spawn_line(%Config{} = cfg, profile, binary, args, log) do
    [program | words] = Proc.role_cmd(cfg, profile, binary, args, run_dir(cfg))
    Proc.spawn_line(program, Enum.map(words, &Proc.quote_bin/1), log, "0<&0")
  end

  defp await(comp, pid, ready) do
    deadline = System.monotonic_time(:millisecond) + @ready_timeout_ms

    case Proc.poll_health(ready, comp.marker, deadline) do
      {:ok, _} ->
        {:ok, {comp.name, {:started, pid}}}

      {:error, reason} ->
        Proc.kill_checked(pid, comp.marker)
        File.rm(comp.pidfile)
        {:error, reason <> "; " <> comp.name <> " log tail: " <> Proc.log_tail(comp.log, 20)}
    end
  end

  @doc "Reservierte Operation `ping` gegen den Connector-Socket (CONTRACT.md §3)."
  @spec ping(Config.t(), Manifest.t()) :: {:ok, map()} | {:error, String.t()}
  def ping(%Config{} = cfg, manifest) do
    socket = Manifest.socket_path(cfg.base_dir, manifest.id)
    call_id = "komki-cli-ping-" <> Integer.to_string(System.unique_integer([:positive]))

    case Client.call(socket, call_id, "ping", %{}, %{}, timeout: 3_000, texts: Text) do
      {:ok, %{"fassung" => fassung} = result} when fassung == manifest.fassung ->
        {:ok, result}

      {:ok, result} ->
        {:error, "ping: falsche Fassung " <> Kernel.inspect(result["fassung"])}

      {:error, %{"code" => code, "detail" => detail}} ->
        {:error, "ping: " <> code <> " " <> detail}
    end
  end

  # komki-egress meldet nach dem Binden aller Ports eine Zeile
  # {"komki_egress":"listening",...} auf stdout (hier: im Log).
  defp egress_ready(cfg) do
    case File.read(egress_log_path(cfg)) do
      {:ok, log} ->
        if String.contains?(log, ~s("komki_egress":"listening")),
          do: {:ok, :listening},
          else: {:error, "egress noch nicht bereit"}

      {:error, _} ->
        {:error, "egress-Log fehlt"}
    end
  end

  @doc """
  Stoppt Connectoren (umgekehrte Startreihenfolge) und danach den Egress.
  Idempotent: ohne pidfile `:no_pidfile`, stale pidfiles werden entfernt.
  """
  @spec down(Config.t()) :: [{String.t(), down_state() | {:error, String.t()}}]
  def down(%Config{} = cfg) do
    Enum.map(stop_order(), fn
      "egress" -> stop(egress_component(cfg))
      "connector-" <> id -> stop(connector_component(cfg, id))
    end)
  end

  defp stop(comp) do
    state =
      case Proc.read_pidfile(comp.pidfile) do
        {:ok, pid} -> stop_pid(comp, pid)
        :none -> :no_pidfile
        {:error, reason} -> {:error, reason}
      end

    if comp.socket do
      File.rm(comp.socket)
      File.rm(Token.for_socket(comp.socket))
    end

    {comp.name, state}
  end

  defp stop_pid(comp, pid) do
    if Proc.pid_alive?(pid, comp.marker) do
      case Proc.kill_checked(pid, comp.marker) do
        :ok ->
          File.rm(comp.pidfile)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      File.rm(comp.pidfile)

      {:stale,
       "pid " <>
         Integer.to_string(pid) <> " ist nicht (mehr) " <> comp.marker <> " — pidfile entfernt"}
    end
  end

  @doc "Zustand je Komponente in Startreihenfolge (Egress zuerst)."
  @spec status(Config.t()) :: [{String.t(), state()}]
  def status(%Config{} = cfg) do
    egress =
      if egress_needed?(cfg), do: comp_state(egress_component(cfg)), else: :disabled

    active = MapSet.new(enabled(cfg), & &1.id)

    connectors =
      Enum.map(Manifest.all(), fn manifest ->
        comp = connector_component(cfg, manifest.id)

        {comp.name,
         if(MapSet.member?(active, manifest.id), do: comp_state(comp), else: :disabled)}
      end)

    [{"egress", egress} | connectors]
  end

  defp comp_state(comp) do
    case alive(comp) do
      {:ok, pid} ->
        {:running, pid}

      :none ->
        case Proc.read_pidfile(comp.pidfile) do
          {:ok, pid} ->
            {:error, "stale pidfile: pid " <> Integer.to_string(pid) <> " is not " <> comp.marker}

          :none ->
            :stopped

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp alive(comp) do
    with {:ok, pid} <- Proc.read_pidfile(comp.pidfile),
         true <- Proc.pid_alive?(pid, comp.marker) do
      {:ok, pid}
    else
      _ -> :none
    end
  end

  defp egress_component(cfg) do
    %{
      name: "egress",
      marker: @egress_marker,
      pidfile: egress_pidfile(cfg),
      log: egress_log_path(cfg),
      socket: nil
    }
  end

  defp connector_component(cfg, id) do
    %{
      name: "connector-" <> id,
      marker: Manifest.fetch!(id).binary,
      pidfile: pidfile(cfg, id),
      log: log_path(cfg, id),
      socket: Manifest.socket_path(cfg.base_dir, id)
    }
  end
end
