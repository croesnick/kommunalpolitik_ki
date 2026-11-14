# elixir .claude/hooks/test/hooks_test.exs
#
# The two hooks of interactive sessions (#462) against throwaway git repos:
# when the stop hook runs the gates, blocks, or steps aside, and what the PR
# hook lets through.

ExUnit.start()
for file <- ~w(stop_gates pr_report), do: Code.require_file("../#{file}.exs", __DIR__)

defmodule RepoHooksTest do
  use ExUnit.Case, async: true

  setup do
    dir = Path.join(System.tmp_dir!(), "repo-hooks-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    git = fn args -> {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true) end
    git.(~w(init -q -b main))
    git.(~w(config user.email t@example.org))
    git.(~w(config user.name Test))
    File.write!(Path.join(dir, "a.txt"), "a\n")
    git.(~w(add -A))
    git.(~w(commit -q -m init))
    git.(~w(update-ref refs/remotes/origin/main HEAD))

    %{dir: dir}
  end

  defp counting_gates(result) do
    calls = :counters.new(1, [])
    gates = fn _cwd -> :counters.add(calls, 1, 1) && result end
    {gates, fn -> :counters.get(calls, 1) end}
  end

  describe "stop gates" do
    test "no change against origin/main: gates do not run", %{dir: dir} do
      {gates, calls} = counting_gates(:ok)
      assert StopGates.run(%{"cwd" => dir}, gates) == {0, "", ""}
      assert calls.() == 0
    end

    test "a red gate blocks the first stop with the output on stderr", %{dir: dir} do
      File.write!(Path.join(dir, "b.txt"), "neu\n")
      {gates, _} = counting_gates({:error, "Tests", "1 test, 1 failure"})

      assert {2, "", stderr} = StopGates.run(%{"cwd" => dir}, gates)
      assert stderr =~ "Gate rot: Tests"
      assert stderr =~ "1 failure"
    end

    test "while a stop hook keeps the session going, red only warns the human", %{dir: dir} do
      File.write!(Path.join(dir, "b.txt"), "neu\n")
      {gates, _} = counting_gates({:error, "Tests", "1 failure"})

      assert {0, stdout, ""} = StopGates.run(%{"cwd" => dir, "stop_hook_active" => true}, gates)
      assert JSON.decode!(stdout)["systemMessage"] =~ "weiterhin rot"
    end

    test "green is remembered until the working state changes", %{dir: dir} do
      File.write!(Path.join(dir, "b.txt"), "neu\n")
      {gates, calls} = counting_gates(:ok)

      assert StopGates.run(%{"cwd" => dir}, gates) == {0, "", ""}
      assert StopGates.run(%{"cwd" => dir}, gates) == {0, "", ""}
      assert calls.() == 1

      File.write!(Path.join(dir, "b.txt"), "anders\n")
      assert StopGates.run(%{"cwd" => dir}, gates) == {0, "", ""}
      assert calls.() == 2
    end

    test "the excerpt shows failing tests and results, not the compile noise" do
      output =
        Enum.map_join(1..80, "\n", &"Compiling dep #{&1}") <>
          "\n==> sidecar\n\e[31m  1) test probe (StopProbeTest)\e[0m\n     test/probe.exs:3\n" <>
          "     Assertion with == failed\nResult: 0/1 passed\n" <>
          Enum.map_join(1..80, "\n", &"==> dep #{&1}\nCompiling")

      excerpt = StopGates.excerpt(output)
      assert excerpt =~ "  1) test probe (StopProbeTest)"
      assert excerpt =~ "Result: 0/1 passed"
      refute excerpt =~ "\e["
      refute excerpt =~ "Compiling dep 1\n"
    end

    test "from a subdirectory the gates run at the repo root", %{dir: dir} do
      File.mkdir_p!(Path.join(dir, "apps/x"))
      File.write!(Path.join(dir, "apps/x/b.txt"), "neu\n")
      test_pid = self()

      gates = fn root ->
        send(test_pid, {:root, root})
        :ok
      end

      StopGates.run(%{"cwd" => Path.join(dir, "apps/x")}, gates)
      assert_received {:root, root}
      assert File.exists?(Path.join(root, "a.txt"))
    end

    test "outside a git repo or without origin/main the hook steps aside", %{dir: dir} do
      {gates, calls} = counting_gates({:error, "Tests", "rot"})
      assert StopGates.run(%{"cwd" => System.tmp_dir!()}, gates) == {0, "", ""}

      File.write!(Path.join(dir, "b.txt"), "neu\n")
      System.cmd("git", ~w(update-ref -d refs/remotes/origin/main), cd: dir)
      assert StopGates.run(%{"cwd" => dir}, gates) == {0, "", ""}
      assert calls.() == 0
    end

    test "when origin/main moves, a green state is checked again", %{dir: dir} do
      File.write!(Path.join(dir, "b.txt"), "neu\n")
      {gates, calls} = counting_gates(:ok)
      StopGates.run(%{"cwd" => dir}, gates)

      System.cmd("git", ~w(commit -q --allow-empty -m main-moves), cd: dir)
      System.cmd("git", ~w(update-ref refs/remotes/origin/main HEAD), cd: dir)
      StopGates.run(%{"cwd" => dir}, gates)
      assert calls.() == 2
    end

    test "the real index stays untouched", %{dir: dir} do
      File.write!(Path.join(dir, "b.txt"), "neu\n")
      {gates, _} = counting_gates(:ok)
      StopGates.run(%{"cwd" => dir}, gates)

      assert {"?? b.txt\n", 0} = System.cmd("git", ~w(status --short), cd: dir)
    end
  end

  describe "PR report" do
    defp report(head) do
      """
      ## Evidence

      ### Prüfbericht

      Gilt für `#{String.slice(head, 0, 7)}`.

      | Prüfpunkt | Ergebnis | Nachweis |
      |---|---|---|
      | Punkt | bestanden | `mix test` |

      ### Entscheidungen, die die Umsetzung selbst getroffen hat

      - Keine.
      """
    end

    defp head(dir), do: dir |> then(&System.cmd("git", ~w(rev-parse HEAD), cd: &1)) |> elem(0)

    defp pr(dir, command),
      do: PrReport.run(%{"cwd" => dir, "tool_input" => %{"command" => command}})

    test "other commands pass without a decision", %{dir: dir} do
      assert pr(dir, "gh pr view 12") == ""
      assert pr(dir, "gh pr list --search new") == ""
      assert pr(dir, "git status") == ""
    end

    test "aliases and flags between the words are caught", %{dir: dir} do
      for command <- [
            "gh pr new --title T",
            "gh pr -R croesnick/kommunalpolitik_ki create --title T",
            "gh -R croesnick/kommunalpolitik_ki pr create --title T",
            "gh  pr  create -b x"
          ] do
        decision = dir |> pr(command) |> JSON.decode!()
        assert decision["hookSpecificOutput"]["permissionDecision"] == "deny", command
      end
    end

    test "a body file with the report for the current head passes", %{dir: dir} do
      File.write!(Path.join(dir, "pr.md"), report(head(dir)))
      assert pr(dir, "gh pr create --title T --body-file pr.md") == ""
    end

    test "an inline body with the report passes", %{dir: dir} do
      assert pr(dir, "gh pr create --title T --body \"#{report(head(dir))}\"") == ""
    end

    test "without a report the call is denied and the reason names what is missing", %{dir: dir} do
      decision = dir |> pr("gh pr create --title T --body 'Closes #1'") |> JSON.decode!()
      output = decision["hookSpecificOutput"]

      assert output["permissionDecision"] == "deny"
      assert output["permissionDecisionReason"] =~ "Überschrift „Prüfbericht“"
      assert output["permissionDecisionReason"] =~ "aktuelle Head"
    end

    test "a report for an older commit is denied", %{dir: dir} do
      File.write!(Path.join(dir, "pr.md"), report("0000000deadbeef"))
      decision = dir |> pr("cd x && gh pr create -F pr.md") |> JSON.decode!()
      assert decision["hookSpecificOutput"]["permissionDecisionReason"] =~ "aktuelle Head"
    end

    # A session standing in another worktree opens a PR for a branch (#532):
    # the report must name that branch's head, not the directory's.
    defp branch(dir, name) do
      git = fn args -> {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true) end
      git.(["branch", name])
      git.(["switch", "-q", name])
      File.write!(Path.join(dir, "b.txt"), "b\n")
      git.(~w(add -A))
      git.(~w(commit -q -m branch))
      sha = head(dir)
      git.(~w(switch -q main))
      sha
    end

    test "with --head the report must name that branch's head", %{dir: dir} do
      sha = branch(dir, "fix")
      File.write!(Path.join(dir, "pr.md"), report(sha))

      for flag <- ["--head fix", "--head=fix", "-H fix", "--head croesnick:fix"] do
        assert pr(dir, "gh pr create #{flag} --body-file pr.md") == "", flag
      end
    end

    test "with --head a report for the directory's head is denied", %{dir: dir} do
      branch(dir, "fix")
      File.write!(Path.join(dir, "pr.md"), report(head(dir)))
      decision = dir |> pr("gh pr create --head fix -F pr.md") |> JSON.decode!()
      assert decision["hookSpecificOutput"]["permissionDecision"] == "deny"
    end

    test "a branch only under origin/ resolves too", %{dir: dir} do
      sha = branch(dir, "fix")
      {_, 0} = System.cmd("git", ~w(update-ref refs/remotes/origin/remote-only fix), cd: dir)
      File.write!(Path.join(dir, "pr.md"), report(sha))
      assert pr(dir, "gh pr create --head remote-only -F pr.md") == ""
    end

    test "an unknown branch is denied, and the reason names it", %{dir: dir} do
      File.write!(Path.join(dir, "pr.md"), report(head(dir)))
      decision = dir |> pr("gh pr create --head nowhere -F pr.md") |> JSON.decode!()
      assert decision["hookSpecificOutput"]["permissionDecision"] == "deny"
      assert decision["hookSpecificOutput"]["permissionDecisionReason"] =~ "`nowhere`"
    end

    # Only gh's own flags count (#540): the same words in the body, the
    # title or another command name no branch.
    test "--head in the body or title text is no flag", %{dir: dir} do
      branch(dir, "fix")
      body = report(head(dir)) <> "\nMit `--head fix` bzw. -H fix prüft der Hook den Branch.\n"
      File.write!(Path.join(dir, "pr.md"), body)

      for command <- [
            "gh pr create --title T --body \"#{body}\"",
            "gh pr create --title 'x -H fix' -F pr.md",
            "gh pr create --title T --body \"$(cat <<'EOF'\n#{body}Etwa: -H \"fix\", geht's?\nEOF\n)\"",
            "gh pr create --title T --body-file - <<'PR-BODY'\n#{body}Etwa: -H \"fix\"\nPR-BODY",
            "curl -s -H fix https://example.org && gh pr create -F pr.md"
          ] do
        assert pr(dir, command) == "", command
      end
    end

    test "a quoted mention before the real --head does not win", %{dir: dir} do
      sha = branch(dir, "fix")
      File.write!(Path.join(dir, "pr.md"), report(sha))
      assert pr(dir, "gh pr create --title 'see -H main' --head fix -F pr.md") == ""
    end

    # Escapes outside quotes must not throw the scan out of step, or a later
    # quote would swallow the real flag and the directory's head would count.
    test "escaped quotes before the real --head keep it a flag", %{dir: dir} do
      branch(dir, "fix")
      File.write!(Path.join(dir, "pr.md"), report(head(dir)))

      for command <- [
            "gh pr create --title 'it'\\''s' --head fix --label 'doc' -F pr.md",
            "gh pr create --title a\\\"b --head fix --label \"doc\" -F pr.md",
            "gh pr create --title $'it\\'s' --head fix --label 'x' -F pr.md",
            "bash <<'EOF'\ngh pr create --head fix -F pr.md\nEOF",
            # A call quoted or in a heredoc earlier must not shift the quotes.
            "git commit -m 'Hook: gh pr create' && gh pr create --head fix --title 'T' -F pr.md",
            "cat > b.md <<'EOF'\nDer Hook lehnt \"gh pr create\" ab, geht's?\nEOF\ngh pr create --head fix --title 'T' -F pr.md",
            "gh pr create --help # don't\ngh pr create --head fix --title 'T' -F pr.md",
            "gh pr create --help; bash <<'EOF'\ngh pr create --head fix -F pr.md\nEOF",
            # The rest of a heredoc's opening line is still arguments.
            "gh pr create --title T -F pr.md <<'EOF' --head fix\nText\nEOF",
            "gh pr create --title \"$(printf '%s' \"it's\")\" --head fix --label 'x' -F pr.md",
            # Other commands, comments and heredocs end where the shell ends them.
            "gh pr create -F pr.md --head fix;# --head main",
            "gh pr create --head fix -F pr.md && curl -s -H main https://x",
            "gh pr create --head fix -F pr.md 2>&1 | grep -H main",
            "gh pr create -F pr.md --head fix; echo gh pr create --head main",
            "gh pr create --head fix -F pr.md <<\\EOF\n--head main\nEOF",
            "gh pr create --title T <<<'true' \\\n--head fix -F pr.md\ntrue",
            "gh pr create --head fix -F pr.md <<'EOF'\nx\nEOF)\n--head main\nEOF",
            "gh pr create --head fix -F pr.md <<A 3<<B\nx\nA\n--head main\nB",
            "gh pr create --head fix -F pr.md <<'E.O'\n--head main\nE.O",
            "gh pr create --head fix -F pr.md &# --head main",
            # Other ways to run gh, next to a call that never runs.
            "gh() { command gh \"$@\" --head fix; }; gh pr create --head main -F pr.md",
            "command gh pr create --head fix -F pr.md; false && gh pr create --head main",
            "env gh pr create --head fix -F pr.md; false && gh pr create --head main",
            "eval gh pr create --head fix -F pr.md; false && gh pr create --head main",
            "bash -c 'gh pr create -Hfix -F pr.md'; false && gh pr create --head main",
            "echo --head fix | xargs gh pr create -F pr.md; false && gh pr create --head main",
            "command gh pr create -Hfix -F pr.md; f() { gh pr create --head main; }",
            "command gh pr create -Hfix -F pr.md; gh -- pr create --head main",
            # Words the shell splits or expands: the old reading applies.
            "gh pr create --title \"x -H nope\" --head main -F pr.md {-H,fix}",
            "gh pr create --title \"x -H nope\" --head main -F pr.md [-]Hfix",
            # Short flags as pflag reads them.
            "gh pr create -Hfix -F pr.md",
            "gh pr create -dH fix -F pr.md",
            "gh pr create \"--head\" fix -F pr.md"
          ] do
        decision = dir |> pr(command) |> JSON.decode!()
        assert decision["hookSpecificOutput"]["permissionDecision"] == "deny", command
      end
    end

    test "a value that is no fixed text is named in the denial", %{dir: dir} do
      File.write!(Path.join(dir, "pr.md"), report(head(dir)))
      decision = dir |> pr("gh pr create --head \"$BRANCH\" -F pr.md") |> JSON.decode!()
      assert decision["hookSpecificOutput"]["permissionDecisionReason"] =~ "`\"$BRANCH\"`"
    end

    # Without shfmt the reading of #532 applies: the first --head anywhere.
    test "without shfmt the old reading applies", %{dir: dir} do
      sha = branch(dir, "fix")
      File.write!(Path.join(dir, "pr.md"), report(sha))
      without = &PrReport.run(%{"cwd" => dir, "tool_input" => %{"command" => &1}}, nil)

      assert without.("gh pr create --head fix -F pr.md") == ""

      # A mention in the title counts again, as before #540.
      File.write!(Path.join(dir, "pr.md"), report(head(dir)))
      command = "gh pr create --title 'x -H fix' -F pr.md"
      assert pr(dir, command) == ""
      decision = command |> without.() |> JSON.decode!()
      assert decision["hookSpecificOutput"]["permissionDecision"] == "deny"
    end

    test "with several --head the last one counts, as in gh", %{dir: dir} do
      sha = branch(dir, "fix")
      File.write!(Path.join(dir, "pr.md"), report(head(dir)))
      decision = dir |> pr("gh pr create --head main --head fix -F pr.md") |> JSON.decode!()
      assert decision["hookSpecificOutput"]["permissionDecision"] == "deny"

      File.write!(Path.join(dir, "pr.md"), report(sha))
      assert pr(dir, "gh pr create --head main --head fix -F pr.md") == ""
    end
  end
end
