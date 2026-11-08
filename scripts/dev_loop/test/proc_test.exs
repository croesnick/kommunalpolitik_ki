# elixir scripts/dev_loop/test/proc_test.exs

ExUnit.start()
Code.require_file("../proc.exs", __DIR__)

defmodule DevLoop.ProcTest do
  use ExUnit.Case, async: true

  alias DevLoop.Proc

  defp sh(script, opts) do
    dir = Path.join(System.tmp_dir!(), "dev-loop-proc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    Proc.run(
      "sh",
      ["-c", script],
      Keyword.merge([cd: dir, timeout_ms: 30_000, log: Path.join(dir, "p.log")], opts)
    )
  end

  describe "idle" do
    test "ends a silent program at the idle limit" do
      assert {:idle, []} = sh("sleep 5", idle_ms: 500)
    end

    test "steady output keeps the program alive" do
      assert {:ok, ["x", "x"]} = sh("echo x; sleep 0.3; echo x", idle_ms: 5000)
    end

    test "without idle_ms only the deadline holds" do
      assert {:timeout, _} = sh("sleep 10", timeout_ms: 1000)
    end
  end
end
