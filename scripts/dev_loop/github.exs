# GitHub and git side of the dev loop (#389). The script is the only GitHub
# writer; agents never see a token. Every `gh` call gets the PAT as
# GH_TOKEN, pushes go over HTTPS with gh as credential helper, so neither
# the SSH key nor the keyring login of the person are used.
#
# With `dry_run: true` in the context, writes are logged instead of sent;
# reads then use whatever gh login exists.
#
# Comments reach the loop only from the repository owner — core.exs holds
# the rule and its reasoning.

defmodule DevLoop.GitHub do
  @moduledoc false

  alias DevLoop.Core

  @repo "croesnick/kommunalpolitik_ki"
  @owner "croesnick"
  @project_owner @owner
  @project_number "1"

  def repo, do: @repo
  def owner, do: @owner
  def issue_url(n), do: "https://github.com/#{@repo}/issues/#{n}"

  # -- reads ---------------------------------------------------------------

  @doc """
  Open issues with author, labels, assignees, comments and open blockers.
  `owner?` marks the owner's own tickets — the only ones whose body may
  confirm a Zielbild (core.exs); comments are filtered at fetch.
  """
  def open_issues(ctx) do
    listed =
      gh!(
        ctx,
        ~w(issue list --repo #{@repo} --state open --limit 500 --json number,title,body,labels,assignees,author,comments)
      )
      |> JSON.decode!()

    # issue list has no dependency info; the REST list carries the summary.
    blockers =
      gh!(ctx, [
        "api",
        "--paginate",
        "repos/#{@repo}/issues?state=open&per_page=100",
        "--jq",
        ".[] | select(.pull_request == null) | [.number, (.issue_dependencies_summary.blocked_by // 0)] | @tsv"
      ])
      |> String.split("\n", trim: true)
      |> Map.new(fn line ->
        [n, b] = String.split(line, "\t")
        {String.to_integer(n), String.to_integer(b)}
      end)

    for i <- listed do
      author = i["author"]["login"]

      %{
        number: i["number"],
        title: i["title"],
        body: i["body"] || "",
        labels: Enum.map(i["labels"], & &1["name"]),
        assignees: Enum.map(i["assignees"], & &1["login"]),
        author: author,
        owner?: author == @owner,
        comments: Core.trusted_comment_bodies(i["comments"], @owner),
        open_blockers: Map.get(blockers, i["number"], 0)
      }
    end
  end

  @doc """
  Open PRs of the base repo as `%{number, branch, sha, closes: [n]}`. Fork
  PRs are left out: strangers cannot push branches here, so only the base
  repo's PRs may shape selection, busyness and reviews.
  """
  def open_prs(ctx) do
    gh!(
      ctx,
      ~w(pr list --repo #{@repo} --state open --limit 200 --json number,headRefName,headRefOid,isCrossRepository,closingIssuesReferences)
    )
    |> JSON.decode!()
    |> Enum.reject(& &1["isCrossRepository"])
    |> Enum.map(fn p ->
      %{
        number: p["number"],
        branch: p["headRefName"],
        sha: p["headRefOid"],
        closes: Enum.map(p["closingIssuesReferences"], & &1["number"])
      }
    end)
  end

  @doc "Issue numbers on the board with the given status; [] if the board is unreadable."
  def board?(ctx),
    do:
      match?(
        {:ok, _},
        gh(ctx, ~w(project view #{@project_number} --owner #{@project_owner} --format json))
      )

  def board_numbers(%{board?: false}, _status), do: []

  def board_numbers(ctx, status) do
    case gh(
           ctx,
           ~w(project item-list #{@project_number} --owner #{@project_owner} --limit 1000 --format json)
         ) do
      {:ok, out} ->
        for %{"status" => ^status, "content" => %{"number" => n}} <- JSON.decode!(out)["items"],
            do: n

      {:error, out} ->
        log(ctx, "Board nicht lesbar: #{first_line(out)}")
        []
    end
  end

  # PR 0 is the placeholder a rehearsal "creates".
  def pr_comments(%{dry_run: true}, 0), do: []

  def pr_comments(ctx, pr) do
    gh!(ctx, ~w(pr view #{pr} --repo #{@repo} --json comments))
    |> JSON.decode!()
    |> Map.fetch!("comments")
    |> Core.trusted_comment_bodies(@owner)
  end

  @doc "The PR text: what the implementation claims, for the review to check."
  def pr_body(%{dry_run: true}, 0), do: ""

  def pr_body(ctx, pr) do
    gh!(ctx, ~w(pr view #{pr} --repo #{@repo} --json body))
    |> JSON.decode!()
    |> Map.fetch!("body")
  end

  @doc "`:pending`, `:green` or `{:red, names}` for all workflow runs of a commit."
  def ci_state(ctx, sha),
    do:
      gh!(ctx, ~w(run list --repo #{@repo} --commit #{sha} --json status,conclusion,workflowName))
      |> JSON.decode!()
      |> Core.runs_state()

  @doc """
  The circuit breaker's view of `main`: `{:red, names}` only when its CI
  is red. Pending, green and unreadable all return nil, so a read hiccup
  cannot end the night — branch protection still guards every merge.
  """
  def main_red?(ctx, sha) do
    case gh(
           ctx,
           ~w(run list --repo #{@repo} --commit #{sha} --json status,conclusion,workflowName)
         ) do
      {:ok, out} ->
        redden(JSON.decode!(out) |> Core.runs_state())

      {:error, out} ->
        log(ctx, "Main-CI nicht prüfbar: #{first_line(out)}")
        nil
    end
  end

  defp redden({:red, names}), do: {:red, names}
  defp redden(_), do: nil

  # -- writes --------------------------------------------------------------

  def comment(ctx, n, body),
    do: write(ctx, ~w(issue comment #{n} --repo #{@repo} --body-file -), body)

  def pr_comment(ctx, pr, body),
    do: write(ctx, ~w(pr comment #{pr} --repo #{@repo} --body-file -), body)

  def assign_me(ctx, n), do: write(ctx, ~w(issue edit #{n} --repo #{@repo} --add-assignee @me))

  def unassign_me(ctx, n),
    do: write(ctx, ~w(issue edit #{n} --repo #{@repo} --remove-assignee @me))

  def add_label(ctx, n, label),
    do: write(ctx, ["issue", "edit", "#{n}", "--repo", @repo, "--add-label", label])

  def remove_label(ctx, n, label),
    do: write(ctx, ["issue", "edit", "#{n}", "--repo", @repo, "--remove-label", label])

  @doc "Board status; a missing option or an unwritable board is logged, not fatal."
  def set_status(%{board?: false}, _n, _status), do: :skip

  def set_status(ctx, n, status) do
    args =
      ~w(project item-edit #{@project_number} --owner #{@project_owner} --url #{issue_url(n)}
         --field Status --value) ++ [status]

    case write(ctx, args) do
      {:error, out} ->
        log(ctx, "Board-Status '#{status}' für ##{n} nicht gesetzt: #{first_line(out)}")

      ok ->
        ok
    end
  end

  @doc "Creates the PR with the given labels and returns its number."
  def create_pr(ctx, branch, title, body, labels \\ []) do
    case write(
           ctx,
           [
             "pr",
             "create",
             "--repo",
             @repo,
             "--base",
             "main",
             "--head",
             branch,
             "--title",
             title,
             "--body-file",
             "-"
           ] ++ Enum.flat_map(labels, &["--label", &1]),
           body
         ) do
      {:ok, url} ->
        url |> String.trim() |> String.split("/") |> List.last() |> String.to_integer()

      {:dry, _} ->
        0

      {:error, out} ->
        raise "PR für #{branch} nicht angelegt: #{out}"
    end
  end

  @doc "Adds the label to the PR or removes it."
  def pr_label(ctx, pr, label, add?),
    do:
      write(ctx, [
        "pr",
        "edit",
        "#{pr}",
        "--repo",
        @repo,
        if(add?, do: "--add-label", else: "--remove-label"),
        label
      ])

  @doc "Replaces the PR text: a rework round brings new evidence and decisions."
  def update_pr(ctx, pr, body) do
    case write(ctx, ~w(pr edit #{pr} --repo #{@repo} --body-file -), body) do
      {:error, out} -> raise "PR-Text von ##{pr} nicht ersetzt: #{out}"
      ok -> ok
    end
  end

  @doc """
  Squash merge of exactly the reviewed head. Subject and an empty body are
  set explicitly so no agent commit trailer ends up on main.
  """
  def merge(ctx, pr, sha, subject) do
    write(
      ctx,
      ~w(pr merge #{pr} --repo #{@repo} --squash --delete-branch --match-head-commit #{sha}) ++
        ["--subject", subject, "--body", ""]
    )
  end

  @doc "Force-pushes the loop branch over HTTPS with the PAT (loop branches belong to the loop)."
  def push(ctx, worktree, branch) do
    args = [
      "-C",
      worktree,
      "-c",
      "credential.helper=",
      "-c",
      "credential.helper=!gh auth git-credential",
      "push",
      "--force",
      "https://github.com/#{@repo}.git",
      "HEAD:refs/heads/#{branch}"
    ]

    if ctx.dry_run do
      log(ctx, "[dry-run] git push #{branch}")
      {:dry, ""}
    else
      run("git", args, ctx)
    end
  end

  # -- plumbing ------------------------------------------------------------

  defp write(ctx, args, stdin \\ nil) do
    if ctx.dry_run do
      log(ctx, "[dry-run] gh " <> Enum.join(args, " "))
      {:dry, ""}
    else
      gh(ctx, args, stdin)
    end
  end

  defp gh!(ctx, args) do
    case gh(ctx, args) do
      {:ok, out} -> out
      {:error, out} -> raise "gh #{Enum.join(Enum.take(args, 2), " ")} fehlgeschlagen: #{out}"
    end
  end

  defp gh(ctx, args, stdin \\ nil) do
    if stdin do
      # System.cmd has no stdin; a temp file keeps bodies out of argv and logs.
      path = Path.join(System.tmp_dir!(), "dev-loop-#{System.unique_integer([:positive])}.md")
      File.write!(path, stdin)

      try do
        run("gh", Enum.map(args, &if(&1 == "-", do: path, else: &1)), ctx)
      after
        File.rm(path)
      end
    else
      run("gh", args, ctx)
    end
  end

  defp run(cmd, args, ctx) do
    env = if ctx.token, do: [{"GH_TOKEN", ctx.token}], else: []

    case System.cmd(cmd, args, env: env, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, _} -> {:error, out}
    end
  end

  defp log(ctx, msg), do: ctx.log.(msg)

  # gh prints its whole usage text after some errors; the first line says it.
  defp first_line(out), do: out |> String.trim() |> String.split("\n", parts: 2) |> hd()
end
