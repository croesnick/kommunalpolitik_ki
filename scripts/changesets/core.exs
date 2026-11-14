# Pure decisions around changesets (#538): which units a PR touches, whether
# its changesets name them, and which units get a patch because a library
# they include was bumped. No I/O here — git and files live in
# scripts/changesets.exs, so the rules are unit-tested
# (scripts/changesets/test/core_test.exs).
#
# A unit is a package from knope.toml, named by its key and located at the
# directory of its first versioned file (`apps/komki_cli/mix.exs` →
# `apps/komki_cli`). knope.toml stays the only list of units.

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
  Units whose `lib/` or `priv/` the changed files touch. Everything else
  (tests, mix.exs, docs) needs no changeset.
  """
  def touched(units, changed_files) do
    for {name, dir} <- units,
        Enum.any?(
          changed_files,
          &(String.starts_with?(&1, dir <> "/lib/") or
              String.starts_with?(&1, dir <> "/priv/"))
        ),
        do: name
  end

  @doc "Touched units that none of the PR's changesets name, sorted."
  def missing(units, changed_files, changesets) do
    named = changesets |> Enum.flat_map(&Map.keys/1) |> MapSet.new()
    units |> touched(changed_files) |> Enum.reject(&(&1 in named)) |> Enum.sort()
  end

  @doc "The project version in a mix.exs source."
  def version(mix_source) do
    case Regex.run(~r/version:\s*"(\d+\.\d+\.\d+[^"]*)"/, mix_source) do
      [_, version] -> version
      nil -> nil
    end
  end

  @doc """
  Which units include which unit as a path dependency, as
  `%{library => [dependent]}`. `mix_sources` maps unit names to their
  mix.exs source.
  """
  def dependents(units, mix_sources) do
    by_dir = Map.new(units, fn {name, dir} -> {Path.basename(dir), name} end)

    for {unit, source} <- mix_sources,
        [_, dir] <- Regex.scan(~r/path:\s*"\.\.\/([^"\/]+)"/, source),
        lib = by_dir[dir],
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
