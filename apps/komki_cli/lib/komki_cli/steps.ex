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
    * `{:up, %{llama: pid, connectors: [{name, up_state}], mediator: mediator_state}}`
      — llama-server, Egress, Connectoren (Ticket #146) und Vermittler laufen; `mediator_state` ist
      `{:started, pid, health}` (frisch gespawnt) oder `{:already, health}`
      (healthz war gruen, kein Neustart) — Struktur aus `KomkiCli.Mediator.up`.
      `health` traegt die healthz-Vertrags-Keys (inkl. `tools`, aus denen
      die mcp.json geschrieben wurde).
    * `{:down, %{llama: down_state, connectors: [{name, down_state}], mediator: down_state}}`
      — gestoppt (Vermittler, Connectoren, Egress, llama);
      `down_state` ∈ `:ok | :already | {:stale, reason}` pro Komponente
      (`:already` = war bereits unten, Idempotenz; `:stale` = stale pidfile
      aufgeräumt, kein Prozess getötet). Stoppreihenfolge: Vermittler zuerst
      (gestartet zuletzt, gestoppt zuerst).
    * `{:status, cfg, %{llama: llama_state, mediator: mediator_state}}` —
      Status-Snapshot (`llama_state`/`mediator_state` uebernehmen die
      Struktur aus `KomkiCli.Llama.status/1` bzw. `KomkiCli.Mediator.status/1`).
    * `{:run_ok, scratch, output, denial_summary}` /
      `{:run_error, scratch, output, pi_code, denial_summary}` — `denial_summary`
      ist `nil` ohne `--capture-denials`, sonst der strukturierte Capture-Status
      (Ticket #125). Die CLI rendert den Footer auf stderr.
    * `{:session, message}` — interaktive pi-Session gestartet oder beendet
      (tmux-Session `komki`; Exit 0).
    * `{:chain_exit, code}` — Ende des internen `session-chain`-Pane-Laufs.
    * `{:error, reason, exit_code}` — Reihenfolge: 2 = Usage/Konfig, 3 = Doctor/
      Boot-Gate, 4 = Runtime (llama/mediator/pi).
  """

  alias KomkiCli.{
    Anzeige,
    Channel,
    Config,
    ConnectorChecks,
    Connectors,
    Denials,
    Gamma,
    Llama,
    Mediator,
    Pi,
    Pins,
    Profile,
    SessionIntake,
    StartContract
  }

  # Seatbelt-Kern (Ticket #226): Boot-Gate-Sonde aus der Library.
  alias Seatbelt.BootCheck

  require Config

  @denial_epistemic_limit "Keine Denials im Fenster sind kein Konfinement-Beweis; das Boot-Gate bleibt die positive Kontrolle."

  @type check :: %{name: String.t(), ok: boolean(), reason: String.t()}

  @type denial_summary :: %{
          status: String.t(),
          denials: [Denials.denial()],
          report_path: String.t() | nil,
          error: String.t() | nil
        }

  @type mediator_state ::
          {:started, pos_integer(), Mediator.health()} | {:already, Mediator.health()}

  @type down_state :: :ok | :already | {:stale, String.t()}

  @type result ::
          {:inited, Config.t(), [String.t()]}
          | {:session_plan, [String.t()], SessionIntake.intake() | nil}
          | {:session_refused, [String.t()], [SessionIntake.entry()]}
          | {:checks, [check()], :ok | :fail | :boot_gate_fail}
          | {:up,
             %{
               llama: pos_integer(),
               connectors: [{String.t(), Connectors.up_state()}],
               mediator: mediator_state()
             }}
          | {:down,
             %{
               llama: down_state(),
               connectors: [{String.t(), down_state() | {:error, String.t()}}],
               mediator: down_state(),
               orphans: non_neg_integer()
             }}
          | {:status, Config.t(),
             %{
               llama: term(),
               connectors: [{String.t(), Connectors.state()}],
               mediator: Mediator.mediator_state() | {:error, String.t()}
             }}
          | {:run_ok, String.t(), String.t(), denial_summary() | nil}
          | {:run_error, String.t(), String.t(), integer(), denial_summary() | nil}
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
          ris_mock_port: parse_int!(opts, "ris-mock-port"),
          ris_base_url: Map.get(opts, "ris-base-url"),
          vault_dir: Map.get(opts, "vault-dir")
        )

      # macOS: Unix-Socket-Pfade hoechstens 103 Byte (CONTRACT.md §2)
      with :ok <- Connectors.socket_length(cfg.base_dir),
           [] <- missing_tools(cfg) do
        create_instance(cfg, opts)
      else
        {:error, reason} -> {:error, "Basis abgelehnt: " <> reason, 2}
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
      write_sandbox_profiles(cfg)
      Config.save(%{cfg | pins: Pins.compute(cfg)})
      {:inited, cfg, gguf_lines}
    else
      # place_gguf liefert {:error, reason, 2}; create_dirs wirft bei Misserfolg
      # (MatchError faellt in den init-Rescue). Ein Catch-All hier waere
      # unerreichbar (Dialyzer) und verdeckte das.
      {:error, _reason, _code} = error -> error
    end
  end

  # Ticket #146/#137: Vermittler-, Egress- und Connector-Profile. Fehlt ein
  # Binary, bleibt sein Profil ungeschrieben; der Doctor meldet es.
  @doc """
  Frischt eine bestehende Instanz nach einem Update auf (Ticket #179,
  `komki setup`): Programmpfade (komki und seine Rollen, Erlang-Laufzeit,
  node, pi, llama-server, fd, rg) neu entdecken und, nur wenn sich einer
  geaendert hat, config.json und alle Sandbox-Profile neu schreiben. Ohne
  Pfadaenderung bleibt alles unberuehrt; eine Profil-Abweichung ist dann
  ein Befund fuer den Doctor, kein Anlass zum Ueberschreiben.
  """
  @spec refresh_instance() :: :unchanged | {:refreshed, [String.t()]} | {:error, String.t(), 2}
  def refresh_instance do
    cfg = load_cfg!()
    fresh = Config.defaults(cfg.base_dir)

    fields =
      [:komki_bin, :launcher, :runtime_root, :mediator_bin, :egress_bin, :connector_bins] ++
        [:escript_bin, :node_bin, :cli_js, :llama_server_bin, :fd_bin, :rg_bin]

    # Nur entdeckte Werte uebernehmen; fehlt ein Werkzeug gerade, bleibt
    # der gepinnte Pfad stehen (der Doctor meldet es).
    changes =
      for field <- fields,
          value = Map.fetch!(fresh, field),
          value not in [nil, %{}],
          value != Map.fetch!(cfg, field),
          do: {field, value}

    updated = struct!(cfg, changes)
    pinned = pin_new(updated, cfg)

    cond do
      changes != [] ->
        write_all_profiles(pinned.cfg)

        {:refreshed,
         Enum.map(changes, fn {field, _} -> Atom.to_string(field) end) ++ pinned.names}

      # Gleiche Pfade, aber der Profil-Generator einer neuen komki-Version
      # erzeugt anderen Text (neue Regeln): neu schreiben und das benennen.
      not profiles_current?(cfg) ->
        write_all_profiles(cfg)
        {:refreshed, ["Sandbox-Profile (neue komki-Version)"] ++ pinned.names}

      pinned.names != [] ->
        {:refreshed, pinned.names}

      true ->
        :unchanged
    end
  rescue
    e -> {:error, "Auffrischen fehlgeschlagen: " <> exception_reason(e), 2}
  end

  @doc """
  Vault der Instanz wechseln: stoppt komki (der laufende Vault-Connector
  hat den alten Ordner im Profil), traegt den neuen Ordner ein und schreibt
  die Profile neu. Gleicher Ordner: `:unchanged`.
  """
  @spec set_vault(String.t()) ::
          :unchanged | {:switched, String.t() | nil} | {:error, String.t(), pos_integer()}
  def set_vault(dir) do
    cfg = load_cfg!()

    if cfg.vault_dir == dir do
      :unchanged
    else
      with {:down, _} <- down_with(cfg) do
        updated = %{cfg | vault_dir: dir}
        Config.save(updated)
        write_all_profiles(updated)
        {:switched, cfg.vault_dir}
      end
    end
  rescue
    e -> {:error, "Vault-Wechsel fehlgeschlagen: " <> exception_reason(e), 2}
  end

  # Neu entdeckte Programme (neuer Pfad, etwa nach `brew upgrade`, oder
  # noch nie festgehalten) pinnt setup selbst: Das Entdecken ist der
  # Bedienschritt. Gleicher Pfad mit anderen Bytes bleibt stehen; das
  # bestaetigt die Person einzeln (`changed_pins/0`, `accept_pins/1`).
  defp pin_new(cfg, original) do
    current = Pins.compute(cfg)
    %{new: new} = Pins.drift(cfg, current)
    updated = %{cfg | pins: Map.merge(cfg.pins, Map.take(current, new))}
    if updated != original, do: Config.save(updated)
    %{cfg: updated, names: Enum.map(new, &("Pin " <> &1))}
  end

  @doc "Programme, die sich am festgehaltenen Pfad verändert haben (Name, Pfad)."
  @spec changed_pins() :: [{String.t(), String.t()}]
  def changed_pins do
    cfg = load_cfg!()
    current = Pins.compute(cfg)
    for name <- Pins.drift(cfg, current).changed, do: {name, current[name]["path"]}
  end

  @doc "Bestaetigte Programme mit ihrem aktuellen Hash festhalten."
  @spec accept_pins([String.t()]) :: :ok
  def accept_pins(names) do
    cfg = load_cfg!()
    Config.save(%{cfg | pins: Map.merge(cfg.pins, Map.take(Pins.compute(cfg), names))})
  end

  defp write_all_profiles(cfg) do
    Profile.write!(cfg.profile_path, Profile.generate(cfg, Profile.check_scratch(cfg)))
    Profile.write!(Llama.llama_profile_path(cfg), Profile.generate_llama(cfg))
    write_sandbox_profiles(cfg)
  end

  defp profiles_current?(cfg) do
    expected =
      [
        {cfg.profile_path, fn -> Profile.generate(cfg, Profile.check_scratch(cfg)) end},
        {Llama.llama_profile_path(cfg), fn -> Profile.generate_llama(cfg) end}
      ] ++ Enum.map(ConnectorChecks.profiles(cfg), fn {_name, path, gen} -> {path, gen} end)

    Enum.all?(expected, fn {path, generate} ->
      try do
        File.read(path) == {:ok, generate.()}
      rescue
        ArgumentError -> true
      end
    end)
  end

  defp write_sandbox_profiles(cfg) do
    for {_name, path, generate} <- ConnectorChecks.profiles(cfg) do
      try do
        Profile.write!(path, generate.())
      rescue
        ArgumentError -> :skipped
      end
    end

    :ok
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
      " — Installation prüfen (node via asdf/brew/nvm, pi via pnpm add -g, llama.cpp)" <>
      " oder Pfade in der config.json manuell setzen"
  end

  defp create_dirs(cfg) do
    dirs = [
      Path.dirname(cfg.profile_path) <> ".d",
      Path.join([cfg.base_dir, "models"]),
      Path.join([cfg.base_dir, "tmp"]),
      Path.join([cfg.base_dir, "runs"]),
      Path.join([cfg.base_dir, "denials"]),
      Path.join([cfg.pi_home, "tmp"]),
      Path.join([cfg.pi_home, ".config"]),
      Path.join([cfg.pi_home, ".local", "share"]),
      Path.join([cfg.pi_home, ".cache", "node-compile"]),
      Path.join([cfg.pi_home, ".pi", "agent"])
    ]

    Enum.each(dirs, &File.mkdir_p!/1)
    # Synthetischer Test-Vault (Default) samt Schreibordner des Vault-Connectors
    if is_binary(cfg.vault_dir), do: File.mkdir_p!(Path.join(cfg.vault_dir, "komki-test"))
    # Der Bericht enthaelt Denial-Targets; das Verzeichnis bleibt privat.
    File.chmod!(Path.join([cfg.base_dir, "denials"]), 0o700)
    :ok
  end

  @doc """
  Legt `dest` als APFS-Klon von `source` an (Ticket #178): `cp -c` nutzt
  clonefile(2), belegt keinen zusaetzlichen Platz und dauert Millisekunden
  statt einer 17-GB-Kopie. Scheitert der Klon (anderes Volume, kein APFS),
  kopiert komki wie bisher. Liefert, welcher Weg genommen wurde.
  """
  @spec clone_or_copy(String.t(), String.t()) :: String.t()
  def clone_or_copy(source, dest) do
    File.rm(dest)

    case System.cmd("/bin/cp", ["-c", source, dest], stderr_to_stdout: true) do
      {_, 0} ->
        "APFS-Klon (kein zusätzlicher Platz)"

      {_, _} ->
        File.rm(dest)
        {:ok, _bytes} = File.copy(source, dest)
        "Kopie (Klon nicht möglich, etwa anderes Volume)"
    end
  end

  # GGUF: Quelle = --gguf-from oder das verifizierte Artefakt der
  # Sandbox-Forschung; SHA-Pflicht
  # (Mismatch bricht ab, die Kopie wird entfernt — KEIN brauchbarer Verweis).
  defp place_gguf(cfg, opts) do
    source = Map.get(opts, "gguf-from") || Config.default_probe_gguf()

    cond do
      is_nil(source) ->
        {:error,
         "keine GGUF-Quelle: 'komki setup' lädt das Modell, oder --gguf-from PATH angeben " <>
           "(erwartet unter " <> Config.staging_gguf_path() <> ")", 2}

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
    how = clone_or_copy(source, dest)

    case sha256(dest) do
      {:ok, actual} ->
        with {:ok, lines} <- verify_gguf_sha(cfg, dest, actual),
             do: {:ok, lines ++ ["gguf-ablage:  " <> how]}

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

  @doc "Doctor-quick (Profil-Identität + Boot-Gate) für up/down."
  @spec doctor_quick() :: result()
  def doctor_quick, do: run_checks(:profile_boot)

  @doc "Checks ausführen; Struktur für den CLI-Renderer."
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
      # Programm-Pins: auch im Kurz-Doctor, `up` startet nur mit gleichen Bytes.
      Pins.checks(cfg),
      gguf_checks(cfg, scope),
      boot_gate(cfg),
      llama_boot_gate(cfg),
      [port_check(cfg), llama_auth_check(cfg)],
      # Erst nach `up` sinnvoll: das Flag setzt der Vermittler beim Start,
      # `up` selbst laeuft mit dem Kurz-Doctor (Ticket #139).
      if(scope == :full, do: [journal_check(cfg)], else: []),
      # Ticket #146/#137: Egress, Connectoren, Vermittler-Profil. Nur im vollen
      # Doctor: `up` schreibt diese Profile vor jedem Start frisch.
      if(scope == :full, do: ConnectorChecks.all(cfg), else: [])
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
            %{name: name, ok: false, reason: "nicht entdeckt (Installation/init prüfen)"}

          File.exists?(path) ->
            %{name: name, ok: true, reason: path}

          true ->
            # Gepinnte Pfade koennen verblassen (z.B. brew-Upgrade verschiebt
            # den Cellar-Realpath) — der Hinweis nennt den Wiederherstellungsweg.
            %{
              name: name,
              ok: false,
              reason: "missing: " <> path <> " — 'komki setup' entdeckt neu"
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
          reason: "komki-mediator nicht entdeckt — 'make komki', dann 'komki setup'"
        }

      File.exists?(cfg.mediator_bin) ->
        %{name: "komki-mediator", ok: true, reason: cfg.mediator_bin}

      true ->
        %{
          name: "komki-mediator",
          ok: false,
          reason: "missing: " <> cfg.mediator_bin <> " — 'komki setup' entdeckt neu"
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
            "pi " <> version <> " (major < 1): MCP-Flags nicht unterstützt — pi aktualisieren"
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
      [%{name: "profile", ok: false, reason: "Werkzeugpfade fehlen (config.json unvollständig)"}]
    end
  end

  # Gemeinsame Drei-Zweig-Kaskade der Profil-Identitaetschecks (missing /
  # byte-stabil / drift); die Wrapper liefern name/Pfad/Erwartung —
  # Reason-Strings byte-identisch gepinnt (Tippfehler "Profiltext" im
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
      "drift: regenerierter Profiltext weicht ab — nach einem Update 'komki setup'; bleibt sie, wurde das Profil verändert"
    )
  end

  # Identitaet des llama-Profils (Ticket #100): gemeinsame Kaskade in identity_checks/4.
  defp llama_profile_identity_checks(cfg) do
    identity_checks(
      "llama profile",
      Llama.llama_profile_path(cfg),
      Profile.generate_llama(cfg),
      "drift: regenerierter llama-Profiltext weicht ab — nach einem Update 'komki setup'; bleibt sie, wurde das Profil verändert"
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
              reason: "llama läuft ohne API-Key — 'komki down' und 'komki up' neu starten"
            }

          {:error, reason} ->
            %{name: name, ok: false, reason: reason}
        end

      _ ->
        %{name: name, ok: true, reason: "llama nicht aktiv"}
    end
  end

  @doc """
  Doctor-Check (Ticket #139): das PDR-Journal traegt das Append-only-Flag
  `uappnd`, das der Vermittler beim Start setzt. Fehlt es, hat jemand es
  entfernt — die Hash-Kette macht Aenderungen dann noch sichtbar, das
  Betriebssystem verhindert sie aber nicht mehr. Public als Testnaht.
  """
  @spec journal_check(Config.t()) :: check()
  def journal_check(cfg) do
    name = "journal append-only"
    path = Path.join([cfg.base_dir, "mediator", "journal", "pdr.jsonl"])

    cond do
      not File.exists?(path) ->
        %{name: name, ok: true, reason: "noch kein Journal"}

      append_only?(path) ->
        %{name: name, ok: true, reason: "uappnd gesetzt"}

      true ->
        %{
          name: name,
          ok: false,
          reason: "uappnd fehlt auf " <> path <> " — 'komki down' und 'komki up' setzen es neu"
        }
    end
  end

  defp append_only?(path) do
    case System.cmd("/usr/bin/stat", ["-f", "%Sf", path], stderr_to_stdout: true) do
      {flags, 0} -> "uappnd" in String.split(String.trim(flags), ",")
      _ -> false
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
    # Sonde aus der Library (Ticket #226); das minimale PATH, die
    # stderr-Umleitung und die rc-Begrundung sind dort Teil des Vertrags.
    result = BootCheck.run(cfg.sandbox_exec, profile_path, binary, args, cwd: boot_cwd(cfg, cwd))

    %{name: "boot " <> binary, ok: result.ok, reason: result.reason}
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

  # ===========================================================================
  # up / down / status
  # ===========================================================================

  @spec up(%{String.t() => String.t()}) :: result()
  def up(opts) do
    case doctor_quick() do
      {:checks, _checks, :ok} ->
        cfg = override_ctx(load_cfg!(), opts)

        # Reihenfolge (Ticket #146): llama -> egress -> Connectoren -> Vermittler
        with {:ok, pid} <- Llama.up(cfg),
             :ok <- write_models(cfg),
             {:ok, connectors} <- Connectors.up(cfg),
             {:ok, mediator} <- mediator_up(cfg) do
          %{"tools" => tools} = health_of(mediator)
          Channel.write_relay!(cfg)
          Mediator.write_mcp_config(cfg, tools)
          {:up, %{llama: pid, connectors: connectors, mediator: mediator}}
        else
          {:error, reason} -> {:error, reason, 4}
        end

      {:checks, checks, _summary} ->
        {:error, "Start verweigert: " <> not_green(checks), 3}

      {:error, reason, _code} ->
        {:error, "Start verweigert: " <> reason, 3}
    end
  rescue
    e -> {:error, "up fehlgeschlagen: " <> exception_reason(e), 2}
  end

  @doc """
  Startet alles, wenn llama oder der Vermittler nicht laufen (Ticket #176:
  `run` und `session` ohne vorheriges `komki up`). `:already`, wenn beide
  laufen oder ein Zustand vorliegt, den die folgenden Pruefungen klar melden
  (fremder Prozess, stale pidfile).
  """
  @spec ensure_up() :: :already | result()
  def ensure_up do
    path = Config.config_path(Config.default_base())

    # Ohne Instanz versucht ensure_up nichts; die folgenden Pruefungen
    # melden die fehlende config.json wie bisher.
    with true <- File.exists?(path),
         cfg = Config.load!(path),
         true <- Llama.status(cfg) == :stopped or Mediator.status(cfg) == :stopped do
      up(%{})
    else
      false -> :already
    end
  rescue
    e -> {:error, "Start fehlgeschlagen: " <> exception_reason(e), 2}
  end

  @doc """
  Journal pruefen (Ticket #176): ruft `komki-mediator verify-journal` fuer
  die Instanz auf und liefert dessen JSON-Ergebnis strukturiert.
  """
  @spec journal_verify() :: {:journal, map()} | {:error, String.t(), 2..4}
  def journal_verify do
    cfg = load_cfg!()

    args =
      KomkiCli.Roles.prefix(cfg, cfg.mediator_bin, "komki-mediator") ++
        ["verify-journal", "--base", cfg.base_dir]

    cond do
      not is_binary(cfg.mediator_bin) ->
        {:error, "komki-mediator nicht gefunden — 'make komki' im Repo, dann 'komki setup'", 2}

      # Burrito-Einzeldatei (Ticket #181): die Binary direkt aufrufen
      cfg.launcher == "burrito" and cfg.mediator_bin == cfg.komki_bin ->
        {out, code} = System.cmd(cfg.komki_bin, args, stderr_to_stdout: true)
        journal_result(out, code)

      not is_binary(cfg.escript_bin) ->
        {:error, "Erlang-escript nicht gefunden (config.json: escript_bin)", 2}

      true ->
        {out, code} =
          System.cmd(cfg.escript_bin, [cfg.mediator_bin | args], stderr_to_stdout: true)

        journal_result(out, code)
    end
  rescue
    e -> {:error, "journal verify fehlgeschlagen: " <> exception_reason(e), 2}
  end

  defp journal_result(out, code) do
    case JSON.decode(out |> String.split("\n", trim: true) |> List.last() |> to_string()) do
      {:ok, %{"result" => _} = result} ->
        {:journal, result}

      _ ->
        {:error,
         "journal verify: unerwartete Ausgabe (exit " <>
           to_string(code) <> "): " <> String.slice(out, 0, 300), 4}
    end
  end

  # Praesenz-Pflicht sitzt HIER (up), nicht in init: der Vermittler-Binary
  # ist optional bei init, aber Pflicht zum Start (Ticket #102).
  defp mediator_up(cfg) do
    cond do
      not is_binary(cfg.mediator_bin) ->
        {:error,
         "komki-mediator nicht gefunden — mix escript.build in apps/komki_mediator" <>
           " oder in PATH/<base>/bin ablegen ('komki setup' entdeckt neu)"}

      # Ticket #137: der Vermittler startet unter seinem Profil ueber escript
      # (unter der Burrito-Einzeldatei direkt ueber die Binary, Ticket #181)
      cfg.launcher != "burrito" and not is_binary(cfg.escript_bin) ->
        {:error, "Erlang-escript nicht entdeckt — Erlang installieren, 'komki setup'"}

      true ->
        Mediator.up(cfg)
    end
  end

  @doc """
  Startreihenfolge von `up` (Ticket #146): llama, Egress (falls noetig),
  aktive Connectoren, Vermittler. Rein; `stop_order/0` ist die Umkehrung
  fuer `down` (dort immer alle Connectoren, idempotent).
  """
  @spec start_order(Config.t()) :: [String.t()]
  def start_order(cfg), do: ["llama"] ++ Connectors.start_order(cfg) ++ ["mediator"]

  @spec stop_order() :: [String.t()]
  def stop_order, do: ["mediator"] ++ Connectors.stop_order() ++ ["llama"]

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
    down_with(load_cfg!())
  rescue
    e -> {:error, "down fehlgeschlagen: " <> exception_reason(e), 2}
  end

  @doc """
  down mit expliziter cfg (Testnaht): Vermittler, Connectoren (rueckwaerts),
  Egress, llama — `stop_order/0`. Ein Connector-Fehler bricht nicht ab:
  der Aufraeumweg stoppt so viel wie moeglich und meldet den Fehler danach.
  """
  @spec down_with(Config.t()) :: result()
  def down_with(cfg) do
    case Mediator.down(cfg) do
      {:error, reason} -> {:error, reason, 4}
      mediator -> down_rest(cfg, mediator, Connectors.down(cfg))
    end
  end

  defp down_rest(cfg, mediator, connectors) do
    errors = for {name, {:error, reason}} <- connectors, do: name <> ": " <> reason

    case Llama.down(cfg) do
      {:error, reason} ->
        {:error, Enum.join(errors ++ [reason], "; "), 4}

      llama when errors == [] ->
        {:down,
         %{
           mediator: down_state(mediator),
           connectors: Enum.map(connectors, fn {name, state} -> {name, down_state(state)} end),
           llama: down_state(llama),
           # Ticket #174: pi-Waisen frueherer Sessions mit aufraeumen
           orphans: KomkiCli.Hangup.reap_orphans(Channel.relay_path(cfg))
         }}

      _llama ->
        {:error, Enum.join(errors, "; "), 4}
    end
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
        {:status, cfg,
         %{
           llama: Llama.status(cfg),
           connectors: Connectors.status(cfg),
           mediator: Mediator.status(cfg)
         }}
    end
  end

  # ===========================================================================
  # run
  # ===========================================================================

  # Laufzeit-Limit des Einmal-Laufs (Ticket #133): ohne Limit drehte ein
  # Modell, das sein Werkzeug nicht fand, ueber zehn Minuten Schleifen.
  @run_timeout_s 600

  # `on_start` bekommt das up-Ergebnis, wenn run/session erst starten mussten
  # (Ticket #176); die CLI zeigt damit die Startzeilen sofort an.
  @type on_start :: (result() -> any())

  @spec run(%{String.t() => term()}, on_start()) :: result()
  def run(opts, on_start \\ fn _ -> :ok end) do
    with {:ok, mode} <- mode_from(Map.get(opts, "mode", "text")),
         :ok <- timeout_valid(Map.get(opts, "timeout", @run_timeout_s)),
         :ok <- start_if_needed(on_start) do
      run_checked(opts, mode)
    else
      {:error, reason} -> {:error, reason, 2}
      {:error, _reason, _code} = error -> error
    end
  end

  # Nach der Usage-Pruefung, vor dem Doctor: fehlt llama oder der
  # Vermittler, startet komki alles (wie `up`).
  defp start_if_needed(on_start) do
    case ensure_up() do
      :already ->
        :ok

      {:up, _} = up ->
        on_start.(up)
        :ok

      {:error, _reason, _code} = error ->
        error
    end
  end

  defp timeout_valid(s) when is_integer(s) and s > 0, do: :ok

  defp timeout_valid(s),
    do: {:error, "invalid --timeout " <> Kernel.inspect(s) <> " (Sekunden > 0)"}

  defp run_checked(opts, mode) do
    case run_checks(:full) do
      {:checks, _checks, :ok} ->
        execute_run(opts, mode)

      {:checks, checks, _} ->
        {:error, "run verweigert: " <> not_green(checks), 3}

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
         {:ok, channel_env} <- prepare_channel(cfg),
         {:ok, scratch} <- scratch_for(opts, cfg.base_dir) do
      File.mkdir_p!(scratch)
      prompt = Map.fetch!(opts, "prompt")
      timeout_ms = Map.get(opts, "timeout", @run_timeout_s) * 1000

      # Solange der Lauf geht, lockert `komki raum` nicht (Ticket #268).
      KomkiCli.Raum.track_run(cfg, fn ->
        run_pi_with_capture(cfg, scratch, mode, prompt,
          capture?: Map.has_key?(opts, "capture-denials"),
          pi_fun: fn cfg, scratch, mode, prompt ->
            Pi.run(cfg, scratch, mode, prompt, timeout_ms, channel_env)
          end
        )
      end)
    else
      {:error, reason, code} -> {:error, reason, code}
    end
  end

  @doc """
  Testnaht des Laufs: pi starten, Zeitfenster festhalten und optional
  Denials capturen.

  Das Fenster beginnt unmittelbar vor `pi_fun` und endet unmittelbar
  danach; die Dauer kommt aus `System.monotonic_time`, die Wanduhrzeiten
  sind UTC. Vor `log show` wartet der Drain-Wait, damit der Unified Log
  die letzten Denials des Laufs aufgenommen hat. Capture laeuft in beiden
  pi-Ausgaengen (`{:ok, out}` und `{:error, out, code}`).

  `:pi_fun` ist Pflicht (der Lauf reicht `Pi.run/6` mit Timeout und
  Socket-Zugang herein), `:capture_fun` injizierbar (Tests ohne echtes
  llama/pi/log). Ohne `capture?: true` wird weder `log show` gerufen noch
  ein Bericht geschrieben.
  """
  @spec run_pi_with_capture(Config.t(), String.t(), Pi.mode(), String.t(), keyword()) ::
          result()
  def run_pi_with_capture(%Config{} = cfg, scratch, mode, prompt, opts \\ []) do
    pi_fun = Keyword.fetch!(opts, :pi_fun)
    capture_fun = Keyword.get(opts, :capture_fun, &Denials.capture/2)
    capture? = Keyword.get(opts, :capture?, false)
    drain_ms = Keyword.get(opts, :drain_ms, 500)

    started_at = DateTime.utc_now()
    mono_start = System.monotonic_time(:millisecond)

    pi_result = pi_fun.(cfg, scratch, mode, prompt)

    finished_at = DateTime.utc_now()
    mono_end = System.monotonic_time(:millisecond)

    denial_summary =
      if capture? do
        Process.sleep(drain_ms)

        window_start = DateTime.add(started_at, -1, :second)

        window = %{
          start: window_start,
          end: DateTime.add(finished_at, 1, :second),
          duration_ms: max(mono_end - mono_start, 0),
          pre_roll_ms: DateTime.diff(started_at, window_start, :millisecond),
          drain_wait_ms: drain_ms
        }

        capture_and_persist(cfg, scratch, mode, pi_result, window, capture_fun)
      end

    case pi_result do
      {:ok, output} -> {:run_ok, scratch, output, denial_summary}
      {:error, output, pi_code} -> {:run_error, scratch, output, pi_code, denial_summary}
    end
  end

  defp capture_and_persist(cfg, scratch, mode, pi_result, window, capture_fun) do
    case capture_fun.(window, base_dir: cfg.base_dir, scratch: scratch) do
      {:ok, capture} ->
        persist_capture(cfg, scratch, mode, pi_result, window, capture)

      {:error, reason} ->
        summary("capture_error", [], nil, redact_error(reason, cfg, scratch))

      other ->
        summary(
          "capture_error",
          [],
          nil,
          redact_error("unexpected capture result: " <> Kernel.inspect(other), cfg, scratch)
        )
    end
  rescue
    e -> summary("capture_error", [], nil, redact_error(Exception.message(e), cfg, scratch))
  end

  defp persist_capture(cfg, scratch, mode, pi_result, window, capture) do
    if capture.status == "ok" do
      report = denial_report(cfg, scratch, mode, pi_result, window, capture)

      case Denials.write_report(cfg, report) do
        {:ok, path} ->
          # Kein absoluter Pfad im Footer: der enthaelt den Username.
          summary("ok", capture.denials, Path.join("denials", Path.basename(path)), nil)

        {:error, reason} ->
          summary("write_error", capture.denials, nil, redact_error(reason, cfg, scratch))
      end
    else
      summary(
        capture.status,
        capture.denials,
        nil,
        redact_error(capture.error || "capture failed", cfg, scratch)
      )
    end
  rescue
    e ->
      summary(
        "write_error",
        capture.denials,
        nil,
        redact_error(Exception.message(e), cfg, scratch)
      )
  end

  defp redact_error(reason, cfg, scratch) when is_binary(reason) do
    Denials.redact(reason, cfg.base_dir, scratch)
  end

  defp redact_error(reason, _cfg, _scratch), do: Kernel.inspect(reason)

  defp summary(status, denials, report_path, error) do
    %{status: status, denials: denials, report_path: report_path, error: error}
  end

  defp denial_report(cfg, scratch, mode, pi_result, window, capture) do
    %{
      "schema" => Denials.schema(),
      "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "window" => %{
        "start" => DateTime.to_iso8601(window.start),
        "end" => DateTime.to_iso8601(window.end),
        "duration_ms" => window.duration_ms,
        "pre_roll_ms" => window.pre_roll_ms,
        "drain_wait_ms" => window.drain_wait_ms
      },
      "run" => %{
        "mode" => Atom.to_string(mode),
        "pi_exit" => pi_exit(pi_result),
        "scratch_hash" => sha256_string(scratch),
        "run_profile_sha256" => file_sha256(Pi.profile_path_for(cfg, scratch)),
        "llama_profile_sha256" => file_sha256(Llama.llama_profile_path(cfg))
      },
      "capture" => %{
        "status" => capture.status,
        "log_binary" => capture.log_binary,
        "argv" => capture.argv,
        "predicate" => capture.predicate,
        "error" => capture.error,
        "matched" => capture.matched,
        "parsed" => capture.parsed,
        "unparsed" => capture.unparsed
      },
      "denials" => Enum.map(capture.denials, &denial_json/1),
      "redaction" => %{
        "policy" => "komki-denials-redact/1",
        "applied" => true,
        "redacted_count" => capture.redacted_count
      },
      "epistemic_limit" => @denial_epistemic_limit
    }
  end

  defp pi_exit({:ok, _output}), do: 0
  defp pi_exit({:error, _output, code}), do: code

  defp denial_json(denial) do
    %{
      "logged_at" => denial.logged_at,
      "process" => denial.process,
      "pid" => denial.pid,
      "deny_count" => denial.deny_count,
      "operation" => denial.operation,
      "target" => denial.target,
      "occurrences" => denial.occurrences
    }
  end

  defp sha256_string(value) do
    digest = :crypto.hash(:sha256, value)
    Base.encode16(digest, case: :lower)
  end

  defp file_sha256(path) do
    case sha256(path) do
      {:ok, hash} -> hash
      {:error, _reason} -> nil
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
  # Ein Server je Instanz: die Standard-Instanz heisst "komki", jede andere
  # (KOMKI_HOME) bekommt einen eigenen Namen aus ihrem Pfad. Sonst teilten
  # sich zwei Instanzen eine Session.
  defp tmux_server(cfg), do: ["-L", tmux_socket(cfg), "-f", "/dev/null"]

  @doc "Name des tmux-Servers der Instanz (`tmux -L <name>`)."
  @spec tmux_socket(Config.t()) :: String.t()
  def tmux_socket(%Config{base_dir: base}) do
    default = Path.join(Config.canonical(System.user_home!()), ".local/share/komki")

    if base == default,
      do: "komki",
      else:
        "komki-" <> String.slice(Base.encode16(:crypto.hash(:sha256, base), case: :lower), 0, 8)
  end

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
  defp attach_hint(cfg), do: "'tmux -L " <> tmux_socket(cfg) <> " attach -t komki'"

  @doc """
  Interner Pane-Einstieg (tmux-Pane der Session): startet die pi-Kette als
  Port-Kind DIESES BEAM mit `:nouse_stdio` — node erbt die Pane-PTY als
  Terminal. Der Port-Kind-Weg ist der Kern des macOS-27.2-Beta-Workarounds:
  node bootet unter dem Profil nur als BEAM-Port-Kind, fork-geborene Ketten
  sterben beim Init mit SIGABRT (Crash-Analyse im Session-Smoke). Der
  Port-Env ersetzt die Umgebung komplett (`Pi.session_env/2`).

  Unter Burrito (`KomkiCli.Runtime.burrito?/0`) leitet die Kette ihr stdout
  zusaetzlich auf /dev/fd/0 um (Dup des lebenden stdin-PTY): Das BEAM-stdout
  ist dort die Wrapper-Pipe, pi beendet sich ohne echtes Terminal sofort
  (Pilot 2026-10-11, Issue-#234-Klasse). Das Profil erlaubt das Oeffnen von
  /dev/fd/0 kontextfrei — Escript-Panels laufen unverändert ueber die
  Direktkette.
  """
  @spec session_chain(%{String.t() => String.t()}) :: result()
  def session_chain(opts) do
    with {:ok, base} <- chain_base(opts, System.get_env("KOMKI_HOME")),
         {:ok, cfg} <- load_chain_cfg(base) do
      do_session_chain(cfg, Map.has_key?(opts, "continue"))
    end
  rescue
    e -> {:error, "session-chain fehlgeschlagen: " <> exception_reason(e), 2}
  end

  @doc """
  Basis des Pane-Laufs (Ticket #251): kommt ausdrücklich als `--base` aus
  dem Pane-Kommando, nie aus der Umgebung des tmux-Servers. Zeigt
  `KOMKI_HOME` im Pane auf eine andere Basis, teilen sich zwei Instanzen
  einen tmux-Server; dann bricht der Lauf ab, statt mit dem falschen
  Vermittler zu sprechen. Public als Testnaht.
  """
  @spec chain_base(%{String.t() => String.t()}, String.t() | nil) ::
          {:ok, String.t()} | {:error, String.t(), 2}
  def chain_base(opts, env_home) do
    case Map.get(opts, "base") do
      nil ->
        {:error,
         "session-chain ohne --base: Pane-Kommando unvollständig, 'komki session' neu starten", 2}

      base ->
        base = Config.canonical(base)

        if is_nil(env_home) or Config.canonical(env_home) == base,
          do: {:ok, base},
          else:
            {:error,
             "Basis des Panes weicht ab: KOMKI_HOME=" <>
               Config.canonical(env_home) <>
               ", die Session gehört zu " <>
               base <>
               ". Zwei Instanzen teilen sich einen tmux-Server; die Session startet nicht.", 2}
    end
  end

  defp load_chain_cfg(base) do
    case Config.load(Config.config_path(base)) do
      {:ok, cfg} -> {:ok, cfg}
      {:error, reason} -> {:error, "config: " <> reason, 2}
    end
  end

  defp do_session_chain(cfg, continue?) do
    case prepare_channel(cfg) do
      {:ok, channel_env} -> start_session_chain(cfg, continue?, channel_env)
      {:error, reason, code} -> {:error, reason, code}
    end
  end

  defp start_session_chain(cfg, continue?, channel_env) do
    File.mkdir_p!(Pi.session_dir(cfg))

    arbeit = Path.join(cfg.base_dir, "arbeit")
    File.mkdir_p!(arbeit)
    Profile.write!(Pi.session_profile_path(cfg), Profile.generate(cfg, arbeit))

    [program | args] = Pi.argv_session(cfg, continue?, KomkiCli.Runtime.burrito?())

    # Port-Env in Charlist-Form: die open_port-Spec fuer :env verlangt sie
    # (Dialyzer-Fund: Binär-Tupel lassen den Aufruf als fehlgeschlagen typisieren).
    env =
      Enum.map(Pi.session_env(cfg, channel_env), fn {key, value} ->
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

    # Ticket #174: schliesst sich das tmux-Fenster, nimmt der BEAM pi mit.
    {:os_pid, pi_pid} = Port.info(port, :os_pid)
    KomkiCli.Hangup.install(pi_pid)
    # Ticket #197: ein Terminal-Resize erreicht pi nur ueber den BEAM.
    KomkiCli.Resize.install(pi_pid)

    # Ticket #98: GO-Anfragen des Vermittlers als Popup in dieser Session.
    with tmux when is_binary(tmux) <- System.find_executable("tmux") do
      KomkiCli.GoWatcher.start_link(
        cfg.base_dir,
        [tmux, "-L", tmux_socket(cfg)],
        KomkiCli.Runtime.self_path()
      )
    end

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
  @spec session(%{String.t() => term()}, on_start()) :: result()
  def session(opts, on_start \\ fn _ -> :ok end) do
    case session_plan(opts, on_start) do
      {:session_plan, _header, intake} -> session_start(intake, opts)
      other -> other
    end
  end

  @doc """
  Plant die Session (Ticket #92): Dateipfade VOR allem anderen pruefen,
  dann komki bei Bedarf starten (damit ist Γ aus dem Label-Store
  synchron, #208), full doctor, dann ohne Dateien nur der
  Startvertrag-Header, mit Dateien die Aufnahmeentscheidung je Datei.
  Der CLI-Weg druckt den Header vor `session_start/2`.

  Testnaehte: `:config` (Config statt config.json), `:start` und
  `:doctor` (0-stellige Funktionen statt Start und Doctor),
  `:tmux_running?`.
  """
  @spec session_plan(%{String.t() => term()}, on_start()) :: result()
  def session_plan(opts, on_start \\ fn _ -> :ok end) do
    cfg = session_cfg(opts)
    db = session_db(opts, cfg)

    with {:ok, files} <-
           SessionIntake.validate_paths(Map.get(opts, "files", []), %{
             base_dir: cfg.base_dir,
             pi_home: cfg.pi_home,
             db: db
           }),
         :ok <- SessionIntake.guard_new_start(files, opts),
         :ok <- check_instance_binding(files, cfg, opts),
         :ok <- guard_running_session(files, cfg, opts),
         :ok <- session_start_needed(opts, on_start),
         :ok <- session_doctor_ok(opts) do
      if files == [] do
        {:session_plan, session_header_without_files(cfg, opts), nil}
      else
        plan_session_intake(cfg, files, opts)
      end
    else
      {:error, reason, code} -> {:error, reason, code}
      {:error, reason} -> {:error, reason, 2}
    end
  rescue
    e -> {:error, "session fehlgeschlagen: " <> exception_reason(e), 2}
  end

  @doc """
  Startet die geplante Session: Liveness von llama und Vermittler, dann
  die zugelassenen Dateien als Raumdokumente ablegen und den Vermittler
  neu starten, damit er den Raum mit ihnen liest; dann tmux.
  """
  @spec session_start(SessionIntake.intake() | nil, %{String.t() => term()}) :: result()
  def session_start(nil, opts), do: execute_session(opts)

  def session_start(intake, opts) do
    cfg = session_cfg(opts)

    with {:ok, _pid} <- require_llama_up(cfg),
         {:ok, _pid} <- require_mediator_up(cfg),
         :ok <- stage_intake(intake),
         :ok <- reload_mediator(cfg) do
      execute_session(opts)
    end
  rescue
    e -> {:error, "session fehlgeschlagen: " <> exception_reason(e), 2}
  end

  defp session_start_needed(opts, on_start) do
    case Map.get(opts, :start) do
      fun when is_function(fun, 0) -> fun.()
      _ -> start_if_needed(on_start)
    end
  end

  # Der Doctor-Gate bleibt vor jedem Start; `:doctor` ist eine Testnaht.
  defp session_doctor_ok(opts) do
    case Map.get(opts, :doctor) do
      fun when is_function(fun, 0) -> normalize_doctor(fun.())
      _ -> normalize_doctor(run_checks(:full))
    end
  end

  defp normalize_doctor(:ok), do: :ok
  defp normalize_doctor({:checks, _checks, :ok}), do: :ok

  defp normalize_doctor({:checks, checks, _}),
    do: {:error, "session verweigert: " <> not_green(checks), 3}

  defp normalize_doctor({:error, reason, code}), do: {:error, reason, code}

  # Aufnahme und Vermittler muessen dieselben Dateien sehen: --db/--room
  # sind Testnaehte und gelten nur, wenn sie auf die Instanzdateien zeigen.
  defp check_instance_binding([], _cfg, _opts), do: :ok

  defp check_instance_binding(_files, cfg, opts) do
    with :ok <-
           same_path(Map.get(opts, "room"), StartContract.default_path(cfg.base_dir), "--room") do
      same_path(Map.get(opts, "db"), Gamma.db_path(cfg), "--db")
    end
  end

  defp same_path(nil, _default, _flag), do: :ok

  defp same_path(path, default, flag) do
    if Config.canonical(path) == Config.canonical(default),
      do: :ok,
      else:
        {:error,
         flag <>
           " ist eine Testnaht und muss auf " <> default <> " zeigen (angegeben: " <> path <> ")"}
  end

  # Aufnahme nur bei neuem Start: Dateien gehoeren nicht in eine laufende
  # pi-Sitzung.
  defp guard_running_session([], _cfg, _opts), do: :ok

  defp guard_running_session(_files, cfg, opts) do
    if session_tmux_running?(cfg, opts),
      do:
        {:error,
         "tmux-session '" <> @tmux_session <> "' läuft bereits; Dateiaufnahme nur bei neuem Start",
         2},
      else: :ok
  end

  defp session_tmux_running?(cfg, opts) do
    case Map.get(opts, :tmux_running?) do
      fun when is_function(fun, 0) ->
        fun.()

      _ ->
        case System.find_executable("tmux") do
          nil -> false
          tmux -> tmux_session_running?(tmux, cfg)
        end
    end
  end

  defp session_header_without_files(cfg, opts) do
    room_path = session_room_path(cfg, opts)

    case StartContract.load(room_path, nil) do
      {:ok, contract} ->
        StartContract.header(contract)

      {:error, reason} ->
        [
          "hinweis: Der Startvertrag in room.json ist nicht lesbar (" <> reason <> ").",
          "         Die Session läuft trotzdem; Dateien mitbringen geht erst mit gültigem Vertrag."
        ]
    end
  end

  defp plan_session_intake(cfg, files, opts) do
    db = session_db(opts, cfg)
    room_path = session_room_path(cfg, opts)

    # Struktur und Zweck zuerst (kein DB-Zugriff ohne Vertrag), dann Γ aus
    # dem Label-Store laden und den Vertrag gegen seine Bindungen pruefen.
    with {:ok, _contract} <- load_session_contract(room_path, nil),
         {:ok, compiled} <- SessionIntake.load_registry(db),
         {:ok, contract} <- load_session_contract(room_path, compiled) do
      intake_opts = %{
        db: db,
        room: contract,
        compiled: compiled,
        files: files,
        base_dir: cfg.base_dir,
        pi_home: cfg.pi_home,
        decided_by: Map.get(opts, "decided-by") || contract.verantwortliche_person
      }

      case SessionIntake.plan(intake_opts) do
        {:ok, intake} ->
          {:session_plan, StartContract.header(contract) ++ SessionIntake.header(intake), intake}

        {:refused, entries} ->
          {:session_refused, StartContract.header(contract) ++ SessionIntake.entry_lines(entries),
           entries}

        {:error, reason} ->
          {:error, reason, 2}
      end
    else
      {:error, reason} -> {:error, reason, 2}
    end
  end

  defp load_session_contract(room_path, compiled) do
    case StartContract.load(room_path, compiled) do
      {:ok, %{contract_hash: nil}} ->
        {:error, StartContract.setup_remedy(room_path, "contract-Block fehlt")}

      {:ok, contract} ->
        case StartContract.validate_for_intake(contract) do
          :ok -> {:ok, contract}
          {:error, reason} -> {:error, StartContract.setup_remedy(room_path, reason)}
        end

      {:error, reason} ->
        {:error, StartContract.setup_remedy(room_path, reason)}
    end
  end

  defp stage_intake(intake) do
    case SessionIntake.stage(intake) do
      :ok -> :ok
      {:error, reason} -> {:error, reason, 2}
    end
  end

  # Der Vermittler liest room.json nur beim Start; neue Raumdokumente
  # brauchen deshalb einen Neustart. Das Token bleibt (Ticket #216).
  defp reload_mediator(cfg) do
    case Mediator.restart(cfg) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Vermittler-Neustart nach der Aufnahme: " <> reason, 2}
    end
  end

  defp session_room_path(cfg, opts) do
    case Map.get(opts, "room") do
      nil -> StartContract.default_path(cfg.base_dir)
      path -> Config.canonical(path)
    end
  end

  defp session_db(opts, cfg) do
    case Map.get(opts, "db") do
      nil -> Gamma.db_path(cfg)
      path -> Config.canonical(path)
    end
  end

  # Testnaht: `:config` ersetzt die geladene config.json.
  defp session_cfg(opts) do
    case Map.get(opts, :config) do
      %Config{} = cfg -> cfg
      _ -> load_cfg!()
    end
  end

  defp execute_session(opts) do
    cfg = load_cfg!()

    # Reihenfolge wie `up`: llama vor Vermittler; auch die Session startet
    # pi mit `-e builtin:mcp` — ein toter Vermittler bricht hier ab.
    with {:ok, _pid} <- require_llama_up(cfg),
         {:ok, _pid} <- require_mediator_up(cfg),
         {:ok, tmux} <- find_tmux() do
      if tmux_session_running?(tmux, cfg) do
        attach_or_refuse(tmux, cfg, opts)
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
           " antwortet, aber pidfile fehlt (fremder Prozess?) — 'komki status' prüfen", 2}

      :stopped ->
        {:error, "llama-server nicht aktiv: 'komki up' zuerst", 2}

      {:error, reason} ->
        {:error, reason, 2}
    end
  end

  # Socket-Zugang fuer einen pi-Start (Ticket #143): Token lesen, Session-ID
  # erzeugen, Relay frisch schreiben. Fehlt das Token, ist `komki up` noetig.
  # Auch die mcp.json wird frisch aus der healthz-Antwort geschrieben: das
  # pi-Home ist fuer den Agenten schreibbar, und ein eingetragener
  # MCP-Server darf keinen Lauf ueberdauern (Labbook S-07). Aus demselben
  # Grund wird die Anzeige-Extension neu geschrieben.
  defp prepare_channel(cfg) do
    with {:ok, env} <- Channel.prepare_pi(cfg),
         {:ok, "200", health} <- Mediator.fetch_health(cfg) do
      :ok = Mediator.write_mcp_config(cfg, health["tools"])
      :ok = Anzeige.write!(cfg)
      {:ok, env}
    else
      {:ok, code, _health} -> {:error, "komki-mediator /healthz returned " <> code, 2}
      {:error, reason} -> {:error, reason, 2}
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
         Channel.socket_path(cfg) <>
           " antwortet healthz, aber pidfile fehlt (fremder Prozess?) — 'komki status' prüfen", 2}

      :stopped ->
        {:error, "komki-mediator nicht aktiv: 'komki up' zuerst", 2}

      {:error, reason} ->
        {:error, reason, 2}
    end
  end

  defp find_tmux do
    case System.find_executable("tmux") do
      nil ->
        {:error, "tmux nicht gefunden (nötig für interaktive Sessions; z.B. 'brew install tmux')",
         2}

      tmux ->
        {:ok, tmux}
    end
  end

  @doc "`komki raum [NAME]` (Ticket #268): anzeigen oder wechseln, siehe `KomkiCli.Raum`."
  @spec raum(String.t() | nil) :: {:raum, String.t()} | {:error, String.t(), pos_integer()}
  def raum(nil), do: KomkiCli.Raum.show(load_cfg!())
  def raum(name), do: KomkiCli.Raum.switch(load_cfg!(), name)

  @doc "Ob die interaktive Session dieser Instanz läuft (für `komki raum`, Ticket #268)."
  @spec session_running?(Config.t()) :: boolean()
  def session_running?(%Config{} = cfg) do
    case System.find_executable("tmux") do
      nil -> false
      tmux -> tmux_session_running?(tmux, cfg)
    end
  end

  defp tmux_session_running?(tmux, cfg) do
    # stderr gefangen: "no server running"-Meldungen sollen das Terminal
    # des Aufrufers nicht zumuellen (Live-Fund aus dem Session-Smoke).
    case System.cmd(tmux, tmux_server(cfg) ++ ["has-session", "-t", "=" <> @tmux_session],
           stderr_to_stdout: true
         ) do
      {_out, 0} -> true
      _ -> false
    end
  end

  # tmux im Attach-Modus braucht das echte Terminal des Aufrufers; System.cmd
  # gäbe BEAM-Pipes ("open terminal failed: not a terminal" — Live-Fund aus
  # dem Session-Smoke). Ein Port ohne :use_stdio reicht das eigene stdio durch.
  defp run_tmux_inheriting_terminal(tmux, cfg, args) do
    # TMUX ausgeblendet: aus einer laufenden tmux-Session heraus startet der
    # eigene komki-Server als verschachtelter Client statt abzulehnen.
    port =
      Port.open({:spawn_executable, tmux}, [
        :nouse_stdio,
        :exit_status,
        {:args, tmux_server(cfg) ++ args},
        {:env, [{~c"TMUX", false}]}
      ])

    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, code}} -> {:error, code}
    end
  end

  defp attach_or_refuse(tmux, cfg, opts) do
    if Map.has_key?(opts, "detach") do
      {:error,
       "tmux-session '" <>
         @tmux_session <>
         "' läuft bereits; ohne --detach via " <> attach_hint(cfg) <> " andocken", 2}
    else
      case run_tmux_inheriting_terminal(tmux, cfg, ["attach", "-t", "=" <> @tmux_session]) do
        :ok ->
          {:session,
           "session beendet oder abgekoppelt; " <>
             attach_hint(cfg) <>
             "' zum Weiterarbeiten"}

        {:error, code} ->
          {:error, "tmux attach endete mit exit " <> to_string(code), 4}
      end
    end
  end

  defp start_new_session(cfg, tmux, opts) do
    continue? = Map.has_key?(opts, "continue")
    detach? = Map.has_key?(opts, "detach")

    with :ok <- continue_precondition(cfg, continue?),
         :ok <- KomkiCli.Raum.mark_session(cfg, continue?) do
      prepare_session_assets(cfg)
      pane = Pi.pane_command(KomkiCli.Runtime.self_path(), cfg.base_dir, continue?)

      if detach?,
        do: create_detached(tmux, cfg, pane),
        else: create_with_attach(tmux, cfg, pane)
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
           tmux_server(cfg) ++
             @tmux_lockdown ++ ["new-session", "-d", "-s", @tmux_session, "-c", cfg.pi_home, pane],
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        {:session, session_started_message(cfg, true)}

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

    case run_tmux_inheriting_terminal(tmux, cfg, args) do
      :ok ->
        {:session, session_started_message(cfg, false)}

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
         "keine frühere Session in " <> Pi.session_dir(cfg) <> "; ohne --continue starten", 2}

      # Fortsetzen nur in einem Raum, der mindestens so streng ist wie der
      # der letzten Session: pi bringt ihren Kontext mit (Ticket #268).
      {:ok, _sessions} ->
        KomkiCli.Raum.continue_allowed(cfg)

      {:error, _posix} ->
        {:error,
         "keine frühere Session in " <> Pi.session_dir(cfg) <> "; ohne --continue starten", 2}
    end
  end

  defp continue_precondition(_cfg, false), do: :ok

  defp session_started_message(cfg, true = _detach) do
    "tmux-session '" <>
      @tmux_session <> "' gestartet (detached); " <> attach_hint(cfg) <> " zum Arbeiten"
  end

  defp session_started_message(cfg, false) do
    "tmux-session '" <>
      @tmux_session <>
      "' beendet oder abgekoppelt; " <> attach_hint(cfg) <> " zum Weiterarbeiten"
  end

  # ===========================================================================
  # Helfer
  # ===========================================================================

  # Die roten Checks beim Namen nennen statt pauschal "Boot-Gate".
  defp not_green(checks) do
    failing = for %{ok: false, name: name} <- checks, do: name
    "nicht grün: " <> Enum.join(failing, ", ") <> " — 'komki doctor' nennt die Gründe"
  end

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
              message: "ungültiger Wert für --" <> flag <> ": " <> Kernel.inspect(raw)
        end

      raw ->
        raise ArgumentError,
          message: "ungültiger Wert für --" <> flag <> ": " <> Kernel.inspect(raw)
    end
  end

  defp load_cfg! do
    Config.load!(Config.config_path(Config.default_base()))
  end

  defp exception_reason(e), do: Exception.message(e)
end
