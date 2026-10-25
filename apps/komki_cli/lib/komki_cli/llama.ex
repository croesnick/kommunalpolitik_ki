defmodule KomkiCli.Llama do
  @moduledoc """
  llama-server-Lebenszyklus (lokal, loopback-only, keine Remote-Load-Flags).

  Gepinnt: llama-server 0.5.0, build 11146 (Flags via `--help` nachgeprüft;
  Beleg: `docs/research/2026-10-04-probe-harness-sandbox.md` im Branch
  `research/probe-harness-sandbox`):

      -m <gguf> --host 127.0.0.1 --port <port> --alias local-model
      --jinja --offline --no-webui --no-slots -c <ctx>

  `--offline` und die Nichtverwendung von `-mu/-hf/-dr` sind Pflicht
  (Quellenbindung: nur das lokale, SHA-verifizierte Artefakt).

  Confinement (Tickets #100/#111): llama-server laeuft unter der eigenen
  deny-default-Grenze `profile/llama-server.sb` — bind auf localhost:PORT
  gepinnt, Inbound nur lokal (die Enge traegt die bind-Regel), kein
  outbound. GPU/Metal-Kette freigegeben (Ticket #111): iokit-Grants
  (AGX/IOSurface), MTLCompilerService-Shader-Kompilierung, System-Haeuser;
  Messung 14.10.2026 ~53 t/s Eval unter der Grenze ≈ ungesandboxete Baseline.
  Belege: Experimentserie 14.10.2026 (llama-server 0.6.0, build 11429,
  macOS 27.2 Build 26B5101f), konsolidiert in
  `docs/research/2026-10-14-llama-server-confinement.md`.

  API-Key (Ticket #136): llama-server spiegelt jeden `Origin` in die
  CORS-Antwort. Ohne Schluessel koennte jede Website im Browser das Modell
  aufrufen und die Antwort lesen. Jeder Start erzeugt deshalb einen
  Zufallsschluessel in `<base>/tmp/llama.key` (0600), llama liest ihn per
  `--api-key-file` (ein `--api-key`-Argument waere in `ps` fuer alle
  lokalen Nutzer sichtbar), pi bekommt ihn ueber seine `models.json`.
  `/health` bleibt bei llama-server ohne Schluessel erreichbar.

  Pidfile, Kill-Eskalation, Spawn-Zeile, Health-Poll und Log-Tail sind
  mit `KomkiCli.Mediator` geteilt und liegen in `KomkiCli.Proc`.
  """

  alias KomkiCli.{Config, Proc, Profile}
  require Config

  @health_timeout_ms 10_000
  @up_timeout_ms 60_000

  @doc "Startet llama-server detached; pidfile unter base. Foreground nach `up` ist der Health-Poll."
  @spec up(Config.t()) :: {:ok, pos_integer()} | {:error, String.t()}
  def up(%Config{} = cfg) do
    case status(cfg) do
      {:running, pid} ->
        {:ok, pid}

      _ ->
        spawn_llama(cfg)
    end
  end

  @doc """
  Stoppt llama-server via pidfile (nur wenn der pid-Prozess llama-server ist).
  `:no_pidfile` wenn kein pidfile existiert; `{:stale, reason}` wenn die
  Pidfile-Pid nicht (mehr) llama-server ist — down ist der Aufräumweg: das
  stale pidfile wird entfernt, aber kein Prozess getötet (Identitätscheck).
  """
  @spec down(Config.t()) :: :ok | :no_pidfile | {:stale, String.t()} | {:error, String.t()}
  def down(%Config{} = cfg) do
    case Proc.read_pidfile(pidfile(cfg)) do
      {:ok, pid} -> down_pid(cfg, pid)
      :none -> :no_pidfile
    end
  end

  # Identitaetscheck vor dem Toeten (Proc.kill_checked): Nur echte
  # llama-server-Prozesse kriegen Signale; alles andere ist ein stale
  # pidfile, das der Aufraeumweg entfernt.
  defp down_pid(cfg, pid) do
    if llama_alive?(pid) do
      case kill_llama(pid) do
        :ok ->
          File.rm(pidfile(cfg))
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      File.rm(pidfile(cfg))

      {:stale, "pid " <> to_string(pid) <> " ist nicht (mehr) llama-server — pidfile entfernt"}
    end
  end

  @type llama_state :: {:running, pos_integer()} | {:health_only, :no_pidfile} | :stopped

  @doc "Zustand: pidfile + Health."
  @spec status(Config.t()) :: llama_state() | {:error, String.t()}
  def status(%Config{} = cfg) do
    case Proc.read_pidfile(pidfile(cfg)) do
      {:ok, pid} ->
        if llama_alive?(pid) do
          {:running, pid}
        else
          {:error, "stale pidfile: pid " <> to_string(pid) <> " is not llama-server"}
        end

      :none ->
        # Ohne pidfile unterscheidet Health: antwortet der Port, laeuft ein
        # fremder Prozess (pidfile verschwunden); sonst ist llama wirklich
        # gestoppt (Dialyzer: :stopped muss hier tatsaechlich entstehen,
        # sonst ist der Renderer-Zweig toter Code).
        case health(cfg) do
          :ok -> {:health_only, :no_pidfile}
          {:error, _reason} -> :stopped
        end
    end
  end

  @doc "Health-Endpoint prüfen (plain TCP auf Loopback, GET /health)."
  @spec health(Config.t()) :: :ok | {:error, String.t()}
  def health(%Config{} = cfg) do
    case http_get_200(port(cfg)) do
      {:ok, "200"} ->
        :ok

      {:ok, code} ->
        {:error, "llama-server /health returned " <> code}

      {:error, reason} ->
        {:error, "llama-server unreachable on port " <> to_string(port(cfg)) <> ": " <> reason}
    end
  end

  # ---------------------------------------------------------------- API-Key

  @doc "Pfad der Schlüsseldatei (außerhalb von pi-home, pi liest sie nicht)."
  @spec key_path(Config.t()) :: String.t()
  def key_path(cfg), do: Path.join([cfg.base_dir, "tmp", "llama.key"])

  @doc "Neuen Zufallsschlüssel schreiben (0600, vor dem Inhalt gesetzt)."
  @spec write_key!(Config.t()) :: String.t()
  def write_key!(cfg) do
    key = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    path = key_path(cfg)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "")
    File.chmod!(path, 0o600)
    File.write!(path, key <> "\n")
    key
  end

  @doc "Schlüssel des laufenden llama-server, falls komki ihn gestartet hat."
  @spec read_key(Config.t()) :: {:ok, String.t()} | :none
  def read_key(cfg) do
    case File.read(key_path(cfg)) do
      {:ok, content} ->
        case String.trim(content) do
          "" -> :none
          key -> {:ok, key}
        end

      {:error, _} ->
        :none
    end
  end

  @doc """
  Verlangt der laufende llama-server einen Schluessel? Fragt `/props` ohne
  Schluessel ab: 401 heisst ja, 200 heisst nein.
  """
  @spec auth_required(pos_integer()) :: {:ok, boolean()} | {:error, String.t()}
  def auth_required(port) do
    case http_get(port, "/props") do
      {:ok, "401"} -> {:ok, true}
      {:ok, "200"} -> {:ok, false}
      {:ok, code} -> {:error, "/props returned " <> code}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------- Pfade

  @doc "Log-Pfad des llama-server (tmp unter dem Instanz-Basisverzeichnis)."
  @spec log_path(Config.t()) :: String.t()
  def log_path(cfg), do: Path.join([cfg.base_dir, "tmp", "llama-server.log"])

  @doc """
  Profil-Pfad des llama-server (Ticket #100): eigene deny-default-Grenze neben
  dem pi-Profil. Abgeleitet aus profile_path (kein config.json-Feld — keine
  Migration noetig): <base>/profile/llama-server.sb.
  """
  @spec llama_profile_path(Config.t()) :: String.t()
  def llama_profile_path(%Config{} = cfg),
    do: Path.join(Path.dirname(cfg.profile_path), "llama-server.sb")

  # ---------------------------------------------------------------- Aufruf-Maschine

  defp spawn_llama(%Config{} = cfg) when Config.tools_ready(cfg) do
    args = [
      "-m",
      cfg.gguf_path,
      "--host",
      "127.0.0.1",
      "--port",
      to_string(port(cfg)),
      "--alias",
      "local-model",
      # GPU unter der Grenze (Ticket #111): kein --device none mehr — die
      # Metal-Kette traegt das Profil (auto-Offload auf MTL0); CPU-only waere
      # ~Faktor 10 langsamer (exp15/16 gegen exp18: ~5 gegen ~53 t/s Eval).
      "--jinja",
      "--offline",
      "--no-webui",
      "--no-slots",
      # Offizielle Sampling-Empfehlung der Gemma-4-Modellkarte
      # (unsloth-Guide, Abruf 05.10.2026)
      "--temp",
      "1.0",
      "--top-p",
      "0.95",
      "--top-k",
      "64",
      "-c",
      to_string(cfg.ctx),
      "--api-key-file",
      key_path(cfg)
    ]

    write_key!(cfg)

    log_path = log_path(cfg)
    File.mkdir_p!(Path.dirname(log_path))

    # Profil frisch regeneriert vor jedem Start — dasselbe Muster wie Pi.run;
    # die Doctor-Identitaet prueft dieselbe Textquelle.
    Profile.write!(llama_profile_path(cfg), Profile.generate_llama(cfg))

    # sandbox-exec -f <llama-Profil> umschliesst ausschliesslich llama-server
    # (das confine gilt dem Inferenz-Prozess); das aeussere sh behaelt die
    # fd-Plumbing-Rolle. Die Spawn-Zeile liegt kanonisch in Proc; llama
    # quottet jeden Arg selbst (spawn_line nimmt Args wortgetreu).
    sandbox_args =
      Enum.map(
        ["-f", llama_profile_path(cfg), "--", cfg.llama_server_bin | args],
        &Proc.quote_bin/1
      )

    line = Proc.spawn_line(cfg.sandbox_exec, sandbox_args, log_path)

    # cwd "/" — getcwd unter der Grenze braucht nur file-read-data "/",
    # das die Startup-Schicht erlaubt (exp14); ein ungeschuetztes Aufrufer-cwd
    # wuerde den Metadaten-Walk blocken.
    case System.cmd("/bin/sh", ["-c", line], cd: "/") do
      {out, 0} ->
        case Integer.parse(String.trim_trailing(out)) do
          {pid, ""} when pid > 0 ->
            File.write!(pidfile(cfg), to_string(pid) <> "\n")
            wait_health(cfg, pid)

          _ ->
            {:error, "llama-server spawn: unexpected pid line: " <> Kernel.inspect(out)}
        end

      {out, code} ->
        {:error, "llama-server spawn failed (exit " <> to_string(code) <> "): " <> out}
    end
  end

  defp spawn_llama(%Config{} = _cfg),
    do:
      raise(ArgumentError,
        message: "config unvollständig: llama-server-Pfad fehlt (init praeflight)"
      )

  defp wait_health(cfg, pid) do
    deadline = System.monotonic_time(:millisecond) + @up_timeout_ms

    check = fn ->
      case health(cfg) do
        :ok -> {:ok, :ok}
        {:error, reason} -> {:error, reason}
      end
    end

    case Proc.poll_health(check, "llama-server", deadline) do
      {:ok, :ok} ->
        {:ok, pid}

      {:error, reason} ->
        kill_llama(pid)
        File.rm(pidfile(cfg))
        reason = reason <> "; llama log tail: " <> log_tail(cfg, 20)
        {:error, reason}
    end
  end

  # Kill-Eskalation TERM→KILL mit Identitaetscheck (Proc.kill_checked).
  defp kill_llama(pid), do: Proc.kill_checked(pid, "llama-server")

  @doc "Prüft, ob pid existiert und als llama-server läuft (ps-Kontrolle)."
  @spec llama_alive?(integer()) :: boolean()
  def llama_alive?(pid), do: Proc.pid_alive?(pid, "llama-server")

  @doc "Log-Tail als Einzeiler kontrolliert für Fehlermeldungen."
  @spec log_tail(Config.t(), pos_integer()) :: String.t()
  def log_tail(cfg, lines), do: Proc.log_tail(log_path(cfg), lines)

  # ---------------------------------------------------------------- Pipeline-Helfer

  defp port(cfg), do: cfg.port

  defp pidfile(cfg), do: Path.join([cfg.base_dir, "tmp", "llama-server.pid"])

  @doc "GET /health via plain TCP; {:ok, status_code_string} oder {:error, reason}."
  @spec http_get_200(pos_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def http_get_200(port) when is_integer(port), do: http_get(port, "/health")

  defp http_get(port, path) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 3000) do
      {:ok, socket} ->
        :gen_tcp.send(
          socket,
          "GET " <> path <> " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )

        case recv_all(socket, <<>>, now_deadline(3000)) do
          {:ok, body} ->
            :gen_tcp.close(socket)
            code(body)

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, Kernel.inspect(reason)}
        end

      {:error, reason} ->
        {:error, Kernel.inspect(reason)}
    end
  end

  defp now_deadline(ms), do: System.monotonic_time(:millisecond) + ms

  defp recv_all(socket, acc, deadline) do
    case :gen_tcp.recv(socket, 0, socket_timeout(deadline)) do
      {:ok, data} ->
        if String.contains?(acc <> data, "\r\n\r\n") do
          {:ok, acc <> data}
        else
          recv_all(socket, acc <> data, deadline)
        end

      {:error, :closed} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp socket_timeout(deadline) do
    left = deadline - System.monotonic_time(:millisecond)
    max(1, min(left, @health_timeout_ms))
  end

  defp code(body) do
    case Regex.run(~r/HTTP\/1\.[01] (\d{3})/, body) do
      [_, codestr] -> {:ok, codestr}
      _ -> {:error, "unparseable /health response"}
    end
  end
end
