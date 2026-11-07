# elixir scripts/dev_loop/test/herdr_live_test.exs
#
# Runs DevLoop.Herdr against the Herdr desktop app this terminal belongs to:
# real tabs open and close in the person's window for a few seconds. Outside
# a Herdr terminal (CI, a plain shell) every test is skipped.

ExUnit.start()
Code.require_file("../herdr.exs", __DIR__)

defmodule DevLoop.HerdrLiveTest do
  use ExUnit.Case, async: false

  alias DevLoop.Herdr

  @space Herdr.space()
  if is_nil(@space), do: @moduletag(:skip)

  setup do
    dir = Path.join(System.tmp_dir!(), "dev-loop-herdr-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    log = Path.join(dir, "stage.jsonl")

    File.write!(
      log,
      ~s({"type":"system","subtype":"init","model":"probe-model","cwd":"/probe"}\n)
    )

    on_exit(fn -> File.rm_rf!(dir) end)
    %{log: log, name: "probe-#{System.unique_integer([:positive])}"}
  end

  defp tabs, do: for(s <- app_ls(), s["id"] == @space, t <- s["tabs"], do: t["name"])

  defp app_ls do
    {out, 0} = System.cmd("herdr-app", ["ls"])
    JSON.decode!(out)["spaces"]
  end

  # How Herdr's window sees the terminal: its agent list reads these fields.
  defp window_entry(name) do
    Enum.find_value(app_ls(), fn s ->
      Enum.find_value(s["tabs"], fn t -> Enum.find(t["terminals"], &(&1["name"] == name)) end)
    end)
  end

  defp viewers do
    {out, 0} = System.cmd("hc", ~w(ls --json --label dev-loop=viewer))
    for t <- JSON.decode!(out)["terminals"], do: t["name"]
  end

  defp eventually(fun, tries \\ 25) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(200) && eventually(fun, tries - 1)
    end
  end

  test "a stage gets a tab that renders its log, counts as a working agent and is gone afterwards",
       ctx do
    result =
      Herdr.watch(
        @space,
        ctx.name,
        ctx.log,
        fn ->
          assert ctx.name in tabs()

          assert eventually(fn ->
                   {screen, 0} = System.cmd("hc", ["read", ctx.name, "--lines", "5"])
                   screen =~ "▶ probe-model · /probe"
                 end)

          assert eventually(fn ->
                   {out, 0} = System.cmd("hc", ["get", ctx.name, "--json"])
                   JSON.decode!(out)["status"]["state"] == "working"
                 end)

          assert eventually(fn ->
                   match?(
                     %{"status" => "working", "app" => "claude-code"},
                     window_entry(ctx.name)
                   )
                 end)

          :stage_result
        end,
        &flunk/1
      )

    assert result == :stage_result
    assert eventually(fn -> ctx.name not in tabs() and ctx.name not in viewers() end)
  end

  test "the tab closes even when the stage raises", ctx do
    assert_raise RuntimeError, fn ->
      Herdr.watch(@space, ctx.name, ctx.log, fn -> raise "stage crashed" end, &flunk/1)
    end

    assert eventually(fn -> ctx.name not in viewers() end)
  end

  test "a run killed mid-stage leaves its tab, the next run's sweep ends it", ctx do
    herdr = Path.expand("../herdr.exs", __DIR__)

    {_, 1} =
      System.cmd("elixir", [
        "-e",
        """
        Code.require_file(#{inspect(herdr)})
        DevLoop.Herdr.watch(#{inspect(@space)}, #{inspect(ctx.name)}, #{inspect(ctx.log)},
          fn -> System.halt(1) end, &IO.puts/1)
        """
      ])

    assert ctx.name in viewers()
    Herdr.sweep(&flunk/1)
    assert eventually(fn -> ctx.name not in viewers() and ctx.name not in tabs() end)
  end

  test "outside a Herdr terminal there is no space" do
    id = System.get_env("HC_TERMINAL_ID")
    System.delete_env("HC_TERMINAL_ID")

    try do
      assert Herdr.space() == nil
    after
      System.put_env("HC_TERMINAL_ID", id)
    end
  end

  test "without hc and herdr-app there is no space, and nothing crashes" do
    path = System.get_env("PATH")
    System.put_env("PATH", "/usr/bin:/bin")

    try do
      assert Herdr.space() == nil
    after
      System.put_env("PATH", path)
    end
  end
end
