defmodule Seatbelt.BootCheckTest do
  @moduledoc """
  Boot gate: the exec-error path runs everywhere; the probe paths run
  only where sandbox-exec exists (the Linux CI runner counts zero tests
  for those).
  """

  use ExUnit.Case, async: true

  alias Seatbelt.{BootCheck, TestSupport}

  test "bogus sandbox-exec: exec error, no crash" do
    dir = TestSupport.tmp_area!("bootcheck-bogus")

    result =
      BootCheck.run(Path.join(dir, "no-such-sandbox-exec"), "/dev/null", "/usr/bin/true", [])

    assert result.ok == false
    assert String.starts_with?(result.reason, "exec error")
  end

  @sandbox_exec System.find_executable("sandbox-exec")

  if @sandbox_exec != nil do
    test "allow-all profile: /usr/bin/true boots (rc0)" do
      dir = TestSupport.tmp_area!("bootcheck-allow")
      profile = Path.join(dir, "allow.sb")
      File.write!(profile, "(version 1)\n(allow default)\n")

      assert BootCheck.run(@sandbox_exec, profile, "/usr/bin/true", [], cwd: dir) == %{
               ok: true,
               reason: "rc0"
             }
    end

    test "deny-default profile: the probe fails with an rc reason" do
      dir = TestSupport.tmp_area!("bootcheck-deny")
      profile = Path.join(dir, "deny.sb")
      File.write!(profile, "(version 1)\n(deny default)\n")

      result = BootCheck.run(@sandbox_exec, profile, "/usr/bin/true", [], cwd: dir)

      assert result.ok == false
      assert String.starts_with?(result.reason, "rc=")
    end

    test "probe stderr lands in the reason excerpt" do
      dir = TestSupport.tmp_area!("bootcheck-stderr")
      profile = Path.join(dir, "allow.sb")
      File.write!(profile, "(version 1)\n(allow default)\n")

      result =
        BootCheck.run(@sandbox_exec, profile, "/bin/sh", ["-c", "echo boom >&2; exit 9"],
          cwd: dir
        )

      assert result.ok == false
      assert result.reason =~ "boom"
      assert String.starts_with?(result.reason, "rc=9")
    end
  end
end
