# Pure decisions around changesets (#538): which units a PR touches, whether
# its changesets name them, and which units get a patch because a library
# they include was bumped. No I/O here — git and files live in
# scripts/changesets.exs, so the rules are unit-tested
# (scripts/changesets/test/core_test.exs).
#
# A unit is a package from knope.toml, named by its key and located at the
# directory of its first versioned file (`apps/komki_cli/mix.exs` →
# `apps/komki_cli`). knope.toml stays the only list of units. A unit's
# bundle adds the apps it ships via path dependencies (`bundles/2`).

defmodule Changesets.Core do
  @moduledoc false

  @levels ~w(major minor patch)

  @doc "Units from knope.toml as `%{name => app_dir}`."
  def units(knope_toml) do
    knope_toml
    |> String.split(~r/^\[/m)
    |> Enum.flat_map(fn section ->
      with [_, name] <- Regex.run(~r/\Apackages\.([\w-]+)\]/, section),
           [_, path] <- Regex.run(~r/path\s*=\s*"([^"]+)"/, section) do
        [{name, Path.dirname(path)}]
      else
        _ -> []
      end
    end)
    |> Map.new()
  end

  @doc """
  The frontmatter of a changeset as `%{unit => level}`. The format is
  knope's: `---`, one `unit: level` line per unit, `---`, then the text.
  """
  def parse_changeset(text) do
    with [_, front] <- Regex.run(~r/\A---\r?\n(.*?)\r?\n---/s, text),
         {:ok, pairs} <- parse_pairs(String.split(front, ~r/\r?\n/, trim: true)) do
      {:ok, Map.new(pairs)}
    else
      nil -> {:error, "kein Frontmatter zwischen zwei Zeilen `---`"}
      {:error, _} = error -> error
    end
  end

  defp parse_pairs(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      case Regex.run(~r/\A\s*"?([\w-]+)"?\s*:\s*(\w+)\s*\z/, line) do
        [_, unit, level] when level in @levels -> {:cont, {:ok, [{unit, level} | acc]}}
        _ -> {:halt, {:error, "Zeile #{inspect(line)} ist nicht `einheit: major|minor|patch`"}}
      end
    end)
  end

  @doc "Unit names a changeset uses that knope.toml does not know."
  def unknown(units, changeset), do: Map.keys(changeset) -- Map.keys(units)

  @doc """
  The apps of the workspace a unit consists of, as `%{unit => [app_dir]}`:
  its own directory plus every app it includes via runtime path dependencies,
  transitively, stopping at other units. komki is one version for the whole
  program, so a change in the mediator or a connector is a change to komki.
  `deps` maps app directories to their path dependencies (`path_deps/1`).
  """
  def bundles(units, deps) do
    unit_dirs = MapSet.new(Map.values(units))
    Map.new(units, fn {name, dir} -> {name, Enum.sort(reach([dir], deps, unit_dirs, [dir]))} end)
  end

  defp reach([], _deps, _unit_dirs, seen), do: seen

  defp reach([dir | rest], deps, unit_dirs, seen) do
    next = for dep <- Map.get(deps, dir, []), dep not in seen, dep not in unit_dirs, do: dep
    reach(rest ++ next, deps, unit_dirs, seen ++ next)
  end

  @doc """
  The runtime path dependencies in a mix.exs source, as app directories
  (`apps/<name>`). Dependencies with `only:` (test or dev tooling) are not
  part of what ships.
  """
  def path_deps(mix_source) do
    for [_, dir, rest] <- Regex.scan(~r/\{:\w+,\s*path:\s*"\.\.\/([^"\/]+)"([^}]*)\}/, mix_source),
        not String.contains?(rest, "only:"),
        do: "apps/" <> dir
  end

  @doc """
  Units whose `lib/` or `priv/` the changed files touch, in any app of their
  bundle. Everything else (tests, mix.exs, docs) needs no changeset.
  """
  def touched(bundles, changed_files) do
    for {name, dirs} <- bundles,
        Enum.any?(changed_files, fn file ->
          Enum.any?(
            dirs,
            &(String.starts_with?(file, &1 <> "/lib/") or
                String.starts_with?(file, &1 <> "/priv/"))
          )
        end),
        do: name
  end

  @doc "Touched units that none of the PR's changesets name, sorted."
  def missing(bundles, changed_files, changesets) do
    named = changesets |> Enum.flat_map(&Map.keys/1) |> MapSet.new()
    bundles |> touched(changed_files) |> Enum.reject(&(&1 in named)) |> Enum.sort()
  end

  @doc "The project version in a mix.exs source."
  def version(mix_source) do
    case Regex.run(~r/version:\s*"(\d+\.\d+\.\d+[^"]*)"/, mix_source) do
      [_, version] -> version
      nil -> nil
    end
  end

  @doc """
  Which units include which other unit, from any app of their bundle, as
  `%{library => [dependent]}`.
  """
  def dependents(units, bundles, deps) do
    unit_by_dir = Map.new(units, fn {name, dir} -> {dir, name} end)

    for {unit, dirs} <- bundles,
        dir <- dirs,
        dep <- Map.get(deps, dir, []),
        lib = unit_by_dir[dep],
        lib && lib != unit,
        reduce: %{} do
      acc -> Map.update(acc, lib, [unit], &Enum.uniq([unit | &1]))
    end
  end

  @doc """
  The cascade after `knope prepare-release`: every unit that includes a
  bumped library and was not bumped itself gets a patch naming the library
  and its new version. `bumped` maps unit names to their new version.
  Returns `[{unit, [{library, version}]}]`, one entry per unit.
  """
  def cascade(dependents, bumped) do
    for {lib, version} <- bumped,
        unit <- Map.get(dependents, lib, []),
        not Map.has_key?(bumped, unit) do
      {unit, {lib, version}}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {unit, libs} -> {unit, Enum.sort(libs)} end)
    |> Enum.sort()
  end

  @doc """
  The changeset file the cascade writes for one unit. A title without body
  becomes one bullet in knope's changelog.
  """
  def cascade_changeset(unit, libs) do
    names = Enum.map(libs, fn {lib, version} -> "#{lib} #{version}" end)

    """
    ---
    #{unit}: patch
    ---

    # Enthält #{join_german(names)}
    """
  end

  defp join_german([one]), do: one

  defp join_german(names),
    do: Enum.join(Enum.drop(names, -1), ", ") <> " und " <> List.last(names)
end
