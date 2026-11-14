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
      case missing(command <> "\n" <> body_file(command, cwd), head(command, cwd)) do
        [] -> ""
        gaps -> deny(gaps)
      end
    else
      ""
    end
  end

  @doc """
  What the PR body lacks: the report's parts and the head commit. `head` is
  a SHA, `{:unknown, branch}` for a `--head` that does not resolve, or nil.
  """
  def missing(body, head) do
    parts = for {pattern, label} <- @required, not (body =~ pattern), do: label

    case head do
      {:unknown, branch} ->
        parts ++ ["der Branch `#{branch}` (weder lokal noch unter origin/)"]

      sha when is_binary(sha) ->
        if String.contains?(body, String.slice(sha, 0, 7)),
          do: parts,
          else: parts ++ ["der aktuelle Head `#{String.slice(sha, 0, 7)}` („Gilt für …“)"]

      nil ->
        parts ++ ["der aktuelle Head `?` („Gilt für …“)"]
    end
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

  # The commit the PR is opened for: with `--head <branch>` (`-H`, also
  # `owner:branch`) that branch, local or under origin/ (#532), otherwise
  # HEAD of the session's directory. A branch that does not resolve yields
  # `{:unknown, branch}`, and the call is denied.
  defp head(command, cwd) do
    case head_flags(command) do
      [] -> commit("HEAD", cwd)
      flags -> flags |> List.last() |> branch_head(cwd)
    end
  end

  defp branch_head(value, cwd) do
    branch = value |> String.trim("\"") |> String.trim("'") |> String.split(":") |> List.last()

    Enum.find_value([branch, "refs/remotes/origin/#{branch}"], &commit(&1, cwd)) ||
      {:unknown, branch}
  end

  # Values of gh's own `--head`/`-H` flags (#540). One scan from the start
  # keeps the quotes in step: heredoc bodies are cut beforehand (the rest of
  # the opening line stays), escapes, quoted strings and comments are
  # skipped as a whole, and only flags after the first `gh pr create`
  # outside them count. A mention in the body or the title is thus no flag.
  #
  # Where that reading is unsure, the old one of #532 applies (first
  # `--head` anywhere), so the hook never lets more through than before: a
  # quote left open (quotes nested in "$(…)"), no call outside quoted text,
  # or quoted text that itself holds a call with `--head` (`bash -c "…"`,
  # `bash <<'EOF'`).
  @old_flag ~r/(?:--head|-H)[=\s]+("[^"]+"|'[^']+'|\S+)/
  @heredoc ~r/(<<(-)?\s*(['"]?)(\w[\w-]*)\3[^\n]*)\n(?:.*?\n)??(?(2)\t*)\4(?=\n|\)|$)/s
  @token Regex.compile!(
           ~S{\\.|\$'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|'[^']*'|(?<!\S)#[^\n]*|(["'])|(} <>
             Regex.source(@create) <>
             ~S{)|(?<!\S)(?:--head|-H)(?:=|\s+)("[^"]*"|'[^']*'|[^\s;&|)]+)}
         )

  defp head_flags(command) do
    text = Regex.replace(@heredoc, command, fn _, opening, _, _, _ -> opening end)

    bodies =
      for [all, opening | _] <- Regex.scan(@heredoc, command),
          do: String.replace_prefix(all, opening, "")

    # Token shapes: [skipped], [_, open quote], [_, "", call], [_, "", "", value].
    tokens = Regex.scan(@token, text)
    call? = &match?([_, "", _], &1)
    skipped = for [skipped] <- tokens, do: skipped

    unsure? =
      Enum.any?(tokens, &match?([_, _], &1)) or not Enum.any?(tokens, call?) or
        Enum.any?(bodies ++ skipped, &(&1 =~ @create and &1 =~ @old_flag))

    if unsure? do
      for [_, value] <- [Regex.run(@old_flag, command)], do: value
    else
      tokens
      |> Enum.drop_while(&(not call?.(&1)))
      |> Enum.flat_map(fn
        [_, "", "", value] -> [value]
        _ -> []
      end)
    end
  end

  defp commit(ref, cwd) do
    case System.cmd("git", ["rev-parse", "--verify", "--quiet", ref <> "^{commit}"],
           cd: cwd,
           stderr_to_stdout: true
         ) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end
end

if System.argv() == ["run"], do: PrReport.main()
