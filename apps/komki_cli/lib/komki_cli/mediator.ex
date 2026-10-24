defmodule KomkiCli.Mediator do
  @moduledoc """
  Vermittler-Lebenszyklus (Ticket #102): die Prozesssteuerung teilt sich
  mit `KomkiCli.Llama` die Mechanik in `KomkiCli.Proc` (Pidfile,
  Identitaetscheck, Kill-Eskalation, Health-Poll) — der langlaufende
  Escript `komki-mediator` (baubar aus `apps/komki_mediator`) wird von
  `komki up` gestartet, per healthz gepinnt befragt und von `komki down`
  gestoppt.

  Der Vertrag zwischen den Apps ist fix und wird hier nicht mehr geprüft
  als nötig (komki_cli liest statt zu raten):

      - Args:            --base <dir>  --socket <base>/run/mediator.sock
                         --token-file <base>/run/mediator.token
      - Health-Endpoint: GET /healthz ueber den Unix-Socket, mit
                         `Authorization: Bearer <token>`
                         -> 200 JSON, byte-stabil, Keys:
                            status ("ok"), fassung_id, tools (sortierte
                            String-Liste), registry_id, gamma_hash
      - MCP-Endpoint:    POST /mcp (anubis streamable HTTP);
                         Server-Name "komki" -> pi-Tool-IDs
                         mcp__komki__<tool>

  Die Fassung (aktuell ["ping", "admit_document"]) wird bei `up` AUS
  healthz GELESEN, nicht hartkodiert — komki_cli kennt keine Tool-Namen.
  Die pi-seitige Freigabe erfolgt via `write_mcp_config/2`: alles zweite
  bleibt verborgen.

  Kanal (Ticket #143, `KomkiCli.Channel`): Der Vermittler lauscht nur auf
  dem Unix-Socket und verlangt das Token, das `up` vor jedem Start neu
  schreibt. pi erreicht ihn ueber `komki-relay.js` (stdio-MCP-Server); das
  pi-Profil erlaubt Netz-Auswaerts nur zu diesem Socket-Pfad und zum
  llama-Port. Die mcp.json enthaelt kein Token, nur den Verweis
  `${KOMKI_MEDIATOR_TOKEN}` auf pis Umgebung.

  Pidfile unter `base/tmp/komki-mediator.pid`, Log unter
  `base/tmp/mediator.log`; der Identitätscheck vor jedem `kill` liest die
  `ps`-Kommandozeile (nur echte komki-mediator-Prozesse empfangen
  Signale — macOS-taugliche Self-Defense gegen pidfile-Wiederverwendung).
  """

  alias KomkiCli.{Channel, Config, Proc}
  require Config

  @health_timeout_ms 10_000
  # Vermittler-Boot ist schnell (escript, keine 17-GB-GGUF): kuerzerer
  # Poll-DEADLINE als llama (60s).
  @up_timeout_ms 30_000

  @type health :: %{optional(String.t()) => term()}

  @doc "Startet komki-mediator detached; pidfile unter base. Foreground nach `up` ist der Health-Poll."

  @spec up(Config.t()) ::
          {:ok, {:started, pos_integer(), health()}}
          | {:ok, {:already, health()}}
          | {:error, String.t()}
  def up(%Config{} = cfg) do
    case fetch_health(cfg) do
      {:ok, "200", health} ->
        # Laufender Vermittler mit dem aktuellen Token: kein Neustart, das
        # Token bleibt (ein neues wuerde ihn aussperren).
        {:ok, {:already, health}}

      _ ->
        # Kein Token, falsches Token oder stiller Socket: neues Token, dann
        # Spawn-Versuch. Bedient ein anderer Prozess den Socket, verweigert
        # der Vermittler den Start; das faellt am Health-Poll auf.
        with :ok <- Channel.check_socket_path(cfg) do
          Channel.write_token!(cfg)
          spawn_mediator(cfg)
        end
    end
  end

  @doc """
  Stoppt komki-mediator via pidfile (nur wenn der pid-Prozess
  komki-mediator ist). `:no_pidfile` wenn kein pidfile existiert;
  `{:stale, reason}` wenn die Pidfile-Pid nicht (mehr) komki-mediator
  ist — down ist der Aufräumweg: das stale pidfile wird entfernt, aber
  kein Prozess getötet (Identitätscheck).
  """
  @spec down(Config.t()) :: :ok | :no_pidfile | {:stale, String.t()} | {:error, String.t()}
  def down(%Config{} = cfg) do
    case Proc.read_pidfile(pidfile(cfg)) do
      {:ok, pid} -> down_pid(cfg, pid)
      :none -> :no_pidfile
    end
  end

  # Identitaetscheck vor dem Toeten (Proc.kill_checked): Nur echte
  # komki-mediator-Prozesse kriegen Signale; alles andere ist ein stale
  # pidfile, das der Aufraeumweg entfernt.
  defp down_pid(cfg, pid) do
    if mediator_alive?(pid) do
      case kill_mediator(pid) do
        :ok ->
          File.rm(pidfile(cfg))
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      File.rm(pidfile(cfg))

      {:stale, "pid " <> to_string(pid) <> " ist nicht (mehr) komki-mediator — pidfile entfernt"}
    end
  end

  @type mediator_state :: {:running, pos_integer()} | {:health_only, :no_pidfile} | :stopped

  @doc "Zustand: pidfile + Health."
  @spec status(Config.t()) :: mediator_state() | {:error, String.t()}
  def status(%Config{} = cfg) do
    case Proc.read_pidfile(pidfile(cfg)) do
      {:ok, pid} ->
        if mediator_alive?(pid) do
          {:running, pid}
        else
          {:error, "stale pidfile: pid " <> to_string(pid) <> " is not komki-mediator"}
        end

      :none ->
        # Ohne pidfile unterscheidet Health: antwortet der Socket, laeuft ein
        # fremder Prozess (pidfile verschwunden); sonst steht der Vermittler
        # wirklich unten.
        case health(cfg) do
          :ok -> {:health_only, :no_pidfile}
          {:error, _reason} -> :stopped
        end
    end
  end

  @doc "Health-Endpoint pruefen (GET /healthz ueber den Unix-Socket, mit Token)."
  @spec health(Config.t()) :: :ok | {:error, String.t()}
  def health(%Config{} = cfg) do
    case fetch_health(cfg) do
      {:ok, "200", _health} ->
        :ok

      {:ok, code, _health} ->
        {:error, "komki-mediator /healthz returned " <> code}

      {:error, reason} ->
        {:error, "komki-mediator unreachable on " <> Channel.socket_path(cfg) <> ": " <> reason}
    end
  end

  @doc "healthz-Uebertrag: {:ok, status_code, geparster Body} | {:error, reason}."
  @spec fetch_health(Config.t()) :: {:ok, String.t(), health()} | {:error, String.t()}
  def fetch_health(%Config{} = cfg) do
    with {:ok, token} <- Channel.read_token(cfg),
         {:ok, code, body} <- http_get(Channel.socket_path(cfg), token) do
      case parse_healthz(body) do
        {:ok, health} -> {:ok, code, health}
        {:error, reason} -> {:error, "healthz-Body unlesbar (" <> code <> "): " <> reason}
      end
    end
  end

  # ---------------------------------------------------------------- Aufruf-Maschine

  defp spawn_mediator(%Config{} = cfg) do
    log_path = log_path(cfg)
    File.mkdir_p!(Path.dirname(log_path))
    line = spawn_line(cfg)

    case System.cmd("/bin/sh", ["-c", line]) do
      {out, 0} ->
        case Integer.parse(String.trim_trailing(out)) do
          {pid, ""} when pid > 0 ->
            File.write!(pidfile(cfg), to_string(pid) <> "\n")
            wait_health(cfg, pid)

          _ ->
            {:error, "komki-mediator spawn: unexpected pid line: " <> Kernel.inspect(out)}
        end

      {out, code} ->
        {:error, "komki-mediator spawn failed (exit " <> to_string(code) <> "): " <> out}
    end
  end

  @doc """
  Spawn-Zeile fuer /bin/sh -c (nohup, Args, Log-Umleitung, pid-Ausgabe).
  Rein: Binary und Pfade werden sh-gequotet — testbar ohne echten
  Prozess. Das Token steht nicht in der Zeile, nur der Pfad der
  Token-Datei. Scaffold in KomkiCli.Proc.spawn_line/3.
  """
  @spec spawn_line(Config.t()) :: String.t()
  def spawn_line(%Config{} = cfg) do
    Proc.spawn_line(
      cfg.mediator_bin,
      [
        "--base",
        Proc.quote_bin(cfg.base_dir),
        "--socket",
        Proc.quote_bin(Channel.socket_path(cfg)),
        "--token-file",
        Proc.quote_bin(Channel.token_path(cfg))
      ],
      log_path(cfg)
    )
  end

  defp wait_health(cfg, pid) do
    deadline = System.monotonic_time(:millisecond) + @up_timeout_ms

    check = fn ->
      case fetch_health(cfg) do
        {:ok, "200", health} -> {:ok, health}
        {:ok, code, _health} -> {:error, "healthz returned " <> code}
        {:error, reason} -> {:error, reason}
      end
    end

    case Proc.poll_health(check, "komki-mediator", deadline) do
      {:ok, health} ->
        {:ok, {:started, pid, health}}

      {:error, reason} ->
        kill_mediator(pid)
        File.rm(pidfile(cfg))
        reason = reason <> "; mediator log tail: " <> log_tail(cfg, 20)
        {:error, reason}
    end
  end

  # Kill-Eskalation TERM→KILL mit Identitaetscheck (Proc.kill_checked).
  defp kill_mediator(pid), do: Proc.kill_checked(pid, "komki-mediator")

  @doc "Prueft, ob pid existiert und als komki-mediator laeuft (ps-Kontrolle)."
  @spec mediator_alive?(integer()) :: boolean()
  def mediator_alive?(pid), do: Proc.pid_alive?(pid, "komki-mediator")

  @doc "Log-Tail als Einzeiler kontrolliert fuer Fehlermeldungen."
  @spec log_tail(Config.t(), pos_integer()) :: String.t()
  def log_tail(cfg, lines), do: Proc.log_tail(log_path(cfg), lines)

  # ---------------------------------------------------------------- Pipeline-Helfer

  defp log_path(cfg), do: Path.join([cfg.base_dir, "tmp", "mediator.log"])
  defp pidfile(cfg), do: Path.join([cfg.base_dir, "tmp", "komki-mediator.pid"])

  @doc """
  GET /healthz ueber den Unix-Socket (minimales HTTP/1.1, `:gen_tcp`
  mit `{:local, path}`); {:ok, status_code_string, body} oder
  {:error, reason} — im Unterschied zu llama http_get_200 wird hier auch
  der BODY gelesen (healthz muss das Fassung-Angebot hergeben).
  """
  @spec http_get(String.t(), String.t()) :: {:ok, String.t(), String.t()} | {:error, String.t()}
  def http_get(socket_path, token) when is_binary(socket_path) and is_binary(token) do
    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false], 3000) do
      {:ok, socket} ->
        :gen_tcp.send(
          socket,
          "GET /healthz HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer " <>
            token <> "\r\nConnection: close\r\n\r\n"
        )

        case recv_all(socket, <<>>, now_deadline(3000)) do
          {:ok, raw} ->
            :gen_tcp.close(socket)
            split_response(raw)

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, Kernel.inspect(reason)}
        end

      {:error, reason} ->
        {:error, Kernel.inspect(reason)}
    end
  end

  defp now_deadline(ms), do: System.monotonic_time(:millisecond) + ms

  # Connection: close: gelesen wird bis der Server die Verbindung schliesst
  # (geparst wird Trennzeichen-basiert, nicht paketweise). Akkumulator und
  # Deadline sind getrennte Parameter — der wiederholte recv rechnet NIE mit
  # den empfangenen Daten (Smoke-Fund: binary-Deadline hob die
  # Arithmetik-Schiene aus und warf alle Chunks weg).
  defp recv_all(socket, acc, deadline) do
    case :gen_tcp.recv(socket, 0, socket_timeout(deadline)) do
      {:ok, data} -> recv_all(socket, acc <> data, deadline)
      {:error, :closed} -> {:ok, acc}
      {:error, reason} -> {:error, reason}
    end
  end

  defp socket_timeout(deadline) do
    left = deadline - System.monotonic_time(:millisecond)
    max(1, min(left, @health_timeout_ms))
  end

  defp split_response(raw) do
    case :binary.split(raw, "\r\n\r\n") do
      [_head, body] -> code(raw, body)
      [_head] -> {:error, "unparseable /healthz response (no header separator)"}
    end
  end

  defp code(raw, body) do
    case Regex.run(~r/HTTP\/1\.[01] (\d{3})/, raw) do
      [_, codestr] -> {:ok, codestr, body}
      _ -> {:error, "unparseable /healthz response"}
    end
  end

  # ---------------------------------------------------------------- Fassung auf pi-Seite

  @doc """
  healthz-Body parsen: JSON-Objekt vom Vertrag (status "ok", tools als
  String-Liste). Rein — kein Prozess, kein Netz. Das JSON ist dasselbe
  eingebaute `JSON`, das config.ex fuer config.json nutzt (kein neues Dep).
  """
  @spec parse_healthz(String.t()) :: {:ok, health()} | {:error, String.t()}
  def parse_healthz(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, %{"status" => "ok"} = health} ->
        tools = Map.get(health, "tools")

        # Tools-Liste als eigene Pruefung (Guards erlauben keine Enum-Funk-
        # tionen); fehlt der Key, ist es nil und faellt durch.
        if is_list(tools) and all_strings?(tools) do
          {:ok, health}
        else
          {:error, "tools fehlt oder ist keine String-Liste"}
        end

      {:ok, %{"status" => status}} ->
        {:error, "status \"ok\" erwartet, got: " <> Kernel.inspect(status)}

      {:ok, other} ->
        {:error, "healthz-Objekt ohne status-Key: " <> Kernel.inspect(other)}

      {:error, err} ->
        {:error, "healthz parse error: " <> Kernel.inspect(err)}
    end
  end

  defp all_strings?([]), do: true
  defp all_strings?([head | rest]) when is_binary(head), do: all_strings?(rest)
  defp all_strings?(_), do: false

  @doc """
  mcp.json-Inhalt als Map (Rendering zum Schreiben via JSON, siehe
  write_mcp_config/2): Server "komki" als stdio-Server — pi startet
  `komki-relay.js` mit demselben node-Binary, das pi selbst ausfuehrt (das
  Profil erlaubt nur dieses `process-exec`). Das Relay spricht den
  Vermittler ueber den Unix-Socket an (Ticket #143).

  `env`: der Socket-Pfad als Literal, Token und Session-ID nur als Verweis
  auf pis Umgebung (`${…}`, von pi beim Start aufgeloest; fehlt eine
  Variable, verweigert pi den Server). Das Token steht damit nie in der
  Datei.

  Server-Exposure "hidden" plus GENAU die Fassung-Tools als "direct" ist
  ein bewusster Fassung-Pin auf pi-Seite: alles, was der Vermittler
  kuenftig ueber die Fassung hinaus anbieten sollte, bleibt hinter dem
  hidden-Default verborgen.
  """
  @spec mcp_config_json(Config.t(), [String.t()]) :: %{String.t() => term()}
  def mcp_config_json(%Config{} = cfg, tools_list) when is_list(tools_list) do
    %{
      "mcpServers" => %{
        "komki" => %{
          "command" => cfg.node_bin,
          "args" => [Channel.relay_path(cfg)],
          "env" => %{
            "KOMKI_MEDIATOR_SOCKET" => Channel.socket_path(cfg),
            "KOMKI_MEDIATOR_TOKEN" => "${KOMKI_MEDIATOR_TOKEN}",
            "KOMKI_SESSION_ID" => "${KOMKI_SESSION_ID}"
          },
          "exposure" => "hidden",
          "toolExposure" => Map.new(tools_list, fn tool -> {tool, "direct"} end)
        }
      }
    }
  end

  @doc """
  mcp.json ins pi-Home schreiben (nutzer-level pi-Konfig; idempotent,
  ueberschrieben). Verzeichnis wird erzeugt; Rendering via JSON genau wie
  config.json (kein neues Dep).
  """
  @spec write_mcp_config(Config.t(), [String.t()]) :: :ok
  def write_mcp_config(%Config{} = cfg, tools_list) when is_list(tools_list) do
    path = Path.join([cfg.pi_home, ".pi", "agent", "mcp.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(mcp_config_json(cfg, tools_list)) <> "\n")
    :ok
  end
end
