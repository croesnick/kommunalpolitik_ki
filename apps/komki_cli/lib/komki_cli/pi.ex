defmodule KomkiCli.Pi do
  @moduledoc """
  pi-Laufmodi unter dem generierten Seatbelt-Profil:

    * **Einmal-Lauf** (`run/4`): headless `--print`, stdin aus `/dev/null`,
      ephemeral (keine Session-Datei).
    * **Interaktive Session** (`argv_session/2`, aufgerufen vom internen
      `session-chain`): pi als Port-Kind des Pane-BEAM mit `:nouse_stdio` —
      die tmux-Pty ist das Terminal. Persistente Session-Dateien unter
      `pi-home/sessions`, fortsetzbar via pi `--continue`.

  Environment (identisch fuer beide Modi — die validierte Lauf-Konvention):

      HOME               = pi-home
      TMPDIR             = pi-home/tmp
      PATH               = /usr/bin:/bin
      XDG_CONFIG_HOME    = pi-home/.config
      XDG_DATA_HOME      = pi-home/.local/share
      XDG_CACHE_HOME     = pi-home/.cache
      NODE_COMPILE_CACHE = pi-home/.cache/node-compile
      PI_OFFLINE         = 1
      LANG / LC_ALL      = C

  Dazu kommt der Kanal zum Vermittler (Ticket #143, `KomkiCli.Channel`):
  `KOMKI_MEDIATOR_TOKEN` und `KOMKI_SESSION_ID`. pi reicht beide ueber die
  `env`-Felder der mcp.json an `komki-relay.js` weiter. Das Token steht nie
  in argv.

  cwd ist beim Einmal-Lauf der Scratch, in der Session die Arbeitsflaeche
  `arbeit` — nie das pi-Home (Ticket #133): pi laedt `AGENTS.md`/`CLAUDE.md`
  aus dem cwd; ein gekapertes Modell koennte sie per `write` dort ablegen
  und sich so in jeden spaeteren Lauf einnisten. Zusaetzlich schaltet
  `--no-context-files` die Discovery ganz ab. Beim Einmal-Lauf kommt stdin aus /dev/null:
  pi liest gepipete stdin als Prompt-Quelle; eine offene Pipe haengt.
  Deshalb startet der Einmal-Lauf ueber
  `/bin/sh -c 'exec "$0" "$@" < /dev/null'` — argv-Einzelwerte, keine
  Shell-Interpolation des Prompts. Die interaktive Session umgeht das:
  tmux stellt eine echte Pty; dort wuerde ein Redirect die Eingabe kappen.
  pi wird in beiden Faellen ueber die aufgeloeste Direktkette
  node -> cli.js gestartet (der asdf-Shim scheitert unter dem Profil stumm).
  """

  alias KomkiCli.Config
  require Config

  @session_term "xterm-256color"

  @incomplete_tools_msg "config unvollstaendig: node/cli/llama-server fehlen — init verweigert unvollstaendige Instanzen"

  @type mode :: :text | :json

  @timeout_status 124

  @doc """
  Einmal-Lauf mit Laufzeit-Limit (Ticket #133): Nach `timeout_ms` beendet
  komki pi per SIGTERM und meldet Status 124 (Konvention von timeout(1)).
  sandbox-exec und `sh -c 'exec …'` ersetzen sich per exec, die OS-pid des
  Ports ist deshalb der node-Prozess selbst.
  """
  @spec run(
          Config.t(),
          String.t(),
          mode(),
          String.t(),
          pos_integer(),
          %{String.t() => String.t()}
        ) ::
          {:ok, output :: String.t()}
          | {:error, output :: String.t(), status :: integer()}
  def run(%Config{} = cfg, scratch_dir, mode, prompt, timeout_ms, channel_env)
      when mode in [:text, :json] and is_binary(prompt) and is_integer(timeout_ms) and
             timeout_ms > 0 and is_map(channel_env) do
    profile_path = profile_path_for(cfg, scratch_dir)
    KomkiCli.Profile.write!(profile_path, KomkiCli.Profile.generate(cfg, scratch_dir))
    [program | args] = argv_for(cfg, scratch_dir, mode, prompt)
    env = Map.merge(env_for(cfg), channel_env)
    run_with_timeout(program, args, env, scratch_dir, timeout_ms)
  end

  @doc """
  Startet `program` als Port-Kind (der Weg, auf dem node unter dem
  macOS-27.2-Beta bootet), sammelt stdout und beendet den Prozess nach
  `timeout_ms` per SIGTERM (Status 124). Public als Testnaht.
  """
  @spec run_with_timeout(
          String.t(),
          [String.t()],
          %{String.t() => String.t()},
          String.t(),
          pos_integer()
        ) ::
          {:ok, String.t()} | {:error, String.t(), integer()}
  def run_with_timeout(program, args, env, cwd, timeout_ms) do
    env = Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    port =
      Port.open({:spawn_executable, program}, [
        :binary,
        :exit_status,
        {:args, args},
        {:env, env},
        {:cd, cwd}
      ])

    timer = Process.send_after(self(), {:komki_run_timeout, port}, timeout_ms)
    result = collect(port, [], false)
    Process.cancel_timer(timer)
    flush_timeout(port)
    result
  end

  defp collect(port, acc, timed_out?) do
    receive do
      {^port, {:data, data}} ->
        collect(port, [acc, data], timed_out?)

      {^port, {:exit_status, status}} ->
        out = IO.iodata_to_binary(acc)

        cond do
          timed_out? ->
            {:error, out <> "\n[komki: Laufzeit-Limit erreicht, pi beendet]", @timeout_status}

          status == 0 ->
            {:ok, out}

          true ->
            {:error, out, status}
        end

      {:komki_run_timeout, ^port} ->
        with {:os_pid, pid} <- Port.info(port, :os_pid) do
          System.cmd("/bin/kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
        end

        collect(port, acc, true)
    end
  end

  defp flush_timeout(port) do
    receive do
      {:komki_run_timeout, ^port} -> :ok
    after
      0 -> :ok
    end
  end

  # ===========================================================================
  # Interaktive Session (tmux-Pty als stdin)
  # ===========================================================================

  @doc "pi-Session-Verzeichnis (persistente Session-Dateien unter pi-home)."
  @spec session_dir(Config.t()) :: String.t()
  def session_dir(%Config{} = cfg), do: Path.join(cfg.pi_home, "sessions")

  @doc """
  Profil-Pfad der interaktiven Session (eine tmux-Session gleichzeitig,
  deshalb stabler Name statt Lauf-Hash).
  """
  @spec session_profile_path(Config.t()) :: String.t()
  def session_profile_path(%Config{} = cfg),
    do: Path.join([cfg.base_dir, "tmp", "profile-session.sb"])

  # Burrito-TTY-Redirect (Pilot 2026-10-11): $0/$1-Form wie beim Einmal-Lauf
  # (argv_for), nur dass stdout auf das lebende stdin-PTY (fd 0) umbiegt —
  # unter der Binary ist das BEAM-stdout die Wrapper-Pipe, pi beendet sich
  # ohne echtes Terminal sofort (Issue-#234-Klasse).
  @redirect_stdout_sh ~s(exec "$0" "$@" > /dev/fd/0)

  @doc """
  argv der interaktiven Session: sandbox-exec-Direktkette ohne `--print`
  und ohne stdin-Redirect (die tmux-Pty ist stdin — ein `/dev/null`-Redirect
  wuerde die TUI-Eingabe kappen). Fuer Doctor/Tests sichtbar.

  `tty_redirect` (Burrito-Fix, Pilot 2026-10-11): Mit `true` laeuft die
  Kette ueber `/bin/sh -c` und leitet stdout auf `/dev/fd/0` um (Dup des
  lebenden stdin-PTY), weil unter der Standalone-Binary das BEAM-stdout
  die Wrapper-Pipe ist. Der Escript-Pfad nutzt die Direktkette weiter
  (dort ist stdout ohnehin die Pane-PTY); das passende Profil erlaubt das
  Oeffnen von /dev/fd/0 kontextfrei.
  """
  @spec argv_session(Config.t(), boolean(), boolean()) :: [String.t()]

  # Header fuehrt den Default (Multi-Clause-Konvention): Escript-Pfad ruft
  # argv_session/2 ohne Redirect-Angabe, session_chain gibt den Kontext mit.
  def argv_session(cfg, continue?, tty_redirect \\ false)

  def argv_session(%Config{} = cfg, continue?, tty_redirect)
      when is_boolean(continue?) and is_boolean(tty_redirect) and Config.tools_ready(cfg) do
    prefix = [cfg.sandbox_exec, "-f", session_profile_path(cfg), "--"]

    chain =
      if tty_redirect do
        ["/bin/sh", "-c", @redirect_stdout_sh, cfg.node_bin, cfg.cli_js]
      else
        [cfg.node_bin, cfg.cli_js]
      end

    prefix ++ chain ++ session_flags(cfg, continue?)
  end

  def argv_session(%Config{}, _continue?, _tty_redirect),
    do: raise(ArgumentError, message: @incomplete_tools_msg)

  @doc "Lauf-Umgebung als Key-Value-Paare (deterministisch sortiert)."
  @spec env_list(Config.t()) :: [{String.t(), String.t()}]
  def env_list(%Config{} = cfg), do: cfg |> env_for() |> Map.to_list() |> Enum.sort()

  @doc """
  Session-Umgebung fuer den Port-Replace: Lauf-Umgebung plus Kanal
  (`KOMKI_MEDIATOR_TOKEN`, `KOMKI_SESSION_ID`, Ticket #143) plus `TERM` fuer
  die TUI. Der Port-Env ersetzt die geerbte Umgebung komplett — dieselbe
  Konvention wie beim Einmal-Lauf via `System.cmd`-env-Replace.
  """
  @spec session_env(Config.t(), %{String.t() => String.t()}) :: [{String.t(), String.t()}]
  def session_env(%Config{} = cfg, channel_env) when is_map(channel_env),
    do: env_list(cfg) ++ Enum.sort(channel_env) ++ [{"TERM", @session_term}]

  @doc """
  Pane-Kommando fuer `tmux new-session … <command>`: der Pfad des
  komki-Programms (Escript oder Burrito-Standalone-Binary, vom Aufrufer
  übergeben — `KomkiCli.Runtime.self_path/0`) plus dem internen
  `session-chain`-Befehl.

  Statt die Sandbox-Kette direkt in die Pane zu legen, startet die Pane
  einen eigenen Mini-BEAM (das komki-Programm selbst). Hintergrund ist ein
  macOS-27.2-Beta-Fund aus der Crash-Analyse: node crasht beim Init mit
  SIGABRT, sobald es aus einer gewoehnlichen fork-Kette geboren wird
  (Shell, tmux-Server), bootet aber problemlos als Port-Kind eines BEAM —
  der VM-Start raeumt den vererbten Prozesszustand auf. `session-chain`
  haelt die Seatbelt-Grenze unverletzt: sandbox-exec bleibt der Anfang
  des gepinnten Kettenstücks.
  """
  @spec pane_command(String.t(), boolean()) :: String.t()
  def pane_command(script_path, continue?) when is_binary(script_path) do
    args =
      [Path.expand(script_path), "session-chain"] ++ if(continue?, do: ["--continue"], else: [])

    Enum.map_join(args, " ", &sh_quote/1)
  end

  # Knapper KomKI-System-Prompt (Nutzer-Wunsch: geeignet, per Default
  # Deutsch). Ersetzt pis Coding-Assistenten-Default — der KomkiCli ist
  # Ratsarbeit, nicht Codearbeit.
  @komki_system_prompt "Antworte knapp und präzise, per Default auf Deutsch und durchgehend in der Du-Form. Du bist Assistent für kommunalpolitische Arbeit in einem lokalen, offline laufenden Arbeitsraum. Belege sachliche Aussagen mit Quellen, wo vorhanden, und markiere Unsicherheit offen."

  defp session_flags(cfg, continue?) do
    base =
      [
        "--offline"
        | mcp_contract_flags()
      ] ++
        [
          "--no-skills",
          "--no-context-files",
          "--no-prompt-templates",
          "--no-themes",
          # KEIN --no-approve hier: Der Flag erzwingt "untrusted" und uebersteuert
          # den trust.json-Eintrag aus dem init — die Trust-Warnung waere die Folge.
          # Headless-Laeufe (pi_flags) behalten --no-approve: dort gibt es keinen
          # Projekt-Kontext.
          "--session-dir",
          session_dir(cfg),
          # ls ist reines Node (kein Binary noetig) — ohne es kann der Agent
          # Verzeichnisse nicht sehen und rät dann zu read . (EISDIR-Live-Fund).
          # find/grep brauchen fd/rg: init kopiert sie in pi's agent-bin-Fundus;
          # fehlen sie auf dem Host, bleiben die Tools ehrlich weg.
          "--tools",
          tools_list(cfg),
          "--system-prompt",
          @komki_system_prompt,
          "--provider",
          "pi-local",
          "--model",
          "local-model"
        ]

    if continue?, do: ["--continue" | base], else: base
  end

  # MCP-Vertrag (Ticket #102, identisch in Session und Einmal-Lauf):
  # `-ne` schaltet ALLE Extensions tot; das explizite `-e builtin:mcp`
  # reaktiviert NUR die eingebaute Extension MCP fuer die Vermittler-
  # Verbindung (pi >= 1.0; Issue #103: kein Pin).
  defp mcp_contract_flags, do: ["--no-extensions", "-e", "builtin:mcp"]

  # Vermittler-Tools (Ticket #133): pi 1.1.0 blendet MCP-Tools aus, sobald
  # --tools eine Allowlist traegt (Live-Fund: das Modell sah nur `write`).
  # Das Muster schaltet genau den Server `komki` frei; welche seiner Tools
  # sichtbar sind, pinnt weiter die mcp.json (exposure hidden + direct).
  @mediator_tools "mcp__komki__*"

  # ls ist immer dabei (reines Node); find/grep nur mit entdeckter Binary —
  # sonst scheitert der Tool-Aufruf erst zur Laufzeit.
  defp tools_list(%Config{} = cfg) do
    ["read", "write", "ls"]
    |> maybe_tool("find", cfg.fd_bin)
    |> maybe_tool("grep", cfg.rg_bin)
    |> Kernel.++([@mediator_tools])
    |> Enum.join(",")
  end

  defp maybe_tool(names, _tool, nil), do: names

  defp maybe_tool(names, tool, _binary), do: names ++ [tool]

  defp sh_quote(bin) when is_binary(bin),
    do: "'" <> String.replace(bin, "'", "'\\''") <> "'"

  # ---------------------------------------------------------------- Helfer

  defp pi_flags(mode, scratch_dir) do
    ["--print", "--mode", Atom.to_string(mode), "--offline"] ++
      mcp_contract_flags() ++
      [
        "--no-skills",
        "--no-context-files",
        "--no-prompt-templates",
        "--no-themes",
        "--no-approve",
        "--no-session",
        "--session-dir",
        Path.join(scratch_dir, "pi-sessions"),
        "--tools",
        "write," <> @mediator_tools,
        "--provider",
        "pi-local",
        "--model",
        "local-model"
      ]
  end

  @doc "Lauf-Umgebung (validierte Konvention)."
  @spec env_for(Config.t()) :: %{binary() => binary()}
  def env_for(cfg) do
    %{
      "PATH" => "/usr/bin:/bin",
      "HOME" => cfg.pi_home,
      "TMPDIR" => Path.join([cfg.pi_home, "tmp"]),
      "XDG_CONFIG_HOME" => Path.join([cfg.pi_home, ".config"]),
      "XDG_DATA_HOME" => Path.join([cfg.pi_home, ".local", "share"]),
      "XDG_CACHE_HOME" => Path.join([cfg.pi_home, ".cache"]),
      "NODE_COMPILE_CACHE" => Path.join([cfg.pi_home, ".cache", "node-compile"]),
      "PI_OFFLINE" => "1",
      "LANG" => "C",
      "LC_ALL" => "C"
    }
  end

  @doc "argv fuer den sandbox-exec-Aufruf (fuer Doctor/Tests sichtbar)."
  @spec argv_for(Config.t(), String.t(), mode(), String.t()) :: [String.t()]
  def argv_for(%Config{} = cfg, scratch_dir, mode, prompt) when Config.tools_ready(cfg) do
    profile_path = profile_path_for(cfg, scratch_dir)

    [
      cfg.sandbox_exec,
      "-f",
      profile_path,
      "--",
      "/bin/sh",
      "-c",
      ~s(exec "$0" "$@" < /dev/null),
      cfg.node_bin,
      cfg.cli_js
    ] ++
      pi_flags(mode, scratch_dir) ++
      [prompt]
  end

  def argv_for(%Config{}, _scratch_dir, _mode, _prompt),
    do: raise(ArgumentError, message: @incomplete_tools_msg)

  @doc "Profil-Pfad je Lauf (Scratch-Hash vermeidet Kollisionen)."
  @spec profile_path_for(Config.t(), String.t()) :: String.t()
  def profile_path_for(cfg, scratch_dir) do
    digest = :crypto.hash(:sha256, scratch_dir)
    hex = Base.encode16(digest, case: :lower)
    hash = binary_part(hex, 0, 12)

    Path.join([cfg.base_dir, "tmp", "profile-run-" <> hash <> ".sb"])
  end
end
