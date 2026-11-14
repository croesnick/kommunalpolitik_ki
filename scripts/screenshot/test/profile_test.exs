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
    programs: ["/Users/u/.local/share/komki-tools/cache/esbuild-0.25.4"],
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

  # Real directories under a temp base stand in for /opt/homebrew (#533),
  # so the checks run without otool and without Homebrew (CI on Linux).
  describe "dylib_dirs/3" do
    setup do
      base =
        Path.join(System.tmp_dir!(), "dylib-#{System.unique_integer([:positive])}")
        |> tap(&File.mkdir_p!/1)
        |> Seatbelt.canonical()

      on_exit(fn -> File.rm_rf!(base) end)

      dir = fn rel -> base |> Path.join(rel) |> tap(&File.mkdir_p!/1) end
      cellar = dir.("homebrew/Cellar/sqlcipher/4.20.0/lib")
      File.mkdir_p!(Path.join(base, "homebrew/opt/sqlcipher"))
      opt = Path.join(base, "homebrew/opt/sqlcipher/lib")
      File.ln_s!(cellar, opt)

      %{
        base: base,
        roots: [Path.join(base, "homebrew")],
        cellar: cellar,
        opt: opt,
        outside: dir.("outside"),
        worktree: dir.("worktree")
      }
    end

    test "linked and kernel path of a Homebrew library both pass", c do
      assert Profile.dylib_dirs([c.opt], [c.worktree], c.roots) ==
               {:ok, Enum.sort([c.cellar, c.opt])}
    end

    test "a missing directory is dropped, e.g. a CI install name", c do
      ci = "/Users/runner/work/exqlite/exqlite/_build/prod/lib/exqlite/priv"
      gone = Path.join(c.base, "homebrew/gone")

      assert Profile.dylib_dirs([ci, gone], [c.worktree], c.roots) == {:ok, []}
    end

    test "a directory outside the roots is refused", c do
      assert Profile.dylib_dirs([c.outside], [c.worktree], c.roots) == {:error, c.outside}
    end

    test "`..` out of a root is refused", c do
      sneaky = Path.join(c.base, "homebrew/../outside")
      assert Profile.dylib_dirs([sneaky], [c.worktree], c.roots) == {:error, c.outside}
    end

    test "`..` inside a root reaches the profile resolved, never as text", c do
      detour = Path.join(c.base, "homebrew/Cellar/../opt/sqlcipher/lib")

      assert Profile.dylib_dirs([detour], [c.worktree], c.roots) ==
               {:ok, Enum.sort([c.cellar, c.opt])}
    end

    test "a symlink from the worktree to outside is refused", c do
      link = Path.join(c.worktree, "lib")
      File.ln_s!(c.outside, link)

      assert Profile.dylib_dirs([link], [c.worktree], c.roots) == {:error, c.outside}
    end

    test "a neighbour sharing a root's prefix is refused", c do
      evil = Path.join(c.base, "homebrew-evil") |> tap(&File.mkdir_p!/1)
      assert Profile.dylib_dirs([evil], [c.worktree], c.roots) == {:error, evil}
    end

    test "the linked path must pass as well, not only its target", c do
      link = Path.join(c.outside, "lib")
      File.ln_s!(c.cellar, link)

      assert Profile.dylib_dirs([link], [c.worktree], c.roots) == {:error, link}
    end

    test "directories inside the own roots need no rule", c do
      own = Path.join(c.worktree, "_build/dev/lib/exqlite/priv") |> tap(&File.mkdir_p!/1)
      assert Profile.dylib_dirs([own], [c.worktree], c.roots) == {:ok, []}
    end

    test "the default roots are package managers and the system" do
      assert Profile.dylib_roots() == ~w(/opt/homebrew /usr/local /usr/lib /System/Library)
    end
  end
end
