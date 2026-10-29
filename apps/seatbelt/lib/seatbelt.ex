defmodule Seatbelt do
  @moduledoc """
  Host path helpers and profile file I/O for macOS Seatbelt (sandbox-exec)
  sandboxes.

  Seatbelt rules match kernel-canonical path forms: a rule written in
  symlink form does not match (on macOS, `/tmp` is only seen as
  `/private/tmp`). `canonical/1` is the single place where that
  kernel view is established for every path that flows into a generated
  profile.
  """

  @doc """
  Canonical form of a path: expanded, then resolved the way the kernel
  sees it (`realpath` of the deepest existing ancestor plus the remainder).
  Symlinks are resolved — on macOS this yields the `/private/...` form;
  on other hosts `/tmp/...` simply stays `/tmp/...`. The definition reads
  the file system itself, no platform switches. Idempotent.
  """
  @spec canonical(String.t()) :: String.t()
  def canonical(path) when is_binary(path) do
    path
    |> Path.expand()
    |> resolve_realpath()
  end

  # Kernel view via readlink(1) (this OTP has no :file.realpath).
  # BSD readlink (macOS) fails on missing paths, GNU allows a missing
  # last component — hence the fallback: resolve the deepest existing
  # ancestor and re-append the remainder. Without readlink the
  # resolution degrades to the expanded form.
  defp resolve_realpath(expanded) do
    if bin = System.find_executable("readlink") do
      resolve(bin, expanded)
    else
      expanded
    end
  end

  defp resolve(bin, path) do
    case System.cmd(bin, ["-f", path]) do
      {real, 0} -> String.trim_trailing(real)
      {_, _} when path == "/" -> path
      {_, _} -> Path.join(resolve(bin, Path.dirname(path)), Path.basename(path))
    end
  end

  @doc "Erlang root for an `escript` path (`<root>/bin/escript`)."
  @spec erlang_root(String.t()) :: String.t()
  def erlang_root(escript_bin), do: escript_bin |> Path.dirname() |> Path.dirname()

  @doc "Write a profile file, creating its directory (parent of the profile path)."
  @spec write!(String.t(), String.t()) :: :ok
  def write!(path, text) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
    :ok
  end
end
