defmodule Seatbelt.MachODeps do
  @moduledoc """
  otool-based Mach-O dependency scanner for sandbox profiles.

  From a Mach-O binary the scanner collects:

    * the declared dependencies (`otool -L`),
    * the LC_RPATH entries for @rpath resolution (`otool -l`),
    * transitive dependencies (recursive otool walk),

  and yields, per resolved dependency, the declared AND the canonical
  path directory (the path-form caveat cuts both ways: rules written
  only in canonical form do not match) plus, per dependency directory,
  its sibling `libexec` when present (the ggml backend scan location:
  the backend bundles libggml-cpu-apple_m*.so, libggml-metal.so live
  there; without it the backend registry stays empty).

  Fallback: otool missing or file unreadable -> [] (CI on Linux; the
  profile stays generatable).

  Evidence: experiment series 14 Oct 2026, exp6/exp7/exp14; consolidated
  in the llama-server confinement research report of the komki project.
  """

  alias Seatbelt

  # Dylib directories of the binary: recursive otool walk.
  # - otool -L yields the declared deps (dyld opens exactly these path forms);
  # - otool -l yields the LC_RPATH entries for @rpath resolution;
  # - transitive deps are walked too (finding: libomp via libggml-base);
  # - per resolved dep: dirname(declared) AND dirname(canonical) (path-form
  #   caveat cuts both ways — exp6: rules in canonical form only do not match);
  # - per dep directory its sibling libexec, when present (ggml puts the
  #   backend bundles there; without it the backend registry stays empty);
  # - otool missing or file unreadable: [] (CI on Linux; profile stays generatable).
  @doc """
  Dylib directories of the binary including libexec siblings; see the
  moduledoc for the methodology.
  """
  @spec dylib_dirs(String.t()) :: [String.t()]
  def dylib_dirs(bin) do
    if System.find_executable("otool") == nil or not File.exists?(bin) do
      []
    else
      # queue = [bin], visited empty — the binary is processed on the first
      # pass and only then marked visited (seed finding: a pre-seeded
      # visited skipped the root and drained the queue immediately;
      # the dep list stayed empty). Accumulators as plain lists: dialyzer
      # sees MapSet.t() in recursive positions as an opaque term with
      # diverging subtypes (call_without_opaque, verification finding);
      # the sets are tiny, uniq/sort sits at the end.
      bin
      |> dylib_walk([bin], [], [])
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

  defp dylib_walk(_bin, [], _visited, dirs), do: dirs

  defp dylib_walk(bin, [macho | queue], visited, dirs) do
    canonical_macho = Seatbelt.canonical(macho)

    if canonical_macho in visited do
      dylib_walk(bin, queue, visited, dirs)
    else
      deps = otool_deps(macho)
      rpaths = otool_rpaths(macho)

      {queue, dirs} =
        Enum.reduce(deps, {queue, dirs}, fn dep, {acc_queue, acc_dirs} ->
          dep_dirs(dep, rpaths, macho, bin, acc_queue, acc_dirs)
        end)

      dylib_walk(bin, queue, [canonical_macho | visited], dirs)
    end
  end

  defp dep_dirs(dep, rpaths, macho, bin, queue, dirs) do
    case resolve_dep(dep, rpaths, macho, bin) do
      :skip ->
        {queue, dirs}

      {:dep, declared, resolved} ->
        # Keep the raw form of the declared directory (dyld opens exactly
        # this path form — path-form caveat exp6) plus the canonical form.
        dirs = Enum.uniq([Path.dirname(declared) | dirs])

        if resolved != nil do
          dirs = Enum.uniq([Seatbelt.canonical(Path.dirname(resolved)) | dirs])
          {queue ++ [resolved], dirs}
        else
          {queue, dirs}
        end
    end
  end

  defp resolve_dep(dep, rpaths, macho, bin) do
    cond do
      String.starts_with?(dep, "@rpath/") ->
        rpath_dep(dep, rpaths, macho, bin)

      String.starts_with?(dep, "/usr/lib") or String.starts_with?(dep, "/System/Library") ->
        # The base layer covers the system houses; do not recurse either.
        :skip

      String.starts_with?(dep, "@executable_path/") or String.starts_with?(dep, "@loader_path/") ->
        loader_dep(dep, macho, bin)

      String.starts_with?(dep, "/") ->
        {:dep, dep, maybe_canonical(dep)}

      true ->
        :skip
    end
  end

  defp rpath_dep(dep, rpaths, macho, bin) do
    rest = String.replace_prefix(dep, "@rpath/", "")

    rpaths
    |> Enum.flat_map(&rpath_roots(&1, macho, bin))
    |> Enum.map(&Path.join(&1, rest))
    |> Enum.find_value(:skip, fn candidate ->
      resolved = maybe_canonical(candidate)
      resolved && {:dep, candidate, resolved}
    end)
  end

  # RPATH values are themselves loader-relative: llama.cpp 0.6.0 pins
  # "@loader_path/../lib" (review finding: without this expansion all
  # @rpath deps stay unresolved and the self-built lib tree drops out of
  # the profile). @loader_path refers to the Mach-O currently being
  # loaded, @executable_path to the root binary; lexical normalization
  # via Path.expand.
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

  defp loader_dep(dep, macho, bin) do
    rest =
      dep
      |> String.replace_prefix("@loader_path/", "")
      |> String.replace_prefix("@executable_path/", "")

    # Loader directory first, then the binary directory (@executable_path).
    candidates = [Path.join(Path.dirname(macho), rest), Path.join(Path.dirname(bin), rest)]

    Enum.find_value(candidates, :skip, fn candidate ->
      resolved = maybe_canonical(candidate)
      resolved && {:dep, candidate, resolved}
    end)
  end

  defp maybe_canonical(path) do
    if File.exists?(path), do: Seatbelt.canonical(path), else: nil
  end

  # Deps from `otool -L`: drop the header line (the binary's own name);
  # per line the first whitespace token is the declared install path.
  # otool indents dep lines with a tab — trim first, otherwise every
  # token starts with "\t" and falls through all path prefixes in
  # resolve_dep (review finding: empty dep list).
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

  # LC_RPATH entries from `otool -l`: after "cmd LC_RPATH" the "path"
  # line follows (behind cmdsize); order as printed.
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
        # Next load-command block without a found path line: back to the
        # header scan (incomplete RPATH block).
        otool_rpaths_scan([line | rest], acc)

      true ->
        # In-between field (cmdsize etc.) in the same RPATH block: keep
        # looking — the path line follows only after it (review finding:
        # an early return to the header scan skipped it and left all
        # @rpath deps unresolved).
        otool_rpath_value(rest, acc)
    end
  end

  defp rpath_value(value), do: value |> String.split(" (", parts: 2) |> List.first()

  # Sibling libexec per dep directory (ggml backend scan location); both
  # path forms stay when canonical and declared diverge.
  defp libexec_forms(dirs) do
    (dirs ++ Enum.flat_map(dirs, &dir_libexec_forms/1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp dir_libexec_forms(dir) do
    declared = Path.join(Path.dirname(dir), "libexec")
    sibling = Seatbelt.canonical(declared)

    if File.exists?(sibling) do
      Enum.uniq([sibling, declared])
    else
      []
    end
  end
end
