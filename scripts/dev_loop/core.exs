# Pure decisions of the dev loop (#389): which ticket is next, which ticket
# the PO looks at, what a review verdict leads to, how many rework rounds a
# PR has had. No I/O here — GitHub, git and the agents live in github.exs
# and agent.exs, so everything that decides about a merge is unit-tested
# (scripts/dev_loop/test/core_test.exs).
#
# An issue is a plain map as github.exs builds it:
#   %{number:, title:, body:, labels: [String], assignees: [String],
#     open_blockers: integer, comments: [String]}

defmodule DevLoop.Core do
  @moduledoc false

  # Mirror of "Geschützte Pfade" in docs/agents/ai-tiers.md (a test checks
  # that every path named there is covered). Entries ending in "/" protect
  # the whole directory.
  @tier_protected [
    "apps/komki_policy/",
    "apps/komki_connector/CONTRACT.md",
    "apps/komki_mediator/lib/komki_mediator/gate.ex",
    "apps/komki_mediator/lib/komki_mediator/connector_gate.ex",
    "apps/komki_mediator/lib/komki_mediator/go.ex",
    "apps/komki_mediator/lib/komki_mediator/go_stand.ex",
    "apps/komki_mediator/lib/komki_mediator/pdr.ex",
    "apps/komki_mediator/lib/komki_mediator/journal.ex",
    "apps/komki_mediator/lib/komki_mediator/room.ex",
    "apps/komki_mediator/lib/komki_mediator/gamma.ex",
    "apps/komki_mediator/lib/komki_mediator/http.ex",
    "apps/seatbelt/",
    "apps/sidecar/",
    "apps/komki_egress/",
    "apps/komki_cli/lib/komki_cli/profile.ex",
    "apps/komki_cli/lib/komki_cli/connector_profile.ex",
    "apps/komki_cli/lib/komki_cli/mediator_profile.ex",
    "apps/komki_cli/lib/komki_cli/escript_profile.ex",
    "apps/komki_cli/lib/komki_cli/pins.ex",
    "apps/komki_cli/lib/komki_cli/channel.ex",
    "apps/komki_cli/lib/komki_cli/keychain.ex",
    "apps/komki_cli/lib/komki_cli/secrets.ex",
    "apps/komki_cli/lib/komki_cli/tresor.ex",
    "apps/komki_cli/lib/komki_cli/tresor/",
    "apps/komki_cli/lib/komki_cli/go_steps.ex",
    "apps/komki_cli/lib/komki_cli/go_watcher.ex",
    "apps/komki_connector_ris/lib/komki_connector_ris/top.ex",
    "apps/komki_connector_vault/lib/komki_connector_vault/paths.ex",
    "apps/komki_connector_vault/lib/komki_connector_vault/note.ex",
    "docs/rfcs/"
  ]

  # The loop must never merge a change to its own rules: its code and
  # prompts, the CI that gates it, and the documents that define tiers and
  # guardrails. Such a diff goes to the human like a tier-protected one.
  @loop_protected [
    "scripts/dev_loop.exs",
    "scripts/dev_loop/",
    ".github/",
    "docs/agents/",
    "AGENTS.md"
  ]

  @max_rework_rounds 2
  @max_po_tickets 5

  @marker_re ~r/<!-- dev-loop:review verdict=(approve|rework|human) sha=([0-9a-f]+) -->/
  @po_marker "<!-- dev-loop:po -->"

  def tier_protected, do: @tier_protected
  def protected_paths, do: @tier_protected ++ @loop_protected
  def max_rework_rounds, do: @max_rework_rounds
  def po_marker, do: @po_marker

  def protected_hits(paths), do: Enum.filter(paths, &protected?/1)

  defp protected?(path) do
    Enum.any?(protected_paths(), fn entry ->
      if String.ends_with?(entry, "/"),
        do: String.starts_with?(path, entry),
        else: path == entry
    end)
  end

  def tier(labels) do
    cond do
      "ai:s-tier" in labels -> :s
      "ai:a-tier" in labels -> :a
      "ai:b-tier" in labels -> :b
      true -> nil
    end
  end

  @doc """
  Pickable tickets in pick order. `busy` holds the numbers of issues that
  already have an open PR or stand on "In Progress" — the hand-opened lanes
  stay untouched.
  """
  def candidates(issues, busy) do
    issues
    |> Enum.filter(&pickable?(&1, busy))
    |> Enum.sort_by(fn i ->
      {if("next" in i.labels, do: 0, else: 1), if(tier(i.labels) == :b, do: 0, else: 1), i.number}
    end)
  end

  defp pickable?(i, busy) do
    "ready-for-agent" in i.labels and tier(i.labels) in [:a, :b] and
      i.open_blockers == 0 and i.assignees == [] and i.number not in busy
  end

  def loop_branch(n), do: "loop/#{n}"

  @doc """
  Issue numbers someone is already working on: closed by an open PR, named
  in the branch of an open PR or of a local worktree (`lane-152-…`,
  `brave-mock-340`, `loop/392`), or "In Progress" on the board.
  """
  def busy(prs, worktree_branches, in_progress) do
    branches = Enum.map(prs, & &1.branch) ++ worktree_branches

    Enum.uniq(
      Enum.flat_map(prs, & &1.closes) ++ Enum.flat_map(branches, &branch_numbers/1) ++ in_progress
    )
  end

  # Ticket numbers are the all-digit segments of at least two digits, so
  # "lane-22-32-37-ratsprojekte" names three tickets and
  # "llama-server-0.9.0" or "renovate/python-3.x" none.
  defp branch_numbers(branch) do
    for seg <- String.split(branch, ["-", "/", "_"]),
        seg =~ ~r/^\d{2,}$/,
        do: String.to_integer(seg)
  end

  @doc "Tickets the PO refines this run: at most #{@max_po_tickets}, oldest first."
  def po_candidates(issues, busy) do
    issues
    |> Enum.filter(&(po_candidate?(&1) and &1.number not in busy))
    |> Enum.sort_by(& &1.number)
    |> Enum.take(@max_po_tickets)
  end

  defp po_candidate?(i) do
    not Enum.any?(i.labels, &po_off_limits?/1) and
      not Enum.any?(i.comments, &String.contains?(&1, @po_marker)) and
      ("needs-triage" in i.labels or (tier(i.labels) in [:a, :b] and not zielbild?(i)))
  end

  defp po_off_limits?(label),
    do:
      label in ["ai:s-tier", "ready-for-human", "wontfix"] or
        String.starts_with?(label, "wayfinder:")

  defp zielbild?(i), do: Enum.any?([i.body | i.comments], &String.contains?(&1, "## Zielbild"))

  @doc """
  What a review leads to: `:merge`, `:await_go`, `:rework` or `:human`.
  `rounds` is the number of rework rounds the PR has had so far.
  """
  def decide(tier, verdict, protected_hits, rounds)
  def decide(_tier, _verdict, [_ | _], _rounds), do: :human
  def decide(_tier, "human", _hits, _rounds), do: :human
  def decide(_tier, "rework", _hits, rounds) when rounds >= @max_rework_rounds, do: :human
  def decide(_tier, "rework", _hits, _rounds), do: :rework
  def decide(:b, "approve", _hits, _rounds), do: :merge
  def decide(:a, "approve", _hits, _rounds), do: :await_go
  def decide(_tier, _verdict, _hits, _rounds), do: :human

  def marker(verdict, sha), do: "<!-- dev-loop:review verdict=#{verdict} sha=#{sha} -->"

  def rework_rounds(comments),
    do: Enum.count(comments, &match?([_, "rework", _], Regex.run(@marker_re, &1)))

  @doc "True if a review comment already approved exactly this head."
  def approved?(comments, sha),
    do: Enum.any?(comments, &match?([_, "approve", ^sha], Regex.run(@marker_re, &1)))

  @doc "Splits `.dev-loop/pr.md`: first line is the title, the rest the body."
  def parse_pr(text, number) do
    [title | rest] = text |> String.trim() |> String.split("\n", parts: 2) |> Kernel.++([""])
    title = title |> String.trim_leading("#") |> String.trim()
    body = rest |> hd() |> String.trim()

    body =
      if Regex.match?(~r/\b(Closes|Refs) ##{number}\b/, body),
        do: body,
        else: String.trim("#{body}\n\nCloses ##{number}")

    {title, body}
  end

  @doc "Validates `.dev-loop/review.json`."
  def parse_review(json) do
    with {:ok, %{"verdict" => v} = r} when v in ["approve", "rework", "human"] <-
           JSON.decode(json) do
      {:ok,
       %{
         verdict: v,
         summary: Map.get(r, "summary", ""),
         brief: Map.get(r, "brief", ""),
         findings: Map.get(r, "findings", [])
       }}
    else
      _ -> {:error, :invalid_review}
    end
  end

  @doc "Validates `.dev-loop/po.json`: a list of `{issue, comment, proposals}`."
  def parse_po(json, allowed) do
    case JSON.decode(json) do
      {:ok, items} when is_list(items) ->
        {:ok,
         for %{"issue" => n} = item <- items, n in allowed do
           %{
             issue: n,
             comment: Map.get(item, "comment", ""),
             proposals: Map.get(item, "proposals", "")
           }
         end}

      _ ->
        {:error, :invalid_po}
    end
  end

  # Usage-limit messages of Claude Code (code.claude.com/docs/en/errors,
  # checked 2026-11-07) end a session without useful work; the agent runner
  # then switches to the next account of the chain. "Server is temporarily
  # limiting requests (not your usage limit)" is retried by Claude Code
  # itself and must not match.
  @exhausted_re ~r/hit your \w+ limit|spend limit reached|usage limit reached|out of extra usage|credit balance is too low/i

  def exhausted?(text), do: Regex.match?(@exhausted_re, text)

  def render(template, assigns) do
    Enum.reduce(assigns, template, fn {k, v}, acc ->
      String.replace(acc, "{{#{k}}}", to_string(v))
    end)
  end

  @doc "The ticket as the agents read it: title, labels, body, comments."
  def issue_text(i) do
    comments =
      case i.comments do
        [] -> "(keine)"
        list -> Enum.join(list, "\n\n---\n\n")
      end

    """
    ### ##{i.number} #{i.title}

    Labels: #{Enum.join(i.labels, ", ")}

    #{i.body}

    #### Kommentare

    #{comments}
    """
  end

  def findings_text(review) do
    lines =
      Enum.map_join(review.findings, "\n", fn f ->
        "- `#{f["file"]}:#{f["line"]}` #{f["text"]}"
      end)

    String.trim("Das Review verlangt Rework.\n\n#{review.summary}\n\n#{lines}")
  end

  def review_comment(review, sha) do
    findings =
      Enum.map_join(review.findings, "\n", fn f ->
        "- `#{f["file"]}:#{f["line"]}` #{f["text"]}"
      end)

    """
    #{marker(review.verdict, sha)}
    **Review (dev-loop): #{review.verdict}**

    #{review.summary}
    #{if findings != "", do: "\n**Befunde:**\n" <> findings, else: ""}
    """
    |> String.trim()
  end

  @doc "The morning comment: one section per outcome, empty sections left out."
  def brief(report) do
    sections = [
      {"Gemergt", report.merged},
      {"Wartet auf GO", report.await_go},
      {"An Mensch übergeben", report.human},
      {"PO-Vorschläge", report.po}
    ]

    body =
      for {title, [_ | _] = items} <- sections, into: "" do
        "### #{title}\n\n" <> Enum.map_join(items, "\n", &"- #{&1}") <> "\n\n"
      end

    """
    ## Dev-Loop-Lauf #{report.started} – #{report.finished}

    #{if body == "", do: "Nichts zu tun gefunden.\n\n", else: body}**Ende:** #{report.reason}
    """
  end
end
