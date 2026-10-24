defmodule KomkiCli.Proc do
  @moduledoc """
  Gemeinsame Prozesssteuerung der langlaufenden Komponenten (llama-server,
  komki-mediator): pidfile-Read, pid-Identitaetscheck mit ps-Marker,
  Kill-Eskalation (TERM → KILL), nohup-Spawn-Zeile, Health-Poll mit
  Deadline und Log-Tail.

  `KomkiCli.Llama` und `KomkiCli.Mediator` trugen diese Mechanik doppelt
  ("gespiegelt auf KomkiCli.Llama", moduledoc dort) — beide setzen jetzt
  hier auf und halten nur die komponentenspezifischen Unterschiede lokal:
  Marker in der ps-Kommandozeile, Pidfile-/Log-Pfad, Health-Funktion und
  Poll-Deadline.

  Der Identitaetscheck liest vor jedem `kill` die `ps`-Kommandozeile
  (nur eigene Prozesse empfangen Signale — macOS-taugliche Self-Defense
  gegen pidfile-Wiederverwendung). `kill` liegt auf macOS in /bin/kill,
  `/usr/bin/kill` existiert nicht (Smoke-Fund 5f: rohes :enoent).
  """

  @doc """
  pidfile lesen: `{:ok, pid}` | `:none` (Datei fehlt) | `{:error, reason}`.
  Kaputter Inhalt ist ein Fehler, kein `:none` — stiller Repair waere
  unbeobachtbar.
  """
  @spec read_pidfile(String.t()) :: {:ok, pos_integer()} | :none | {:error, String.t()}
  def read_pidfile(path) do
    case File.read(path) do
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

  @doc "Prueft, ob pid existiert und den `marker` in der ps-Kommandozeile faehrt."
  @spec pid_alive?(term(), String.t()) :: boolean()
  def pid_alive?(pid, marker) when is_integer(pid) and pid > 0 do
    case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "command="]) do
      {out, 0} -> String.contains?(out, marker)
      _ -> false
    end
  end

  def pid_alive?(_pid, _marker), do: false

  @doc """
  Kill mit Identitaetscheck und Eskalation: SIGTERM, nach 800 ms SIGKILL,
  danach Rest-Lebensprobe. Nur der pid-Prozess mit dem eigenen `marker`
  (z. B. "llama-server" / "komki-mediator") kriegt Signale; alles andere
  ist ein stale pidfile und erzeugt `{:error, ...}` statt eines Treffers.
  """
  @spec kill_checked(term(), String.t()) :: :ok | {:error, String.t()}
  def kill_checked(pid, marker) do
    if pid_alive?(pid, marker) do
      System.cmd("/bin/kill", ["-TERM", to_string(pid)])
      Process.sleep(800)

      if pid_alive?(pid, marker) do
        System.cmd("/bin/kill", ["-KILL", to_string(pid)])
        Process.sleep(300)
      end

      if pid_alive?(pid, marker) do
        {:error, marker <> " pid " <> to_string(pid) <> " still alive after SIGKILL"}
      else
        :ok
      end
    else
      {:error,
       "pid " <> to_string(pid) <> " is not " <> marker <> " (pidfile stale); not sent any signal"}
    end
  end

  @doc """
  Spawn-Zeile fuer `/bin/sh -c` (nohup, Args, Log-Umleitung,
  pid-Ausgabe):

      nohup '<bin>' <args> > '<log>' 2>&1 & echo $!

  `binary` und `log_path` werden hier gequotet (keine Pfad-Injection);
  `args` werden wortgetreu uebernommen — die Aufrufer quotten ihre
  NavParams selbst (llama quottet jeden Arg, der Vermittler haelt
  Flags/Port bewusst unquotiert).
  """
  @spec spawn_line(String.t(), [String.t()], String.t()) :: String.t()
  def spawn_line(binary, args, log_path), do: spawn_line(binary, args, log_path, "")

  @doc """
  Spawn-Zeile mit stdin-Umleitung (Ticket #146): `"0<&0"` reicht das stdin
  der Shell an den Hintergrundprozess durch (ohne explizite Umleitung gibt
  sh einem `&`-Job /dev/null), `"< /dev/null"` schliesst es.
  """
  @spec spawn_line(String.t(), [String.t()], String.t(), String.t()) :: String.t()
  def spawn_line(binary, args, log_path, stdin_redirect) do
    "nohup " <>
      quote_bin(binary) <>
      " " <>
      Enum.join(args, " ") <>
      stdin_part(stdin_redirect) <>
      " > " <> quote_bin(log_path) <> " 2>&1 & echo $!"
  end

  defp stdin_part(""), do: ""
  defp stdin_part(redirect), do: " " <> redirect

  @doc """
  Gesandboxter Escript-Start (Ticket #146), als gequotete Wortliste fuer
  `spawn_line/4`:

      env -i HOME=<home> PATH=/usr/bin:/bin LANG=C
        sandbox-exec -f <profil> <escript> <datei> <args>

  `env -i` leert die Umgebung: Variablen aus der Shell der nutzenden Person
  (etwa API-Tokens) erreichen den gesandboxten Prozess nicht. erlexec
  verlangt HOME; es zeigt auf ein Verzeichnis, das das Profil nicht freigibt.
  Der erste Eintrag ist das Programm (`/usr/bin/env`), der Rest die
  Argumente; ungequotet (die Aufrufer quoten fuer `spawn_line/4`).
  """
  @spec escript_cmd(String.t(), String.t(), String.t(), String.t(), [String.t()], String.t()) ::
          [String.t()]
  def escript_cmd(sandbox_exec, profile, escript_bin, file, args, home) do
    [
      "/usr/bin/env",
      "-i",
      "HOME=" <> home,
      "PATH=/usr/bin:/bin",
      "LANG=C",
      sandbox_exec,
      "-f",
      profile,
      escript_bin,
      file | args
    ]
  end

  @doc """
  Startet eine Spawn-Zeile (`spawn_line/4` mit `"0<&0"`) und schreibt
  `input` in ihr stdin (Ticket #146: Credentials nur ueber stdin, nie argv
  oder Umgebung). Die Daten liegen im Pipe-Puffer, bevor die Shell
  zurueckkehrt; danach schliesst komki das Schreibende — der Kindprozess
  liest die Zeile und dann EOF. Kein Temp-File, keine Shell-Interpolation
  des Inhalts. Liefert die pid aus `echo $!`.
  """
  @spec spawn_detached(String.t(), iodata(), String.t()) ::
          {:ok, pos_integer()} | {:error, String.t()}
  def spawn_detached(line, input, cd) do
    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: ["-c", line],
        cd: cd
      ])

    Port.command(port, input)
    result = collect_spawn(port, "")
    close_quietly(port)
    result
  end

  defp collect_spawn(port, acc) do
    receive do
      {^port, {:data, data}} ->
        collect_spawn(port, acc <> data)

      {^port, {:exit_status, 0}} ->
        case Integer.parse(String.trim(acc)) do
          {pid, ""} when pid > 0 -> {:ok, pid}
          _ -> {:error, "spawn: unexpected pid line: " <> Kernel.inspect(acc)}
        end

      {^port, {:exit_status, code}} ->
        {:error, "spawn failed (exit " <> to_string(code) <> "): " <> acc}
    after
      10_000 -> {:error, "spawn: keine pid nach 10 s"}
    end
  end

  defp close_quietly(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Health-Poll mit Deadline: `check` liefert `{:ok, value}` oder
  `{:error, reason}`; im Fehlerfall alle 500 ms erneut, bis die Deadline
  (Monotonic-ms) verstrichen ist — dann "`<marker>` health timeout
  (`<reason>`)". Erfolg liefert den Check-Wert unverändert.
  """
  @spec poll_health(
          (-> {:ok, value :: term()} | {:error, String.t()}),
          String.t(),
          pos_integer()
        ) :: {:ok, term()} | {:error, String.t()}
  def poll_health(check, marker, deadline) do
    case check.() do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        now = System.monotonic_time(:millisecond)

        if now >= deadline do
          {:error, marker <> " health timeout (" <> reason <> ")"}
        else
          Process.sleep(500)
          poll_health(check, marker, deadline)
        end
    end
  end

  @doc "Log-Tail als Einzeiler kontrolliert fuer Fehlermeldungen."
  @spec log_tail(String.t(), pos_integer()) :: String.t()
  def log_tail(path, lines) do
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

  ## Shell-Quote fuer Spawn-Zeile (keine Pfad-Injection).
  @spec quote_bin(String.t()) :: String.t()
  def quote_bin(bin) when is_binary(bin) do
    "'" <> String.replace(bin, "'", "'\\''") <> "'"
  end
end
