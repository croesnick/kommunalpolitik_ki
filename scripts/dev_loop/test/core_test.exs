# elixir scripts/dev_loop/test/core_test.exs

ExUnit.start()
Code.require_file("../core.exs", __DIR__)

defmodule DevLoop.CoreTest do
  use ExUnit.Case, async: true

  alias DevLoop.Core

  defp issue(number, labels, extra \\ []) do
    Map.merge(
      %{
        number: number,
        title: "T#{number}",
        body: "",
        labels: labels,
        assignees: [],
        open_blockers: 0,
        comments: []
      },
      Map.new(extra)
    )
  end

  describe "protected paths" do
    test "every path named in ai-tiers.md is covered" do
      section =
        Path.expand("../../../docs/agents/ai-tiers.md", __DIR__)
        |> File.read!()
        |> String.split("## Geschützte Pfade")
        |> Enum.at(1)
        |> String.split("\n## ")
        |> hd()

      tokens =
        for [_, t] <- Regex.scan(~r/`([^`]+)`/, section), not String.starts_with?(t, "ai:"), do: t

      assert tokens != []

      for t <- tokens do
        assert Enum.any?(Core.tier_protected(), &String.contains?(&1, t)), "not covered: #{t}"
      end
    end

    test "directories protect everything below, files only themselves" do
      assert Core.protected_hits(["apps/seatbelt/lib/x.ex"]) == ["apps/seatbelt/lib/x.ex"]
      assert Core.protected_hits(["apps/komki_cli/lib/komki_cli/tresor/core.ex"]) != []
      assert Core.protected_hits(["apps/komki_cli/lib/komki_cli/doctor.ex"]) == []
      assert Core.protected_hits(["apps/komki_mediator/lib/komki_mediator/gate_helper.ex"]) == []
    end

    test "the loop's own rules are protected" do
      for p <- [
            "scripts/dev_loop.exs",
            "scripts/dev_loop/prompts/review.md",
            ".github/workflows/ci.yml",
            "AGENTS.md"
          ] do
        assert Core.protected_hits([p]) == [p]
      end
    end
  end

  describe "candidates/2" do
    test "only ready A/B tickets without blocker, assignee or running lane" do
      issues = [
        issue(1, ["ready-for-agent", "ai:b-tier"]),
        issue(2, ["ready-for-agent", "ai:s-tier"]),
        issue(3, ["ai:b-tier"]),
        issue(4, ["ready-for-agent", "ai:a-tier"], open_blockers: 1),
        issue(5, ["ready-for-agent", "ai:a-tier"], assignees: ["croesnick"]),
        issue(6, ["ready-for-agent", "ai:a-tier"])
      ]

      assert Enum.map(Core.candidates(issues, [6]), & &1.number) == [1]
    end

    test "order: next, then B before A, then number" do
      issues = [
        issue(10, ["ready-for-agent", "ai:a-tier"]),
        issue(11, ["ready-for-agent", "ai:b-tier"]),
        issue(12, ["ready-for-agent", "ai:a-tier", "next"]),
        issue(9, ["ready-for-agent", "ai:a-tier"])
      ]

      assert Enum.map(Core.candidates(issues, []), & &1.number) == [12, 11, 9, 10]
    end
  end

  test "busy/3 collects PR links, PR and worktree branches, and In Progress" do
    prs = [
      %{number: 390, branch: "lane-383-tool-call-loops", closes: []},
      %{number: 391, branch: "ris-mock-339", closes: [339]},
      %{number: 384, branch: "sealed-envelope-335", closes: [224]},
      %{number: 325, branch: "renovate/python-3.x", closes: []}
    ]

    worktrees = [
      "main",
      "lane-152-deps-advisories",
      "lane-22-32-37-ratsprojekte",
      "llama-server-0.9.0",
      "loop/392"
    ]

    assert Enum.sort(Core.busy(prs, worktrees, [295])) == [
             22,
             32,
             37,
             152,
             224,
             295,
             335,
             339,
             383,
             392
           ]
  end

  describe "po_candidates/1" do
    test "needs-triage or A/B without Zielbild; off-limits labels and done tickets skipped" do
      issues = [
        issue(1, ["needs-triage"]),
        issue(2, ["ai:a-tier"]),
        issue(3, ["ai:b-tier"], body: "## Zielbild\n**Ziel:** x"),
        issue(4, ["ai:a-tier"], comments: ["## Zielbild\n..."]),
        issue(5, ["needs-triage", "ai:s-tier"]),
        issue(6, ["needs-triage", "wayfinder:grilling"]),
        issue(7, ["needs-triage", "ready-for-human"]),
        issue(8, ["needs-triage"], comments: [Core.po_marker() <> " Entwurf"])
      ]

      assert Enum.map(Core.po_candidates(issues, []), & &1.number) == [1, 2]
      assert Enum.map(Core.po_candidates(issues, [1]), & &1.number) == [2]
    end

    test "at most five per run" do
      issues = for n <- 1..8, do: issue(n, ["needs-triage"])
      assert length(Core.po_candidates(issues, [])) == 5
    end
  end

  describe "decide/4" do
    test "protected path always goes to the human" do
      assert Core.decide(:b, "approve", ["apps/seatbelt/x.ex"], 0) == :human
    end

    test "approve merges B, waits for GO on A, never merges S" do
      assert Core.decide(:b, "approve", [], 0) == :merge
      assert Core.decide(:a, "approve", [], 1) == :await_go
      assert Core.decide(:s, "approve", [], 0) == :human
      assert Core.decide(nil, "approve", [], 0) == :human
    end

    test "rework until the limit, then the human" do
      assert Core.decide(:b, "rework", [], 0) == :rework
      assert Core.decide(:b, "rework", [], 1) == :rework
      assert Core.decide(:b, "rework", [], 2) == :human
      assert Core.decide(:a, "human", [], 0) == :human
    end
  end

  describe "review markers" do
    test "count rework rounds and find approval of a given head" do
      comments = [
        Core.marker("rework", "aaa") <> "\nBefund",
        "unrelated comment",
        Core.marker("rework", "bbb"),
        Core.marker("approve", "ccc")
      ]

      assert Core.rework_rounds(comments) == 2
      assert Core.approved?(comments, "ccc")
      refute Core.approved?(comments, "bbb")
    end
  end

  describe "parse_pr/2" do
    test "title from first line, Closes appended when missing" do
      assert Core.parse_pr("# Titel\n\nText", 7) == {"Titel", "Text\n\nCloses #7"}

      assert Core.parse_pr("Titel\nRefs #7, weil Rest offen", 7) ==
               {"Titel", "Refs #7, weil Rest offen"}

      assert Core.parse_pr("Nur Titel", 7) == {"Nur Titel", "Closes #7"}
    end

    test "a different ticket number does not count" do
      assert {_, "Closes #70\n\nCloses #7"} = Core.parse_pr("T\nCloses #70", 7)
    end
  end

  describe "parse_review/1 and parse_po/2" do
    test "accepts the three verdicts only" do
      assert {:ok, %{verdict: "rework", findings: [_]}} =
               Core.parse_review(
                 ~s({"verdict":"rework","findings":[{"file":"a","line":1,"text":"x"}]})
               )

      assert {:error, :invalid_review} = Core.parse_review(~s({"verdict":"merge"}))
      assert {:error, :invalid_review} = Core.parse_review("kein json")
    end

    test "drops PO items for tickets it was not given" do
      json = ~s([{"issue":1,"comment":"c"},{"issue":99,"comment":"x"}])
      assert {:ok, [%{issue: 1, comment: "c"}]} = Core.parse_po(json, [1, 2])
    end
  end

  test "exhausted?/1 recognises usage-limit messages" do
    assert Core.exhausted?("You've hit your session limit · resets 3:45pm")
    assert Core.exhausted?("You've hit your weekly limit · resets Mon 12:00am")
    assert Core.exhausted?("You've hit your Opus limit · resets 3:45pm")
    assert Core.exhausted?("spend limit reached (daily; resets 2026-08-09 00:00 UTC)")
    assert Core.exhausted?("Claude AI usage limit reached|1762560000")
    refute Core.exhausted?("Server is temporarily limiting requests (not your usage limit)")
    refute Core.exhausted?("All tests passed")
  end

  test "brief/1 leaves out empty sections" do
    text =
      Core.brief(%{
        started: "22:00",
        finished: "07:00",
        merged: ["#392 Tag – PR #400: Anders: x\nGeprüft: y"],
        await_go: [],
        human: [],
        po: [],
        reason: "Zeitfenster abgelaufen"
      })

    assert text =~ "### Gemergt"
    assert text =~ "- #392 Tag – PR #400: Anders: x\n  Geprüft: y"
    refute text =~ "Wartet auf GO"
    assert text =~ "**Ende:** Zeitfenster abgelaufen"
  end
end
