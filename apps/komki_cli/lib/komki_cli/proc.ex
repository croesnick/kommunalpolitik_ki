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

  @typedoc """
  Basis-Anker (Ticket #164): ein Pfad, der als ganzes Wort in der
  ps-Kommandozeile stehen muss (`String.t()`), oder eine Datei, die der
  Prozess offen hält (`{:open_file, pfad}`, Vergleich über die Inode).
  """
  @type anchor :: String.t() | {:open_file, String.t()} | nil

  @doc """
  Prüft, ob pid existiert, den `marker` in der ps-Kommandozeile fährt und –
  mit `anchor` – zu genau einer Basis gehört (Ticket #164).

  Der Prozessname allein trennt zwei Basen nicht: ein pidfile mit der PID
  eines gleichartigen Prozesses einer anderen Basis würde sonst als eigener
  gelten. Ein Pfad-`anchor` (Socket, Schlüsseldatei) muss als ganzes Wort in
  der Kommandozeile stehen (`ps -ww`: macOS kürzt lange Zeilen sonst);
  Wortgrenzen verhindern, dass `/x/run` in `/y/x/run` gefunden wird. Der
  Egress startet ohne Argumente und trägt die Basis nur in seinem Log
  (stdout), und macOS zeigt Umgebungen nicht an: dort bindet
  `{:open_file, log}` über `lsof` an die Inode der Log-Datei. Ohne `anchor`
  (`nil`) gilt nur der Marker.
  """
  @spec pid_alive?(term(), String.t(), anchor()) :: boolean()
  def pid_alive?(pid, marker, anchor \\ nil)

  def pid_alive?(pid, marker, anchor) when is_integer(pid) and pid > 0 do
    case System.cmd("/bin/ps", ["-ww", "-p", to_string(pid), "-o", "command="]) do
      {out, 0} -> String.contains?(out, marker) and anchored?(pid, out, anchor)
      _ -> false
    end
  end

  def pid_alive?(_pid, _marker, _anchor), do: false

  defp anchored?(_pid, _out, nil), do: true

  defp anchored?(pid, _out, {:open_file, path}) do
    with {:ok, %File.Stat{inode: inode}} <- File.stat(path),
         {out, 0} <-
           System.cmd("/usr/sbin/lsof", ["-nP", "-Fi", "-a", "-p", to_string(pid), "-d", "0-9"]) do
      ("i" <> Integer.to_string(inode)) in String.split(out, "\n", trim: true)
    else
      _ -> false
    end
  end

  defp anchored?(_pid, out, anchor) do
    padded = " " <> String.trim(out) <> " "
    String.contains?(padded, " " <> anchor <> " ")
  end

  @doc """
  Kill mit Identitaetscheck und Eskalation: SIGTERM, nach 800 ms SIGKILL,
  danach Rest-Lebensprobe. Nur der pid-Prozess mit dem eigenen `marker`
  (z. B. "llama-server" / "komki-mediator") und dem Basis-`anchor`
  (`pid_alive?/3`) kriegt Signale; alles andere ist ein stale pidfile bzw.
  ein Prozess einer fremden Basis und erzeugt `{:error, ...}` statt eines
  Treffers.
  """
  @spec kill_checked(term(), String.t(), anchor()) :: :ok | {:error, String.t()}
  def kill_checked(pid, marker, anchor \\ nil) do
    if pid_alive?(pid, marker, anchor) do
      # Burrito-Einzeldatei (Ticket #181): der Wrapper startet die VM als
      # Kindprozess. Nur den Wrapper zu beenden liesse die Rolle als Waise
      # weiterlaufen; deshalb alle Nachfahren mit demselben Marker mit.
      family = [pid | marked_descendants(pid, marker, anchor)]
      signal(family, "-TERM")
      Process.sleep(800)

      case Enum.filter(family, &pid_alive?(&1, marker, anchor)) do
        [] ->
          :ok

        alive ->
          signal(alive, "-KILL")
          Process.sleep(300)
      end

      if Enum.any?(family, &pid_alive?(&1, marker, anchor)) do
        {:error, marker <> " pid " <> to_string(pid) <> " still alive after SIGKILL"}
      else
        :ok
      end
    else
      {:error, not_ours(pid, marker)}
    end
  end

  @doc "Meldung für eine pid, die nicht `marker` dieser Basis ist (stale oder fremd)."
  @spec not_ours(integer(), String.t()) :: String.t()
  def not_ours(pid, marker) do
    "pid " <>
      to_string(pid) <>
      " ist nicht (mehr) " <>
      marker <> " dieser Basis (stale oder fremd) — kein Signal gesendet, pidfile entfernt"
  end

  defp signal(pids, sig), do: System.cmd("/bin/kill", [sig | Enum.map(pids, &to_string/1)])

  @doc "Nachfahren von `pid` (rekursiv per pgrep -P), die `marker` in der Kommandozeile tragen."
  @spec marked_descendants(pos_integer(), String.t(), anchor()) :: [pos_integer()]
  def marked_descendants(pid, marker, anchor \\ nil) do
    pid
    |> descendants()
    |> Enum.filter(&pid_alive?(&1, marker, anchor))
  end

  defp descendants(pid) do
    case System.cmd("/usr/bin/pgrep", ["-P", to_string(pid)], stderr_to_stdout: true) do
      {out, 0} ->
        children = out |> String.split("\n", trim: true) |> Enum.map(&String.to_integer/1)
        children ++ Enum.flat_map(children, &descendants/1)

      _ ->
        []
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
  der Shell an den Hintergrundprozess durch, `"< /dev/null"` schliesst es.

  POSIX gibt einem `&`-Job in einer nicht-interaktiven Shell /dev/null als
  stdin, BEVOR explizite Umleitungen greifen; ein schlichtes `0<&0`
  duplizierte dann nur /dev/null (dash auf Linux; bash auf macOS ist
  nachsichtiger). Deshalb wird stdin vorher auf fd 3 gesichert und im Job
  explizit von dort umgeleitet (`exec 3<&0; … 0<&3 3<&- &`).
  """
  @spec spawn_line(String.t(), [String.t()], String.t(), String.t()) :: String.t()
  def spawn_line(binary, args, log_path, stdin_redirect) do
    stdin_prefix(stdin_redirect) <>
      "nohup " <>
      quote_bin(binary) <>
      " " <>
      Enum.join(args, " ") <>
      stdin_part(stdin_redirect) <>
      " > " <> quote_bin(log_path) <> " 2>&1 & echo $!"
  end

  defp stdin_prefix("0<&0"), do: "exec 3<&0; "
  defp stdin_prefix(_redirect), do: ""

  defp stdin_part(""), do: ""
  defp stdin_part("0<&0"), do: " 0<&3 3<&-"
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
  Gesandboxter Start einer Rolle der Burrito-Einzeldatei (Ticket #181):

      env -i HOME=<home> PATH=/usr/bin:/bin LANG=C KOMKI_INSTALL_DIR=<dir>
        sandbox-exec -f <profil> <komki-binary> <args>

  Wie `escript_cmd/6` mit geleerter Umgebung; einzige Ergaenzung ist
  `KOMKI_INSTALL_DIR`, damit der Burrito-Wrapper die schon entpackte
  Laufzeit findet (er sucht sie sonst unter HOME, und HOME zeigt hier auf
  das Laufverzeichnis der Instanz).
  """
  @spec burrito_cmd(String.t(), String.t(), String.t(), [String.t()], String.t(), String.t()) ::
          [String.t()]
  def burrito_cmd(sandbox_exec, profile, binary, args, home, install_dir) do
    [
      "/usr/bin/env",
      "-i",
      "HOME=" <> home,
      "PATH=/usr/bin:/bin",
      "LANG=C",
      "KOMKI_INSTALL_DIR=" <> install_dir,
      sandbox_exec,
      "-f",
      profile,
      binary | args
    ]
  end

  @doc """
  Start-Wortliste einer Rolle je nach Startart der Instanz: Burrito-Binary
  oder Escript (`escript_cmd/6`, Rollenname steckt dann schon in `args`).
  """
  @spec role_cmd(KomkiCli.Config.t(), String.t(), String.t(), [String.t()], String.t()) ::
          [String.t()]
  def role_cmd(cfg, profile, binary, args, home) do
    if cfg.launcher == "burrito" and binary == cfg.komki_bin do
      burrito_cmd(
        cfg.sandbox_exec,
        profile,
        binary,
        args,
        home,
        KomkiCli.Config.burrito_install_dir(cfg)
      )
    else
      escript_cmd(cfg.sandbox_exec, profile, escript!(cfg), binary, args, home)
    end
  end

  defp escript!(%{escript_bin: bin}) when is_binary(bin), do: bin

  defp escript!(_cfg),
    do:
      raise(ArgumentError, "escript-Laufzeit nicht entdeckt (Erlang installieren, 'komki setup')")

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

  @doc "Log-Tail als Einzeiler kontrolliert für Fehlermeldungen."
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
