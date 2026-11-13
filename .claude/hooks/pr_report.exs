# PreToolUse hook (#462): `gh pr create` goes through only with a Prüfbericht
# for the current head in the PR body (docs/agents/lane-protocol.md). The hook
# checks the form; whether the evidence holds is the reviewer's job (#463).
#
#   elixir .claude/hooks/pr_report.exs run   # reads the hook JSON on stdin

defmodule PrReport do
  @required [
    {~r/^\#{2,3} Prüfbericht\s*$/m, "Überschrift „Prüfbericht“"},
    {~r/\|\s*Prüfpunkt\s*\|\s*Ergebnis\s*\|\s*Nachweis\s*\|/,
     "Tabelle „Prüfpunkt | Ergebnis | Nachweis“"},
    {~r/Entscheidungen, die die Umsetzung selbst getroffen hat/,
     "Abschnitt „Entscheidungen, die die Umsetzung selbst getroffen hat“"}
  ]

  # `gh pr create` or its alias `gh pr new`, with flags such as `-R <repo>`
  # between the words; `gh pr list --search new` does not count.
  @flags "(?:\\s+-{1,2}[\\w-]+(?:[=\\s]+[^-\\s]\\S*)?)*"
  @create Regex.compile!("\\bgh#{@flags}\\s+pr#{@flags}\\s+(?:create|new)\\b")

  def main do
    input = :stdio |> IO.read(:eof) |> JSON.decode!()
    IO.write(run(input))
  end

  @doc "Returns the hook's stdout: empty to let the call pass, a deny decision otherwise."
  def run(input) do
    command = get_in(input, ["tool_input", "command"]) || ""
    cwd = input["cwd"] || File.cwd!()

    if command =~ @create do
      case missing(command <> "\n" <> body_file(command, cwd), head(cwd)) do
        [] -> ""
        gaps -> deny(gaps)
      end
    else
      ""
    end
  end

  @doc "What the PR body lacks: the report's parts and the current head commit."
  def missing(body, head) do
    parts = for {pattern, label} <- @required, not (body =~ pattern), do: label

    if head && String.contains?(body, String.slice(head, 0, 7)),
      do: parts,
      else: parts ++ ["der aktuelle Head `#{String.slice(head || "?", 0, 7)}` („Gilt für …“)"]
  end

  defp deny(gaps) do
    reason =
      "PR ohne vollständigen Prüfbericht. Es fehlt: #{Enum.join(gaps, "; ")}. " <>
        "Lass ihn von einem frischen Subagent schreiben (docs/agents/lane-protocol.md, Prüfbericht) " <>
        "und setz ihn unter „## Evidence“ in den PR-Text."

    JSON.encode!(%{
      hookSpecificOutput: %{
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason
      }
    })
  end

  defp body_file(command, cwd) do
    with [_, path] <- Regex.run(~r/(?:--body-file|-F)[=\s]+("[^"]+"|'[^']+'|\S+)/, command),
         {:ok, text} <-
           path |> String.trim("\"") |> String.trim("'") |> Path.expand(cwd) |> File.read() do
      text
    else
      _ -> ""
    end
  end

  defp head(cwd) do
    case System.cmd("git", ~w(rev-parse HEAD), cd: cwd, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end
end

if System.argv() == ["run"], do: PrReport.main()
