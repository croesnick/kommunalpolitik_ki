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

  @doc """
  Returns the hook's stdout: empty to let the call pass, a deny decision
  otherwise. `shfmt` is the parser for the command (#540); nil means none.
  """
  def run(input, shfmt \\ System.find_executable("shfmt")) do
    command = get_in(input, ["tool_input", "command"]) || ""
    cwd = input["cwd"] || File.cwd!()

    if command =~ @create do
      case missing(command <> "\n" <> body_file(command, cwd), head(command, cwd, shfmt)) do
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
  defp head(command, cwd, shfmt) do
    case heads(command, shfmt) do
      [] -> commit("HEAD", cwd)
      values -> values |> List.last() |> branch_head(cwd)
    end
  end

  defp branch_head({:unknown, text}, _cwd), do: {:unknown, text}

  defp branch_head(value, cwd) do
    branch = value |> String.split(":") |> List.last()

    Enum.find_value([branch, "refs/remotes/origin/#{branch}"], &commit(&1, cwd)) ||
      {:unknown, branch}
  end

  # `--head` values as gh would get them (#540), read from the shell's
  # syntax tree. Where that reading is unsure, or shfmt is missing, the old
  # one of #532 applies: the first `--head` anywhere in the command. The
  # hook thus never lets more through than before.
  @old_flag ~r/(?:--head|-H)[=\s]+("[^"]+"|'[^']+'|\S+)/

  defp heads(command, shfmt) do
    case PrReport.GhArgs.heads(command, shfmt, &(&1 =~ @create and &1 =~ @old_flag)) do
      {:ok, values} ->
        values

      :unsure ->
        for [_, value] <- [Regex.run(@old_flag, command)],
            do: value |> String.trim("\"") |> String.trim("'")
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

