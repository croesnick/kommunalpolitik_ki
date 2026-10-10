defmodule KomkiCli.Steps do
  @moduledoc """
  Befehls-Orchestrierung fuer den `komki`-Escript (Ticket #74).

  **CLI-Surface-Isolation (API-Vertrag):** alle menschlichen Ausgaben
  (Verdict-Zeilen, Farben, Progress-Messaging) rendert ausschliesslich
  `KomkiCli.CLI`. Diese Orchestrierung liefert *strukturierte* Resultate —
  ein späteres CLI-Library-Retrofit (owl/optimus, in Forschung) berührt nur
  die Render-Schicht in `KomkiCli.CLI`, nie Profile/Llama/Pi/Config.

  Resultatformen:

    * `{:inited, cfg, gguf_lines}` — init ok; `gguf_lines` sind Datenzeilen
      (Pfad + SHA), die CLI rendert sie.
    * `{:checks, [%{name, ok, reason}], summary_state}` — Doctor-Ergebnis;
      `summary_state` ∈ `:ok | :fail | :boot_gate_fail`.
    * `{:llama_up, pid}` — llama-server running.
    * `{:llama_down}` — sauber gestoppt; `{:llama_down, :already}` — war
      bereits unten (Idempotenz); `{:llama_down, :stale, reason}` — stale
      pidfile aufgeräumt, kein Prozess getötet.
    * `{:status, cfg, llama_state}` — Status-Snapshot (`llama_state`
      uebernimmt die Struktur aus `KomkiCli.Llama.status/1`).
    * `{:run_ok, scratch, output}` / `{:run_error, scratch, output, pi_code}`.
    * `{:session, message}` — interaktive pi-Session gestartet oder beendet
      (tmux-Session `komki`; Exit 0).
    * `{:chain_exit, code}` — Ende des internen `session-chain`-Pane-Laufs.
    * `{:error, reason, exit_code}` — Reihenfolge: 2 = Usage/Konfig, 3 = Doctor/
      Boot-Gate, 4 = Runtime (llama/pi).
  """

  alias KomkiCli.{Config, Llama, Pi, Profile}
  require Config

  @type check :: %{name: String.t(), ok: boolean(), reason: String.t()}

  @type result ::
          {:inited, Config.t(), [String.t()]}
          | {:checks, [check()], :ok | :fail | :boot_gate_fail}
          | {:llama_up, pos_integer()}
          | {:llama_down}
          | {:llama_down, :already}
          | {:llama_down, :stale, String.t()}
          | {:status, Config.t(), term()}
          | {:run_ok, String.t(), String.t()}
          | {:run_error, String.t(), String.t(), integer()}
          | {:session, String.t()}
          | {:chain_exit, integer()}
          | {:error, String.t(), non_neg_integer()}

  # ===========================================================================
  # init
  # ===========================================================================

  @spec init(%{String.t() => String.t()}) :: result()
  def init(opts) do
    base = Config.default_base()
    config_path = Config.config_path(base)

    if File.exists?(config_path) and not Map.has_key?(opts, "force") do
      {:error, "config.json bereits vorhanden: " <> config_path <> "; --force verwenden", 2}
    else
      cfg = Config.defaults(base, port: parse_int!(opts, "port"), ctx: parse_int!(opts, "ctx"))

      case missing_tools(cfg) do
        [] -> create_instance(cfg, opts)
        missing -> {:error, tools_error(missing), 2}
      end
    end
  rescue
    e -> {:error, "init fehlgeschlagen: " <> exception_reason(e), 2}
  end

  defp create_instance(cfg, opts) do
    with :ok <- create_dirs(cfg),
         {:ok, gguf_lines} <- place_gguf(cfg, opts) do
      write_pi_home(cfg)
      Profile.write!(cfg.profile_path, Profile.generate(cfg, Profile.check_scratch(cfg)))
      Config.save(cfg)
      {:inited, cfg, gguf_lines}
    else
      # place_gguf liefert {:error, reason, 2}; create_dirs wirft bei Misserfolg
      # (MatchError faellt in den init-Rescue). Ein Catch-All hier waere
      # unerreichbar (Dialyzer) und verdeckte das.
      {:error, _reason, _code} = error -> error
    end
  end

  # Entdeckung schlug fehl -> init verweigert mit klaren Namen statt
  # spaeter kryptisch zu crashen.
  defp missing_tools(%Config{} = cfg) do
    [
      {"node", cfg.node_bin},
      {"pi-Bundle (cli.js)", cfg.cli_js},
      {"llama-server", cfg.llama_server_bin}
    ]
    |> Enum.filter(fn {_name, path} -> is_nil(path) end)
    |> Enum.map(fn {name, _path} -> name end)
  end

  defp tools_error(missing) do
    "Werkzeug nicht entdeckt: " <>
      Enum.join(missing, ", ") <>
      " — Installation pruefen (node via asdf/brew/nvm, pi-Bundle via npm-global, llama.cpp)" <>
      " oder Pfade in der config.json manuell setzen"
  end

  defp create_dirs(cfg) do
    dirs = [
      Path.dirname(cfg.profile_path) <> ".d",
      Path.join([cfg.base_dir, "models"]),
      Path.join([cfg.base_dir, "tmp"]),
      Path.join([cfg.base_dir, "runs"]),
      Path.join([cfg.pi_home, "tmp"]),
      Path.join([cfg.pi_home, ".config"]),
      Path.join([cfg.pi_home, ".local", "share"]),
      Path.join([cfg.pi_home, ".cache", "node-compile"]),
      Path.join([cfg.pi_home, ".pi", "agent"])
    ]

    Enum.each(dirs, &File.mkdir_p!/1)
    :ok
  end

  # GGUF: Quelle = --gguf-from oder das verifizierte Artefakt der
  # Sandbox-Forschung; SHA-Pflicht
  # (Mismatch bricht ab, die Kopie wird entfernt — KEIN brauchbarer Verweis).
  defp place_gguf(cfg, opts) do
    source = Map.get(opts, "gguf-from") || Config.default_probe_gguf()

    cond do
      is_nil(source) ->
        {:error,
         "keine GGUF-Quelle: --gguf-from PATH angeben (komki laedt nichts herunter; " <>
           "das Default-Artefakt liegt nicht am erwarteten Ort)", 2}

      not File.exists?(source) ->
        {:error, "--gguf-from Pfad nicht gefunden: " <> source, 2}

      true ->
        copy_and_verify_gguf(cfg, source)
    end
  end

  # Mismatch bricht ab, die Kopie wird entfernt — KEIN brauchbarer Verweis.
  defp copy_and_verify_gguf(cfg, source) do
    dest = cfg.gguf_path
    File.mkdir_p!(Path.dirname(dest))
    {:ok, _bytes} = File.copy(source, dest)

    case sha256(dest) do
      {:ok, actual} ->
        verify_gguf_sha(cfg, dest, actual)

      {:error, reason} ->
        File.rm(dest)
        {:error, reason, 2}
    end
  end

  defp verify_gguf_sha(cfg, dest, actual) do
    if actual == cfg.gguf_sha256 do
      {:ok, ["gguf:         " <> dest, "gguf-sha256:  " <> actual <> " (pinned, verified)"]}
    else
      File.rm(dest)

      {:error,
       "GGUF SHA256 mismatch: pinned " <>
         cfg.gguf_sha256 <>
         ", got " <>
         actual <>
         "; kopie entfernt — nicht verwendet", 2}
    end
  end

  @doc """
  Schreibt die pi-Konfiguration ins pi-home (models/auth/settings/trust;
  bei asdf-gemanagtem node zusaetzlich .tool-versions). Reine
  cfg->Dateisystem-Funktion — Testnaeht fuer Trust-Wurzel und
  Settings-Global.
  """
  def write_pi_home(cfg) do
    agent = Path.join([cfg.pi_home, ".pi", "agent"])
    File.mkdir_p!(agent)

    models =
      JSON.encode!(%{
        "providers" => %{
          "pi-local" => %{
            "baseUrl" => "http://127.0.0.1:" <> to_string(cfg.port) <> "/v1",
            "api" => "openai-completions",
            "apiKey" => "dummy-synthetic-token",
            "models" => [%{"id" => "local-model"}]
          }
        }
      })

    File.write!(Path.join(agent, "models.json"), models <> "\n")
    File.write!(Path.join(agent, "auth.json"), "{}\n")

    # Thinking per Default eingeklappt (pi-Settings-Global "hideThinkingBlock";
    # Nutzer-Wunsch aus der Session-Erprobung).
    File.write!(Path.join(agent, "settings.json"), ~s({"hideThinkingBlock":true}) <> "\n")

    # Instanz-Wurzel als vertraut markieren, damit keine "This project
    # is not trusted"-Warnung leuchtet. pi's Trust-Store laeuft vom cwd die
    # Elternkette hoch — die Wurzel deckt beide Orte ab: die Arbeitsflaeche
    # (arbeit, Session-cwd) und das pi-Home. Trust-Format: Map mit realpath
    # als Schluessel und Booleschem als Wert (aus pi's ProjectTrustStore).
    File.write!(
      Path.join(agent, "trust.json"),
      JSON.encode!(%{Config.canonical(cfg.base_dir) => true}) <> "\n"
    )

    # pi's Such-Werkzeuge fd/rg in den agent-bin-Fundus kopieren (pi's
    # TOOLS_DIR ist agentDir/bin). Ohne die Kopie sucht pi unter
    # PI_OFFLINE=1 vergeblich nach einem Download und warnt bei jedem
    # Start. Kopie statt Pfad: das Profil erlaubt exec genau fuer diese
    # Fundus-Pfade, und der Fundus wandert mit dem pi-home.
    copy_pi_tool(cfg.fd_bin, agent, "fd")
    copy_pi_tool(cfg.rg_bin, agent, "rg")

    # .tool-versions nur bei asdf-gemanagtem node: Version aus dem
    # Installationspfad abgeleitet statt hartkodiert. Andere Manager
    # (brew/nvm) ignorieren die Datei ohnehin.
    case asdf_node_version(cfg.node_bin) do
      nil ->
        :ok

      version ->
        File.write!(Path.join([cfg.pi_home, ".tool-versions"]), "nodejs " <> version <> "\n")
    end

    :ok
  end

  defp asdf_node_version(node_bin) when is_binary(node_bin) do
    if String.contains?(node_bin, "/.asdf/installs/nodejs/") do
      node_bin |> Path.dirname() |> Path.dirname() |> Path.basename()
    else
      nil
    end
  end

  defp asdf_node_version(nil), do: nil

  # Nil-tolerant: fehlt das Host-Werkzeug, bleibt es beim Verzicht (pi warnt
  # dann beim Start ueber den fehlenden Fundus) — kein harter init-Fail fuer
  # optionale Werkzeuge. Auch eine konfigurierte, aber zwischenzeitlich
  # verschwundene Quelle wird uebersprungen statt init zu killen.
  defp copy_pi_tool(nil, _agent, _name), do: :ok

  defp copy_pi_tool(src, agent, name) when is_binary(src) do
    if File.exists?(src) do
      bin_dir = Path.join(agent, "bin")
      File.mkdir_p!(bin_dir)

      dest = Path.join(bin_dir, name)

      # Alte Kopien behalten den Write-Schutz der Quelle (echte Binaries:
      # 555). cp! scheitert beim Ueberschreiben einer solchen Datei — erst
      # entfernen (Verzeichnis ist schreibbar), dann frisch kopieren.
      File.rm(dest)
      File.cp!(src, dest)
    end
  end

  # ===========================================================================
  # doctor (full) / doctor-quick (profile_boot)
  # ===========================================================================

  @spec doctor() :: result()
  def doctor, do: run_checks(:full)

  @doc "Doctor-quick (Profil-Identität + Boot-Gate) fuer up/down."
  @spec doctor_quick() :: result()
  def doctor_quick, do: run_checks(:profile_boot)

  @doc "Checks ausfuehren; Struktur fuer den CLI-Renderer."
  @spec run_checks(:full | :profile_boot) :: result()
  def run_checks(scope) do
    case Config.load(Config.config_path(Config.default_base())) do
      {:error, reason} ->
        {:error, "config: " <> reason, 2}

      {:ok, cfg} ->
        checks = all_checks(cfg, scope)
        all_ok = Enum.all?(checks, fn %{ok: ok} -> ok end)
        boot_ok = Enum.all?(Enum.filter(checks, &boot_check?/1), fn %{ok: ok} -> ok end)

        summary =
          cond do
            all_ok -> :ok
            boot_ok -> :fail
            true -> :boot_gate_fail
          end

        {:checks, checks, summary}
    end
  end

  defp boot_check?(%{name: name}), do: String.starts_with?(name, "boot ")

  defp all_checks(cfg, scope) do
    Enum.concat([
      tools_checks(cfg),
      profile_checks(cfg),
      gguf_checks(cfg, scope),
      boot_gate(cfg),
      [port_check(cfg)]
    ])
  end

  defp tools_checks(cfg) do
    tools = [
      {"node", cfg.node_bin},
      {"cli.js", cfg.cli_js},
      {"llama-server", cfg.llama_server_bin},
      {"sandbox-exec", cfg.sandbox_exec}
    ]

    Enum.map(tools, fn {name, path} ->
      cond do
        is_nil(path) ->
          %{name: name, ok: false, reason: "nicht entdeckt (Installation/init pruefen)"}

        File.exists?(path) ->
          %{name: name, ok: true, reason: path}

        true ->
          # Gepinnte Pfade koennen verblassen (z.B. brew-Upgrade verschiebt
          # den Cellar-Realpath) — der Hinweis nennt den Wiederherstellungsweg.
          %{
            name: name,
            ok: false,
            reason: "missing: " <> path <> " — 'komki init --force' entdeckt neu"
          }
      end
    end)
  end

  defp profile_checks(cfg) do
    if Config.tools_ready(cfg) do
      profile_identity_checks(cfg)
    else
      [%{name: "profile", ok: false, reason: "Werkzeugpfade fehlen (config.json unvollstaendig)"}]
    end
  end

  defp profile_identity_checks(cfg) do
    expected = Profile.generate(cfg, Profile.check_scratch(cfg))

    if File.exists?(cfg.profile_path) do
      if File.read!(cfg.profile_path) == expected do
        [%{name: "profile", ok: true, reason: "regeneration byte-stabil"}]
      else
        [
          %{
            name: "profile",
            ok: false,
            reason: "drift: regenerierter Profilttext weicht ab (init --force)"
          }
        ]
      end
    else
      [%{name: "profile", ok: false, reason: "missing (init first)"}]
    end
  end

  defp gguf_checks(cfg, :full) do
    if File.exists?(cfg.gguf_path) do
      gguf_sha_checks(cfg)
    else
      [%{name: "gguf sha256", ok: false, reason: "missing: " <> cfg.gguf_path}]
    end
  end

  defp gguf_checks(cfg, :profile_boot) do
    if File.exists?(cfg.gguf_path) do
      [%{name: "gguf presence", ok: true, reason: cfg.gguf_path}]
    else
      [%{name: "gguf presence", ok: false, reason: "missing: " <> cfg.gguf_path}]
    end
  end

  defp gguf_sha_checks(cfg) do
    case sha256(cfg.gguf_path) do
      {:ok, actual} ->
        [
          %{
            name: "gguf sha256",
            ok: actual == cfg.gguf_sha256,
            reason:
              if(actual == cfg.gguf_sha256,
                do: actual,
                else: "recorded " <> cfg.gguf_sha256 <> ", actual " <> actual
              )
          }
        ]

      {:error, reason} ->
        [%{name: "gguf sha256", ok: false, reason: reason}]
    end
  end

  defp port_check(cfg) do
    case Llama.http_get_200(cfg.port) do
      {:ok, "200"} ->
        %{name: "port " <> to_string(cfg.port), ok: true, reason: "llama already up (health 200)"}

      {:ok, code} ->
        %{
          name: "port " <> to_string(cfg.port),
          ok: false,
          reason: "fremder Dienst am Port (health " <> code <> ")"
        }

      {:error, _} ->
        %{name: "port " <> to_string(cfg.port), ok: true, reason: "free (refused)"}
    end
  end

  # Boot-Gate: Pflicht vor jedem Lauf (dokumentierte Unstabilitätsklasse
  # deny-default-Profile auf macOS 27.x, siehe Research-Report der
  # Sandbox-Forschung).
  @spec boot_gate(Config.t()) :: [check()]
  def boot_gate(cfg) do
    [
      boot_l(cfg, "/usr/bin/true"),
      boot_l(cfg, "/bin/sh", ["-c", "exit 0"])
    ]
  end

  @spec boot_l(Config.t(), String.t(), [String.t()]) :: check()
  defp boot_l(cfg, binary, args \\ []) do
    # Arbeitsverzeichnis in den erlaubten Bereich legen (pi-home, sonst base-dir):
    # Erbt das Kind das Aufruferverzeichnis, scheitert getcwd() unter dem Profil
    # und sh meldet "shell-init: error retrieving current directory" (Smoke-Fund).
    cwd = if File.exists?(cfg.pi_home), do: cfg.pi_home, else: cfg.base_dir

    {ok, reason} =
      try do
        case System.cmd(cfg.sandbox_exec, ["-f", cfg.profile_path, "--", binary] ++ args,
               env: %{"PATH" => "/usr/bin:/bin"},
               cd: cwd
             ) do
          {_out, 0} -> {true, "rc0"}
          {out, code} -> {false, rc_reason(code, out)}
        end
      rescue
        e -> {false, "exec error: " <> exception_reason(e)}
      catch
        kind, thrown ->
          {false, "exec error " <> Kernel.inspect(kind) <> ": " <> Kernel.inspect(thrown)}
      end

    %{name: "boot " <> binary, ok: ok, reason: reason}
  end

  defp rc_reason(code, out) do
    excerpt = out |> String.trim_trailing() |> String.slice(0, 200)
    "rc=" <> to_string(code) <> " " <> excerpt
  end

  # ===========================================================================
  # up / down / status
  # ===========================================================================

  @spec up(%{String.t() => String.t()}) :: result()
  def up(opts) do
    case doctor_quick() do
      {:checks, _checks, :ok} ->
        cfg = override_ctx(load_cfg!(), opts)

        case Llama.up(cfg) do
          {:ok, pid} -> {:llama_up, pid}
          {:error, reason} -> {:error, reason, 4}
        end

      _ ->
        {:error, "llama start verweigert: doctor-quick nicht gruen (Boot-Gate)", 3}
    end
  rescue
    e -> {:error, "up fehlgeschlagen: " <> exception_reason(e), 2}
  end

  defp override_ctx(cfg, opts) do
    case parse_int!(opts, "ctx") do
      nil -> cfg
      ctx -> Map.replace!(cfg, :ctx, ctx)
    end
  end

  # down ist der Aufraeumweg und traegt KEIN Boot-Gate: Das Gate schuetzt das
  # Starten von Arbeit (run/session), nie das Stoppen — sonst finge das CLI
  # seine Nutzer in einem Zustand ein, aus dem sie llama nicht mehr stoppen
  # koennten (git-stash-/compose-down-Schule). Die Sicherheit sitzt im
  # Identitaetscheck: Llama.down toetet nur, wenn die Pidfile-Pid wirklich
  # llama-server ist. Bereits unten ist Erfolg (Idempotenz), und stale
  # pidfiles werden aufgeraeumt statt als Fehler stehen gelassen.
  @spec down() :: result()
  def down do
    case Llama.down(load_cfg!()) do
      :ok -> {:llama_down}
      :no_pidfile -> {:llama_down, :already}
      {:stale, reason} -> {:llama_down, :stale, reason}
      {:error, reason} -> {:error, reason, 4}
    end
  rescue
    e -> {:error, "down fehlgeschlagen: " <> exception_reason(e), 2}
  end

  @spec status() :: result()
  def status do
    case Config.load(Config.config_path(Config.default_base())) do
      {:error, reason} -> {:error, "config: " <> reason, 2}
      {:ok, cfg} -> {:status, cfg, Llama.status(cfg)}
    end
  end

  # ===========================================================================
  # run
  # ===========================================================================

  @spec run(%{String.t() => String.t()}) :: result()
  def run(opts) do
    case mode_from(Map.get(opts, "mode", "text")) do
      {:error, reason} ->
        {:error, reason, 2}

      {:ok, mode} ->
        case run_checks(:full) do
          {:checks, _checks, :ok} ->
            execute_run(opts, mode)

          {:checks, _checks, _} ->
            {:error, "run verweigert: doctor nicht gruen (Boot-Gate ist Pflicht vor jedem Lauf)",
             3}

          {:error, reason, code} ->
            {:error, reason, code}
        end
    end
  end

  defp mode_from("text"), do: {:ok, :text}
  defp mode_from("json"), do: {:ok, :json}

  defp mode_from(mode),
    do: {:error, "invalid --mode " <> Kernel.inspect(mode) <> " (allowed: text|json)"}

  # Fail-fast wie session (kubectl-Schule): alle Vorbedingungen pruefen, bevor
  # die Sandbox-Kette startet — sonst stirbt run erst tief in pi mit einem
  # opaken Connection-Refused (Exit 4) statt sofort mit Handlungs-Hinweis.
  defp execute_run(opts, mode) do
    cfg = load_cfg!()

    case require_llama_up(cfg) do
      {:ok, _pid} ->
        scratch = scratch_for(opts, cfg.base_dir)
        File.mkdir_p!(scratch)
        prompt = Map.fetch!(opts, "prompt")

        case Pi.run(cfg, scratch, mode, prompt) do
          {:ok, out} ->
            {:run_ok, scratch, out}

          {:error, out, pi_code} ->
            {:run_error, scratch, out, pi_code}
        end

      {:error, reason, code} ->
        {:error, reason, code}
    end
  end

  defp scratch_for(opts, base) do
    case Map.get(opts, "scratch") do
      nil ->
        stamp =
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()
          |> String.replace([" ", ":"], "-")

        Path.join([base, "runs", stamp])

      scratch ->
        Config.canonical(scratch)
    end
  end

  # ===========================================================================
  # session (interaktiv: pi in tmux, echte Pty statt /dev/null)
  # ===========================================================================

  @tmux_session "komki"

  @doc """
  Interner Pane-Einstieg (tmux-Pane der Session): startet die pi-Kette als
  Port-Kind DIESES BEAM mit `:nouse_stdio` — node erbt die Pane-PTY als
  Terminal. Der Port-Kind-Weg ist der Kern des macOS-27.2-Beta-Workarounds:
  node bootet unter dem Profil nur als BEAM-Port-Kind, fork-geborene Ketten
  sterben beim Init mit SIGABRT (Crash-Analyse im Session-Smoke). Der
  Port-Env ersetzt die Umgebung komplett (`Pi.session_env/1`).
  """
  @spec session_chain(%{String.t() => String.t()}) :: result()
  def session_chain(opts) do
    case Config.load(Config.config_path(Config.default_base())) do
      {:error, reason} ->
        {:error, "config: " <> reason, 2}

      {:ok, cfg} ->
        do_session_chain(cfg, Map.has_key?(opts, "continue"))
    end
  rescue
    e -> {:error, "session-chain fehlgeschlagen: " <> exception_reason(e), 2}
  end

  defp do_session_chain(cfg, continue?) do
    File.mkdir_p!(Pi.session_dir(cfg))

    arbeit = Path.join(cfg.base_dir, "arbeit")
    File.mkdir_p!(arbeit)
    Profile.write!(Pi.session_profile_path(cfg), Profile.generate(cfg, arbeit))

    [program | args] = Pi.argv_session(cfg, continue?)

    # Port-Env in Charlist-Form: die open_port-Spec fuer :env verlangt sie
    # (Dialyzer-Fund: Binär-Tupel lassen den Aufruf als fehlgeschlagen typisieren).
    env =
      Enum.map(Pi.session_env(cfg), fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end)

    port =
      Port.open(
        {:spawn_executable, program},
        [
          :nouse_stdio,
          :exit_status,
          {:args, args},
          {:env, env},
          # cwd = die Arbeitsflaeche: "Was steht an?" soll die Dateien der
          # Nutzerin/des Nutzers zeigen (arbeit), nicht pi-Interna (pi-home).
          # HOME bleibt pi-home — pi's Agent-Verzeichnis liegt unangetastet.
          {:cd, arbeit}
        ]
      )

    receive do
      {^port, {:exit_status, code}} -> {:chain_exit, code}
    end
  end

  @doc """
  Interaktive pi-Session in der tmux-Session `komki` (attach-or-create).
  Full doctor zuerst (Boot-Gate), llama muss laufen. Das Pane-Kommando
  startet das komki-Escript als Mini-BEAM (`session-chain`), der die
  Sandbox-Kette als Port-Kind spawnt — macOS-27.2-Beta: fork-geborenes
  node stirbt beim Init, Port-Kind-boots laufen (Crash-Analyse).
  tmux-Aufrufe im Attach-Modus laufen als Port mit `:nouse_stdio`, damit
  der tmux-Client das echte Terminal erhaelt (System.cmd gäbe BEAM-Pipes:
  "open terminal failed: not a terminal"). `--continue` setzt die letzte
  Session fort (pi-Flag gleichen Namens), `--detach` startet ohne attach.
  """
  @spec session(%{String.t() => String.t()}) :: result()
  def session(opts) do
    case run_checks(:full) do
      {:checks, _checks, :ok} ->
        execute_session(opts)

      {:checks, _checks, _} ->
        {:error, "session verweigert: doctor nicht gruen (Boot-Gate ist Pflicht vor jedem Lauf)",
         3}

      {:error, reason, code} ->
        {:error, reason, code}
    end
  rescue
    e -> {:error, "session fehlgeschlagen: " <> exception_reason(e), 2}
  end

  defp execute_session(opts) do
    cfg = load_cfg!()

    with {:ok, _pid} <- require_llama_up(cfg),
         {:ok, tmux} <- find_tmux() do
      if tmux_session_running?(tmux) do
        attach_or_refuse(tmux, opts)
      else
        start_new_session(cfg, tmux, opts)
      end
    else
      {:error, reason, code} -> {:error, reason, code}
    end
  end

  defp require_llama_up(cfg) do
    case Llama.status(cfg) do
      {:running, pid} ->
        {:ok, pid}

      {:health_only, :no_pidfile} ->
        {:error,
         "port " <>
           to_string(cfg.port) <>
           " antwortet, aber pidfile fehlt (fremder Prozess?) — 'komki status' pruefen", 2}

      :stopped ->
        {:error, "llama-server nicht aktiv: 'komki up' zuerst", 2}

      {:error, reason} ->
        {:error, reason, 2}
    end
  end

  defp find_tmux do
    case System.find_executable("tmux") do
      nil ->
        {:error,
         "tmux nicht gefunden (noetig fuer interaktive Sessions; z.B. 'brew install tmux')", 2}

      tmux ->
        {:ok, tmux}
    end
  end

  defp tmux_session_running?(tmux) do
    # stderr gefangen: "no server running"-Meldungen sollen das Terminal
    # des Aufrufers nicht zumuellen (Live-Fund aus dem Session-Smoke).
    case System.cmd(tmux, ["has-session", "-t", "=" <> @tmux_session], stderr_to_stdout: true) do
      {_out, 0} -> true
      _ -> false
    end
  end

  # tmux im Attach-Modus braucht das echte Terminal des Aufrufers; System.cmd
  # gäbe BEAM-Pipes ("open terminal failed: not a terminal" — Live-Fund aus
  # dem Session-Smoke). Ein Port ohne :use_stdio reicht das eigene stdio durch.
  defp run_tmux_inheriting_terminal(tmux, args) do
    port = Port.open({:spawn_executable, tmux}, [:nouse_stdio, :exit_status, {:args, args}])

    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, code}} -> {:error, code}
    end
  end

  defp attach_or_refuse(tmux, opts) do
    if Map.has_key?(opts, "detach") do
      {:error,
       "tmux-session '" <>
         @tmux_session <>
         "' laeuft bereits; ohne --detach via 'tmux attach -t " <>
         @tmux_session <> "' andocken", 2}
    else
      case run_tmux_inheriting_terminal(tmux, ["attach", "-t", "=" <> @tmux_session]) do
        :ok ->
          {:session,
           "session beendet oder abgekoppelt; 'tmux attach -t " <>
             @tmux_session <>
             "' zum Weiterarbeiten"}

        {:error, code} ->
          {:error, "tmux attach endete mit exit " <> to_string(code), 4}
      end
    end
  end

  defp start_new_session(cfg, tmux, opts) do
    continue? = Map.has_key?(opts, "continue")
    detach? = Map.has_key?(opts, "detach")

    case continue_precondition(cfg, continue?) do
      :ok ->
        prepare_session_assets(cfg)
        pane = Pi.pane_command(escript_path!(), continue?)

        if detach?,
          do: create_detached(tmux, cfg, pane),
          else: create_with_attach(tmux, cfg, pane)

      {:error, reason, code} ->
        {:error, reason, code}
    end
  end

  defp prepare_session_assets(cfg) do
    File.mkdir_p!(Pi.session_dir(cfg))

    # Schreibbereich interaktiver Arbeit (persistenter Workspace im KomkiCli)
    arbeit = Path.join(cfg.base_dir, "arbeit")
    File.mkdir_p!(arbeit)
    Profile.write!(Pi.session_profile_path(cfg), Profile.generate(cfg, arbeit))
  end

  # Detached: kein Terminalbedarf, System.cmd genuegt (stderr gefangen).
  defp create_detached(tmux, cfg, pane) do
    case System.cmd(
           tmux,
           ["new-session", "-d", "-s", @tmux_session, "-c", cfg.pi_home, pane],
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        {:session, session_started_message(true)}

      {out, code} ->
        {:error,
         "tmux new-session fehlgeschlagen (exit " <>
           to_string(code) <>
           "): " <>
           String.trim_trailing(out), 4}
    end
  end

  # Attach-Create: tmux uebernimmt das Terminal des Aufrufers und
  # kehrt erst bei Abkopplung/Session-Ende zurueck.
  defp create_with_attach(tmux, cfg, pane) do
    args = ["new-session", "-s", @tmux_session, "-c", cfg.pi_home, pane]

    case run_tmux_inheriting_terminal(tmux, args) do
      :ok ->
        {:session, session_started_message(false)}

      {:error, code} ->
        {:error, "tmux new-session fehlgeschlagen (exit " <> to_string(code) <> ")", 4}
    end
  end

  # pi --continue ohne fruehere Session wuerde in der TUI fehlschlagen;
  # deshalb explizit und mit klarem Text verweigern.
  defp continue_precondition(cfg, true) do
    case File.ls(Pi.session_dir(cfg)) do
      {:ok, []} ->
        {:error,
         "keine fruehere Session in " <> Pi.session_dir(cfg) <> "; ohne --continue starten", 2}

      {:ok, _sessions} ->
        :ok

      {:error, _posix} ->
        {:error,
         "keine fruehere Session in " <> Pi.session_dir(cfg) <> "; ohne --continue starten", 2}
    end
  end

  defp continue_precondition(_cfg, false), do: :ok

  # Pfad des laufenden Escripts (fuer das Pane-Kommando der Session): absolut,
  # damit die Pane unabhaengig von ihrem Startverzeichnis laeuft. Ausserhalb
  # des Escript-Kontexts wirft :escript.script_name/0 — der session-Rescue
  # fasst das mit einer klaren Meldung ab.
  defp escript_path!, do: Path.expand(to_string(:escript.script_name()))

  defp session_started_message(true = _detach) do
    "tmux-session '" <>
      @tmux_session <>
      "' gestartet (detached); 'tmux attach -t " <>
      @tmux_session <> "' zum Arbeiten"
  end

  defp session_started_message(false) do
    if System.get_env("TMUX") do
      "tmux-session '" <>
        @tmux_session <>
        "' gestartet; tmux hat den Client umgeschaltet — pi mit /exit beenden, " <>
        "Ruecksprung mit 'tmux switch-client -p'"
    else
      "tmux-session '" <>
        @tmux_session <>
        "' beendet oder abgekoppelt; 'tmux attach -t " <>
        @tmux_session <>
        "' zum Weiterarbeiten"
    end
  end

  # ===========================================================================
  # Helfer
  # ===========================================================================

  @doc "Streamed SHA-256 (1-MiB-Chunks; kein OOM beim 469-MiB-Artefakt)."
  @spec sha256(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def sha256(path) do
    digest =
      path
      |> File.stream!(1024 * 1024)
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, hash ->
        :crypto.hash_update(hash, chunk)
      end)
      |> :crypto.hash_final()

    {:ok, Base.encode16(digest, case: :lower)}
  rescue
    e in File.Error -> {:error, Exception.message(e)}
    e in RuntimeError -> {:error, Exception.message(e)}
  end

  defp parse_int!(opts, flag) do
    case Map.get(opts, flag) do
      nil ->
        nil

      # Optimus-Optionen mit parser: :integer kommen bereits als Integer an.
      value when is_integer(value) and value > 0 ->
        value

      raw when is_binary(raw) ->
        case Integer.parse(raw) do
          {value, ""} when value > 0 ->
            value

          _ ->
            raise ArgumentError,
              message: "ungueltiger Wert fuer --" <> flag <> ": " <> Kernel.inspect(raw)
        end

      raw ->
        raise ArgumentError,
          message: "ungueltiger Wert fuer --" <> flag <> ": " <> Kernel.inspect(raw)
    end
  end

  defp load_cfg! do
    Config.load!(Config.config_path(Config.default_base()))
  end

  defp exception_reason(e), do: Exception.message(e)
end
