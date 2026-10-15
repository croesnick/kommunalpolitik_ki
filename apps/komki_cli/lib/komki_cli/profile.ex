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

  alias KomkiCli.{Config, Llama}
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

  ## ---------------------------------------------- llama-server-Profil (Ticket #100)

  @doc """
  llama-server-Profil (Ticket #100): eigene deny-default-Grenze fuer den
  Inferenz-Prozess. R.3 ("Lokale KI") wird damit zur geprüften Aussage statt
  zur unbelegten Ausnahme. Feste cfg -> byte-identischer Output.

  Verifiziert 14.10.2026 auf macOS 27.2 (Build 26B5101f), llama-server 0.6.0
  (build 11429): Modell-Load, Health, Inferenz und TERM-Exit unter der Grenze
  (Experimente exp4–exp16, Ticket #100). Bewusste benannte Grenzen:
  GPU/Metal-Kette freigegeben (Ticket #111, exp18 14.10.2026: ~53 t/s Eval
  unter der Grenze ≈ ungesandboxete Baseline ~57, gegen ~5 CPU-only) — die
  GPU-Treiber-Angriffsflaeche ist die bewusst eingegangene Grenze; kein
  network-outbound (llama laeuft --offline); Memory-Fitter bricht mit Warnung
  ab und laesst die Parameter wie angefordert.
  """
  @spec generate_llama(Config.t()) :: String.t()
  def generate_llama(%Config{} = cfg) when Config.tools_ready(cfg) do
    cfg |> llama_rules_for() |> Enum.join("\n") |> Kernel.<>("\n")
  end

  # Unvollstaendige config (Werkzeugpfade fehlen): klar scheitern, so wie
  # generate/2 es tut, statt kryptisch in Regel-Konkatenationen zu crashen.
  def generate_llama(%Config{}) do
    raise ArgumentError,
      message:
        "llama-Profil-Generierung braucht vollstaendige Werkzeugpfade " <>
          "(node/cli/llama-server) — init verweigert unvollstaendige Instanzen; config.json pruefen"
  end

  ## Komposition (festgelegte Reihenfolge, deterministisch):
  ## Header -> Startup-Schicht -> exec/Read Binaer -> dylib-Baum -> /dev ->
  ## Modell -> Log -> Netz -> Sysctl-Pins -> /etc -> Mach/shm -> Metal ->
  ## Pfad-Sonden -> CFPreferences -> Metadaten-Vorfahrnkette -> Schlussgrenzen.
  defp llama_rules_for(%Config{} = cfg) do
    user_home = System.user_home!()
    dylib_dirs = llama_dylib_dirs(cfg.llama_server_bin)
    log_path = Llama.log_path(cfg)

    rules =
      llama_header() ++
        llama_start_layer() ++
        llama_exec_read_rules(cfg.llama_server_bin) ++
        llama_dylib_rules(dylib_dirs) ++
        llama_dev_rules() ++
        llama_model_rules(cfg.gguf_path) ++
        llama_log_rules(log_path) ++
        llama_network_rules(cfg.port) ++
        llama_sysctl_rules() ++
        llama_etc_passwd_rules() ++
        llama_mach_shm_rules() ++
        llama_metal_rules() ++
        llama_probe_rules() ++
        llama_prefs_rules(user_home) ++
        meta_ancestors(llama_meta_paths(cfg, log_path, dylib_dirs, user_home)) ++
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
      "; Rationale je Regel: die Kommentare unten (Evidenz exp4-exp16, Ticket #100).",
      "(version 1)",
      "(deny default)"
    ]
  end

  # Startup-Schicht: common_boot_rules() wiederverwendet (die validierte
  # Ticket-#70-Schicht; ohne sie stirbt jeder exec auf macOS 27.2 mit
  # SIGABRT rc=134). Die pi-spezifische Kopfzeile
  # ("asdf-Boot-Proben") entfaellt — das llama-Profil hat keine asdf-Schicht
  # und der Profil-Test prueft das hart.
  defp llama_start_layer do
    Enum.reject(common_boot_rules(), &String.starts_with?(&1, "; env/bash/asdf"))
  end

  defp llama_exec_read_rules(bin) do
    [
      "; llama-server-Binaer: exec + read (config haelt den kernel-kanonischen Pfad).",
      "(allow process-exec (literal \"" <> bin <> "\"))",
      "(allow file-read* (literal \"" <> bin <> "\"))"
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
      Enum.map(dirs, fn dir -> "(allow file-read* (subpath \"" <> dir <> "\"))" end)
  end

  defp llama_dev_rules do
    [
      "(allow file-read* (literal \"/dev/null\"))",
      "(allow file-read* (literal \"/dev/random\"))",
      "(allow file-read* (literal \"/dev/urandom\"))"
    ]
  end

  defp llama_model_rules(gguf_path) do
    [
      "; Modell (mmap)",
      "(allow file-read* (literal \"" <> gguf_path <> "\"))"
    ]
  end

  defp llama_log_rules(log_path) do
    [
      "; Log (Redirect-Ziel des Spawn-Shells; Write-Scope ausschliesslich diese Datei)",
      "(allow file-read* (literal \"" <> log_path <> "\"))",
      "(allow file-write* (literal \"" <> log_path <> "\"))"
    ]
  end

  defp llama_network_rules(port) do
    [
      "; Netz: Management-Port, loopback-bind + inbound, KEIN outbound (--offline wird",
      "; profilseitig erzwungen). SBPL-Grammatik-Fund exp7/exp8: host muss * oder localhost",
      "; sein; \"localhost:PORT\" ist die engste Form und matcht den 127.0.0.1-Bind.",
      "(allow network-bind (local ip \"localhost:" <> to_string(port) <> "\"))",
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
        "(allow sysctl-read (sysctl-name \"" <> name <> "\"))"
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
        "(allow mach-lookup (global-name \"" <> name <> "\"))"
      end) ++
      [
        "(allow ipc-posix-shm (ipc-posix-name \"apple.shm.notification_center\"))"
      ]
  end

  # GPU/Metal-Kette (Ticket #111: Aufhebung der CPU-only-Grenze aus #100).
  # Evidenz: exp18-Runden 1-3, 14.10.2026 (Unified-Log-Denials je Runde):
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
    ["; Pfad-Sonden-Metadaten (benign, exp15)"] ++ metadata_literals(@llama_probe_paths)
  end

  defp llama_prefs_rules(user_home) do
    [
      "; CFPreferences-Global-Read (CoreFoundation-Init)",
      "(allow file-read* (literal \"/Library/Preferences/.GlobalPreferences.plist\"))",
      "(allow file-read-metadata (literal \"/Library/Preferences\"))",
      "(allow file-read* (literal \"" <>
        user_home <> "/Library/Preferences/.GlobalPreferences.plist\"))",
      "(allow file-read-metadata (literal \"" <> user_home <> "/Library/Preferences\"))",
      "(allow file-read-metadata (literal \"" <> user_home <> "/Library/Preferences/ByHost\"))",
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

  # Dylib-Verzeichnisse des llama-server-Binaers: rekursiver otool-Walk.
  # - otool -L liefert die deklarierten Deps (dyld oeffnet genau diese Pfadformen);
  # - otool -l liefert die LC_RPATH-Eintraege fuer @rpath-Aufloesung;
  # - transitive Deps werden mitgegangen (Fund: libomp via libggml-base);
  # - je aufgeloester Dep: dirname(deklariert) UND dirname(canonical) (Pfadform-Cave
  #   in beide Richtungen — exp6: Regeln nur in kanonischer Form matchen nicht);
  # - pro Dep-Verzeichnis dessen Geschwister-libexec, wenn vorhanden (ggml legt
  #   dort die Backend-Bundles ab: libggml-cpu-apple_m*.so, libggml-metal.so;
  #   ohne das bleibt die Backend-Registry leer — exp14);
  # - otool fehlend oder Datei unlesbar: [] (CI-Linux; Profil bleibt generierbar).
  defp llama_dylib_dirs(bin) do
    if System.find_executable("otool") == nil or not File.exists?(bin) do
      []
    else
      # queue = [bin], visited leer — das Bin wird beim ersten Durchlauf
      # verarbeitet und erst dann als besucht markiert (Seed-Fund: ein
      # vorbelegtes visited skipped die Wurzel und leert die Queue sofort;
      # die Dep-Liste blieb leer). Accumulatoren als einfache Listen:
      # dialyzer sieht MapSet.t() in den rekursiven Positionen als opaken
      # Term mit auseinanderlaufenden Subtypen (call_without_opaque,
      # Verify-Fund); die Mengen sind winzig, uniq/sort sitzt am Ende.
      bin
      |> llama_dylib_walk([bin], [], [])
      |> libexec_forms()
    end
  end

  defp otool_output(args) do
    case System.find_executable("otool") do
      nil ->
        nil

      otool ->
        case System.cmd(otool, args, stderr_to_stdout: true) do
          {out, 0} -> out
          _ -> nil
        end
    end
  end

  defp llama_dylib_walk(_bin, [], _visited, dirs), do: dirs

  defp llama_dylib_walk(bin, [macho | queue], visited, dirs) do
    canonical_macho = Config.canonical(macho)

    if canonical_macho in visited do
      llama_dylib_walk(bin, queue, visited, dirs)
    else
      deps = otool_deps(macho)
      rpaths = otool_rpaths(macho)

      {queue, dirs} =
        Enum.reduce(deps, {queue, dirs}, fn dep, {acc_queue, acc_dirs} ->
          llama_dep_dirs(dep, rpaths, macho, bin, acc_queue, acc_dirs)
        end)

      llama_dylib_walk(bin, queue, [canonical_macho | visited], dirs)
    end
  end

  defp llama_dep_dirs(dep, rpaths, macho, bin, queue, dirs) do
    case llama_resolve_dep(dep, rpaths, macho, bin) do
      :skip ->
        {queue, dirs}

      {:dep, declared, resolved} ->
        # Rohform des deklarierten Verzeichnisses behalten (dyld oeffnet genau
        # diese Pfadform — Pfadform-Cave exp6) plus die kanonische Form.
        dirs = Enum.uniq([Path.dirname(declared) | dirs])

        if resolved != nil do
          dirs = Enum.uniq([Config.canonical(Path.dirname(resolved)) | dirs])
          {queue ++ [resolved], dirs}
        else
          {queue, dirs}
        end
    end
  end

  defp llama_resolve_dep(dep, rpaths, macho, bin) do
    cond do
      String.starts_with?(dep, "@rpath/") ->
        llama_rpath_dep(dep, rpaths, macho, bin)

      String.starts_with?(dep, "/usr/lib") or String.starts_with?(dep, "/System/Library") ->
        # Basis-Layer deckt die System-Haeuser ab; auch nicht rekursieren.
        :skip

      String.starts_with?(dep, "@executable_path/") or String.starts_with?(dep, "@loader_path/") ->
        llama_loader_dep(dep, macho, bin)

      String.starts_with?(dep, "/") ->
        {:dep, dep, maybe_canonical(dep)}

      true ->
        :skip
    end
  end

  defp llama_rpath_dep(dep, rpaths, macho, bin) do
    rest = String.replace_prefix(dep, "@rpath/", "")

    rpaths
    |> Enum.flat_map(&rpath_roots(&1, macho, bin))
    |> Enum.map(&Path.join(&1, rest))
    |> Enum.find_value(:skip, fn candidate ->
      resolved = maybe_canonical(candidate)
      resolved && {:dep, candidate, resolved}
    end)
  end

  # RPATH-Werte sind selbst loader-relativ: llama.cpp 0.6.0 pinnt
  # "@loader_path/../lib" (Review-Fund: ohne diese Expansion bleiben alle
  # @rpath-Deps unloesbar und der Eigenbau-Lib-Baum faellt aus dem Profil).
  # @loader_path bezieht sich auf das gerade geladene Mach-O, @executable_path
  # auf die Wurzel-Binary; lexikalische Normalisierung via Path.expand.
  defp rpath_roots(rpath, macho, bin) do
    cond do
      String.starts_with?(rpath, "@loader_path/") ->
        [Path.expand(String.replace_prefix(rpath, "@loader_path/", ""), Path.dirname(macho))]

      String.starts_with?(rpath, "@executable_path/") ->
        [Path.expand(String.replace_prefix(rpath, "@executable_path/", ""), Path.dirname(bin))]

      true ->
        [rpath]
    end
  end

  defp llama_loader_dep(dep, macho, bin) do
    rest =
      dep
      |> String.replace_prefix("@loader_path/", "")
      |> String.replace_prefix("@executable_path/", "")

    # Loader-Verzeichnis zuerst, dann das Bin-Verzeichnis (@executable_path).
    candidates = [Path.join(Path.dirname(macho), rest), Path.join(Path.dirname(bin), rest)]

    Enum.find_value(candidates, :skip, fn candidate ->
      resolved = maybe_canonical(candidate)
      resolved && {:dep, candidate, resolved}
    end)
  end

  defp maybe_canonical(path) do
    if File.exists?(path), do: Config.canonical(path), else: nil
  end

  # Deps aus `otool -L`: Kopfzeile (Binaer-Selbstname) weg, pro Zeile das erste
  # Whitespace-Token = der deklarierte Installationspfad. otool rückt Dep-Zeilen
  # mit Tab ein — erst trimmen, sonst startet jedes Token mit "\t" und fällt
  # in llama_resolve_dep durch alle Pfad-Präfixe (Review-Fund: leere Dep-Liste).
  defp otool_deps(macho) do
    case otool_output(["-L", macho]) do
      nil ->
        []

      out ->
        out
        |> String.split("\n")
        |> Enum.drop(1)
        |> Enum.map(&first_token/1)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp first_token(line), do: line |> String.trim() |> String.split(" ") |> List.first()

  # LC_RPATH-Eintraege aus `otool -l`: nach "cmd LC_RPATH" folgt (hinter
  # cmdsize) die "path"-Zeile; Reihenfolge wie gedruckt.
  defp otool_rpaths(macho) do
    case otool_output(["-l", macho]) do
      nil -> []
      out -> otool_rpaths_scan(String.split(out, "\n"), [])
    end
  end

  defp otool_rpaths_scan([], acc), do: Enum.reverse(acc)

  defp otool_rpaths_scan([line | rest], acc) do
    if String.trim(line) == "cmd LC_RPATH" do
      otool_rpath_value(rest, acc)
    else
      otool_rpaths_scan(rest, acc)
    end
  end

  defp otool_rpath_value([], acc), do: Enum.reverse(acc)

  defp otool_rpath_value([line | rest], acc) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "path ") ->
        value = String.replace_prefix(trimmed, "path ", "")
        otool_rpaths_scan(rest, [rpath_value(value) | acc])

      String.starts_with?(trimmed, "cmd ") or String.starts_with?(trimmed, "Load command") ->
        # Naechster Load-Command-Block ohne gefundene path-Zeile: zurueck zum
        # Header-Scan (unvollstaendiger RPATH-Block).
        otool_rpaths_scan([line | rest], acc)

      true ->
        # Zwischenfeld (cmdsize u.a.) im selben RPATH-Block: weitersuchen —
        # die path-Zeile folgt erst danach (Review-Fund: Fruehrueckkehr zum
        # Header-Scan uebersprang sie und liess alle @rpath-Deps unloesbar).
        otool_rpath_value(rest, acc)
    end
  end

  defp rpath_value(value), do: value |> String.split(" (", parts: 2) |> List.first()

  # Geschwister-libexec je Dep-Verzeichnis (ggml-Backend-Scan-Ort); beide
  # Pfadformen bleiben stehen, wenn kanonisch und deklariert auseinanderlaufen.
  defp libexec_forms(dirs) do
    (dirs ++ Enum.flat_map(dirs, &dir_libexec_forms/1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp dir_libexec_forms(dir) do
    declared = Path.join(Path.dirname(dir), "libexec")
    sibling = Config.canonical(declared)

    if File.exists?(sibling) do
      Enum.uniq([sibling, declared])
    else
      []
    end
  end

  defp metadata_literals(paths) do
    Enum.map(paths, fn path ->
      "(allow file-read-metadata (literal \"" <> path <> "\"))"
    end)
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
      "(allow sysctl-read (sysctl-name-prefix \"kern.proc.\"))",
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
