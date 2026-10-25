defmodule KomkiCli.EscriptProfile do
  @moduledoc """
  Gemeinsame Regelschicht fuer Escripts unter deny-default (Ticket #146):
  Vermittler, Egress-Proxy und Connectoren sind Escripts mit Erlang-Runtime.
  Ihre Profile unterscheiden sich nur in Socket, Netz und Dateisystem; die
  Grundschicht hier ist fuer alle gleich:

    * Start ueber den aufgeloesten `escript`-Pfad (`<erlang-root>/bin/escript
      <datei>`); die Kette escript → erl (sh-Skript mit dirname/basename) →
      erlexec → beam.smp → erl_child_setup laeuft per exec im selben Prozess.
    * Erlang-Wurzel lesen und ausfuehren, die Escript-Datei lesen.
    * Boot-Schicht (dieselbe Klasse wie beim llama-Profil, Ticket #70/#100)
      und die Sonden der BEAM-Initialisierung.
    * Die dylib-Verzeichnisse der crypto-NIF (OpenSSL liegt meist ausserhalb
      der Erlang-Wurzel, etwa unter Homebrew).

  Ermittelt per Denial-Log (`log show --predicate 'sender == "Sandbox"'`),
  Befehle und Ergebnisse: `docs/research/2026-10-23-connector-profile.md`.
  Bewusst nicht erlaubt: der syslog-Unix-Socket (os_log-Fallback, die
  Denials sind folgenlos), `~/.CFUserTextEncoding`, `/dev/tty`.

  Alle Pfade kommen kanonisch aus der config.json; feste Eingaben ergeben
  byte-identischen Text (der Doctor prueft das).
  """

  alias KomkiCli.{Config, MachODeps}

  @doc """
  Erlang-Wurzel aus der config: unter der Burrito-Einzeldatei (Ticket #181)
  die entpackte Laufzeit (`runtime_root`), sonst die Wurzel zu `escript_bin`;
  fehlt sie, scheitert die Generierung klar.
  """
  @spec erlang_root!(Config.t()) :: String.t()
  def erlang_root!(%Config{launcher: "burrito", runtime_root: root}) when is_binary(root),
    do: root

  def erlang_root!(%Config{escript_bin: bin}) when is_binary(bin), do: Config.erlang_root(bin)

  def erlang_root!(%Config{}),
    do:
      raise(ArgumentError, "escript-Laufzeit nicht entdeckt (Erlang installieren, 'komki setup')")

  @doc "Regeln zu einem Profiltext verbinden (ein finales Newline, Duplikate entfernt)."
  @spec render([String.t()]) :: String.t()
  def render(rules), do: rules |> Enum.uniq() |> Enum.join("\n") |> Kernel.<>("\n")

  @doc "Kopf: Kommentarzeilen, Version, deny default."
  @spec header([String.t()]) :: [String.t()]
  def header(comments), do: Enum.map(comments, &("; " <> &1)) ++ ["(version 1)", "(deny default)"]

  @doc """
  Grundschicht eines Escripts: Runtime unter `erlang_root`, die
  Escript-Datei `escript_file` und die Startsonden.
  """
  @spec runtime(String.t(), String.t()) :: [String.t()]
  def runtime(erlang_root, escript_file) do
    exec_rules(erlang_root, escript_file) ++
      boot_rules() ++
      beam_rules() ++
      crypto_rules(erlang_root)
  end

  @doc """
  Grundschicht fuer die Rolle `binary` nach der Startart der Instanz. Im
  Escript-Betrieb genau `runtime/2` (Profiltext unveraendert); unter der
  Burrito-Einzeldatei (Ticket #181) zusaetzlich das Ausfuehren der Binary,
  die als Wrapper die entpackte Laufzeit unter `runtime_root` startet.
  """
  @spec runtime_for(Config.t(), String.t()) :: [String.t()]
  def runtime_for(%Config{} = cfg, binary) do
    runtime(erlang_root!(cfg), binary) ++ burrito_rules(cfg, binary)
  end

  defp burrito_rules(%Config{launcher: "burrito", komki_bin: komki}, komki) do
    [
      "; Burrito-Einzeldatei (Ticket #181): komki startet als Wrapper und fuehrt",
      "; die entpackte Laufzeit (Erlang-Wurzel oben) aus",
      "(allow process-exec (literal \"" <> komki <> "\"))"
    ]
  end

  defp burrito_rules(_cfg, _binary), do: []

  defp exec_rules(root, escript_file) do
    [
      "; Erlang-Runtime: escript -> erl (sh) -> erlexec -> beam.smp -> erl_child_setup",
      "(allow process-fork)",
      "(allow process-exec (subpath \"" <> root <> "\"))",
      "(allow file-read* (subpath \"" <> root <> "\"))",
      "; erl ist ein sh-Skript (dirname/basename); /bin/sh ist ein Variantenwaehler,",
      "; der /private/var/select/sh liest und /bin/bash startet",
      ~s{(allow process-exec (literal "/bin/sh") (literal "/bin/bash")} <>
        ~s{ (literal "/usr/bin/dirname") (literal "/usr/bin/basename"))},
      ~s{(allow file-read* (literal "/bin/sh") (literal "/bin/bash")} <>
        ~s{ (literal "/usr/bin/dirname") (literal "/usr/bin/basename"))},
      "(allow file-read-metadata (literal \"/private/var/select\"))",
      "(allow file-read* (literal \"/private/var/select/sh\"))",
      "; das Escript selbst (Zip-Archiv mit Shebang; nur lesen)",
      "(allow file-read* (literal \"" <> escript_file <> "\"))"
    ]
  end

  # Boot-Schicht: ohne sie stirbt jeder exec auf macOS 27.2 mit SIGABRT
  # (rc=134), dieselbe Klasse wie Profile.common_boot_rules/0.
  defp boot_rules do
    [
      "; Boot-Schicht (macOS 27.2: ohne sie SIGABRT rc=134 beim exec)",
      "(allow file-read* (subpath \"/System/Library\"))",
      "(allow file-read* (subpath \"/usr/lib\"))",
      "(allow file-read* (subpath \"/System/Volumes/Preboot\"))",
      "(allow file-read* (literal \"/dev/null\") (literal \"/dev/random\") (literal \"/dev/urandom\"))",
      "(allow file-write* (literal \"/dev/null\"))",
      "(allow sysctl-read (sysctl-name \"security.mac.lockdown_mode_state\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/Rosetta\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/App\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/OS\"))",
      "(allow file-read-metadata (literal \"/System/Volumes/Data\"))",
      "(allow file-read-metadata (literal \"/var\"))",
      "(allow file-read-data (literal \"/\"))",
      "(allow file-read* file-test-existence file-write-data file-ioctl (literal \"/dev/dtracehelper\"))",
      "(allow system-info (info-type \"vfs.disk-space\"))"
    ]
  end

  @sysctls [
    "kern.bootargs",
    "kern.hostname",
    "kern.iossupportversion",
    "kern.ngroups",
    "kern.osproductversion",
    "kern.osrelease",
    "kern.ostype",
    "kern.osvariant_status",
    "kern.version"
  ]

  defp beam_rules do
    ["; BEAM-Initialisierung: CPU-/OS-Sonden, Benutzerauflösung, Zeitzone, Protokolle"] ++
      Enum.map(@sysctls, &("(allow sysctl-read (sysctl-name \"" <> &1 <> "\"))")) ++
      [
        "(allow sysctl-read (sysctl-name-prefix \"hw.\"))",
        "(allow sysctl-read (sysctl-name-prefix \"machdep.cpu.\"))",
        "(allow file-read-metadata (literal \"/etc\"))",
        "(allow mach-lookup (global-name \"com.apple.system.opendirectoryd.libinfo\"))",
        "(allow mach-lookup (global-name \"com.apple.system.notification_center\"))",
        "(allow ipc-posix-shm-read-data (ipc-posix-name \"apple.shm.notification_center\"))",
        "(allow file-read* (literal \"/private/etc/localtime\"))",
        "(allow file-read* (subpath \"/private/var/db/timezone\"))",
        "(allow file-read* (literal \"/private/etc/protocols\"))",
        "; erl_child_setup schliesst geerbte Deskriptoren ueber /dev/fd",
        "(allow file-read-data (literal \"/dev/fd\"))",
        "(allow file-read-data (literal \"/dev/autofs_nowait\"))"
      ]
  end

  # crypto-NIF: dyld oeffnet die gelinkte OpenSSL (z. B. Homebrew). Ohne
  # Lesrecht scheitert der Start jedes Escripts mit :crypto.
  defp crypto_rules(root) do
    pattern = Path.join([root, "lib", "crypto-*", "priv", "lib", "crypto.so"])

    dirs =
      pattern
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.flat_map(&MachODeps.dylib_dirs/1)
      |> Enum.reject(&String.starts_with?(&1, root <> "/"))
      |> Enum.uniq()

    case dirs do
      [] ->
        []

      _ ->
        # dyld folgt dem deklarierten Symlink-Pfad (/opt/homebrew/opt/...):
        # ohne Metadaten der Vorfahren "blocked by sandbox" (Denial-Log).
        ["; dylib-Verzeichnisse der crypto-NIF (otool-Walk, beide Pfadformen)"] ++
          Enum.map(dirs, &("(allow file-read* (subpath \"" <> &1 <> "\"))")) ++
          meta_ancestors(dirs)
    end
  end

  @doc "Log-Datei (Redirect-Ziel der Spawn-Shell) lesen und schreiben."
  @spec log_rules(String.t()) :: [String.t()]
  def log_rules(log_path) do
    [
      "; Log (stderr-Redirect; Write-Scope genau diese Datei)",
      "(allow file-read* file-write* (literal \"" <> log_path <> "\"))"
    ]
  end

  @doc """
  `file-read-metadata` fuer alle Vorfahren der Pfade (realpath-Walk von
  dyn_erl und dem Socket-Bind); sortiert, inklusive `/`.
  """
  @spec meta_ancestors([String.t()]) :: [String.t()]
  def meta_ancestors(paths) do
    paths
    |> Enum.flat_map(fn path ->
      segments = String.split(path, "/", trim: true)
      Enum.map(1..length(segments)//1, &("/" <> Enum.join(Enum.take(segments, &1), "/")))
    end)
    |> Enum.concat(["/"])
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&("(allow file-read-metadata (literal \"" <> &1 <> "\"))"))
  end
end
