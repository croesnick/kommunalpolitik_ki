# The dev loop's only contact with herdr (#389). When the script runs in a
# herdr pane, every agent stage gets a sibling viewer pane that renders the
# stage's stream-json log live (viewer.jq) and shows up as a working agent;
# notifications go to herdr as well.
#
# Observation only: the agents stay headless child processes of the script.
# agent.exs reaches this module through `ctx.watch` and does not know about
# herdr. Every herdr call is best effort: a failure is logged and never stops
# the loop.

defmodule DevLoop.Herdr do
  @moduledoc false

  @viewer Path.expand("viewer.jq", __DIR__)
  @source "dev-loop"
  # Viewer panes carry this label prefix, so a later run can find and close
  # the ones a killed run left behind (sweep/1).
  @prefix "dev-loop · "

  def active?, do: System.get_env("HERDR_ENV") == "1" and System.get_env("HERDR_PANE_ID") != nil

  @doc "Runs `fun` while a viewer pane shows `stage_log`; returns what `fun` returns."
  def watch(label, stage_log, fun, log) do
    pane = open(@prefix <> label, stage_log, log)

    try do
      fun.()
    after
      close(pane)
    end
  end

  @doc "Closes viewer panes of earlier runs."
  def sweep(log) do
    case cmd(~w(pane list)) do
      {:ok, %{"result" => %{"panes" => panes}}} ->
        for %{"pane_id" => pane, "label" => @prefix <> _} <- panes, do: close(pane)

      error ->
        log.("herdr: Panes nicht lesbar: #{inspect(error)}")
    end
  end

  def notify(title, body), do: cmd(["notification", "show", title, "--body", body])

  def viewer_command(stage_log),
    do: "tail -n +1 -F #{shell_quote(stage_log)} | jq -rR --unbuffered -f #{shell_quote(@viewer)}"

  defp open(label, stage_log, log) do
    split =
      ~w(pane split --pane #{System.get_env("HERDR_PANE_ID")} --direction right --no-focus) ++
        ["--cwd", Path.dirname(stage_log)]

    case cmd(split) do
      {:ok, %{"result" => %{"pane" => %{"pane_id" => pane}}}} ->
        # Label first: a pane that sweep/1 can find never leaks.
        with {:ok, _} <- cmd(["pane", "rename", pane, label]),
             {:ok, _} <- cmd(["pane", "run", pane, viewer_command(stage_log)]),
             {:ok, _} <-
               cmd(
                 ~w(pane report-agent #{pane} --source #{@source} --agent claude --state working) ++
                   ["--message", label]
               ) do
          pane
        else
          error -> fail(log, error, pane)
        end

      error ->
        fail(log, error, nil)
    end
  end

  defp fail(log, error, pane) do
    log.("herdr: Viewer-Pane nicht geöffnet: #{inspect(error)}")
    close(pane)
    nil
  end

  defp close(nil), do: :ok
  defp close(pane), do: cmd(["pane", "close", pane])

  # Control commands answer with JSON; a command without an answer is fine.
  defp cmd(args) do
    case System.cmd("herdr", args, stderr_to_stdout: true) do
      {out, 0} ->
        case JSON.decode(out) do
          {:ok, json} -> {:ok, json}
          _ -> {:ok, nil}
        end

      {out, status} ->
        {:error, status, String.trim(out)}
    end
  end

  defp shell_quote(s), do: "'" <> String.replace(s, "'", ~S('\'')) <> "'"
end
