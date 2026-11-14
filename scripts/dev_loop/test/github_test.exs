# elixir scripts/dev_loop/test/github_test.exs
#
# GitHub reads without a login: a fake gh on PATH serves fixtures, so the
# fetch layer is tested — the comment filter's wiring, the fork filter and
# the breaker's read.

ExUnit.start()
for file <- ~w(core github), do: Code.require_file("../#{file}.exs", __DIR__)

defmodule DevLoop.GitHubTest do
  use ExUnit.Case, async: false

  alias DevLoop.GitHub

  @fake_gh """
  #!/bin/sh
  case "$*" in
    *"issue list"*) cat "$GH_ISSUES" ;;
    *"kommunalpolitik_ki/issues?"*) cat "$GH_BLOCKERS" ;;
    *"pr list"*) cat "$GH_PRS" ;;
    *"pr view"*) cat "$GH_PR" ;;
    *"run list"*) cat "$GH_RUNS" ;;
    *) echo "unexpected gh call: $*" >&2; exit 1 ;;
  esac
  """

  setup do
    dir = System.tmp_dir!() |> Path.join("dev-loop-gh-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "bin"))
    fake = Path.join(dir, "bin/gh")
    File.write!(fake, @fake_gh)
    File.chmod!(fake, 0o755)

    path = System.get_env("PATH")
    System.put_env("PATH", Path.join(dir, "bin") <> ":" <> path)

    on_exit(fn ->
      System.put_env("PATH", path)
      File.rm_rf!(dir)
    end)

    %{dir: dir, ctx: %{token: "t", log: fn _ -> :ok end}}
  end

  defp serve(dir, key, text) do
    file = Path.join(dir, key)
    File.write!(file, text)
    System.put_env("GH_" <> String.upcase(key), file)
  end

  test "open_issues keeps only the owner's comments and marks ownership", %{
    dir: dir,
    ctx: ctx
  } do
    serve(dir, "issues", """
    [{"number": 7, "title": "T7", "body": "B", "author": {"login": "someone"},
      "labels": [], "assignees": [],
      "comments": [
        {"author": {"login": "someone"}, "body": "inject"},
        {"author": {"login": "croesnick"}, "body": "GO"}
      ]}]
    """)

    serve(dir, "blockers", "")

    [issue] = GitHub.open_issues(ctx)

    assert issue.comments == ["GO"]
    assert issue.author == "someone"
    assert issue.owner? == false
  end

  test "open_prs drops fork PRs", %{dir: dir, ctx: ctx} do
    serve(dir, "prs", """
    [
      {"number": 401, "headRefName": "loop/164", "headRefOid": "abc",
       "isCrossRepository": false, "closingIssuesReferences": []},
      {"number": 402, "headRefName": "loop/999", "headRefOid": "def",
       "isCrossRepository": true, "closingIssuesReferences": [{"number": 999}]}
    ]
    """)

    prs = GitHub.open_prs(ctx)

    assert Enum.map(prs, & &1.number) == [401]
  end

  test "pr_comments keeps only the owner's comments", %{dir: dir, ctx: ctx} do
    serve(
      dir,
      "pr",
      ~s({"comments": [{"author": {"login": "bot"}, "body": "x"}, {"author": {"login": "croesnick"}, "body": "ok"}]})
    )

    assert GitHub.pr_comments(ctx, 401) == ["ok"]
  end

  test "pr_body returns the PR text for the review", %{dir: dir, ctx: ctx} do
    serve(dir, "pr", ~s({"body": "## Prüfbericht"}))
    assert GitHub.pr_body(ctx, 401) == "## Prüfbericht"
  end

  test "main_red? is nil on pending, green and gh failure, red otherwise", %{
    dir: dir,
    ctx: ctx
  } do
    serve(dir, "runs", ~s([{"status": "in_progress", "conclusion": null, "workflowName": "ci"}]))
    assert GitHub.main_red?(ctx, "abc") == nil

    serve(
      dir,
      "runs",
      ~s([{"status": "completed", "conclusion": "success", "workflowName": "ci"}])
    )

    assert GitHub.main_red?(ctx, "abc") == nil

    serve(
      dir,
      "runs",
      ~s([{"status": "completed", "conclusion": "failure", "workflowName": "Elixir quality gates"}])
    )

    assert GitHub.main_red?(ctx, "abc") == {:red, ["Elixir quality gates"]}

    File.rm(Path.join(dir, "runs"))
    assert GitHub.main_red?(ctx, "abc") == nil
  end
end
