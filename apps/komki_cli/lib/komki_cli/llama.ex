defmodule KomkiCli.Llama do
  @moduledoc """
  llama-server-Lebenszyklus (lokal, loopback-only, keine Remote-Load-Flags).

  Gepinnt: llama-server 0.5.0, build 11146 (Flags via `--help` nachgeprüft;
  Evidenz: `docs/research/2026-10-04-probe-harness-sandbox.md` im Branch
  `research/probe-harness-sandbox`):

      -m <gguf> --host 127.0.0.1 --port <port> --alias local-model
      --jinja --offline --no-webui --no-slots -c <ctx>

  `--offline` und die Nichtverwendung von `-mu/-hf/-dr` sind Pflicht
  (Quellenbindung: nur das lokale, SHA-verifizierte Artefakt).
  """

  alias KomkiCli.Config
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
    case read_pidfile(cfg) do
      {:ok, pid} -> down_pid(cfg, pid)
      :none -> :no_pidfile
    end
  end

  # Identitaetscheck vor dem Toeten: Nur echte llama-server-Prozesse kriegen
  # Signale; alles andere ist ein stale pidfile, das der Aufraeumweg entfernt.
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
    case read_pidfile(cfg) do
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

  @doc "Health-Endpoint pruefen (plain TCP auf Loopback, GET /health)."
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
      to_string(cfg.ctx)
    ]

    log_path = log_path(cfg)
    File.mkdir_p!(Path.dirname(log_path))

    line =
      "nohup " <>
        quote_bin(cfg.llama_server_bin) <>
        " " <>
        Enum.map_join(args, " ", &quote_bin/1) <>
        " > " <> quote_bin(log_path) <> " 2>&1 & echo $!"

    case System.cmd("/bin/sh", ["-c", line]) do
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
        message: "config unvollstaendig: llama-server-Pfad fehlt (init praeflight)"
      )

  defp wait_health(cfg, pid) do
    deadline = System.monotonic_time(:millisecond) + @up_timeout_ms

    case poll_health(cfg, deadline) do
      :ok ->
        {:ok, pid}

      {:error, reason} ->
        kill_llama(pid)
        File.rm(pidfile(cfg))
        reason = reason <> "; llama log tail: " <> log_tail(cfg, 20)
        {:error, reason}
    end
  end

  defp poll_health(cfg, deadline) do
    case health(cfg) do
      :ok ->
        :ok

      {:error, reason} ->
        now = System.monotonic_time(:millisecond)

        if now >= deadline do
          {:error, "llama-server health timeout (" <> reason <> ")"}
        else
          Process.sleep(500)
          poll_health(cfg, deadline)
        end
    end
  end

  defp kill_llama(pid) do
    # Nur llama-server: der pid-Prozess wird zuerst per `ps` identifiziert
    # (Pidfile-Wiederverwendungsschutz). kill liegt auf macOS in /bin/kill
    # (/usr/bin/kill existiert nicht — Smoke-Fund 5f: rohes :enoent).
    if llama_alive?(pid) do
      System.cmd("/bin/kill", ["-TERM", to_string(pid)])
      Process.sleep(800)

      if llama_alive?(pid) do
        System.cmd("/bin/kill", ["-KILL", to_string(pid)])
        Process.sleep(300)
      end

      if llama_alive?(pid) do
        {:error, "llama-server pid " <> to_string(pid) <> " still alive after SIGKILL"}
      else
        :ok
      end
    else
      {:error,
       "pid " <> to_string(pid) <> " is not llama-server (pidfile stale); not sent any signal"}
    end
  end

  @doc "Prueft, ob pid existiert und als llama-server laeuft (ps-Kontrolle)."
  @spec llama_alive?(integer()) :: boolean()
  def llama_alive?(pid) when is_integer(pid) and pid > 0 do
    case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "command="]) do
      {out, 0} -> String.contains?(out, "llama-server")
      _ -> false
    end
  end

  def llama_alive?(_), do: false

  @doc "Log-Tail als Einzeiler kontrolliert fuer Fehlermeldungen."
  @spec log_tail(Config.t(), pos_integer()) :: String.t()
  def log_tail(cfg, lines) do
    path = log_path(cfg)

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.map(&String.trim_trailing/1)
      |> Stream.take(-lines)
      |> Enum.join(" | ")
    else
      "(no log)"
    end
  end

  # ---------------------------------------------------------------- Pipeline-Helfer

  defp port(cfg), do: cfg.port

  defp log_path(cfg), do: Path.join([cfg.base_dir, "tmp", "llama-server.log"])
  defp pidfile(cfg), do: Path.join([cfg.base_dir, "tmp", "llama-server.pid"])

  defp read_pidfile(cfg) do
    case File.read(pidfile(cfg)) do
      {:ok, content} ->
        case Integer.parse(String.trim_trailing(content)) do
          {pid, ""} when pid > 0 -> {:ok, pid}
          _ -> {:error, "corrupt pidfile: " <> Kernel.inspect(content)}
        end

      {:error, :enoent} ->
        :none

      {:error, posix} ->
        {:error, "cannot read pidfile: " <> List.to_string(:file.format_error(posix))}
    end
  end

  @doc "GET /health via plain TCP; {:ok, status_code_string} oder {:error, reason}."
  @spec http_get_200(pos_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def http_get_200(port) when is_integer(port) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 3000) do
      {:ok, socket} ->
        :gen_tcp.send(
          socket,
          "GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
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

  ## Shell-Quote fuer Spawn-Zeile (keine Pfad-Injection).
  defp quote_bin(bin) when is_binary(bin) do
    "'" <> String.replace(bin, "'", "'\\''") <> "'"
  end
end
