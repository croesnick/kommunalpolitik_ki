# Changesets around knope (#538). Rules: docs/agents/changesets.md.
#
#     elixir scripts/changesets.exs check <base-ref>   # CI gate of a PR
#     elixir scripts/changesets.exs cascade            # after knope prepare-release
#     elixir scripts/changesets.exs bumped             # "unit version" per bumped unit
#
# check: fails when the PR changes lib/ or priv/ of a unit from knope.toml
# and none of the changesets the PR adds names that unit. Also fails on a
# changeset that knope could not read (unknown unit, bad level). The label
# `ohne-changeset` skips the gate in the workflow, not here.
#
# cascade: compares each unit's mix.exs version against HEAD. For every unit
# that includes a bumped library as a path dependency and was not bumped
# itself, it writes `.changeset/kaskade-<unit>.md` with a patch. The
# workflow then runs `knope prepare-release` a second time. Libraries do not
# depend on each other today, so one pass reaches the fixpoint; the workflow
# runs `cascade` again and fails if it writes another changeset.
#
# bumped: the units whose version differs from HEAD, for the Version PR's
# title.

Code.require_file("changesets/core.exs", __DIR__)

defmodule Changesets do
  @moduledoc false

  alias Changesets.Core

  @dir ".changeset"

  def main(["check", base]), do: check(base)
  def main(["cascade"]), do: cascade()
  def main(["bumped"]), do: Enum.each(bumped(units()), fn {u, v} -> IO.puts("#{u} #{v}") end)

  def main(_) do
    IO.puts(:stderr, "Aufruf: elixir scripts/changesets.exs check <base-ref> | cascade | bumped")
    System.halt(2)
  end

  defp check(base) do
    units = units()
    changed = git!(~w(diff --name-only --diff-filter=ACMR #{base}...HEAD)) |> lines()
    deleted = git!(~w(diff --name-only --diff-filter=D #{base}...HEAD)) |> lines()
    files = Enum.filter(changed, &changeset_file?/1)

    parsed = for file <- files, do: {file, Core.parse_changeset(File.read!(file))}

    errors =
      for {file, result} <- parsed, error <- changeset_errors(units, result) do
        "#{file}: #{error}"
      end

    changesets = for {_file, {:ok, changeset}} <- parsed, do: changeset
    missing = Core.missing(units, changed ++ deleted, changesets)

    errors =
      errors ++
        Enum.map(missing, fn unit ->
          "#{unit}: lib/ oder priv/ geändert, aber kein Changeset nennt die Einheit"
        end)

    case errors do
      [] ->
        IO.puts("Changesets ok (#{length(files)} im PR).")

      errors ->
        IO.puts(:stderr, Enum.join(errors, "\n"))

        IO.puts(:stderr, """

        Spürbare Änderungen brauchen ein Changeset unter .changeset/ (docs/agents/changesets.md).
        Ist die Änderung für Nutzende nicht spürbar: Label `ohne-changeset` setzen und im
        Prüfbericht begründen.\
        """)

        System.halt(1)
    end
  end

  defp changeset_errors(_units, {:error, reason}), do: [reason]

  defp changeset_errors(units, {:ok, changeset}) do
    case Core.unknown(units, changeset) do
      [] ->
        []

      names ->
        [
          "unbekannte Einheit #{Enum.join(names, ", ")} (bekannt: #{Enum.join(Enum.sort(Map.keys(units)), ", ")})"
        ]
    end
  end

  defp cascade do
    units = units()
    plan = Core.cascade(Core.dependents(units, mix_sources(units)), bumped(units))
    File.mkdir_p!(@dir)

    for {unit, libs} <- plan do
      path = Path.join(@dir, "kaskade-#{unit}.md")
      File.write!(path, Core.cascade_changeset(unit, libs))

      IO.puts(
        "#{path}: #{unit} patch, enthält " <>
          Enum.map_join(libs, ", ", fn {l, v} -> "#{l} #{v}" end)
      )
    end

    if plan == [], do: IO.puts("Keine Kaskade nötig.")
  end

  defp units, do: Core.units(File.read!("knope.toml"))

  defp mix_sources(units),
    do: Map.new(units, fn {name, dir} -> {name, File.read!(Path.join(dir, "mix.exs"))} end)

  # Units whose mix.exs version in the working tree differs from HEAD, as
  # `%{unit => new_version}`.
  defp bumped(units) do
    sources = mix_sources(units)

    for {name, dir} <- units,
        now = Core.version(sources[name]),
        now != Core.version(git!(["show", "HEAD:" <> Path.join(dir, "mix.exs")])),
        into: %{},
        do: {name, now}
  end

  defp changeset_file?(path),
    do: Path.dirname(path) == @dir and Path.extname(path) == ".md"

  defp lines(out), do: String.split(out, "\n", trim: true)

  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {out, 0} -> out
      {out, code} -> raise "git #{Enum.join(args, " ")} endete mit #{code}: #{out}"
    end
  end
end

Changesets.main(System.argv())
