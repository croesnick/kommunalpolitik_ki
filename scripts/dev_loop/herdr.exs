# The dev loop's only contact with Herdr (#389), the desktop app on top of
# herdr-core (`hc`). When the script runs in a Herdr terminal, every agent
# stage gets its own tab in that terminal's space: an hc terminal that
# renders the stage's stream-json log live (viewer.jq) and reports the
# stage's state, so Herdr lists it under Agents. The tab goes away when the
# stage ends; the log stays in the run directory.
#
# The agents stay headless child processes of the script; agent.exs reaches
# this module through `ctx.watch` and `ctx.take_over` and does not know
# about Herdr. When the person takes a stage over, its session continues
# interactively in a tab of its own (take_over/5). Every call is best
# effort: a failure is logged and never stops the loop.

defmodule DevLoop.Herdr do
  @moduledoc false

  @viewer Path.expand("viewer.jq", __DIR__)
  # Viewer terminals carry this label, so a later run can find and end the
  # ones a killed run left behind (sweep/1).
  @label "dev-loop=viewer"
  # Taken-over sessions belong to the person: sweep/1 leaves them alone.
  @takeover_label "dev-loop=takeover"

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

  @doc """
  Opens a tab in `space` that runs `command` in `cwd` and shows it; the tab
  lives until its program ends. Returns the terminal or nil.
  """
  def take_over(space, name, cwd, command, log) do
    with {terminal, tab} <- start(space, @takeover_label, name, cwd, command, log) do
      if tab, do: cmd("herdr-app", ["do", "tab.select", "--id", tab])
      terminal
    end
  end

  @doc "Ends viewer terminals of earlier runs."
  def sweep(log) do
    case cmd("hc", ~w(ls --json --label #{@label})) do
      {:ok, %{"terminals" => terminals}} -> Enum.each(terminals, &close(&1["address"]))
      error -> log.("Herdr: Viewer nicht lesbar: #{inspect(error)}")
    end
  end

  # `--arg status 1` makes the viewer report the stage's state (OSC 7501),
  # so Herdr lists the tab under Agents like a Claude Code session.
  def viewer_command(stage_log, title),
    do:
      "tail -n +1 -F #{shell_quote(stage_log)} | jq -rR --unbuffered " <>
        "--arg status 1 --arg title #{shell_quote(title)} -f #{shell_quote(@viewer)}"

  # Names are unique among live terminals, 1-32 of a-z 0-9 - _.
  def terminal_name(stage),
    do: stage |> String.downcase() |> String.replace(~r/[^a-z0-9_-]+/, "-") |> String.slice(0, 32)

  defp open(space, name, stage_log, log) do
    command = viewer_command(stage_log, name)

    with {terminal, _tab} <- start(space, @label, name, Path.dirname(stage_log), command, log),
         do: terminal
  end

  # Returns {terminal, tab | nil} or nil. --no-parent: nobody's sub-agent,
  # it gets its own tab and no notes go to the terminal that started the
  # script.
  defp start(space, label, name, cwd, command, log) do
    args =
      ~w(run --bg --json --no-parent --no-notify --rm --label #{label}) ++
        ["--label", "herdr.space=#{space}", "--name", terminal_name(name)] ++
        ["--cwd", cwd, command]

    case cmd("hc", args) do
      {:ok, %{"address" => terminal}} ->
        {terminal, name_tab(space, terminal, name)}

      error ->
        log.("Herdr: Tab nicht geöffnet: #{inspect(error)}")
        nil
    end
  end

  # Herdr makes the tab shortly after it sees the terminal and calls it by
  # its number; the stage name is more useful. Returns the tab, or nil when
  # none showed up within about two seconds (cosmetic, nothing fails).
  defp name_tab(space, terminal, name, tries \\ 10)
  defp name_tab(_space, _terminal, _name, 0), do: nil

  defp name_tab(space, terminal, name, tries) do
    with {:ok, %{"spaces" => spaces}} <- cmd("herdr-app", ["ls"]),
         tab when is_binary(tab) <- tab_of(spaces, space, terminal) do
      cmd("herdr-app", ["do", "tab.rename", "--id", tab, "--name", name])
      tab
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