defmodule PrReport.GhArgs do
  @moduledoc false

  # Reads the `gh pr create` call the shell would run from the syntax tree
  # of shfmt (mvdan/sh, `--to-json`), so quotes, escapes, heredocs and
  # comments mean what they mean to the shell (#540). Flags follow pflag,
  # as gh parses them. `:unsure` wherever the tree leaves room for doubt:
  # no parse, not exactly one create call, a word that is not literal where
  # a flag could stand, an unknown flag, or text that holds a call of its
  # own (`bash -c "gh pr create --head …"`, `bash <<'EOF'`).

  # Flags of `gh pr create` and the persistent `--repo`.
  @value_long ~w(assignee base body body-file head label milestone project recover repo reviewer template title)
  @bool_long ~w(draft dry-run editor fill fill-first fill-verbose help no-maintainer-edit web)
  @value_short ~w(B F H R T a b l m p r t)
  @bool_short ~w(d e f h w)

  @doc "`{:ok, values}` of `--head` in order, a value that is no literal as `{:unknown, source}`; or `:unsure`."
  def heads(_command, nil, _hidden_call?), do: :unsure

  def heads(command, shfmt, hidden_call?) do
    with {:ok, tree} <- parse(command, shfmt),
         false <- tree |> nodes() |> Enum.any?(&(word?(&1) and hidden_call?.(text(&1)))),
         results = for(args <- calls(tree), do: call(args, command)),
         false <- :unsure in results,
         [{:create, values}] <- Enum.filter(results, &match?({:create, _}, &1)) do
      {:ok, values}
    else
      _ -> :unsure
    end
  end

  # shfmt reads the tree only from stdin.
  defp parse(command, shfmt) do
    path =
      Path.join(System.tmp_dir!(), "pr-report-#{Base.encode16(:crypto.strong_rand_bytes(8))}.sh")

    File.write!(path, command, [:exclusive])

    script = ~s(exec "$0" --to-json -ln bash < "$1" 2>/dev/null)

    try do
      case System.cmd("sh", ["-c", script, shfmt, path]) do
        {json, 0} -> JSON.decode(json)
        _ -> :error
      end
    after
      File.rm(path)
    end
  end

  defp nodes(node) when is_map(node), do: [node | node |> Map.values() |> Enum.flat_map(&nodes/1)]
  defp nodes(list) when is_list(list), do: Enum.flat_map(list, &nodes/1)
  defp nodes(_), do: []

  defp word?(node), do: Map.has_key?(node, "Parts") and not Map.has_key?(node, "Type")

  defp calls(tree) do
    for %{"Type" => "CallExpr", "Args" => [first | args]} <- nodes(tree),
        {:ok, cmd} <- [literal(first)],
        Path.basename(cmd) == "gh",
        do: args
  end

  # {:create, heads}, :other for gh calls that are no `pr create`, :unsure.
  defp call(args, command) do
    case flags(args, command, [], []) do
      {["pr", sub | _], heads} when sub in ["create", "new"] -> {:create, heads}
      {_, _} -> :other
      :unsure -> :unsure
    end
  end

  defp flags([], _command, positional, heads), do: {Enum.reverse(positional), Enum.reverse(heads)}

  defp flags([word | rest], command, positional, heads) do
    case literal(word) do
      :error ->
        :unsure

      {:ok, "--"} ->
        rest_positional(rest, positional, heads)

      {:ok, "--" <> long} ->
        long(String.split(long, "=", parts: 2), rest, command, positional, heads)

      {:ok, "-" <> short} when short != "" ->
        short(String.graphemes(short), rest, command, positional, heads)

      {:ok, arg} ->
        flags(rest, command, [arg | positional], heads)
    end
  end

  defp rest_positional(words, positional, heads) do
    literals = Enum.map(words, &literal/1)

    if :error in literals,
      do: :unsure,
      else:
        {Enum.reverse(positional) ++ for({:ok, arg} <- literals, do: arg), Enum.reverse(heads)}
  end

  defp long([name, value], rest, command, positional, heads) when name in @value_long,
    do: flags(rest, command, positional, record(name == "head", value, heads))

  defp long([name], rest, command, positional, heads) when name in @value_long,
    do: value(name == "head", rest, command, positional, heads)

  defp long([name | _], rest, command, positional, heads) when name in @bool_long,
    do: flags(rest, command, positional, heads)

  defp long(_, _rest, _command, _positional, _heads), do: :unsure

  # A cluster such as `-dH fix` or `-Hfix`: booleans, then at most one flag
  # that takes the rest of the cluster or the next word.
  defp short([], rest, command, positional, heads), do: flags(rest, command, positional, heads)

  defp short([char | more], rest, command, positional, heads) when char in @bool_short,
    do: short(more, rest, command, positional, heads)

  defp short([char | more], rest, command, positional, heads) when char in @value_short do
    case Enum.join(more) do
      "" ->
        value(char == "H", rest, command, positional, heads)

      inline ->
        flags(
          rest,
          command,
          positional,
          record(char == "H", String.trim_leading(inline, "="), heads)
        )
    end
  end

  defp short(_, _rest, _command, _positional, _heads), do: :unsure

  defp value(_head?, [], _command, positional, heads), do: flags([], nil, positional, heads)

  defp value(head?, [word | rest], command, positional, heads) do
    value =
      case literal(word) do
        {:ok, value} -> value
        :error -> {:unknown, source(word, command)}
      end

    flags(rest, command, positional, record(head?, value, heads))
  end

  defp record(true, value, heads), do: [value | heads]
  defp record(false, _value, heads), do: heads

  defp source(%{"Pos" => %{"Offset" => from}, "End" => %{"Offset" => to}}, command),
    do: binary_part(command, from, to - from)

  # The word's value if it is fixed text, as the shell would pass it.
  defp literal(%{"Parts" => parts}) do
    values = Enum.map(parts, &literal_part/1)
    if :error in values, do: :error, else: {:ok, Enum.join(values)}
  end

  defp literal_part(%{"Type" => "Lit", "Value" => value}),
    do: Regex.replace(~r/\\(\n|.)/s, value, fn _, char -> if char == "\n", do: "", else: char end)

  defp literal_part(%{"Type" => "SglQuoted", "Dollar" => true, "Value" => value}),
    do: if(String.contains?(value, "\\"), do: :error, else: value)

  defp literal_part(%{"Type" => "SglQuoted", "Value" => value}), do: value

  # `$"…"` is a translated string: its text is not known here.
  defp literal_part(%{"Type" => "DblQuoted", "Dollar" => true}), do: :error

  defp literal_part(%{"Type" => "DblQuoted"} = part) do
    values =
      for p <- Map.get(part, "Parts", []) do
        case p do
          %{"Type" => "Lit", "Value" => value} ->
            Regex.replace(~r/\\([$`"\\\n])/, value, fn _, char ->
              if char == "\n", do: "", else: char
            end)

          _ ->
            :error
        end
      end

    if :error in values, do: :error, else: Enum.join(values)
  end

  defp literal_part(_), do: :error

  # The fixed text of a word, other parts as a blank, to find calls in text.
  defp text(%{"Parts" => parts}), do: Enum.map_join(parts, &text_part/1)

  defp text_part(%{"Type" => type, "Value" => value}) when type in ["Lit", "SglQuoted"], do: value

  defp text_part(%{"Type" => "DblQuoted"} = part),
    do: text(%{"Parts" => Map.get(part, "Parts", [])})

  defp text_part(_), do: " "
end

if System.argv() == ["run"], do: PrReport.main()
