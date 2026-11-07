# The dev loop's only contact with Herdr (#389), the desktop app on top of
# herdr-core (`hc`). When the script runs in a Herdr terminal, every agent
# stage gets its own tab in that terminal's space: an hc terminal that
# renders the stage's stream-json log live (viewer.jq). The tab goes away
# when the stage ends; the log stays in the run directory.
#
# Observation only: the agents stay headless child processes of the script.
# agent.exs reaches this module through `ctx.watch` and does not know about
# Herdr. Every call is best effort: a failure is logged and never stops the
# loop.

defmodule DevLoop.Herdr do
  @moduledoc false

  @viewer Path.expand("viewer.jq", __DIR__)
  # Viewer terminals carry this label, so a later run can find and end the
  # ones a killed run left behind (sweep/1).
  @label "dev-loop=viewer"

  @doc "The Herdr space of the terminal running the script, or nil outside Herdr."
  def space do
    with id when is_binary(id) <- System.get_env("HC_TERMINAL_ID"),
         {:ok, %{"spaces" => spaces}} <- cmd("herdr-app", ["ls"]) do
      Enum.find_value(spaces, fn s ->
        if Enum.any?(s["tabs"], fn t -> Enum.any?(t["terminals"], &(&1["terminal"] == id)) end),
          do: s["id"]
      end)
    else
      _ -> nil
    end
  end

  @doc "Runs `fun` while a tab in `space` shows `stage_log`; returns what `fun` returns."
  def watch(space, name, stage_log, fun, log) do
    terminal = open(space, name, stage_log, log)

    try do
      fun.()
    after
      close(terminal)
    end
  end

  @doc "Ends viewer terminals of earlier runs."
  def sweep(log) do
    case cmd("hc", ~w(ls --json --label #{@label})) do
      {:ok, %{"terminals" => terminals}} -> Enum.each(terminals, &close(&1["address"]))
      error -> log.("Herdr: Viewer nicht lesbar: #{inspect(error)}")
    end
  end

  def viewer_command(stage_log),
    do: "tail -n +1 -F #{shell_quote(stage_log)} | jq -rR --unbuffered -f #{shell_quote(@viewer)}"

  # Names are unique among live terminals, 1-32 of a-z 0-9 - _.
  def terminal_name(stage),
    do: stage |> String.downcase() |> String.replace(~r/[^a-z0-9_-]+/, "-") |> String.slice(0, 32)

  # --no-parent: a viewer is nobody's sub-agent, it gets its own tab and no
  # notes go to the terminal that started the script.
  defp open(space, name, stage_log, log) do
    args =
      ~w(run --bg --json --no-parent --no-notify --rm --label #{@label}) ++
        ["--label", "herdr.space=#{space}", "--name", terminal_name(name)] ++
        ["--cwd", Path.dirname(stage_log), viewer_command(stage_log)]

    case cmd("hc", args) do
      {:ok, %{"address" => terminal}} ->
        name_tab(space, terminal, name)
        terminal

      error ->
        log.("Herdr: Viewer nicht geöffnet: #{inspect(error)}")
        nil
    end
  end

  # Herdr makes the tab shortly after it sees the terminal and calls it by
  # its number; the stage name is more useful. Cosmetic: after about two
  # seconds without a tab it gives up.
  defp name_tab(space, terminal, name, tries \\ 10)
  defp name_tab(_space, _terminal, _name, 0), do: :ok

  defp name_tab(space, terminal, name, tries) do
    with {:ok, %{"spaces" => spaces}} <- cmd("herdr-app", ["ls"]),
         tab when is_binary(tab) <- tab_of(spaces, space, terminal) do
      cmd("herdr-app", ["do", "tab.rename", "--id", tab, "--name", name])
    else
      _ ->
        Process.sleep(200)
        name_tab(space, terminal, name, tries - 1)
    end
  end

  defp tab_of(spaces, space, terminal) do
    for(
      %{"id" => ^space, "tabs" => tabs} <- spaces,
      tab <- tabs,
      Enum.any?(tab["terminals"], &(&1["terminal"] == terminal)),
      do: tab["id"]
    )
    |> List.first()
  end

  # With --rm the terminal is removed once it ends; kill's reply does not matter.
  defp close(nil), do: :ok
  defp close(terminal), do: cmd("hc", ["kill", terminal, "--json"])

  defp cmd(program, args) do
    case System.cmd(program, args, stderr_to_stdout: true) do
      {out, 0} -> JSON.decode(out)
      {out, status} -> {:error, status, String.trim(out)}
    end
  rescue
    error in ErlangError -> {:error, error.original}
  end

  defp shell_quote(s), do: "'" <> String.replace(s, "'", ~S('\'')) <> "'"
end
