defmodule KomkiPolicy.LeanSyncTest do
  @moduledoc false

  # The Lean model (lean/KomkiSpec/) mirrors these modules step by step.
  # lean/SYNC.sha256 pins the state it was last checked against, so a change
  # to them fails here until someone has looked at the Lean side
  # (lean/README.md). Behavioural agreement is the job of lean_spec_test.exs.

  use ExUnit.Case, async: true

  @app_dir Path.expand("../..", __DIR__)
  @pin_file Path.join(@app_dir, "lean/SYNC.sha256")

  test "die Lean-Spezifikation kennt den aktuellen Stand der gespiegelten Module" do
    stale =
      for line <- String.split(File.read!(@pin_file), "\n", trim: true),
          [pinned, path] = String.split(line, ~r/\s+/, parts: 2),
          sha256(Path.join(@app_dir, path)) != pinned,
          do: path

    assert stale == [], """
    Geändert seit dem letzten Abgleich mit der Lean-Spezifikation: #{Enum.join(stale, ", ")}.
    Das Lean-Modell in lean/KomkiSpec/ dagegen prüfen und anpassen (lean/README.md),
    dann in apps/komki_policy den Pin erneuern:

        shasum -a 256 lib/komki_policy/{calculus,context,derive,evaluator,json,registry,release,remedies,stand,verify}.ex > lean/SYNC.sha256
    """
  end

  defp sha256(path) do
    :sha256 |> :crypto.hash(File.read!(path)) |> Base.encode16(case: :lower)
  end
end
