defmodule Seatbelt.Preset do
  @moduledoc """
  Validated rule layers for common confinement scenarios, harvested from
  denial-log campaigns (see the survey in the komki research reports).

  Determinism contract: these functions return plain rule lists; fixed
  inputs produce byte-identical profile text via `Seatbelt.SBPL.render/1`.
  Rule *contents* are pinned — do not edit them without a fresh
  denial-log validation run. Comments are English by library policy.

  Note: `macos_exec_boot/0` and `escript_boot/0` are deliberately NOT
  unified. They are two independently validated layers from different
  denial-log campaigns; the escript layer additionally needs the
  `/System/Volumes/Data` metadata read, a `/dev/null` write and the
  system-house read subpaths. Merging them would trade a documented
  difference for an unvalidated guess.
  """

  @doc """
  Boot layer for arbitrary exec'd programs under deny-default on macOS
  27.x: without it, every exec dies with SIGABRT rc=134 before the
  target even runs.
  """
  @spec macos_exec_boot() :: [String.t()]
  def macos_exec_boot do
    [
      "; macOS exec boot layer: without it every exec dies with SIGABRT rc=134",
      "(allow sysctl-read (sysctl-name \"security.mac.lockdown_mode_state\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/Rosetta\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/App\"))",
      "(allow file-read-metadata (literal \"/System/Cryptexes/OS\"))",
      "(allow file-read-metadata (literal \"/var\"))",
      "(allow file-read-data (literal \"/\"))",
      "(allow file-write-data (literal \"/dev/dtracehelper\"))",
      "; dtracehelper triple grant (grammar from system.sb:122)",
      "(allow file-read* file-test-existence file-write-data file-ioctl (literal \"/dev/dtracehelper\"))",
      "; disk-space probe (fstatfs; grammar from system.sb:202)",
      "(allow system-info (info-type \"vfs.disk-space\"))"
    ]
  end

  @doc """
  Boot layer for Escript/BEAM runtimes (see `Seatbelt.Escript`): the
  exec layer above plus the reads a fresh BEAM needs before the first
  Erlang code runs. Different campaign, deliberately separate — see the
  moduledoc before merging anything.
  """
  @spec escript_boot() :: [String.t()]
  def escript_boot do
    [
      "; Boot layer (macOS 27.2: without it every exec dies with SIGABRT rc=134)",
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

  # TUI class (pattern from anthropic-experimental/sandbox-runtime,
  # macos-sandbox-utils.ts and srt issue #419): TUIs (raw mode, terminal
  # size, signals) fail SILENTLY under deny-default unless the terminal
  # class is allowed explicitly. Headless probes never needed these
  # rules; an interactive session on a pty does. Scopes: process control
  # only within the same sandbox, terminal access only on real tty
  # devices.
  #
  # Residual risk to know about: distributed-notification-post is a
  # channel to every process of the invoking user (it needs a receiver
  # outside the boundary). Only remove after measuring whether the TUI
  # boots without it.
  @doc """
  Terminal/TUI class: ioctls on real ttys, pseudo-ttys, in-sandbox
  process control, the `hw.*`/`kern.proc.*` sysctl prefixes (version
  robust: new OS versions read new fields — the zsh 5.9 regression
  class on darwin25+). Launcher-specific stdio plumbing (e.g. redirecting
  stdout onto a pty via `/dev/fd/0`) is caller knowledge and not part of
  this class.
  """
  @spec tui() :: [String.t()]
  def tui do
    [
      "; TUI/terminal class (sandbox-runtime pattern; srt #419)",
      "(allow file-ioctl (literal \"/dev/tty\"))",
      "(allow file-ioctl (regex #\"^/dev/ttys[0-9]+$\"))",
      "(allow pseudo-tty)",
      "(allow process-info* (target same-sandbox))",
      "(allow signal (target same-sandbox))",
      "(allow mach-priv-task-port (target same-sandbox))",
      "(allow user-preference-read)",
      "(allow distributed-notification-post)",
      "(allow ipc-posix-sem)",
      "; hw.*/kern.proc.* pinned by prefix: new OS versions read new fields",
      "(allow sysctl-read (sysctl-name-prefix \"hw.\"))",
      "(allow sysctl-read (sysctl-name-prefix \"kern.proc.\"))"
    ]
  end
end
