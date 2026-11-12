# Lane protocol: work and close a wayfinder ticket

Updated: 2026-11-12. This protocol tells a session how to work a wayfinder ticket from claim to close: read the ticket, build the smallest slice that satisfies it, verify, and record the result. It covers two cases: a dispatched lane in a herdr worktree, and a cold session that takes a ticket from the frontier.

Acceptance criteria used to live in per-dispatch prompts, and a dispatch prompt dies with its session. The criteria now live in the ticket and in this protocol. If a line would have to appear in a dispatch prompt, put it in the ticket body or here.

## Read the ticket as a contract

A ticket on this map carries six sections:

| Section | What it holds |
|---|---|
| `## Ziel` | What this ticket decides or builds. |
| `## Erwartung` | The measurable end state, in one or two sentences. |
| `## Zu messen / Zu verifizieren` | The acceptance list: tests, smoke commands, negative controls. |
| `## Bewusst offen` | Non-goals, declared at charting time. Done provably excludes them. |
| `## Vereinbarungen` | Shared contracts: what this ticket may change, what is frozen, and the base branch. |
| `## Abhängigkeiten` | Decisions from other tickets that apply here. |

The section headings are the charting terms of this map and stay in German.

If a section is missing, derive the acceptance criteria from the sources the ticket links (RFC chapters, research documents) and record the derivation as a comment on the ticket.

## Gates

Run the gates from the tooling table in [AGENTS.md](../../AGENTS.md) before you close a ticket: format, compile with warnings as errors, credo strict, dialyzer, and tests. A red gate means the ticket stays open. Record what failed and what remains in a comment on the ticket.

## Prüfbericht: the verification report

A ticket ends with a Prüfbericht. The human reads the result and this report instead of the diff (#460). The report is German because the human reads it.

```markdown
## Prüfbericht

| Prüfpunkt | Ergebnis | Nachweis |
|---|---|---|
| Punkt aus „Fertig, wenn“ | bestanden | `mix test test/pfad_test.exs:42` |
| noch ein Punkt | nicht bestanden | Befehl und die entscheidende Zeile der Ausgabe |
| noch ein Punkt | nicht geprüft | warum nicht, und wie es sich prüfen lässt |

### Entscheidungen, die die Umsetzung selbst getroffen hat

- Was festgelegt wurde, mit Grund und Quelle. Weicht vom Bestand ab: ja oder nein.
```

- **Who grades.** Not the session that built. In the dev loop the review session grades, and the script renders the table into its comment on the PR. In an interactive session, give a fresh subagent that has not seen the conversation the ticket, the base ref, and your claims, and let it write the report. Nothing enforces this in an interactive session yet (#462). Until then it is a request.
- **Rows.** One per point the ticket agrees on (`Fertig, wenn` or `Zu messen / Zu verifizieren`), plus one per checkpoint of every area the diff touches, as listed in [pruefpunkte.md](pruefpunkte.md).
- **Results.** `bestanden` needs evidence the grader has seen itself: a test name, a command with the line of output that decides, a screenshot, a real run. Measure against the ticket and against how the rest of the product behaves, not against what the builder intended. `nicht geprüft` is a valid result, with the reason. It never counts as `bestanden`.
- **What the builder supplies.** Per point, the test or command that checks it. And the decisions it took on its own: everything that neither the ticket, the canonical documents, nor the existing code prescribe. A deviation from how the existing product behaves is always a decision, even when a source backs it. Ask before you build one in an interactive session, and escalate in the dev loop if it belongs to the human. The grader looks for decisions in the diff before it reads the builder's list, and marks what the list leaves out.
- **Where it goes.** In the dev loop, the review comment on the PR. In an interactive session, under `Evidence` in the PR body and as the closing message to the human.
- **What slipped through.** When a review or the human finds something that no checkpoint caught, propose a new checkpoint, ideally as an automatic check ([pruefpunkte.md](pruefpunkte.md#neue-prüfpunkte)). The human decides whether it goes in.

## Independent review before the PR is done

For `ai:s-tier` and `ai:a-tier` tickets, an interactive session runs an independent review before it reports the PR as done ([ai-tiers.md](ai-tiers.md#prüfung-vor-dem-merge)). The reviewer is a fresh subagent that has not seen the conversation, for example the skill `code-review` against `origin/main`. It may be the same subagent that writes the Prüfbericht. It gets the ticket, the base ref, the checkpoints of the touched areas, and the builder's list of decisions, and it checks the diff against all of them. It looks for decisions in the diff before it reads the list.

- Append the result to the Prüfbericht: one line with the reviewed commit, then the findings.
- Fix each finding, or hand it to the human as a decision with your proposal. Never drop a finding silently.
- A fix after the review is not reviewed. Say so in the report and name the commit, or run the review again.

## Traps that cost failed attempts

- When you work in a herdr worktree, run every `gh` command with `--repo croesnick/kommunalpolitik_ki`. Without `--repo`, gh returns empty output without an error, even for `gh issue view`.
- The bash deny-list of this harness blocks `grep`, `cat`, `echo`, `sed`, `awk`, and `rm`. Read and change files with the Read, Grep, Edit, and Write tools. Produce shell output with `printf`.
- Treat `apps/komki_policy/CONTRACT.md` as the binding boundary for Γ consumption: schemas, base facts, and blocker codes live there. `KomkiPolicy.Registry.compile/1` is the only schema instance. A store writes no schema checks of its own.

## Close the ticket

1. Commit on the lane branch. Reference the ticket number in the commit message.
2. Open the PR with `Closes #<n>` in its body. In an interactive session the body also carries the Prüfbericht under `## Evidence`. The merge closes the ticket, and the board workflow moves it to Done. `(Ticket #<n>)` in the title or in commits does not close anything. If the PR deliberately covers only part of the ticket, write `Refs #<n>` and one sentence on what remains. Do not close the ticket by hand.
3. Post a resolution comment on the ticket with three parts. `Gebaut` states what you built, where, and in which commit. `Bewusst offen` states what you deliberately left out and where the follow-up lives. `Verifiziert` links the Prüfbericht on the PR, or holds it if there is no PR.
4. Leave the map alone. The `wayfinder:map` issue is maintained by the orchestrator session that charted it.

## Escalate instead of reinterpreting

If the ticket's wording conflicts with what is implementable, comment on the ticket and leave it blocked. Decisions that belong to the human, such as pins, releases, and boundary raises, go into a comment as a proposal (GO-Prinzip, AGENTS.md). A lane proposes, the human decides.

If the ticket carries `ai:a-tier` or `ai:b-tier` and the work turns out to touch a protected path listed in [ai-tiers.md](ai-tiers.md), stop, comment on the ticket, and propose `ai:s-tier`. Read the `## Zielbild` comment as part of the contract.
