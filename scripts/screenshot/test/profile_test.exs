# elixir scripts/screenshot/test/profile_test.exs
#
# Text-level checks of the generated profile. Whether macOS enforces it is
# measured by `elixir scripts/screenshot.exs --probe` (needs sandbox-exec).

ExUnit.start()

Kernel.ParallelCompiler.require(
  [Path.expand("../../../apps/seatbelt/lib/seatbelt.ex", __DIR__)] ++
    Path.wildcard(Path.expand("../../../apps/seatbelt/lib/seatbelt/*.ex", __DIR__)) ++
    [Path.expand("../profile.exs", __DIR__)],
  return_diagnostics: true
)

defmodule Screenshot.ProfileTest do
  use ExUnit.Case, async: true

  alias Screenshot.Profile

  @paths %{
    erlang_root: "/opt/erlang",
    elixir_root: "/opt/elixir",
    mix_archives: "/Users/u/.mix/archives",
    worktree: "/Users/u/wt",
    writable: ["/private/tmp/scratch"],
    programs: ["/Users/u/.cache/komki-screenshot/esbuild-0.25.4"],
    browser: "/Users/u/Library/Caches/ms-playwright/shell",
    dylib_dirs: ["/opt/homebrew/opt/sqlcipher/lib"],
    logs: ["/Users/u/wt/.screenshots/server.log"],
    denied: ["/Users/u/.ssh", "/Users/u/Library/Application Support/ratsprojekte"],
    hub_port: 54_321
  }

  setup_all do
    text = Profile.render(@paths)
    %{text: text, lines: String.split(text, "\n", trim: true)}
  end

  test "deny-default and deterministic", %{text: text, lines: lines} do
    assert "(deny default)" in lines
    assert text == Profile.render(@paths)
  end

  test "network only on loopback, and there only on the hub port", %{lines: lines} do
    network = Enum.filter(lines, &String.starts_with?(&1, "(allow network"))

    assert network == [
             ~s{(allow network-bind (local ip "localhost:54321"))},
             ~s{(allow network-inbound (local ip "localhost:54321"))},
             ~s{(allow network-outbound (remote ip "localhost:54321"))}
           ]

    # A (local ip …) filter on network-outbound also passes connects from
    # that port to the internet (measured with --probe, #510).
    refute Enum.any?(lines, &(&1 =~ ~r/network-outbound.*\(local /))
  end

  test "the worktree is read-only, writes stay in the named places", %{lines: lines} do
    assert ~s{(allow file-read* (subpath "/Users/u/wt"))} in lines
    refute Enum.any?(lines, &(&1 =~ ~s{file-write* (subpath "/Users/u/wt")}))

    writes =
      lines
      |> Enum.filter(&(&1 =~ ~r/^\(allow [^;]*file-write\*/))
      |> Enum.reject(&(&1 =~ "/dev/null" or &1 =~ "/dev/dtracehelper"))

    for line <- writes do
      assert Enum.any?(@paths.writable ++ @paths.logs, &String.contains?(line, &1)), line
    end
  end

  test "the read ban closes the profile, after every allow", %{lines: lines} do
    denies = Enum.filter(lines, &String.starts_with?(&1, "(deny file-read*"))
    assert length(denies) == length(@paths.denied)
    assert Enum.take(lines, -length(denies)) == denies
  end

  test "paths that could leave the string literal are refused" do
    assert_raise ArgumentError, fn ->
      Profile.render(%{@paths | worktree: ~s{/a") (allow default}})
    end
  end
end
