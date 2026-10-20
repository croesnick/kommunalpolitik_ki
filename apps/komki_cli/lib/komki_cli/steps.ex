defmodule KomkiCli.Steps do
  @moduledoc """
  Befehls-Orchestrierung fuer den `komki`-Escript (Ticket #74; Vermittler-
  Anbindung Ticket #102).

  **CLI-Surface-Isolation (API-Vertrag):** alle menschlichen Ausgaben
  (Verdict-Zeilen, Farben, Progress-Messaging) rendert ausschliesslich
  `KomkiCli.CLI`. Diese Orchestrierung liefert *strukturierte* Resultate —
  ein späteres CLI-Library-Retrofit (owl/optimus, in Forschung) berührt nur
  die Render-Schicht in `KomkiCli.CLI`, nie Profile/Llama/Mediator/Pi/Config.

  Resultatformen:

    * `{:inited, cfg, gguf_lines}` — init ok; `gguf_lines` sind Datenzeilen
      (Pfad + SHA), die CLI rendert sie.
    * `{:checks, [%{name, ok, reason}], summary_state}` — Doctor-Ergebnis;
      `summary_state` ∈ `:ok | :fail | :boot_gate_fail`.
    * `{:up, %{llama: pid, mediator: mediator_state}}` — llama-server und
      Vermittler laufen; `mediator_state` ist
      `{:started, pid, health}` (frisch gespawnt) oder `{:already, health}`
      (healthz war gruen, kein Neustart) — Struktur aus `KomkiCli.Mediator.up`.
      `health` traegt die healthz-Vertrags-Keys (inkl. `tools`, aus denen
      die mcp.json geschrieben wurde).
    * `{:down, %{llama: down_state, mediator: down_state}}` — gestoppt;
      `down_state` ∈ `:ok | :already | {:stale, reason}` pro Komponente
      (`:already` = war bereits unten, Idempotenz; `:stale` = stale pidfile
      aufgeräumt, kein Prozess getötet). Stoppreihenfolge: Vermittler zuerst
      (gestartet zuletzt, gestoppt zuerst).
    * `{:status, cfg, %{llama: llama_state, mediator: mediator_state}}` —
      Status-Snapshot (`llama_state`/`mediator_state` uebernehmen die
      Struktur aus `KomkiCli.Llama.status/1` bzw. `KomkiCli.Mediator.status/1`).
    * `{:run_ok, scratch, output}` / `{:run_error, scratch, output, pi_code}`.
    * `{:session, message}` — interaktive pi-Session gestartet oder beendet
      (tmux-Session `komki`; Exit 0).
    * `{:chain_exit, code}` — Ende des internen `session-chain`-Pane-Laufs.
    * `{:error, reason, exit_code}` — Reihenfolge: 2 = Usage/Konfig, 3 = Doctor/
      Boot-Gate, 4 = Runtime (llama/mediator/pi).
  """

  alias KomkiCli.{Config, Llama, Mediator, Pi, Profile}
  require Config

  @type check :: %{name: String.t(), ok: boolean(), reason: String.t()}

  @type mediator_state ::
          {:started, pos_integer(), Mediator.health()} | {:already, Mediator.health()}

  @type down_state :: :ok | :already | {:stale, String.t()}

  @type result ::
          {:inited, Config.t(), [String.t()]}
          | {:checks, [check()], :ok | :fail | :boot_gate_fail}
          | {:up, %{llama: pos_integer(), mediator: mediator_state()}}
          | {:down, %{llama: down_state(), mediator: down_state()}}
          | {:status, Config.t(),
             %{llama: term(), mediator: Mediator.mediator_state() | {:error, String.t()}}}
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
      cfg =
        Config.defaults(base,
          port: parse_int!(opts, "port"),
          ctx: parse_int!(opts, "ctx"),
          mediator_port: parse_int!(opts, "mediator-port")
        )

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
      # Ticket #100: llama-server-Profil neben dem pi-Profil schreiben
      Profile.write!(Llama.llama_profile_path(cfg), Profile.generate_llama(cfg))
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
  cfg->Dateisystem-Funktion — Testnaeht fuer Trust-Root und
  Settings-Global.
  """
  def write_pi_home(cfg) do
    agent = Path.join([cfg.pi_home, ".pi", "agent"])
    File.mkdir_p!(agent)

    write_models(cfg)
    File.write!(Path.join(agent, "auth.json"), "{}\n")

    # Thinking per Default eingeklappt (pi-Settings-Global "hideThinkingBlock";
    # Nutzer-Wunsch aus der Session-Erprobung).
    File.write!(Path.join(agent, "settings.json"), ~s({"hideThinkingBlock":true}) <> "\n")

    # Instanz-Root als vertraut markieren, damit keine "This project
    # is not trusted"-Warnung leuchtet. pi's Trust-Store laeuft vom cwd die
    # Elternkette hoch — das Root deckt beide Orte ab: die Arbeitsflaeche
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

  @doc """
  pis Provider-Konfiguration (`models.json`) mit dem llama-API-Key
  (Ticket #136). Ohne gestarteten llama steht ein Platzhalter darin;
  `up` schreibt die Datei nach jedem llama-Start neu.
  """
  @spec write_models(Config.t()) :: :ok
  def write_models(cfg) do
    api_key =
      case Llama.read_key(cfg) do
        {:ok, key} -> key
        :none -> "kein-llama-key"
      end

    models =
      JSON.encode!(%{
        "providers" => %{
          "pi-local" => %{
            "baseUrl" => "http://127.0.0.1:" <> to_string(cfg.port) <> "/v1",
            "api" => "openai-completions",
            "apiKey" => api_key,
            "models" => [%{"id" => "local-model"}]
          }
        }
      })

    path = Path.join([cfg.pi_home, ".pi", "agent", "models.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, models <> "\n")
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
      tools_checks(cfg, scope),
      pi_version_checks(cfg, scope),
      profile_checks(cfg),
      gguf_checks(cfg, scope),
      boot_gate(cfg),
      llama_boot_gate(cfg),
      [port_check(cfg), llama_auth_check(cfg)]
    ])
  end

  defp tools_checks(cfg, scope) do
    tools = [
      {"node", cfg.node_bin},
      {"cli.js", cfg.cli_js},
      {"llama-server", cfg.llama_server_bin},
      {"sandbox-exec", cfg.sandbox_exec}
    ]

    checks =
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

    # Vermittler-Praesenz (Ticket #102) nur im vollen Doctor-Check: der
    # profile_boot-Gate fuer `up` bleibt exakt die heutige Pflichtmenge —
    # der Start enforce't die mediator-Binary selbst (Steps.up/2).
    if scope == :full, do: checks ++ [mediator_check(cfg)], else: checks
  end

  defp mediator_check(cfg) do
    cond do
      is_nil(cfg.mediator_bin) ->
        %{
          name: "komki-mediator",
          ok: false,
          reason:
            "komki-mediator nicht entdeckt — init --force oder mix escript.build in apps/komki_mediator"
        }

      File.exists?(cfg.mediator_bin) ->
        %{name: "komki-mediator", ok: true, reason: cfg.mediator_bin}

      true ->
        %{
          name: "komki-mediator",
          ok: false,
          reason: "missing: " <> cfg.mediator_bin <> " — 'komki init --force' entdeckt neu"
        }
    end
  end

  # pi-Version (Ticket #103-Konsolidierung): KEIN Pin — der Check meldet die
  # installierte Version und die zu erwartende Flag-Oberflaeche (Report, kein
  # Gate). Nur im vollen Doctor-Check, wie der Vermittler-Praesenz-Check.
  defp pi_version_checks(cfg, scope) do
    if scope == :full, do: [pi_version_check(cfg)], else: []
  end

  defp pi_version_check(cfg) do
    case pi_version(cfg) do
      {:ok, version, major} when major >= 1 ->
        %{
          name: "pi version",
          ok: true,
          reason:
            "pi " <>
              version <>
              ": erwartet -e builtin:mcp (>= 1.0); ab 1.0.4: --no-mcp + " <>
              "mcp__-Patterns; ab 1.1.0: +/- in --tools"
        }

      {:ok, version, _major} ->
        %{
          name: "pi version",
          ok: false,
          reason:
            "pi " <> version <> " (major < 1): MCP-Flags nicht unterstuetzt — pi aktualisieren"
        }

      {:error, reason} ->
        %{name: "pi version", ok: false, reason: reason}
    end
  end

  defp pi_version(cfg) when is_binary(cfg.node_bin) and is_binary(cfg.cli_js) do
    case System.cmd(cfg.node_bin, [cfg.cli_js, "--version"], stderr_to_stdout: true) do
      {out, 0} ->
        case Regex.run(~r/\b(\d+\.\d+\.\d+)\b/, out) do
          [version | _] ->
            [major | _] = String.split(version, ".")
            {:ok, version, String.to_integer(major)}

          nil ->
            {:error, "pi-Version unlesbar: " <> excerpt(out)}
        end

      {out, code} ->
        {:error, "pi-Version unlesbar (exit " <> to_string(code) <> "): " <> excerpt(out)}
    end
  end

  defp pi_version(_cfg),
    do: {:error, "pi-Version unlesbar: node/cli.js fehlen in der config"}

  defp excerpt(text), do: text |> String.trim_trailing() |> String.slice(0, 200)

  defp profile_checks(cfg) do
    if Config.tools_ready(cfg) do
      profile_identity_checks(cfg) ++ llama_profile_identity_checks(cfg)
    else
      [%{name: "profile", ok: false, reason: "Werkzeugpfade fehlen (config.json unvollstaendig)"}]
    end
  end

  # Gemeinsame Drei-Zweig-Kaskade der Profil-Identitaetschecks (missing /
  # byte-stabil / drift); die Wrapper liefern name/Pfad/Erwartung —
  # Reason-Strings byte-identisch gepinnt (Tippfehler "Profilttext" im
  # pi-Drift-String ist Bestand).
  defp identity_checks(name, path, expected, drift_reason) do
    if File.exists?(path) do
      if File.read!(path) == expected do
        [%{name: name, ok: true, reason: "regeneration byte-stabil"}]
      else
        [%{name: name, ok: false, reason: drift_reason}]
      end
    else
      [%{name: name, ok: false, reason: "missing (init first)"}]
    end
  end

  defp profile_identity_checks(cfg) do
    identity_checks(
      "profile",
      cfg.profile_path,
      Profile.generate(cfg, Profile.check_scratch(cfg)),
      "drift: regenerierter Profilttext weicht ab (init --force)"
    )
  end

  # Identitaet des llama-Profils (Ticket #100): gemeinsame Kaskade in identity_checks/4.
  defp llama_profile_identity_checks(cfg) do
    identity_checks(
      "llama profile",
      Llama.llama_profile_path(cfg),
      Profile.generate_llama(cfg),
      "drift: regenerierter llama-Profiltext weicht ab (init --force)"
    )
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

  # Ticket #136: ein laufender llama ohne API-Key ist fuer jede Website im
  # Browser lesbar (CORS spiegelt den Origin). Typisch: vor #136 gestartet.
  defp llama_auth_check(cfg) do
    name = "llama auth"

    case Llama.http_get_200(cfg.port) do
      {:ok, "200"} ->
        case Llama.auth_required(cfg.port) do
          {:ok, true} ->
            %{name: name, ok: true, reason: "API-Key verlangt (/props ohne Key: 401)"}

          {:ok, false} ->
            %{
              name: name,
              ok: false,
              reason: "llama laeuft ohne API-Key — 'komki down' und 'komki up' neu starten"
            }

          {:error, reason} ->
            %{name: name, ok: false, reason: reason}
        end

      _ ->
        %{name: name, ok: true, reason: "llama nicht aktiv"}
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
      boot_l(cfg, cfg.profile_path, "/usr/bin/true"),
      boot_l(cfg, cfg.profile_path, "/bin/sh", ["-c", "exit 0"])
    ]
  end

  # Ticket #100: llama-server boot-Gate — das Inferenz-Binary muss unter
  # seinem eigenen Profil execbar sein (--version: kein Modell, kein Port,
  # kein Netz). cwd "/" wie beim Spawn (llama-Profil erlaubt
  # file-read-data "/" aus der Startup-Schicht; pi-home liegt ausserhalb
  # seiner Grenze).
  defp llama_boot_gate(%Config{} = cfg) do
    [boot_l(cfg, Llama.llama_profile_path(cfg), cfg.llama_server_bin, ["--version"], "/")]
  end

  @spec boot_l(Config.t(), String.t(), String.t(), [String.t()], String.t() | nil) :: check()
  defp boot_l(cfg, profile_path, binary, args \\ [], cwd \\ nil)

  defp boot_l(cfg, profile_path, binary, args, cwd) do
    {ok, reason} =
      try do
        case System.cmd(cfg.sandbox_exec, ["-f", profile_path, "--", binary] ++ args,
               env: %{"PATH" => "/usr/bin:/bin"},
               cd: boot_cwd(cfg, cwd)
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

  # Arbeitsverzeichnis in den erlaubten Bereich legen (pi-home, sonst
  # base-dir): Erbt das Kind das Aufruferverzeichnis, scheitert getcwd()
  # unter dem Profil und sh meldet "shell-init: error retrieving current
  # directory" (Smoke-Fund). Explizit uebergebene cwds (llama-Probe: "/")
  # gewinnen.
  defp boot_cwd(_cfg, cwd) when is_binary(cwd), do: cwd

  defp boot_cwd(cfg, nil) do
    if File.exists?(cfg.pi_home), do: cfg.pi_home, else: cfg.base_dir
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

        with {:ok, pid} <- Llama.up(cfg),
             :ok <- write_models(cfg),
             {:ok, mediator} <- mediator_up(cfg) do
          %{"tools" => tools} = health_of(mediator)
          Mediator.write_mcp_config(cfg, tools)
          {:up, %{llama: pid, mediator: mediator}}
        else
          {:error, reason} -> {:error, reason, 4}
        end

      _ ->
        {:error, "llama start verweigert: doctor-quick nicht gruen (Boot-Gate)", 3}
    end
  rescue
    e -> {:error, "up fehlgeschlagen: " <> exception_reason(e), 2}
  end

  # Praesenz-Pflicht sitzt HIER (up), nicht in init: der Vermittler-Binary
  # ist optional bei init, aber Pflicht zum Start (Ticket #102).
  defp mediator_up(cfg) do
    if is_binary(cfg.mediator_bin) do
      Mediator.up(cfg)
    else
      {:error,
       "komki-mediator nicht gefunden — mix escript.build in apps/komki_mediator" <>
         " oder in PATH/<base>/bin ablegen ('komki init --force' entdeckt neu)"}
    end
  end

  defp health_of({:started, _pid, health}), do: health
  defp health_of({:already, health}), do: health

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
  # Identitaetscheck: Llama.down/Mediator.down toeten nur, wenn die Pidfile-
  # Pid wirklich der eigene Prozess ist. Bereits unten ist Erfolg
  # (Idempotenz), und stale pidfiles werden aufgeraeumt statt als Fehler
  # stehen gelassen.
  #
  # Stoppreihenfolge kompositorisch rueckwaerts (compose-down-Schule): der
  # Vermittler wurde von up zuletzt gestartet, wird hier zuerst gestoppt.
  @spec down() :: result()
  def down do
    cfg = load_cfg!()

    case Mediator.down(cfg) do
      {:error, reason} ->
        {:error, reason, 4}

      mediator ->
        case Llama.down(cfg) do
          {:error, reason} -> {:error, reason, 4}
          llama -> {:down, %{mediator: down_state(mediator), llama: down_state(llama)}}
        end
    end
  rescue
    e -> {:error, "down fehlgeschlagen: " <> exception_reason(e), 2}
  end

  defp down_state(:ok), do: :ok
  defp down_state(:no_pidfile), do: :already
  defp down_state({:stale, reason}), do: {:stale, reason}

  @spec status() :: result()
  def status do
    case Config.load(Config.config_path(Config.default_base())) do
      {:error, reason} ->
        {:error, "config: " <> reason, 2}

      {:ok, cfg} ->
        {:status, cfg, %{llama: Llama.status(cfg), mediator: Mediator.status(cfg)}}
    end
  end

  # ===========================================================================
  # run
  # ===========================================================================

  # Laufzeit-Limit des Einmal-Laufs (Ticket #133): ohne Limit drehte ein
  # Modell, das sein Werkzeug nicht fand, ueber zehn Minuten Schleifen.
  @run_timeout_s 600

  @spec run(%{String.t() => term()}) :: result()
  def run(opts) do
    with {:ok, mode} <- mode_from(Map.get(opts, "mode", "text")),
         :ok <- timeout_valid(Map.get(opts, "timeout", @run_timeout_s)) do
      run_checked(opts, mode)
    else
      {:error, reason} -> {:error, reason, 2}
    end
  end

  defp timeout_valid(s) when is_integer(s) and s > 0, do: :ok

  defp timeout_valid(s),
    do: {:error, "invalid --timeout " <> Kernel.inspect(s) <> " (Sekunden > 0)"}

  defp run_checked(opts, mode) do
    case run_checks(:full) do
      {:checks, _checks, :ok} ->
        execute_run(opts, mode)

      {:checks, _checks, _} ->
        {:error, "run verweigert: doctor nicht gruen (Boot-Gate ist Pflicht vor jedem Lauf)", 3}

      {:error, reason, code} ->
        {:error, reason, code}
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

    # Fail-Fast vor der Sandbox-Kette: pi startet sonst mit `-e builtin:mcp`
    # gegen eine tote mcp.json (Vertragsluecke nach Mediator-Crash).
    with {:ok, _pid} <- require_llama_up(cfg),
         {:ok, _pid} <- require_mediator_up(cfg),
         {:ok, scratch} <- scratch_for(opts, cfg.base_dir) do
      File.mkdir_p!(scratch)
      prompt = Map.fetch!(opts, "prompt")
      timeout_ms = Map.get(opts, "timeout", @run_timeout_s) * 1000

      case Pi.run(cfg, scratch, mode, prompt, timeout_ms) do
        {:ok, out} ->
          {:run_ok, scratch, out}

        {:error, out, pi_code} ->
          {:run_error, scratch, out, pi_code}
      end
    else
      {:error, reason, code} -> {:error, reason, code}
    end
  end

  @doc """
  Scratch-Verzeichnis eines Laufs (Ticket #132): der Default
  `<base>/runs/<UTC-Stamp>` oder ein `--scratch`-Pfad, der kanonisch
  (Symlinks aufgeloest) echt unterhalb von `<base>/runs/` liegt. Der
  Scratch ist pis Schreib-Scope im Seatbelt-Profil; ein freier Pfad wie
  `--scratch ~/Vault` wuerde die Grenze auf beliebige Verzeichnisse
  ausdehnen. Public als Testnaht.
  """
  @spec scratch_for(%{String.t() => term()}, String.t()) ::
          {:ok, String.t()} | {:error, String.t(), 2}
  def scratch_for(opts, base) do
    runs = Config.canonical(Path.join(base, "runs"))

    case Map.get(opts, "scratch") do
      nil ->
        stamp =
          DateTime.utc_now()
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()
          |> String.replace([" ", ":"], "-")

        {:ok, Path.join(runs, stamp)}

      scratch ->
        scratch = Config.canonical(scratch)

        if String.starts_with?(scratch, runs <> "/") do
          {:ok, scratch}
        else
          {:error, "--scratch muss unterhalb von " <> runs <> " liegen (ist: " <> scratch <> ")",
           2}
        end
    end
  end

  # ===========================================================================
  # session (interaktiv: pi in tmux, echte Pty statt /dev/null)
  # ===========================================================================

  @tmux_session "komki"

  # Eigener tmux-Server (Ticket #132): pis Ausgabe erreicht ueber tmux das
  # Terminal ausserhalb der Seatbelt-Grenze. `-f /dev/null` haelt die
  # persoenliche tmux-Config fern (dort steht oft `set-clipboard on`, das
  # OSC 52 aus dem Pane in die System-Zwischenablage durchreicht); die
  # Optionen unten setzen die Sperren explizit. `external` laesst den
  # Copy-Modus weiter in die Zwischenablage schreiben, ignoriert aber
  # OSC 52 von pi; `allow-passthrough off` sperrt rohe Sequenzen am tmux
  # vorbei. Restrisiko: OSC 8 (Hyperlinks) reicht tmux durch, wenn das
  # aeussere Terminal das Feature meldet.
  @tmux_server ["-L", "komki", "-f", "/dev/null"]
  @tmux_lockdown [
    "set-option",
    "-s",
    "set-clipboard",
    "external",
    ";",
    "set-option",
    "-g",
    "allow-passthrough",
    "off",
    ";"
  ]
  @tmux_attach_hint "'tmux -L komki attach -t komki'"

  @doc """
  Interner Pane-Einstieg (tmux-Pane der Session): startet die pi-Kette als
  Port-Kind DIESES BEAM mit `:nouse_stdio` — node erbt die Pane-PTY als
  Terminal. Der Port-Kind-Weg ist der Kern des macOS-27.2-Beta-Workarounds:
  node bootet unter dem Profil nur als BEAM-Port-Kind, fork-geborene Ketten
  sterben beim Init mit SIGABRT (Crash-Analyse im Session-Smoke). Der
  Port-Env ersetzt die Umgebung komplett (`Pi.session_env/1`).

  Unter Burrito (`KomkiCli.Runtime.burrito?/0`) leitet die Kette ihr stdout
  zusaetzlich auf /dev/fd/0 um (Dup des lebenden stdin-PTY): Das BEAM-stdout
  ist dort die Wrapper-Pipe, pi beendet sich ohne echtes Terminal sofort
  (Pilot 2026-10-11, Issue-#234-Klasse). Das Profil erlaubt das Oeffnen von
  /dev/fd/0 kontextfrei — Escript-Panels laufen unverändert ueber die
  Direktkette.
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

    [program | args] = Pi.argv_session(cfg, continue?, KomkiCli.Runtime.burrito?())

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
  startet das komki-Programm als Mini-BEAM (`session-chain`; Escript oder
  Burrito-Standalone-Binary — der Pfad kommt aus
  `KomkiCli.Runtime.self_path/0`), der die Sandbox-Kette als Port-Kind
  spawnt — macOS-27.2-Beta: fork-geborenes node stirbt beim Init,
  Port-Kind-boots laufen (Crash-Analyse).
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

    # Reihenfolge wie `up`: llama vor Vermittler; auch die Session startet
    # pi mit `-e builtin:mcp` — ein toter Vermittler bricht hier ab.
    with {:ok, _pid} <- require_llama_up(cfg),
         {:ok, _pid} <- require_mediator_up(cfg),
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

  @doc """
  Vermittler-Liveness-Gate vor jedem pi-Start (`run` UND `session`,
  Ticket #102; Review-Fund zur Vertragsluecke): pi startet mit
  `-e builtin:mcp` gegen eine tote mcp.json, wenn der Vermittler
  gestorben oder das pidfile stale ist (z. B. Mediator-Crash) — hier
  bricht der Lauf vor der Sandbox-Kette ab und verweist auf `komki up`.
  Mechanik wie require_llama_up: Pidfile + ps-Identitaet + healthz
  (Struktur aus `KomkiCli.Mediator.status/1`). Public als Testnaeht:
  Status-Fixturen statt echter Prozesse.
  """
  @spec require_mediator_up(Config.t()) :: {:ok, pos_integer()} | {:error, String.t(), 2}
  def require_mediator_up(cfg) do
    case Mediator.status(cfg) do
      {:running, pid} ->
        {:ok, pid}

      {:health_only, :no_pidfile} ->
        {:error,
         "port " <>
           to_string(cfg.mediator_port) <>
           " antwortet healthz, aber pidfile fehlt (fremder Prozess?) — 'komki status' pruefen",
         2}

      :stopped ->
        {:error, "komki-mediator nicht aktiv: 'komki up' zuerst", 2}

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
    case System.cmd(tmux, @tmux_server ++ ["has-session", "-t", "=" <> @tmux_session],
           stderr_to_stdout: true
         ) do
      {_out, 0} -> true
      _ -> false
    end
  end

  # tmux im Attach-Modus braucht das echte Terminal des Aufrufers; System.cmd
  # gäbe BEAM-Pipes ("open terminal failed: not a terminal" — Live-Fund aus
  # dem Session-Smoke). Ein Port ohne :use_stdio reicht das eigene stdio durch.
  defp run_tmux_inheriting_terminal(tmux, args) do
    # TMUX ausgeblendet: aus einer laufenden tmux-Session heraus startet der
    # eigene komki-Server als verschachtelter Client statt abzulehnen.
    port =
      Port.open({:spawn_executable, tmux}, [
        :nouse_stdio,
        :exit_status,
        {:args, @tmux_server ++ args},
        {:env, [{~c"TMUX", false}]}
      ])

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
         "' laeuft bereits; ohne --detach via " <> @tmux_attach_hint <> " andocken", 2}
    else
      case run_tmux_inheriting_terminal(tmux, ["attach", "-t", "=" <> @tmux_session]) do
        :ok ->
          {:session,
           "session beendet oder abgekoppelt; " <>
             @tmux_attach_hint <>
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
        pane = Pi.pane_command(KomkiCli.Runtime.self_path(), continue?)

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
           @tmux_server ++
             @tmux_lockdown ++ ["new-session", "-d", "-s", @tmux_session, "-c", cfg.pi_home, pane],
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
    args = @tmux_lockdown ++ ["new-session", "-s", @tmux_session, "-c", cfg.pi_home, pane]

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

  defp session_started_message(true = _detach) do
    "tmux-session '" <>
      @tmux_session <> "' gestartet (detached); " <> @tmux_attach_hint <> " zum Arbeiten"
  end

  defp session_started_message(false) do
    "tmux-session '" <>
      @tmux_session <>
      "' beendet oder abgekoppelt; " <> @tmux_attach_hint <> " zum Weiterarbeiten"
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
