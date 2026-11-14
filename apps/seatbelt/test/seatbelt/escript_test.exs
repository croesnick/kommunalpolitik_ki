defmodule Seatbelt.EscriptTest do
  @moduledoc """
  Escript/BEAM runtime layer: byte golden for the deterministic core
  (crypto wildcard finds nothing for a nonexistent root — no host
  dependencies), Burrito switch, determinism.
  """

  use ExUnit.Case, async: true

  alias Seatbelt.{Escript, SBPL, TestSupport}

  @golden Path.join([__DIR__, "..", "fixtures", "escript-runtime.sb"])
  @root "/opt/erl"
  @escript "/opt/app/tool/bin/tool.escript"

  # Byte golden: fixed inputs -> identical text. SEATBELT_UPDATE_GOLDEN=1
  # rewrites the fixture (deliberate changes only, then review the diff).
  test "runtime/2 golden (byte-exact)" do
    text = SBPL.render(Escript.runtime(@root, @escript))

    if System.get_env("SEATBELT_UPDATE_GOLDEN") do
      File.write!(@golden, text)
    end

    assert text == File.read!(@golden)
  end

  test "runtime/2: deterministic" do
    assert SBPL.render(Escript.runtime(@root, @escript)) ==
             SBPL.render(Escript.runtime(@root, @escript))
  end

  test "runtime_for/3: nil burrito is exactly runtime/2" do
    assert SBPL.render(Escript.runtime_for(@root, @escript, nil)) ==
             SBPL.render(Escript.runtime(@root, @escript))
  end

  test "runtime_for/3: burrito layer adds the wrapper rules" do
    text =
      SBPL.render(
        Escript.runtime_for(@root, @escript, %{
          wrapper: "/opt/app/tool",
          runtime_root: "/opt/app/.burrito/runtime"
        })
      )

    assert text =~ "(allow process-exec (literal \"/opt/app/tool\"))"
    assert text =~ "(allow file-write-create (literal \"/opt/app/.burrito/runtime\"))"
    assert text =~ "(allow file-read* (literal \"/opt/app/.burrito\"))"

    assert text =~
             "(allow file-write-data (literal \"/opt/app/.burrito/runtime/releases/COOKIE\"))"
  end

  test "runtime/2: crypto NIF wildcard finds nothing for a nonexistent root" do
    # No dylib lines and no crypto comment in the golden case.
    text = SBPL.render(Escript.runtime("/definitely/not/erlang", @escript))

    refute text =~ "crypto NIF"
    assert text =~ "(allow file-read* (literal \"#{@escript}\"))"
  end

  test "runtime/2: unscannable crypto NIF keeps the profile generable" do
    dir = TestSupport.tmp_area!("escript-crypto")

    # Fake crypto NIF layout <root>/lib/crypto-*/priv/lib/crypto.so with a
    # non-Mach-O file: the otool walk yields [] without crashing, the
    # profile stays generable and simply has no crypto dylib lines.
    root = Path.join(dir, "erlang")
    nif = Path.join([root, "lib", "crypto-1.3", "priv", "lib", "crypto.so"])
    File.mkdir_p!(Path.dirname(nif))
    File.write!(nif, "#!/bin/sh\n")

    text = SBPL.render(Escript.runtime(root, Path.join(dir, "tool.escript")))

    refute text =~ "crypto NIF"
  end

  test "log_rules/1: read-write scope on exactly the log file" do
    assert Escript.log_rules("/var/log/tool.log") == [
             "; Log (stderr redirect; write scope is exactly this file)",
             "(allow file-read* file-write* (literal \"/var/log/tool.log\"))"
           ]
  end

  # Real runtime (needs otool AND a crypto NIF in the running OTP with
  # dylibs outside the root — the Homebrew-OpenSSL case; skips elsewhere).
  # The crypto layer then has subpath rules and ancestor metadata.
  @real_root to_string(:code.root_dir())
  @crypto_so List.first(
               Path.wildcard(
                 Path.join([@real_root, "lib", "crypto-*", "priv", "lib", "crypto.so"])
               )
             )

  if System.find_executable("otool") != nil and @crypto_so != nil do
    test "runtime/2: real erlang root yields crypto NIF dylib rules" do
      text = SBPL.render(Escript.runtime(@real_root, Path.join([@real_root, "bin", "escript"])))

      assert text =~ "crypto NIF"
      # The crypto NIF is inside the root: the walk only reports dylib
      # dirs OUTSIDE it, and every rule line carries a real directory.
      assert text =~ "(allow file-read* (subpath \""
    end
  end
end
