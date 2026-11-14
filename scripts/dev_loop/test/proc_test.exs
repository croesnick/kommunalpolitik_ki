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

    test "steady output resets the idle clock" do
      assert {:ok, lines} = sh("for i in 1 2 3 4 5 6; do echo x; sleep 1; done", idle_ms: 5000)
      assert lines == ["x", "x", "x", "x", "x", "x"]
    end

    test "without idle_ms only the deadline holds" do
      assert {:timeout, _} = sh("sleep 10", timeout_ms: 1000)
    end
  end

  describe "finish_on" do
    test "a matching line ends the program at once, well before its end" do
      assert {:ok, [line]} =
               sh(~s(echo '{"type":"result","is_error":false}'; sleep 30),
                 finish_on: ~s({"type":"result"),
                 timeout_ms: 10_000
               )

      assert line =~ ~s({"type":"result")
    end

    test "without finish_on the program runs to its end" do
      assert {:ok, ["x"]} = sh("echo x; sleep 1", finish_on: "never-matches")
    end
  end
end
