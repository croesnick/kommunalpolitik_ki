defmodule Seatbelt.MachODepsTest do
  @moduledoc """
  Fallback behavior of the otool walk, plus the seam contract of #474:
  load-command declarations become read scopes only when the declared
  dep resolves to an existing file and its directory sits inside the
  allowlist. The happy path (real Mach-O with dylibs) only exists on
  hosts with otool; it is exercised indirectly by the komki profile
  suites on macOS.
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

      # #474: every granted dir sits inside the default roots (package
      # managers, system) or the install prefix of the NIF itself.
      priv_dir = Path.dirname(@crypto_so)
      allowed = ["/opt/homebrew", "/usr/local", "/usr/lib", "/System/Library", priv_dir]

      assert Enum.all?(dirs, fn dir ->
               Enum.any?(allowed, &(&1 == dir or String.starts_with?(dir, &1 <> "/")))
             end)
    end
  end

  # Committed fixture, built once (recipe below): an executable whose load
  # commands declare a root-level dylib (/libfoo.dylib — no such file) and
  # an existing file outside every default root (/private/etc/hosts).
  # Before #474 the walk granted both as read scopes unchecked; for
  # /libfoo.dylib that is dirname "/", the whole file system.
  #
  #     printf 'void noop(void){}\n'         > stub.c
  #     printf 'int main(void){return 0;}\n' > main.c
  #     clang -dynamiclib stub.c -o libfoo.dylib -install_name /libfoo.dylib
  #     clang -dynamiclib stub.c -o libetc.dylib -install_name /private/etc/hosts
  #     clang main.c -o macho-fixture -L. -lfoo -letc
  #
  # The stub dylibs need not exist at scan time: otool -L lists the load
  # commands whether or not dyld could satisfy them.
  @fixture Path.expand("../fixtures/macho-fixture", __DIR__)

  if System.find_executable("otool") != nil do
    describe "grants are validated at the seam (#474)" do
      test "root-level and outside-roots declarations yield no scope" do
        assert MachODeps.dylib_dirs(@fixture) == []
      end

      test "an existing dep inside a caller-declared root is granted" do
        assert MachODeps.dylib_dirs(@fixture, ["/private/etc"]) == ["/private/etc"]
      end

      test "caller roots shallower than two segments grant nothing" do
        assert MachODeps.dylib_dirs(@fixture, ["/"]) == []
      end
    end
  end

  # The legit channel must survive #474: a <prefix>/bin build whose libs sit
  # in the sibling lib dir, reached via @rpath over @loader_path (the
  # llama.cpp release layout the komki llama profile grants; exp evidence in
  # the MachODeps moduledoc). Needs clang at test time, skips elsewhere.
  if System.find_executable("otool") != nil and System.find_executable("clang") != nil do
    test "<prefix>/bin layout: @rpath dep in the sibling lib dir is granted" do
      base = Seatbelt.canonical(Seatbelt.TestSupport.tmp_area!("macho-rpath"))
      lib_dir = Path.join(base, "lib")
      bin_dir = Path.join(base, "bin")
      File.mkdir_p!(lib_dir)
      File.mkdir_p!(bin_dir)
      stub = Path.join(base, "stub.c")
      main = Path.join(base, "main.c")
      File.write!(stub, "void noop(void){}\n")
      File.write!(main, "int main(void){return 0;}\n")

      clang = System.find_executable("clang")
      dylib = Path.join(lib_dir, "libdep.dylib")

      {_out, 0} =
        System.cmd(clang, [
          "-dynamiclib",
          stub,
          "-o",
          dylib,
          "-install_name",
          "@rpath/libdep.dylib"
        ])

      {_out, 0} =
        System.cmd(clang, [
          main,
          "-o",
          Path.join(bin_dir, "llama-shape"),
          "-L" <> lib_dir,
          "-ldep",
          "-Wl,-rpath,@loader_path/../lib"
        ])

      assert MachODeps.dylib_dirs(Path.join(bin_dir, "llama-shape")) == [lib_dir]
    end
  end
end
