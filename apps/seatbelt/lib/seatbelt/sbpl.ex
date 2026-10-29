defmodule Seatbelt.SBPL do
  @moduledoc """
  SBPL (Seatbelt Profile Language) rule emitters and composition helpers.

  Every emitter produces byte-exact `(allow …)` lines for one operation and
  target shape. Compound one-off rules (e.g. the dtracehelper triple grant)
  live as verbatim strings inside the presets in `Seatbelt.Preset` — they
  are pinned constants, that is their point.

  The emitters do not escape paths: paths flowing into a profile are
  expected to be kernel-canonical (`Seatbelt.canonical/1`) and
  quote-free, same contract as the profiles that predate this library.
  """

  @doc "Comment line."
  @spec comment(String.t()) :: String.t()
  def comment(text), do: "; " <> text

  @doc "Header: comment lines, version, deny-default base."
  @spec header([String.t()]) :: [String.t()]
  def header(comments), do: Enum.map(comments, &("; " <> &1)) ++ ["(version 1)", "(deny default)"]

  @doc "Join rules into a profile text (duplicates removed, one final newline)."
  @spec render([String.t()]) :: String.t()
  def render(rules), do: rules |> Enum.uniq() |> Enum.join("\n") |> Kernel.<>("\n")

  @doc "(allow file-read* (literal path))"
  @spec read_literal(String.t()) :: String.t()
  def read_literal(path), do: "(allow file-read* (literal \"" <> path <> "\"))"

  @doc "(allow file-read* (subpath dir))"
  @spec read_subpath(String.t()) :: String.t()
  def read_subpath(dir), do: "(allow file-read* (subpath \"" <> dir <> "\"))"

  @doc "(allow file-write* (literal path))"
  @spec write_literal(String.t()) :: String.t()
  def write_literal(path), do: "(allow file-write* (literal \"" <> path <> "\"))"

  @doc "(allow file-write* (subpath dir))"
  @spec write_subpath(String.t()) :: String.t()
  def write_subpath(dir), do: "(allow file-write* (subpath \"" <> dir <> "\"))"

  @doc "(allow file-read* file-write* (literal path)) — read-write scope on exactly one file (log/socket pattern)."
  @spec read_write_literal(String.t()) :: String.t()
  def read_write_literal(path), do: "(allow file-read* file-write* (literal \"" <> path <> "\"))"

  @doc "(allow process-exec (literal binary))"
  @spec exec_literal(String.t()) :: String.t()
  def exec_literal(bin), do: "(allow process-exec (literal \"" <> bin <> "\"))"

  @doc "(allow process-exec* (literal binary))"
  @spec exec_star_literal(String.t()) :: String.t()
  def exec_star_literal(bin), do: "(allow process-exec* (literal \"" <> bin <> "\"))"

  @doc "(allow file-read-metadata (literal path))"
  @spec metadata_literal(String.t()) :: String.t()
  def metadata_literal(path), do: "(allow file-read-metadata (literal \"" <> path <> "\"))"

  @doc "(allow sysctl-read (sysctl-name name))"
  @spec sysctl(String.t()) :: String.t()
  def sysctl(name), do: "(allow sysctl-read (sysctl-name \"" <> name <> "\"))"

  @doc "(allow sysctl-read (sysctl-name-prefix prefix))"
  @spec sysctl_prefix(String.t()) :: String.t()
  def sysctl_prefix(prefix), do: "(allow sysctl-read (sysctl-name-prefix \"" <> prefix <> "\"))"

  @doc "(allow mach-lookup (global-name name))"
  @spec mach_lookup(String.t()) :: String.t()
  def mach_lookup(name), do: "(allow mach-lookup (global-name \"" <> name <> "\"))"

  @doc "(allow ipc-posix-shm (ipc-posix-name name))"
  @spec ipc_posix_shm(String.t()) :: String.t()
  def ipc_posix_shm(name), do: "(allow ipc-posix-shm (ipc-posix-name \"" <> name <> "\"))"

  @doc """
  `(allow file-read-metadata …)` rules for every ancestor of the given
  paths (sorted, deduplicated, always including `/`). Without metadata
  on the ancestors, `realpath` walks fail with "blocked by sandbox"
  (dyld and socket binds open each path component on the way down).
  """
  @spec metadata_ancestors([String.t()]) :: [String.t()]
  def metadata_ancestors(paths) do
    paths
    |> Enum.flat_map(fn path ->
      abs = String.trim_leading(path, "/")
      segments = String.split(abs, "/", trim: true)

      # Explicit step: `1..0` (empty path) would otherwise default to a
      # decreasing range in current Elixir and warn at runtime.
      Enum.map(1..length(segments)//1, fn i ->
        "/" <> Enum.join(Enum.take(segments, i), "/")
      end)
    end)
    |> MapSet.new()
    |> MapSet.put("/")
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(&metadata_literal/1)
  end
end
