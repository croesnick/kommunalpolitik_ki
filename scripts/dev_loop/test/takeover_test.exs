# elixir scripts/dev_loop/test/takeover_test.exs
#
# Takeover without an account: a fake `claude` on PATH stands in for the
# headless session and records the arguments it was started with.

ExUnit.start()
for file <- ~w(core proc agent), do: Code.require_file("../#{file}.exs", __DIR__)

defmodule DevLoop.TakeoverTest do
  use ExUnit.Case, async: false

  alias DevLoop.{Agent, Proc}

  setup do
    dir = Path.join(System.tmp_dir!(), "dev-loop-takeover-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "bin"))
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp proc(dir, script, opts) do
    Proc.run(
      "sh",
      ["-c", script],
      [cd: dir, timeout_ms: 30_000, log: Path.join(dir, "p.log")] ++ opts
    )
  end

  describe "Proc cancel" do
    test "ends the program within about a second, also while it keeps printing", %{dir: dir} do
      flag = Path.join(dir, "flag")
      started = System.monotonic_time(:millisecond)
      Task.start(fn -> Process.sleep(1500) && File.write!(flag, "") end)

      assert {:cancelled, lines} =
               proc(dir, "echo $$ > pid; while :; do echo tick; sleep 0.1; done",
                 cancel: fn -> File.exists?(flag) end
               )

      assert System.monotonic_time(:millisecond) - started < 4000
      assert "tick" in lines
      pid = File.read!(Path.join(dir, "pid")) |> String.trim()
      Process.sleep(200)
      assert {_, 1} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)
    end

    test "without cancel a program runs to its end", %{dir: dir} do
      assert {:ok, ["a", "b"]} = proc(dir, "echo a; sleep 1.2; echo b", [])
      assert {:error, 3, []} = proc(dir, "exit 3", [])
    end

    test "the deadline still holds", %{dir: dir} do
      assert {:timeout, _} =
               Proc.run("sh", ["-c", "sleep 30"],
                 cd: dir,
                 timeout_ms: 1500,
                 log: Path.join(dir, "p.log")
               )
    end
  end

  describe "Agent takeover" do
    # Prints stream-json like a headless session and works until it is ended.
    @fake_claude """
    #!/bin/sh
    printf '%s\\n' "$@" > "$FAKE_ARGS"
    echo '{"type":"system","subtype":"init","model":"fake","cwd":"x"}'
    while :; do sleep 0.1; done
    """

    setup %{dir: dir} do
      fake = Path.join([dir, "bin", "claude"])
      File.write!(fake, @fake_claude)
      File.chmod!(fake, 0o755)
      path = System.get_env("PATH")
      args_env = System.get_env("FAKE_ARGS")
      System.put_env("PATH", Path.join(dir, "bin") <> ":" <> path)
      System.put_env("FAKE_ARGS", Path.join(dir, "args"))

      on_exit(fn ->
        System.put_env("PATH", path)

        if args_env,
          do: System.put_env("FAKE_ARGS", args_env),
          else: System.delete_env("FAKE_ARGS")
      end)

      test = self()
      takeover_file = Path.join(dir, "TAKEOVER")

      ctx = %{
        stop_file: Path.join(dir, "STOP"),
        takeover_file: takeover_file,
        logs: dir,
        stamp: fn -> "000000" end,
        log: fn _ -> :ok end,
        stage_timeout_ms: 30_000,
        account: :claude,
        watch: fn _name, _log, fun -> fun.() end,
        take_over: fn name, cwd, command -> send(test, {:take_over, name, cwd, command}) end
      }

      %{ctx: ctx, cwd: Path.join(dir, "loop-7")}
    end

    test "the takeover file ends the session and continues it under the same id", ctx do
      Task.start(fn -> Process.sleep(1200) && File.write!(ctx.ctx.takeover_file, "") end)

      assert {:taken_over, text} = Agent.run(:implement, "Auftrag", ctx.cwd, ctx.ctx)

      args = File.read!(Path.join(ctx.dir, "args")) |> String.split("\n", trim: true)
      session = Enum.at(args, Enum.find_index(args, &(&1 == "--session-id")) + 1)
      assert session =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

      assert_received {:take_over, "loop-7-implement-claude-hand", cwd, command}
      assert cwd == ctx.cwd
      assert command =~ "--resume '#{session}'"
      assert command =~ "'--model' 'claude-sonnet-5-5'"
      assert text =~ "Session `#{session}`"
      assert text =~ "claude --resume #{session}"
      # One request takes over one stage.
      refute File.exists?(ctx.ctx.takeover_file)
    end
  end

  describe "Agent metrics" do
    # Prints stream-json with a result event and exits: a finished stage.
    @result_claude """
    #!/bin/sh
    echo '{"type":"system","subtype":"init","model":"fake","cwd":"x"}'
    echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"duration_ms":120000,"usage":{"input_tokens":100,"output_tokens":7}}'
    """

    setup %{dir: dir} do
      File.mkdir_p!(Path.join(dir, "bin"))
      fake = Path.join([dir, "bin", "claude"])
      File.write!(fake, @result_claude)
      File.chmod!(fake, 0o755)
      path = System.get_env("PATH")
      System.put_env("PATH", Path.join(dir, "bin") <> ":" <> path)
      on_exit(fn -> System.put_env("PATH", path) end)

      ctx = %{
        stop_file: Path.join(dir, "STOP"),
        takeover_file: Path.join(dir, "TAKEOVER"),
        logs: dir,
        stamp: fn -> "000000" end,
        log: fn _ -> :ok end,
        stage_timeout_ms: 30_000,
        account: :claude,
        watch: fn _name, _log, fun -> fun.() end,
        take_over: fn _name, _cwd, _command -> :ok end
      }

      %{ctx: ctx, cwd: Path.join(dir, "loop-7")}
    end

    test "a finished session writes one metrics line", ctx do
      assert {:ok, _} = Agent.run(:implement, "Auftrag", ctx.cwd, ctx.ctx)

      [line] =
        Path.join(ctx.dir, "metrics.jsonl") |> File.read!() |> String.split("\n", trim: true)

      assert {:ok, m} = JSON.decode(line)

      assert m == %{
               "stage" => "implement",
               "issue" => 7,
               "account" => "claude",
               "turns" => 3,
               "duration_ms" => 120_000,
               "tokens_in" => 100,
               "tokens_out" => 7
             }
    end
  end

  describe "resume command" do
    test "tt reads its token when the command runs, never carries it" do
      command = Agent.resume_command(:tt, "s-1", ["--effort", "max"])

      assert command =~ "CLAUDE_CONFIG_DIR='#{Path.expand("~/.claude-tt")}'"

      assert command =~
               ~s[ANTHROPIC_AUTH_TOKEN="$('#{Path.expand("~/.claude-tt/anthropic-token.sh")}')"]

      assert command =~
               "--resume 's-1' '--permission-mode' 'auto' '--strict-mcp-config' '--settings'"

      assert command =~ "'--effort' 'max'"
    end

    test "the claude account sets no account variables" do
      command = Agent.resume_command(:claude, "s-2", [])
      refute command =~ "CLAUDE_CONFIG_DIR"
      refute command =~ "ANTHROPIC_AUTH_TOKEN"
    end
  end
end
