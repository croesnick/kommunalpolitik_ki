defmodule Seatbelt.SBPL do
  @moduledoc """
  SBPL (Seatbelt Profile Language) rule emitters and composition helpers.

  Every emitter produces byte-exact `(allow …)` lines for one operation and
  target shape. Compound one-off rules (e.g. the dtracehelper triple grant)
  live as verbatim strings inside the presets in `Seatbelt.Preset` — they
  are pinned constants, that is their point.

  Paths flowing into a profile are expected to be kernel-canonical
  (`Seatbelt.canonical/1`). Every caller-supplied string goes through
  `quote!/1`, which rejects anything that could leave the string literal
  (`"`, `\\`, control characters): a path like `/a") (allow default` must
  never become a rule. Comment text is checked the same way for line
  breaks.
  """

  @doc """
  SBPL string literal for `value`. Raises `ArgumentError` for `"`, `\\`
  and control characters — the profile stays deny-default no matter what a
  caller passes in.
  """
  @spec quote!(String.t()) :: String.t()
  def quote!(value) when is_binary(value) do
    if String.match?(value, ~r/["\\\x00-\x1f\x7f]/) do
      raise ArgumentError, "unsafe SBPL string: " <> inspect(value)
    end

    "\"" <> value <> "\""
  end

  @doc "Header: comment lines, version, deny-default base."
  @spec header([String.t()]) :: [String.t()]
  def header(comments),
    do: Enum.map(comments, &comment!/1) ++ ["(version 1)", "(deny default)"]

  # A line break in a comment would start a new, uncommented rule line.
  defp comment!(text) do
    if String.match?(text, ~r/[\x00-\x1f\x7f]/) do
      raise ArgumentError, "unsafe SBPL comment: " <> inspect(text)
    end

    "; " <> text
  end

  @doc "Join rules into a profile text (duplicates removed, one final newline)."
  @spec render([String.t()]) :: String.t()
  def render(rules), do: rules |> Enum.uniq() |> Enum.join("\n") |> Kernel.<>("\n")

  @doc "(allow file-read* (subpath dir))"
  @spec read_subpath(String.t()) :: String.t()
  def read_subpath(dir), do: "(allow file-read* (subpath " <> quote!(dir) <> "))"

  @doc "(allow file-read* file-write* (literal path)) — read-write scope on exactly one file (log/socket pattern)."
  @spec read_write_literal(String.t()) :: String.t()
  def read_write_literal(path),
    do: "(allow file-read* file-write* (literal " <> quote!(path) <> "))"

  @doc "(allow file-read-metadata (literal path))"
  @spec metadata_literal(String.t()) :: String.t()
  def metadata_literal(path), do: "(allow file-read-metadata (literal " <> quote!(path) <> "))"

  @doc "(allow sysctl-read (sysctl-name name))"
  @spec sysctl(String.t()) :: String.t()
  def sysctl(name), do: "(allow sysctl-read (sysctl-name " <> quote!(name) <> "))"

  @doc "(allow sysctl-read (sysctl-name-prefix prefix))"
  @spec sysctl_prefix(String.t()) :: String.t()
  def sysctl_prefix(prefix),
    do: "(allow sysctl-read (sysctl-name-prefix " <> quote!(prefix) <> "))"

  @doc "(allow mach-lookup (global-name name))"
  @spec mach_lookup(String.t()) :: String.t()
  def mach_lookup(name), do: "(allow mach-lookup (global-name " <> quote!(name) <> "))"

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
