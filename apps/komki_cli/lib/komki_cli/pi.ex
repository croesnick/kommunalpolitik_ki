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

  cwd ist das pi-Home. Beim Einmal-Lauf kommt stdin aus /dev/null:
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

  @spec run(Config.t(), String.t(), mode(), String.t()) ::
          {:ok, output :: String.t()}
          | {:error, output :: String.t(), status :: integer()}
  def run(%Config{} = cfg, scratch_dir, mode, prompt)
      when mode in [:text, :json] and is_binary(prompt) do
    profile_path = profile_path_for(cfg, scratch_dir)
    KomkiCli.Profile.write!(profile_path, KomkiCli.Profile.generate(cfg, scratch_dir))
    argv = argv_for(cfg, scratch_dir, mode, prompt)

    case System.cmd(hd(argv), tl(argv), env: env_for(cfg), cd: cfg.pi_home) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, out, code}
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

  @doc """
  argv der interaktiven Session: sandbox-exec-Direktkette ohne `--print`
  und ohne stdin-Redirect (die tmux-Pty ist stdin — ein `/dev/null`-Redirect
  wuerde die TUI-Eingabe kappen). Fuer Doctor/Tests sichtbar.
  """
  @spec argv_session(Config.t(), boolean()) :: [String.t()]
  def argv_session(%Config{} = cfg, continue?)
      when is_boolean(continue?) and Config.tools_ready(cfg) do
    [cfg.sandbox_exec, "-f", session_profile_path(cfg), "--", cfg.node_bin, cfg.cli_js] ++
      session_flags(cfg, continue?)
  end

  def argv_session(%Config{}, _continue?),
    do: raise(ArgumentError, message: @incomplete_tools_msg)

  @doc "Lauf-Umgebung als Key-Value-Paare (deterministisch sortiert)."
  @spec env_list(Config.t()) :: [{String.t(), String.t()}]
  def env_list(%Config{} = cfg), do: cfg |> env_for() |> Map.to_list() |> Enum.sort()

  @doc """
  Session-Umgebung fuer den Port-Replace: Lauf-Umgebung plus `TERM` fuer
  die TUI. Der Port-Env ersetzt die geerbte Umgebung komplett — dieselbe
  Konvention wie beim Einmal-Lauf via `System.cmd`-env-Replace.
  """
  @spec session_env(Config.t()) :: [{String.t(), String.t()}]
  def session_env(%Config{} = cfg),
    do: env_list(cfg) ++ [{"TERM", @session_term}]

  @doc """
  Pane-Kommando fuer `tmux new-session … <command>`: der Pfad des
  komki-Escripts plus dem internen `session-chain`-Befehl.

  Statt die Sandbox-Kette direkt in die Pane zu legen, startet die Pane
  einen eigenen Mini-BEAM (das Escript selbst). Hintergrund ist ein
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
    base = [
      "--offline",
      "--no-extensions",
      "--no-skills",
      "--no-prompt-templates",
      "--no-themes",
      # KEIN --no-approve hier: Der Flag erzwingt "untrusted" und uebersteuert
      # den trust.json-Eintrag aus dem init — die Trust-Warnung waere die Folge.
      # Headless-Laeufe (argv_for) behalten --no-approve: dort gibt es keinen
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

  # ls ist immer dabei (reines Node); find/grep nur mit entdeckter Binary —
  # sonst scheitert der Tool-Aufruf erst zur Laufzeit.
  defp tools_list(%Config{} = cfg) do
    ["read", "write", "ls"]
    |> maybe_tool("find", cfg.fd_bin)
    |> maybe_tool("grep", cfg.rg_bin)
    |> Enum.join(",")
  end

  defp maybe_tool(names, _tool, nil), do: names

  defp maybe_tool(names, tool, _binary), do: names ++ [tool]

  defp sh_quote(bin) when is_binary(bin),
    do: "'" <> String.replace(bin, "'", "'\\''") <> "'"

  # ---------------------------------------------------------------- Helfer

  defp pi_flags(mode, scratch_dir) do
    [
      "--print",
      "--mode",
      Atom.to_string(mode),
      "--offline",
      "--no-extensions",
      "--no-skills",
      "--no-prompt-templates",
      "--no-themes",
      "--no-approve",
      "--no-session",
      "--session-dir",
      Path.join(scratch_dir, "pi-sessions"),
      "--tools",
      "write",
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
