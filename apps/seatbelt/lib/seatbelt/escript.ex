defmodule Seatbelt.Escript do
  @moduledoc """
  Common rule layer for Escripts under deny-default: a sandboxed Escript
  runs on an Erlang runtime, and the chain
  escript → erl (sh script with dirname/basename) → erlexec → beam.smp →
  erl_child_setup executes in the same process. This layer covers:

    * Exec and read of the Erlang root and the Escript file itself.
    * The boot layer (`Seatbelt.Preset.escript_boot/0`).
    * The BEAM initialization probes (CPU/OS sysctls, user resolution,
      timezone, protocols).
    * The dylib directories of the crypto NIF (OpenSSL usually lives
      outside the Erlang root, e.g. under Homebrew).

  Conventions:

    * All paths are kernel-canonical (`Seatbelt.canonical/1`) — the
      caller resolves them before passing them in.
    * Fixed inputs produce byte-identical text (`Seatbelt.SBPL.render/1`).

  Deliberately not allowed: the syslog Unix socket (os_log fallback —
  its denials are inconsequential), `~/.CFUserTextEncoding`, `/dev/tty`.

  Discovered via denial log (`log show --predicate 'sender == "Sandbox"'`)
  during the komki connector profile campaign, October 2026.
  """

  alias Seatbelt.{MachODeps, Preset, SBPL}

  @type burrito :: %{wrapper: String.t(), runtime_root: String.t()}

  @doc """
  Rule layer for an Escript running on `erlang_root`, started from
  `escript_file`.
  """
  @spec runtime(String.t(), String.t()) :: [String.t()]
  def runtime(erlang_root, escript_file) do
    exec_rules(erlang_root, escript_file) ++
      Preset.escript_boot() ++
      beam_rules() ++
      crypto_rules(erlang_root)
  end

  @doc """
  `runtime/2` plus the Burrito single-file layer: when the program is a
  Burrito wrapper, it executes itself and starts the unpacked runtime
  under `runtime_root`. Pass `nil` when the program is a plain Escript
  (the profile text is then exactly `runtime/2`).
  """
  @spec runtime_for(String.t(), String.t(), burrito() | nil) :: [String.t()]
  def runtime_for(erlang_root, escript_file, nil),
    do: runtime(erlang_root, escript_file)

  def runtime_for(erlang_root, escript_file, %{} = burrito),
    do: runtime(erlang_root, escript_file) ++ burrito_rules(burrito)

  # Established by narrowing against the running wrapper (Burrito 1.6,
  # wrapper.zig and erlang_launcher.zig); deleting stays forbidden: old
  # versions are cleaned up by the unsandboxed launcher before the run.
  defp burrito_rules(%{wrapper: wrapper, runtime_root: root}) do
    [
      "; Burrito single file: the program runs as a wrapper that starts the",
      "; unpacked runtime (Erlang root above)",
      "(allow process-exec (literal " <> SBPL.quote!(wrapper) <> "))",
      "; the wrapper re-creates its runtime directory on every start (mkdir -p; it exists)",
      "(allow file-write-create (literal " <> SBPL.quote!(root) <> "))",
      "; and lists .burrito to find old versions",
      "(allow file-read* (literal " <> SBPL.quote!(Path.dirname(root)) <> "))",
      "; releases/COOKIE is opened read-write but only read from",
      "; (no distributed Erlang inside the sandbox)",
      "(allow file-write-data (literal " <>
        SBPL.quote!(Path.join([root, "releases", "COOKIE"])) <> "))"
    ]
  end

  defp exec_rules(root, escript_file) do
    [
      "; Erlang runtime chain: escript -> erl (sh) -> erlexec -> beam.smp -> erl_child_setup",
      "(allow process-fork)",
      "(allow process-exec (subpath " <> SBPL.quote!(root) <> "))",
      SBPL.read_subpath(root),
      "; erl is an sh script (dirname/basename); /bin/sh is a variant selector",
      "; that reads /private/var/select/sh and execs /bin/bash",
      ~s{(allow process-exec (literal "/bin/sh") (literal "/bin/bash")} <>
        ~s{ (literal "/usr/bin/dirname") (literal "/usr/bin/basename"))},
      ~s{(allow file-read* (literal "/bin/sh") (literal "/bin/bash")} <>
        ~s{ (literal "/usr/bin/dirname") (literal "/usr/bin/basename"))},
      "(allow file-read-metadata (literal \"/private/var/select\"))",
      "(allow file-read* (literal \"/private/var/select/sh\"))",
      "; the Escript itself (zip archive with a shebang; read-only)",
      "(allow file-read* (literal " <> SBPL.quote!(escript_file) <> "))"
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
    ["; BEAM initialization: CPU/OS probes, user resolution, timezone, protocols"] ++
      Enum.map(@sysctls, &SBPL.sysctl/1) ++
      [
        SBPL.sysctl_prefix("hw."),
        SBPL.sysctl_prefix("machdep.cpu."),
        SBPL.metadata_literal("/etc"),
        SBPL.mach_lookup("com.apple.system.opendirectoryd.libinfo"),
        SBPL.mach_lookup("com.apple.system.notification_center"),
        "(allow ipc-posix-shm-read-data (ipc-posix-name \"apple.shm.notification_center\"))",
        "(allow file-read* (literal \"/private/etc/localtime\"))",
        "(allow file-read* (subpath \"/private/var/db/timezone\"))",
        "(allow file-read* (literal \"/private/etc/protocols\"))",
        "; erl_child_setup closes inherited descriptors via /dev/fd",
        "(allow file-read-data (literal \"/dev/fd\"))",
        "(allow file-read-data (literal \"/dev/autofs_nowait\"))"
      ]
  end

  # crypto NIF: dyld opens the linked OpenSSL (e.g. Homebrew). Without
  # read access, the start of every Escript using :crypto fails.
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
        # dyld follows the declared symlink path (/opt/homebrew/opt/...):
        # without metadata on the ancestors, "blocked by sandbox"
        # (denial-log finding).
        ["; dylib directories of the crypto NIF (otool walk, both path forms)"] ++
          Enum.map(dirs, &SBPL.read_subpath/1) ++
          SBPL.metadata_ancestors(dirs)
    end
  end

  @doc "Log file (redirect target of the spawn shell): read and write."
  @spec log_rules(String.t()) :: [String.t()]
  def log_rules(log_path) do
    [
      "; Log (stderr redirect; write scope is exactly this file)",
      SBPL.read_write_literal(log_path)
    ]
  end
end
