defmodule KomkiCli.Profile do
  @moduledoc """
  Generiert das Seatbelt-Profil (SBPL) für pi-Läufe unter deny-default.

  Semantisch exakt die validierte Kandidat-Kombination aus dem
  Ticket-#70-Beschluss (inkl. pi/node-Erweiterungen; die Begründung je
  Regel steht im Research-Report
  `docs/research/2026-10-04-probe-harness-sandbox.md` im Branch
  `research/probe-harness-sandbox`), parametrisiert auf:

    * Port — einzige Netz-Exception `(allow network-outbound (remote tcp "localhost:<port>"))`
    * pi-Home — isoliertes HOME (lesend/schreibend, inkl. Komponenten-Kette)
    * Scratch-Verzeichnis — die Write-Scope dieses Laufs (lesend/schreibend)

  Garantien (vom Profil-Test erzwungen):

    * `(deny default)` Basis; niemals `(allow default)`, keine Host-Wildcards,
      kein breites `(allow mach-lookup)` im Kandidatenprofil.
    * Nur kernel-kanonische Pfade (realpath-aufgeloest; unter macOS die
      `/private/...`-Form) — Pfadform-Cave aus Phase 1.
    * Feste Eingaben erzeugen byte-identischen Output (Determinismus).
    * pi Erst-Aufruf-Kette ist die Direktkette node -> cli.js (dokumentierte
      Abweichung: der asdf-Shim-Layer scheitert stumm unter dem schmalen
      Profil).
  """

  alias KomkiCli.Config
  require Config

  @doc """
  Scratch-Verzeichnis für die Identitäts-Regeneration (init/doctor):
  regeneriertes Profil muss byte-identisch mit der gespeicherten Datei sein.
  """
  @spec check_scratch(Config.t()) :: String.t()
  def check_scratch(%Config{} = cfg) do
    Path.join(Path.dirname(cfg.profile_path) <> ".d", "check-scratch")
  end

  @doc "Profil-Text generieren. Feste Eingaben -> byte-identischer Output."
  @spec generate(Config.t(), String.t()) :: String.t()
  def generate(%Config{} = cfg, scratch)
      when is_binary(scratch) and Config.tools_ready(cfg) do
    scratch = Config.canonical(scratch)

    # Host-unabhaengig: <home> und asdf-Root aus der gepinnten node-Kette
    # (cfg.node_bin) ableiten statt vom laufenden Host — CI-Linux hat kein
    # ~/.asdf und System.user_home! zeigt auf den Runner; der Profiltext
    # waere dort unvollstaendig (CI-Fund: fehlende asdf-Sysctl-Pins).
    {user_home, asdf_root_dir} = pinned_chain_roots(cfg.node_bin)

    asdf_root_dir
    |> rules_for(cfg, scratch, user_home)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Unvollstaendige config (Werkzeugpfade fehlen): klar scheitern statt
  # kryptisch in Regel-Konkatenationen zu crashen.
  def generate(%Config{}, _scratch) do
    raise ArgumentError,
      message:
        "Profil-Generierung braucht vollstaendige Werkzeugpfade " <>
          "(node/cli/llama-server) — init verweigert unvollstaendige Instanzen; config.json pruefen"
  end

  @doc "Profil schreiben (Verzeichnis wird erzeugt)."
  @spec write!(String.t(), String.t()) :: :ok
  def write!(path, text) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
    :ok
  end

  ## ---------------------------------------------------------------- Regelaufbau

  defp rules_for(asdf_root_dir, cfg, scratch, user_home) do
    node = cfg.node_bin
    # node installiert im asdf-Schema <asdf-root>/installs/nodejs/<v>/bin/node:
    # bin_dir = .../bin, install_root = .../<v>.
    node_bin_dir = Path.dirname(node)
    node_install = Path.dirname(node_bin_dir)
    pi_launcher = Path.join([node_install, "bin", "pi"])
    pi_pkg = cli_js_pkg(cfg.cli_js)
    node_modules_root = Path.join([node_install, "lib", "node_modules"])
    port = to_string(cfg.port)

    base_rules =
      basis_and_exec_rules(cfg, node, pi_launcher) ++
        meta_rules(
          cfg,
          scratch,
          node_install,
          node_modules_root,
          pi_pkg,
          asdf_root_dir,
          user_home
        )

    port_rule = "(allow network-outbound (remote tcp \"localhost:" <> port <> "\"))"

    base_rules ++
      common_boot_rules() ++
      asdf_rules(asdf_root_dir) ++
      node_boot_rules(pi_pkg, node_modules_root, user_home) ++
      tui_rules() ++
      scope_rules(cfg, scratch) ++
      [port_rule]
  end

  ## ---------------------------------------------------------------- TUI/Terminal-Klasse

  # Muster aus anthropic-experimental/sandbox-runtime (macos-sandbox-utils.ts)
  # und srt-Issue #419: TUIs (raw mode, Terminalgroesse, Signale) scheitern
  # unter deny-default STILL, wenn die Terminal-Klasse nicht explizit erlaubt
  # ist. Die Headless-Sonden brauchten diese Regeln nie; die interaktive
  # Session (pi-TUI auf der tmux-Pty) schon. Scopes: Prozesssteuerung nur
  # innerhalb desselben Sandkastens, Terminal-Zugriff nur auf echte tty-Geraete.
  defp tui_rules do
    [
      "; TUI/Terminal-Klasse (sandbox-runtime-Muster; srt #419)",
      "(allow file-ioctl (literal \"/dev/tty\"))",
      "(allow file-ioctl (regex #\"^/dev/ttys[0-9]+$\"))",
      "(allow pseudo-tty)",
      "(allow process-info* (target same-sandbox))",
      "(allow signal (target same-sandbox))",
      "(allow mach-priv-task-port (target same-sandbox))",
      "(allow user-preference-read)",
      "(allow distributed-notification-post)",
      "(allow ipc-posix-sem)",
      "; hw.*/kern.proc.* versionsfest: neue OS-Versionen lesen neue Felder",
      "; (zsh-5.9-Regressionsklasse auf darwin25+)",
      "(allow sysctl-read (sysctl-name-prefix \"hw.\"))",
      "(allow sysctl-read (sysctl-name-prefix \"kern.proc.\"))"
    ]
  end

  defp basis_and_exec_rules(cfg, node, pi_launcher) do
    tools_fd = Path.join([cfg.pi_home, ".pi", "agent", "bin", "fd"])
    tools_rg = Path.join([cfg.pi_home, ".pi", "agent", "bin", "rg"])

    [
      "(version 1)",
      "(deny default)",
      "; Basis: validierter Kandidat aus Ticket #70 (Evidenz: Research-Report der Sandbox-Forschung).",
      "; Jede pi/node-Zusatzregel traegt ihre Rationale im Research-Report (Branch research/probe-harness-sandbox).",
      "(allow process-exec (literal \"/usr/bin/true\"))",
      "(allow process-exec (literal \"/bin/sh\"))",
      "(allow process-exec (literal \"/bin/bash\"))",
      "(allow process-exec (literal \"" <> node <> "\"))",
      "(allow process-exec (literal \"" <> pi_launcher <> "\"))",
      "(allow process-exec* (literal \"" <> pi_launcher <> "\"))",
      "; pi's Such-Werkzeuge fd/rg: Kopien im agent-bin-Fundus (init schreibt sie)",
      "(allow process-exec (literal \"" <> tools_fd <> "\"))",
      "(allow process-exec* (literal \"" <> tools_fd <> "\"))",
      "(allow process-exec (literal \"" <> tools_rg <> "\"))",
      "(allow process-exec* (literal \"" <> tools_rg <> "\"))",
      "(allow process-fork)",
      "(allow file-read* (subpath \"/System/Library\"))",
      "(allow file-read* (subpath \"/usr/lib\"))",
      "(allow file-read* (subpath \"/System/Volumes/Preboot\"))",
      "(allow file-read* (literal \"/usr/bin/true\"))",
      "(allow file-read* (literal \"/bin/sh\"))",
      "(allow file-read* (literal \"/bin/bash\"))",
      "(allow file-read* (literal \"" <> node <> "\"))",
      "(allow file-read* (literal \"" <> pi_launcher <> "\"))",
      "(allow file-read* (literal \"/dev/null\"))",
      "(allow file-read* (literal \"/dev/random\"))",
      "(allow file-read* (literal \"/dev/urandom\"))",
      "; Shebang-Hop-Schicht kommt im Lauf nicht vor (direkte node-Kette): /usr/bin/env nicht erlaubt."
    ]
  end

  ## ---------------------------------------------------------------- Metadaten-Kette

  defp meta_rules(cfg, scratch, node_install, node_modules_root, pi_pkg, asdf_root_dir, user_home) do
    # Install-Pfade (brew, asdf, nvm) entstehen hier NUR aus den entdeckten
    # Werkzeugpfaden (Vorfahr-Kette des jeweiligen Pfads) — keine hartkodierten
    # Systemwurzeln (Portabilitaets-Regel).
    paths = [
      "/System",
      "/System/Volumes",
      "/System/Cryptexes",
      "/bin",
      "/dev",
      "/opt",
      cfg.llama_server_bin,
      "/private/var/select",
      cfg.base_dir,
      Path.dirname(cfg.profile_path) <> ".d",
      scratch,
      cfg.pi_home,
      Path.join([cfg.pi_home, "tmp"]),
      Path.join([cfg.pi_home, ".config"]),
      Path.join([cfg.pi_home, ".local"]),
      Path.join([cfg.pi_home, ".local", "share"]),
      Path.join([cfg.pi_home, ".cache"]),
      Path.join([cfg.pi_home, ".pi"]),
      Path.join([cfg.pi_home, ".pi", "agent"]),
      "/private/var/db/timezone",
      "/usr/share",
      "/usr/share/icu",
      node_install,
      node_modules_root,
      pi_pkg,
      user_home
    ]

    base_meta = meta_ancestors(paths)

    asdf_meta =
      if is_binary(asdf_root_dir) do
        asdf_paths =
          [
            asdf_root_dir,
            Path.join([asdf_root_dir, "shims"]),
            Path.join([asdf_root_dir, "installs"]),
            Path.join([asdf_root_dir, "installs", "nodejs"]),
            Path.join([asdf_root_dir, "plugins"]),
            node_install
            # asdf-Binary (z.B. brew-installiert): Metadaten-Vorfahrn aus dem
            # entdeckten Pfad statt hartkodierter brew-Wurzeln.
          ] ++ asdf_binary_paths()

        meta_ancestors(asdf_paths)
      else
        []
      end

    base_meta ++ asdf_meta
  end

  defp meta_ancestors(paths) do
    paths
    |> Enum.flat_map(fn path ->
      abs = String.trim_leading(path, "/")
      segments = String.split(abs, "/", trim: true)

      Enum.map(1..length(segments), fn i ->
        "/" <> Enum.join(Enum.take(segments, i), "/")
      end)
    end)
    |> MapSet.new()
    |> MapSet.put("/")
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(fn c -> "(allow file-read-metadata (literal \"" <> c <> "\"))" end)
  end

  ## ---------------------------------------------------------------- Boot-Schicht

  defp common_boot_rules do
    [
      "; env/bash/asdf-Boot-Proben (Evidenz 10:52:46/56 UTC)",
      "(allow sysctl-read (sysctl-name \"security.mac.lockdown_mode_state\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/Rosetta\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/App\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/OS\"))",
      "(allow file-read-metadata (literal \"/var\"))",
      "(allow file-read-data (literal \"/\"))",
      "(allow file-write-data (literal \"/dev/dtracehelper\"))",
      "; dtracehelper-Dreifach-Grant (Grammatik aus system.sb:122)",
      "(allow file-read* file-test-existence file-write-data file-ioctl (literal \"/dev/dtracehelper\"))",
      "; disk-space-Probe (fstatfs; Grammatik aus system.sb:202)",
      "(allow system-info (info-type \"vfs.disk-space\"))"
    ]
  end

  defp asdf_rules(asdf_root_dir) do
    if is_binary(asdf_root_dir) do
      shims_root = Path.join([asdf_root_dir, "shims"])
      installs_root = Path.join([asdf_root_dir, "installs"])
      plugins_root = Path.join([asdf_root_dir, "plugins"])

      Kernel.++(
        [
          "; asdf-Shim-Layer bleibt erlaubt (validiert); der Runtime-Aufruf nutzt die Direktkette nicht.",
          "(allow file-read* (literal \"" <> Path.join([shims_root, "pi"]) <> "\"))",
          "(allow file-read* (literal \"" <> Path.join([shims_root, "node"]) <> "\"))",
          "(allow process-exec (literal \"" <> Path.join([shims_root, "pi"]) <> "\"))",
          "(allow process-exec* (literal \"" <> Path.join([shims_root, "pi"]) <> "\"))",
          "(allow process-exec (literal \"" <> Path.join([shims_root, "node"]) <> "\"))",
          "(allow process-exec* (literal \"" <> Path.join([shims_root, "node"]) <> "\"))",
          "(allow file-read* (subpath \"" <> installs_root <> "\"))",
          "(allow file-read-metadata (subpath \"" <> installs_root <> "\"))",
          "(allow file-read* (subpath \"" <> shims_root <> "\"))",
          "(allow file-read-metadata (subpath \"" <> shims_root <> "\"))",
          "(allow file-read* (subpath \"" <> plugins_root <> "\"))",
          "(allow file-read-metadata (subpath \"" <> plugins_root <> "\"))",
          "; asdf-Go-Runtime CPU-Feature-Proben (Probe-Evidenz 10:52:46/56 UTC)",
          "(allow sysctl-read (sysctl-name \"hw.optional.armv8_1_atomics\"))",
          "(allow sysctl-read (sysctl-name \"hw.optional.armv8_crc32\"))",
          "(allow sysctl-read (sysctl-name \"hw.optional.arm.FEAT_DIT\"))",
          "(allow sysctl-read (sysctl-name \"hw.optional.arm.FEAT_SB\"))",
          "; asdf-Start (Probe-Evidenz 10:41:13 UTC, pid 50429)",
          "(allow sysctl-read (sysctl-name \"kern.bootargs\"))",
          "(allow sysctl-read (sysctl-name \"kern.osvariant_status\"))",
          "(allow sysctl-read (sysctl-name \"hw.ephemeral_storage\"))",
          "(allow sysctl-read (sysctl-name \"hw.pagesize_compat\"))"
        ],
        asdf_exec_rules()
      )
    else
      []
    end
  end

  # asdf-Binary: zur Generierungszeit entdeckt (find_executable) — keine
  # hartkodierten Systempfade im Projekt (Portabilitaets-Regel). Zwei Formen
  # wie in der Probe-Evidenz: die PATH-Form (Hop) und der Realpath.
  defp asdf_exec_rules do
    case System.find_executable("asdf") do
      nil ->
        []

      asdf_path ->
        asdf_path
        |> path_forms()
        |> Enum.flat_map(&asdf_exec_literals/1)
    end
  end

  # Beide Pfadformen: die PATH-Form, wie der Aufrufer sie nutzt, plus der
  # kernel-kanonische Realpath (Symlink-Form matcht nicht — Pfadform-Cave
  # Phase 1). Dedupliziert, wenn der PATH-Eintrag bereits der Realpath ist.
  defp path_forms(path), do: Enum.uniq([Config.canonical(path), path])

  defp asdf_exec_literals(bin) do
    [
      "(allow process-exec (literal \"" <> bin <> "\"))",
      "(allow file-read* (literal \"" <> bin <> "\"))"
    ]
  end

  # Metadaten-Pfad(e) der asdf-Binary: entdeckt statt hartkodiert.
  defp asdf_binary_paths do
    case System.find_executable("asdf") do
      nil -> []
      path -> [Config.canonical(path)]
    end
  end

  defp node_boot_rules(pi_pkg, node_modules_root, user_home) do
    Kernel.++(
      [
        "; node-Runtime (Probe-Evidenz: Sandbox-Direktaufruf; os-Builtin-Assert rc134)",
        "(allow sysctl-read (sysctl-name \"hw.optional.armv8_2_sha512\"))",
        "(allow sysctl-read (sysctl-name \"hw.optional.armv8_2_sha3\"))",
        "(allow mach-lookup (global-name \"com.apple.system.opendirectoryd.libinfo\"))",
        "(allow mach-lookup (global-name \"com.apple.system.notification_center\"))",
        "(allow ipc-posix-shm (ipc-posix-name \"apple.shm.notification_center\"))",
        "(allow file-read-metadata (literal \"/etc\"))",
        "(allow sysctl-read (sysctl-name \"kern.osrelease\"))",
        "(allow sysctl-read (sysctl-name \"hw.ncpu\"))",
        "; libuv-Limits (Probe-Evidenz: kern.maxfilesperproc, diag-G1-pi)",
        "(allow sysctl-read (sysctl-name \"kern.maxfilesperproc\"))",
        "(allow sysctl-read (sysctl-name \"net.routetable.0.0.3.0\"))",
        "(allow mach-lookup (global-name \"com.apple.CoreServices.coreservicesd\"))",
        "; uname(2)-Rueckgrat-Felder (Evidenz 10:51:07 UTC)",
        "(allow sysctl-read (sysctl-name \"kern.ostype\"))",
        "(allow sysctl-read (sysctl-name \"kern.hostname\"))",
        "(allow sysctl-read (sysctl-name \"kern.version\"))",
        "(allow sysctl-read (sysctl-name \"hw.machine\"))",
        "(allow sysctl-read (sysctl-name \"machdep.cpu.brand_string\"))",
        "(allow file-read-data (literal \"/dev/autofs_nowait\"))",
        "(allow file-read-data (literal \"" <>
          Path.join([user_home, ".CFUserTextEncoding"]) <> "\"))",
        "(allow network-outbound (remote unix-socket (literal \"/private/var/run/syslog\")))",
        "; ICU/tz-Zugriffe (Evidenz 10:37:40 UTC)",
        "(allow file-read* (subpath \"/private/var/db/timezone\"))",
        "(allow file-read* (subpath \"/usr/share/icu\"))"
      ],
      pi_pkg_reads(pi_pkg, node_modules_root)
    )
  end

  defp pi_pkg_reads(pi_pkg, node_modules_root) do
    [
      "; pi-Paket-Installations-Subtree (self-contained Bundle + Runtime-Daten)",
      "(allow file-read* (subpath \"" <> pi_pkg <> "\"))",
      "; node-module-resolution geht exports/symlinks im Install-Subtree nach",
      "(allow file-read* (subpath \"" <> node_modules_root <> "\"))"
    ]
  end

  ## ---------------------------------------------------------------- Scopes

  defp scope_rules(%Config{} = cfg, scratch) do
    [
      "; isoliertes HOME (agentDir ~/.pi/agent, Sessions) + Scratch-Write-Scope",
      "(allow file-read* (subpath \"" <> cfg.pi_home <> "\"))",
      "(allow file-write* (subpath \"" <> cfg.pi_home <> "\"))",
      "; Scratch: lesend (Tool-Ergebnis) und schreibend (Run-Ziel)",
      "(allow file-read* (subpath \"" <> scratch <> "\"))",
      "(allow file-write* (subpath \"" <> scratch <> "\"))",
      "; stdio/dev-Schreibscope (Phase-1-Ansatz)",
      "(allow file-write* (literal \"/dev/null\"))",
      "; /private/var/select/sh: npm-Link-Aufloeser (Phase-1-Evidenz)",
      "(allow file-read-metadata (literal \"/private/var/select\"))",
      "(allow file-read* (literal \"/private/var/select/sh\"))"
    ]
  end

  ## ---------------------------------------------------------------- Helfer

  # Gepinnte Kette: <home>/.asdf/installs/nodejs/<v>/bin/node
  # (fuenfmal dirname -> <home>/.asdf). Deterministische Formpruefung statt
  # Host-File.exists?: Nicht-asdf-Konfigurationen bekommen keine asdf-
  # Regelschicht, asdf-Konfigurationen immer — egal, wer gerade generiert.
  # Fuer nicht-asdf-Knoten ist der wahre user_home die richtige Referenz
  # (die .CFUserTextEncoding-Zeile zeigt dorthin), nicht ein Pfad-Abschnitt
  # aus der node-Herkunft.
  defp pinned_chain_roots(node_bin) do
    asdf_root =
      node_bin
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()

    if Path.basename(asdf_root) == ".asdf" do
      {Path.dirname(asdf_root), asdf_root}
    else
      {System.user_home!(), nil}
    end
  end

  @doc "pi-Bundle-Paket aus dem cli.js-Pfad (dist/bundle abschneiden)."
  @spec cli_js_pkg(String.t()) :: String.t()
  def cli_js_pkg(cli_js) do
    cli_js
    |> Path.dirname()
    |> Path.dirname()
    |> Path.dirname()
  end
end
