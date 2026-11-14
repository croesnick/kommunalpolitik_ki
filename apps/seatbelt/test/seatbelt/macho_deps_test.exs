defmodule Seatbelt.MachODepsTest do
  @moduledoc """
  Fallback behavior of the otool walk. The happy path (real Mach-O with
  dylibs) only exists on hosts with otool; it is exercised indirectly by
  the komki profile suites on macOS.
  """

  use ExUnit.Case, async: true

  alias Seatbelt.MachODeps

  test "nonexistent binary yields [] (profile stays generable)" do
    assert MachODeps.dylib_dirs("/definitely/not/a/binary") == []
  end

  test "plain file without Mach-O headers yields []" do
    dir = Seatbelt.TestSupport.tmp_area!("macho-plain")
    file = Path.join(dir, "tool")
    File.write!(file, "#!/bin/sh\n")

    # Without otool this is the [] fallback; with otool the walk over a
    # non-Mach-O file also yields []. Either way: [], never a crash.
    assert MachODeps.dylib_dirs(file) == []
  end

  # Happy path (needs otool AND a real crypto NIF in the running OTP —
  # every macOS dev host and CI-macOS runner has both; skips elsewhere).
  # The crypto NIF links OpenSSL outside the Erlang root — the canonical
  # case the walk exists for.
  @crypto_so List.first(
               Path.wildcard(
                 Path.join([
                   to_string(:code.root_dir()),
                   "lib",
                   "crypto-*",
                   "priv",
                   "lib",
                   "crypto.so"
                 ])
               )
             )

  if System.find_executable("otool") != nil and @crypto_so != nil do
    test "real Mach-O: external dylib dirs in both path forms, all existing" do
      dirs = MachODeps.dylib_dirs(@crypto_so)

      assert dirs != []

      # Declared AND canonical form (path-form caveat), unique and sorted.
      assert dirs == Enum.uniq(dirs)
      assert dirs == Enum.sort(dirs)
      assert Enum.all?(dirs, &File.dir?/1)
    end
  end
end
