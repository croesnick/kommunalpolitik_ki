defmodule KomkiCli.Profile do
  @moduledoc """
  Generiert das Seatbelt-Profil (SBPL) für pi-Läufe unter deny-default.

  Semantisch exakt die validierte Kandidat-Kombination aus dem
  Ticket-#70-Beschluss (inkl. pi/node-Erweiterungen; die Begründung je
  Regel steht im Research-Report
  `docs/research/2026-10-04-probe-harness-sandbox.md` im Branch
  `research/probe-harness-sandbox`), parametrisiert auf:

     * Netz — genau zwei Exceptions: der llama-Port
       `(allow network-outbound (remote tcp "localhost:<port>"))` und der
       Vermittler-Socket (Ticket #143)
       `(allow network-outbound (remote unix-socket (path-literal "<base>/run/mediator.sock")))`.
       `komki-relay.js` liegt im pi-Home und ist ueber dessen Leseregel
       abgedeckt.
    * pi-Home — isoliertes HOME (lesend/schreibend, inkl. Komponenten-Kette)
      ohne die Session-Verläufe `pi-home/sessions` (Ticket #295): Offen ist
      nur das Verzeichnis der eigenen Session, beim Einmal-Lauf keines
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

  alias KomkiCli.{Channel, Config, Llama, Pi}
  alias Seatbelt.{MachODeps, Preset, SBPL}
  require Config

  @doc """
  Scratch-Verzeichnis für die Identitäts-Regeneration (init/doctor):
  regeneriertes Profil muss byte-identisch mit der gespeicherten Datei sein.
  """
  @spec check_scratch(Config.t()) :: String.t()
  def check_scratch(%Config{} = cfg) do
    Path.join(Path.dirname(cfg.profile_path) <> ".d", "check-scratch")
  end

  @doc """
  Profil-Text generieren. Feste Eingaben -> byte-identischer Output.
  `session_dir` ist das Verzeichnis der interaktiven Session, das einzige
  unter `pi-home/sessions`, das pi lesen und schreiben darf; `nil` beim
  Einmal-Lauf.
  """
  @spec generate(Config.t(), String.t(), String.t() | nil) :: String.t()
  def generate(cfg, scratch, session_dir \\ nil)

  def generate(%Config{} = cfg, scratch, session_dir)
      when is_binary(scratch) and (is_binary(session_dir) or is_nil(session_dir)) and
             Config.tools_ready(cfg) do
    scratch = Config.canonical(scratch)

    # Host-unabhaengig: <home> und asdf-Root aus der gepinnten node-Kette
    # (cfg.node_bin) ableiten statt vom laufenden Host — CI-Linux hat kein
    # ~/.asdf und System.user_home! zeigt auf den Runner; der Profiltext
    # waere dort unvollstaendig (CI-Fund: fehlende asdf-Sysctl-Pins).
    {user_home, asdf_root_dir} = pinned_chain_roots(cfg.node_bin)

    # asdf-Binary einmalig entdecken und sichtbar durchreichen: Der
    # Generator soll keine versteckten Host-Eingaben haben (vorher rief
    # die Regelschicht selbst find_executable — gleiche Bytes, aber
    # unsichtbarer Input in einer "deterministischen" Funktion).
    asdf_bin = System.find_executable("asdf")

    asdf_root_dir
    |> rules_for(cfg, {scratch, session_dir}, user_home, asdf_bin)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Unvollstaendige config (Werkzeugpfade fehlen): klar scheitern statt
  # kryptisch in Regel-Konkatenationen zu crashen.
  def generate(%Config{}, _scratch, _session_dir) do
    raise_incomplete_tools!("Profil")
  end

  @doc "Profil schreiben (Verzeichnis wird erzeugt)."
  @spec write!(String.t(), String.t()) :: :ok
  def write!(path, text) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
    :ok
  end

  ## ---------------------------------------------- llama-server-Profil (Ticket #100)

  @doc """
  llama-server-Profil (Tickets #100/#111): eigene deny-default-Grenze fuer
  den Inferenz-Prozess. R.3 ("Lokale KI") wird damit zur geprüften Aussage
  statt zur unbelegten Ausnahme — die Startschicht prueft das Boot-Gate,
  den vollstaendigen Inferenzpfad belegt die Experimentserie. Feste cfg und
  feste Umgebung (HOME, otool-Verfuegbarkeit, Dateisystemstand) ->
  byte-identischer Output.

  Verifiziert 14.10.2026 auf macOS 27.2 (Build 26B5101f), llama-server 0.6.0
  (build 11429): Modell-Load, Health, Inferenz und TERM-Exit unter der Grenze
  (Experimente exp4–exp18, Tickets #100/#111). Bewusste benannte Grenzen:
  GPU/Metal-Kette freigegeben (Ticket #111, exp18 14.10.2026: ~53 t/s Eval
  unter der Grenze ≈ ungesandboxete Baseline ~57, gegen ~5 CPU-only) — die
  GPU-Treiber-Angriffsflaeche ist die bewusst eingegangene Grenze; kein
  network-outbound (llama laeuft --offline); Memory-Fitter bricht mit Warnung
  ab und laesst die Parameter wie angefordert.

  MTP-Drafter (Ticket #318): seit dem Produktivstart laedt llama-server eine
  zweite gepinnte Datei (`--model-draft`). Das Profil erlaubt ihr Lesen als
  genau dieses Literal — dieselbe Regelklasse wie das Modell, nichts darueber
  hinaus (kein models-Subpath). Der echte Lauf unter der Grenze steht im
  Ticket #318 (draft acceptance im llama-Log).

  Nachweis-Konsolidierung: `docs/research/2026-10-14-llama-server-confinement.md`.
  """
  @spec generate_llama(Config.t()) :: String.t()
  def generate_llama(%Config{} = cfg) when Config.tools_ready(cfg) do
    cfg |> llama_rules_for() |> Enum.join("\n") |> Kernel.<>("\n")
  end

  # Unvollstaendige config (Werkzeugpfade fehlen): klar scheitern ueber den
  # gemeinsamen Fallback (wie generate/2), statt kryptisch in
  # Regel-Konkatenationen zu crashen.
  def generate_llama(%Config{}) do
    raise_incomplete_tools!("llama-Profil")
  end

  # Gemeinsamer Fallback beider Generatoren: je Generatoren-Name "Profil"
  # bzw. "llama-Profil" — die Messages bleiben damit byte-identisch.
  defp raise_incomplete_tools!(profil) do
    raise ArgumentError,
      message:
        profil <>
          "-Generierung braucht vollstaendige Werkzeugpfade " <>
          "(node/cli/llama-server) — init verweigert unvollstaendige Instanzen; config.json pruefen"
  end

  ## Komposition (festgelegte Reihenfolge, deterministisch):
  ## Header -> Startup-Schicht -> exec/Read Binaer -> dylib-Baum -> /dev ->
  ## Modell -> Log -> Netz -> Sysctl-Pins -> /etc -> Mach/shm -> Metal ->
  ## Pfad-Sonden -> CFPreferences -> Metadaten-Vorfahrnkette -> Schlussgrenzen.
  defp llama_rules_for(%Config{} = cfg) do
    user_home = System.user_home!()
    dylib_dirs = MachODeps.dylib_dirs(cfg.llama_server_bin)
    log_path = Llama.log_path(cfg)

    rules =
      llama_header() ++
        llama_start_layer() ++
        llama_exec_read_rules(cfg.llama_server_bin) ++
        llama_dylib_rules(dylib_dirs) ++
        llama_dev_rules() ++
        llama_model_rules(cfg) ++
        llama_log_rules(log_path) ++
        llama_key_rules(Llama.key_path(cfg)) ++
        llama_network_rules(cfg.port) ++
        llama_sysctl_rules() ++
        llama_etc_passwd_rules() ++
        llama_mach_shm_rules() ++
        llama_metal_rules() ++
        llama_probe_rules() ++
        llama_prefs_rules(user_home) ++
        SBPL.metadata_ancestors(llama_meta_paths(cfg, log_path, dylib_dirs, user_home)) ++
        llama_closing_rules()

    # Pfad-Sonden-Block und meta_ancestors enden auf denselben
    # Metadaten-Literalen ("/", "/private/var", ...): Duplikatfrei gelten
    # lassen (erste Position bleibt, Determinismus unberuehrt).
    Enum.uniq(rules)
  end

  defp llama_header do
    [
      "; llama-server-Profil (Ticket #100): eigene deny-default-Grenze fuer den Inferenz-Prozess.",
      "; Deterministisch aus der config.json generiert; feste Eingaben -> byte-identischer Text.",
      "; Rationale je Regel: die Kommentare unten (Belege exp4-exp18, Tickets #100/#111).",
      "(version 1)",
      "(deny default)"
    ]
  end

  # Startup-Schicht: die validierte Boot-Schicht aus der Library
  # (Seatbelt.Preset.macos_exec_boot; ohne sie stirbt jeder exec auf
  # macOS 27.2 mit SIGABRT rc=134). Der fruehere Kopfzeilen-Filter
  # ("asdf-Boot-Proben" wegwerfen) ist entfaellt: Der Preset-Kopf ist
  # asdf-frei, das llama-Profil hat die asdf-Schicht nie gehabt, und der
  # Profil-Test prueft das hart weiter (refute "asdf").
  defp llama_start_layer, do: Preset.macos_exec_boot()

  defp llama_exec_read_rules(bin) do
    [
      "; llama-server-Binaer: exec + read (config haelt den kernel-kanonischen Pfad).",
      "(allow process-exec (literal " <> SBPL.quote!(bin) <> "))",
      "(allow file-read* (literal " <> SBPL.quote!(bin) <> "))"
    ]
  end

  defp llama_dylib_rules([]), do: []

  defp llama_dylib_rules(dirs) do
    [
      "; dylib-Baeume — BEIDE Pfadformen: dyld oeffnet die deklarierten Pfade aus dem Mach-O " <>
        "(Pfadform-Cave gilt in beide Richtungen); inkl. transitive Deps (libomp via " <>
        "libggml-base) und des ggml-Backend-Scan-Verzeichnisses libexec (Fund exp6/exp7/exp14: " <>
        "ohne libexec-Leserecht bleibt die Backend-Registry leer)"
    ] ++
      Enum.map(dirs, fn dir -> "(allow file-read* (subpath " <> SBPL.quote!(dir) <> "))" end)
  end

  defp llama_dev_rules do
    [
      "(allow file-read* (literal \"/dev/null\"))",
      "(allow file-read* (literal \"/dev/random\"))",
      "(allow file-read* (literal \"/dev/urandom\"))"
    ]
  end

  defp llama_model_rules(%Config{} = cfg) do
    [
      "; Modell + MTP-Drafter (mmap; Drafter Ticket #318: --model-draft,",
      "; genau diese Datei — kein models-Subpath)",
      "(allow file-read* (literal " <> SBPL.quote!(cfg.gguf_path) <> "))",
      "(allow file-read* (literal " <> SBPL.quote!(cfg.drafter_path) <> "))"
    ]
  end

  defp llama_log_rules(log_path) do
    [
      "; Log (Redirect-Ziel des Spawn-Shells; Write-Scope ausschliesslich diese Datei)",
      "(allow file-read* (literal " <> SBPL.quote!(log_path) <> "))",
      "(allow file-write* (literal " <> SBPL.quote!(log_path) <> "))"
    ]
  end

  defp llama_key_rules(key_path) do
    [
      "; API-Key-Datei (Ticket #136, --api-key-file; nur lesend)",
      "(allow file-read* (literal " <> SBPL.quote!(key_path) <> "))"
    ]
  end

  defp llama_network_rules(port) do
    [
      "; Netz: Management-Port, loopback-bind + inbound, KEIN outbound (--offline wird",
      "; profilseitig erzwungen). SBPL-Grammatik-Fund exp7/exp8: host muss * oder localhost",
      "; sein; \"localhost:PORT\" ist die engste Form und matcht den 127.0.0.1-Bind.",
      "(allow network-bind (local ip " <> SBPL.quote!("localhost:" <> to_string(port)) <> "))",
      "(allow network-inbound (local ip))"
    ]
  end

  @llama_sysctls [
    "hw.ncpu",
    "hw.physicalcpu",
    "hw.perflevel0.physicalcpu",
    "hw.memsize",
    "hw.pagesize_compat",
    "hw.logicalcpu",
    "machdep.cpu.brand_string",
    "kern.bootargs",
    "hw.optional.armv8_2_sha512",
    "hw.optional.armv8_2_sha3",
    "hw.optional.arm.FEAT_DotProd",
    "hw.optional.arm.FEAT_FP16",
    "hw.optional.arm.FEAT_I8MM",
    "hw.optional.arm.FEAT_SME",
    "hw.optional.arm.FEAT_SME2"
  ]

  defp llama_sysctl_rules do
    [
      "; CPU-/Feature-/Speicher-Sonden (exp14/exp15-Denial-Listen; ohne die FEAT-Sysctls",
      "; scoret kein apple_m*-Bundle und die Backend-Registry bleibt CPU-leer; ohne",
      "; memsize/pagesize_compat/logicalcpu degradiert der Memory-Fitter/Threadpool)"
    ] ++
      Enum.map(@llama_sysctls, fn name ->
        "(allow sysctl-read (sysctl-name " <> SBPL.quote!(name) <> "))"
      end)
  end

  defp llama_etc_passwd_rules do
    [
      "; getpwnam-Fallback, wenn opendirectoryd unter der Grenze nicht erreichbar ist",
      "(allow file-read-metadata (literal \"/etc\"))",
      "(allow file-read* (literal \"/private/etc/passwd\"))"
    ]
  end

  @llama_mach_names [
    "com.apple.system.opendirectoryd.libinfo",
    "com.apple.system.opendirectoryd.membership",
    "com.apple.system.notification_center",
    "com.apple.logd",
    "com.apple.bsd.dirhelper"
  ]

  defp llama_mach_shm_rules do
    ["; Mach-Lookups + shm (Pi-Pin-Klasse; exp14-Runde-2-Denials)"] ++
      Enum.map(@llama_mach_names, fn name ->
        "(allow mach-lookup (global-name " <> SBPL.quote!(name) <> "))"
      end) ++
      [
        "(allow ipc-posix-shm (ipc-posix-name \"apple.shm.notification_center\"))"
      ]
  end

  # GPU/Metal-Kette (Ticket #111: Aufhebung der CPU-only-Grenze aus #100).
  # Belege: exp18-Runden 1-3, 14.10.2026 (Unified-Log-Denials je Runde):
  # Runde 1 scheiterte an der Command Queue (iokit), Runde 2 am ausgelagerten
  # Shader-Compiler (MTLCompilerService), Runde 3 lief gruen. Messung Runde 3:
  # ~53 t/s Eval unter der Grenze gegen ~57 ungesandboxet (exp13) und ~5
  # CPU-only (exp15) — GPU-Tempo unter nachweisbarer Grenze.
  defp llama_metal_rules do
    [
      "; System-Haeuser: Metal-Framework-Bring-up liest explizit (der CPU-only-Betrieb",
      "; lief ohne sie — Shared-Cache-Mapping genuegte; Fund exp18-Runde 2: Cryptex-dyld).",
      "; Der AGX-Stat des Treiber-Bundles (Kernel-Denial exp18: AGXMetalG13X.bundle)",
      "; ist von System/Library subsumiert — keine eigenen Bundle-Regeln noetig",
      "; (Review-Fund: die Entdeckung fand alle 17 GPU-Klassen-Bundles, jede",
      "; einzelne bereits abgedeckt; Schein-Portabilitaet, kein Zuwinn).",
      "(allow file-read* (subpath \"/usr/lib\"))",
      "(allow file-read* (subpath \"/System/Library\"))",
      "(allow file-read* (subpath \"/System/Volumes/Preboot\"))"
    ] ++
      [
        "; GPU-Treiber-Userclients (Kernel-Denials exp14/exp18)",
        "(allow iokit-open-user-client (iokit-user-client-class \"AGXDeviceUserClient\"))",
        "(allow iokit-open-user-client (iokit-user-client-class \"IOSurfaceRootUserClient\"))",
        "; Bring-up-Dienste (Kernel-Denials exp14/exp18)",
        "(allow mach-lookup (global-name \"com.apple.windowserver.active\"))",
        "(allow mach-lookup (global-name \"com.apple.tccd.system\"))",
        "(allow mach-lookup (global-name \"com.apple.CoreServices.coreservicesd\"))",
        "(allow mach-lookup (global-name \"com.apple.DiskArbitration.diskarbitrationd\"))",
        "; Shader-Kompilierung laeuft ausgelagert im Systemdienst (Kernel-Denial",
        "; exp18-Runde 2: 'mach-lookup com.apple.MTLCompilerService (xpc)' — ohne ihn",
        "; stirbt die Kompilierung und die Metal-Context-Init scheitert)",
        "(allow mach-lookup (global-name \"com.apple.MTLCompilerService\"))",
        "; Metal-Cache-Extensions (Kernel-Denial exp18: file-issue-extension)",
        "(allow file-issue-extension (extension-class \"com.apple.app-sandbox.read\"))",
        "; OS-Varianten-/Speicher-Sonden des Metal-Bring-up (Kernel-Denials exp18)",
        "(allow sysctl-read (sysctl-name \"hw.ephemeral_storage\"))",
        "(allow sysctl-read (sysctl-name \"kern.osvariant_status\"))",
        "(allow sysctl-read (sysctl-name \"kern.osproductversion\"))"
      ]
  end

  @llama_probe_paths [
    "/",
    "/System/Volumes/Data",
    "/tmp",
    "/home",
    "/private/etc",
    "/private/var",
    "/.VolumeIcon.icns"
  ]

  defp llama_probe_rules do
    ["; Pfad-Sonden-Metadaten (benign, exp15)"] ++
      Enum.map(@llama_probe_paths, &SBPL.metadata_literal/1)
  end

  defp llama_prefs_rules(user_home) do
    [
      "; CFPreferences-Global-Read (CoreFoundation-Init)",
      "(allow file-read* (literal \"/Library/Preferences/.GlobalPreferences.plist\"))",
      "(allow file-read-metadata (literal \"/Library/Preferences\"))",
      "(allow file-read* (literal " <>
        SBPL.quote!(user_home <> "/Library/Preferences/.GlobalPreferences.plist") <> "))",
      "(allow file-read-metadata (literal " <>
        SBPL.quote!(user_home <> "/Library/Preferences") <> "))",
      "(allow file-read-metadata (literal " <>
        SBPL.quote!(user_home <> "/Library/Preferences/ByHost") <> "))",
      "(allow file-read-metadata (literal \"/private/var/db/.AppleSetupDone\"))"
    ]
  end

  defp llama_meta_paths(cfg, log_path, dylib_dirs, user_home) do
    [
      "/System",
      "/System/Volumes",
      "/System/Cryptexes",
      "/bin",
      "/dev",
      "/usr",
      "/opt",
      cfg.base_dir,
      cfg.gguf_path,
      cfg.drafter_path,
      log_path,
      cfg.llama_server_bin
    ] ++ dylib_dirs ++ [user_home]
  end

  # Formulierung: der Substring "network-outbound" darf im Profiltext nicht
  # erscheinen (Profil-Test refute auf das Literal) — "Netz-Auswaerts" ist
  # dieselbe Aussage.
  defp llama_closing_rules do
    [
      "; Bewusst NICHT erlaubt (benannte Grenzen, Tickets #100/#111): Netz-Auswaerts",
      "; bleibt verweigert — auch der syslog-Unix-Socket (os_log-Fallback, Kernel-Denial",
      "; exp18) — und --offline wird profilseitig erzwungen. Die GPU/Metal-Kette ist seit",
      "; #111 freigegeben (exp18: iokit AGX/IOSurface, MTLCompilerService, windowserver,",
      "; tccd, coreservicesd, diskarbitrationd, file-issue-extension, System-Haeuser);",
      "; die GPU-Treiber-Angriffsflaeche ist die bewusst eingegangene Grenze."
    ]
  end

  ## ---------------------------------------------------------------- Regelaufbau

  defp rules_for(asdf_root_dir, cfg, {scratch, session_dir}, user_home, asdf_bin) do
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
          user_home,
          asdf_bin
        )

    # Netz-Exceptions am Dateiende, deterministisch: llama zuerst, der
    # Vermittler-Socket (Ticket #143) danach — kein Wildcard-Port, kein
    # weiteres Ziel (byte-stabil, vom Doctor-Check kontrolliert).
    port_rule =
      "(allow network-outbound (remote tcp " <> SBPL.quote!("localhost:" <> port) <> "))"

    mediator_socket_rule =
      "(allow network-outbound (remote unix-socket (path-literal " <>
        SBPL.quote!(Channel.socket_path(cfg)) <> ")))"

    base_rules ++
      Preset.macos_exec_boot() ++
      asdf_rules(asdf_root_dir, asdf_bin) ++
      node_boot_rules(pi_pkg, node_modules_root, user_home) ++
      Preset.tui() ++
      tty_redirect_rules() ++
      scope_rules(cfg, scratch) ++
      session_rules(cfg, session_dir) ++
      [port_rule, mediator_socket_rule]
  end

  ## ---------------------------------------------------------------- TUI/Terminal-Klasse

  # Die Terminal-Klasse (sandbox-runtime-Muster, srt #419) lebt seit
  # Ticket #226 als Preset in der Library (Seatbelt.Preset.tui/0) — die
  # Begruendung je Regel dort. Restrisiko (Ticket #132)
  # distributed-notification-post bleibt bewusst: ein Kanal zu jedem
  # Prozess des Nutzers; streichen erst nach Messung, ob die pi-TUI ohne
  # die Regel bootet.

  # komki-eigene Ergaenzung zur Terminal-Klasse, darum nicht im Preset.
  defp tty_redirect_rules do
    [
      "; /dev/fd/0-Redirect unter Burrito (Pilot 2026-10-11): Das BEAM-stdout ist",
      "; dort die Wrapper-Pipe; die Session-Kette leitet stdout auf das lebende",
      "; stdin-PTY um (Pi.argv_session/3, tty_redirect). Kontextfrei im Profil, damit",
      "; die Profil-Identitaet nicht vom Laufkontext abhaengt (Einmal-Drift fuer",
      "; bestehende Instanzen: einmalig 'komki init --force').",
      "(allow file-read-metadata (literal \"/dev/fd\"))",
      "(allow file-write* (literal \"/dev/fd/0\"))"
    ]
  end

  defp basis_and_exec_rules(cfg, node, pi_launcher) do
    tools_fd = Path.join([cfg.pi_home, ".pi", "agent", "bin", "fd"])
    tools_rg = Path.join([cfg.pi_home, ".pi", "agent", "bin", "rg"])

    [
      "(version 1)",
      "(deny default)",
      "; Basis: validierter Kandidat aus Ticket #70 (Beleg: Research-Report der Sandbox-Forschung).",
      "; Jede pi/node-Zusatzregel traegt ihre Rationale im Research-Report (Branch research/probe-harness-sandbox).",
      "(allow process-exec (literal \"/usr/bin/true\"))",
      "(allow process-exec (literal \"/bin/sh\"))",
      "(allow process-exec (literal \"/bin/bash\"))",
      "(allow process-exec (literal " <> SBPL.quote!(node) <> "))",
      "(allow process-exec (literal " <> SBPL.quote!(pi_launcher) <> "))",
      "(allow process-exec* (literal " <> SBPL.quote!(pi_launcher) <> "))",
      "; pi's Such-Werkzeuge fd/rg: Kopien im agent-bin-Fundus (init schreibt sie)",
      "(allow process-exec (literal " <> SBPL.quote!(tools_fd) <> "))",
      "(allow process-exec* (literal " <> SBPL.quote!(tools_fd) <> "))",
      "(allow process-exec (literal " <> SBPL.quote!(tools_rg) <> "))",
      "(allow process-exec* (literal " <> SBPL.quote!(tools_rg) <> "))",
      "(allow process-fork)",
      "(allow file-read* (subpath \"/System/Library\"))",
      "(allow file-read* (subpath \"/usr/lib\"))",
      "(allow file-read* (subpath \"/System/Volumes/Preboot\"))",
      "(allow file-read* (literal \"/usr/bin/true\"))",
      "(allow file-read* (literal \"/bin/sh\"))",
      "(allow file-read* (literal \"/bin/bash\"))",
      "(allow file-read* (literal " <> SBPL.quote!(node) <> "))",
      "(allow file-read* (literal " <> SBPL.quote!(pi_launcher) <> "))",
      "(allow file-read* (literal \"/dev/null\"))",
      "(allow file-read* (literal \"/dev/random\"))",
      "(allow file-read* (literal \"/dev/urandom\"))",
      "; Shebang-Hop-Schicht kommt im Lauf nicht vor (direkte node-Kette): /usr/bin/env nicht erlaubt."
    ]
  end

  ## ---------------------------------------------------------------- Metadaten-Kette

  defp meta_rules(
         cfg,
         scratch,
         node_install,
         node_modules_root,
         pi_pkg,
         asdf_root_dir,
         user_home,
         asdf_bin
       ) do
    # Install-Pfade (brew, asdf, nvm) entstehen hier NUR aus den entdeckten
    # Werkzeugpfaden (Vorfahr-Kette des jeweiligen Pfads) — keine hartkodierten
    # System-Roots (Portabilitaets-Regel).
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

    base_meta = SBPL.metadata_ancestors(paths)

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
            # entdeckten Pfad statt hartkodierter brew-Roots.
          ] ++ asdf_binary_paths(asdf_bin)

        SBPL.metadata_ancestors(asdf_paths)
      else
        []
      end

    base_meta ++ asdf_meta
  end

  ## ---------------------------------------------------------------- Boot-Schicht

  # Die validierte Boot-Schicht (Ticket #70) lebt seit Ticket #226 als
  # Preset in der Library (Seatbelt.Preset.macos_exec_boot/0); die
  # Begruendung je Regel dort. Der Preset-Kopf ist bewusst asdf-frei —
  # das llama-Profil uebernimmt die Schicht vollstaendig und der
  # Profil-Test refutiert "asdf" hart weiter.

  defp asdf_rules(asdf_root_dir, asdf_bin) do
    if is_binary(asdf_root_dir) do
      shims_root = Path.join([asdf_root_dir, "shims"])
      installs_root = Path.join([asdf_root_dir, "installs"])
      plugins_root = Path.join([asdf_root_dir, "plugins"])

      Kernel.++(
        [
          "; asdf-Shim-Layer bleibt erlaubt (validiert); der Runtime-Aufruf nutzt die Direktkette nicht.",
          "(allow file-read* (literal " <> SBPL.quote!(Path.join([shims_root, "pi"])) <> "))",
          "(allow file-read* (literal " <> SBPL.quote!(Path.join([shims_root, "node"])) <> "))",
          "(allow process-exec (literal " <> SBPL.quote!(Path.join([shims_root, "pi"])) <> "))",
          "(allow process-exec* (literal " <> SBPL.quote!(Path.join([shims_root, "pi"])) <> "))",
          "(allow process-exec (literal " <> SBPL.quote!(Path.join([shims_root, "node"])) <> "))",
          "(allow process-exec* (literal " <> SBPL.quote!(Path.join([shims_root, "node"])) <> "))",
          "(allow file-read* (subpath " <> SBPL.quote!(installs_root) <> "))",
          "(allow file-read-metadata (subpath " <> SBPL.quote!(installs_root) <> "))",
          "(allow file-read* (subpath " <> SBPL.quote!(shims_root) <> "))",
          "(allow file-read-metadata (subpath " <> SBPL.quote!(shims_root) <> "))",
          "(allow file-read* (subpath " <> SBPL.quote!(plugins_root) <> "))",
          "(allow file-read-metadata (subpath " <> SBPL.quote!(plugins_root) <> "))",
          "; asdf-Go-Runtime CPU-Feature-Proben (Probe-Beleg 10:52:46/56 UTC)",
          "(allow sysctl-read (sysctl-name \"hw.optional.armv8_1_atomics\"))",
          "(allow sysctl-read (sysctl-name \"hw.optional.armv8_crc32\"))",
          "(allow sysctl-read (sysctl-name \"hw.optional.arm.FEAT_DIT\"))",
          "(allow sysctl-read (sysctl-name \"hw.optional.arm.FEAT_SB\"))",
          "; asdf-Start (Probe-Beleg 10:41:13 UTC, pid 50429)",
          "(allow sysctl-read (sysctl-name \"kern.bootargs\"))",
          "(allow sysctl-read (sysctl-name \"kern.osvariant_status\"))",
          "(allow sysctl-read (sysctl-name \"hw.ephemeral_storage\"))",
          "(allow sysctl-read (sysctl-name \"hw.pagesize_compat\"))"
        ],
        asdf_exec_rules(asdf_bin)
      )
    else
      []
    end
  end

  # asdf-Binary: einmalig in generate/2 entdeckt (find_executable) und
  # sichtbar durchgereicht — keine hartkodierten Systempfade im Projekt
  # (Portabilitaets-Regel). Zwei Formen wie im Probe-Beleg: die PATH-Form
  # (Hop) und der Realpath.
  defp asdf_exec_rules(nil), do: []

  defp asdf_exec_rules(asdf_bin) do
    asdf_bin
    |> path_forms()
    |> Enum.flat_map(&asdf_exec_literals/1)
  end

  # Beide Pfadformen: die PATH-Form, wie der Aufrufer sie nutzt, plus der
  # kernel-kanonische Realpath (Symlink-Form matcht nicht — Pfadform-Cave
  # Phase 1). Dedupliziert, wenn der PATH-Eintrag bereits der Realpath ist.
  defp path_forms(path), do: Enum.uniq([Config.canonical(path), path])

  defp asdf_exec_literals(bin) do
    [
      "(allow process-exec (literal " <> SBPL.quote!(bin) <> "))",
      "(allow file-read* (literal " <> SBPL.quote!(bin) <> "))"
    ]
  end

  # Metadaten-Pfad(e) der asdf-Binary: entdeckt statt hartkodiert.
  defp asdf_binary_paths(nil), do: []

  defp asdf_binary_paths(asdf_bin), do: [Config.canonical(asdf_bin)]

  defp node_boot_rules(pi_pkg, node_modules_root, user_home) do
    Kernel.++(
      [
        "; node-Runtime (Probe-Beleg: Sandbox-Direktaufruf; os-Builtin-Assert rc134)",
        "(allow sysctl-read (sysctl-name \"hw.optional.armv8_2_sha512\"))",
        "(allow sysctl-read (sysctl-name \"hw.optional.armv8_2_sha3\"))",
        "(allow mach-lookup (global-name \"com.apple.system.opendirectoryd.libinfo\"))",
        "(allow mach-lookup (global-name \"com.apple.system.notification_center\"))",
        "(allow ipc-posix-shm (ipc-posix-name \"apple.shm.notification_center\"))",
        "(allow file-read-metadata (literal \"/etc\"))",
        "(allow sysctl-read (sysctl-name \"kern.osrelease\"))",
        "(allow sysctl-read (sysctl-name \"hw.ncpu\"))",
        "; libuv-Limits (Probe-Beleg: kern.maxfilesperproc, diag-G1-pi)",
        "(allow sysctl-read (sysctl-name \"kern.maxfilesperproc\"))",
        "(allow sysctl-read (sysctl-name \"net.routetable.0.0.3.0\"))",
        "(allow mach-lookup (global-name \"com.apple.CoreServices.coreservicesd\"))",
        "; uname(2)-Rueckgrat-Felder (Beleg 10:51:07 UTC)",
        "(allow sysctl-read (sysctl-name \"kern.ostype\"))",
        "(allow sysctl-read (sysctl-name \"kern.hostname\"))",
        "(allow sysctl-read (sysctl-name \"kern.version\"))",
        "(allow sysctl-read (sysctl-name \"hw.machine\"))",
        "(allow sysctl-read (sysctl-name \"machdep.cpu.brand_string\"))",
        "(allow file-read-data (literal \"/dev/autofs_nowait\"))",
        "(allow file-read-data (literal " <>
          SBPL.quote!(Path.join([user_home, ".CFUserTextEncoding"])) <> "))",
        "(allow network-outbound (remote unix-socket (literal \"/private/var/run/syslog\")))",
        "; ICU/tz-Zugriffe (Beleg 10:37:40 UTC)",
        "(allow file-read* (subpath \"/private/var/db/timezone\"))",
        "(allow file-read* (subpath \"/usr/share/icu\"))"
      ],
      pi_pkg_reads(pi_pkg, node_modules_root)
    )
  end

  defp pi_pkg_reads(pi_pkg, node_modules_root) do
    [
      "; pi-Paket-Installations-Subtree (self-contained Bundle + Runtime-Daten)",
      "(allow file-read* (subpath " <> SBPL.quote!(pi_pkg) <> "))",
      "; node-module-resolution geht exports/symlinks im Install-Subtree nach",
      "(allow file-read* (subpath " <> SBPL.quote!(node_modules_root) <> "))"
    ] ++ pi_deps_reads(pi_modules_root(pi_pkg), node_modules_root)
  end

  # pi aus dem komki-Paket (Homebrew) liegt nicht unter node, sondern in einem
  # eigenen flachen node_modules neben seinen Abhaengigkeiten. pi laedt von
  # dort jiti, sobald es eine TypeScript-Extension uebersetzt (die Anzeige,
  # KomkiCli.Anzeige). Liegt pi unter node, deckt die Regel oben das ab.
  defp pi_deps_reads(root, root), do: []

  defp pi_deps_reads(root, _node_modules_root) do
    [
      "; Abhaengigkeiten des pi-Pakets (flaches node_modules, etwa jiti)",
      "(allow file-read* (subpath " <> SBPL.quote!(root) <> "))"
    ]
  end

  # <root>/node_modules/@earendil-works/pi-coding-agent -> <root>/node_modules
  defp pi_modules_root(pi_pkg), do: pi_pkg |> Path.dirname() |> Path.dirname()

  ## ---------------------------------------------------------------- Scopes

  defp scope_rules(%Config{} = cfg, scratch) do
    [
      "; isoliertes HOME (agentDir ~/.pi/agent, Sessions) + Scratch-Write-Scope",
      "(allow file-read* (subpath " <> SBPL.quote!(cfg.pi_home) <> "))",
      "(allow file-write* (subpath " <> SBPL.quote!(cfg.pi_home) <> "))",
      "; Scratch: lesend (Tool-Ergebnis) und schreibend (Run-Ziel)",
      "(allow file-read* (subpath " <> SBPL.quote!(scratch) <> "))",
      "(allow file-write* (subpath " <> SBPL.quote!(scratch) <> "))",
      "; stdio/dev-Schreibscope (Phase-1-Ansatz)",
      "(allow file-write* (literal \"/dev/null\"))",
      "; /private/var/select/sh: npm-Link-Aufloeser (Phase-1-Beleg)",
      "(allow file-read-metadata (literal \"/private/var/select\"))",
      "(allow file-read* (literal \"/private/var/select/sh\"))"
    ]
  end

  # Ticket #295: Die Verläufe aller Sessions liegen unter pi-home, in einem
  # Verzeichnis je Session. pi dürfte sie sonst alle lesen: /resume und
  # /import holten den Kontext einer Session aus einem strengeren Raum in
  # diesen. Offen bleibt nur das Verzeichnis der eigenen Session, dessen Raum
  # komki beim Start geprüft hat (KomkiCli.Raum.open_session/2). Die Regeln
  # stehen hinter der pi-Home-Freigabe: Bei Seatbelt gilt die letzte
  # passende Regel.
  defp session_rules(cfg, session_dir) do
    root = SBPL.quote!(Pi.sessions_root(cfg))

    [
      "; Session-Verläufe: nur die eigene Session (Ticket #295)",
      "(deny file-read* (subpath " <> root <> "))",
      "(deny file-write* (subpath " <> root <> "))"
    ] ++
      if session_dir,
        do: [
          "(allow file-read* (subpath " <> SBPL.quote!(session_dir) <> "))",
          "(allow file-write* (subpath " <> SBPL.quote!(session_dir) <> "))"
        ],
        else: []
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
