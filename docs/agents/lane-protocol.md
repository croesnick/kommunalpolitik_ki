# Lane protocol: work and close a wayfinder ticket

Updated: 2026-10-15. This protocol tells a session how to work a wayfinder ticket from claim to close: read the ticket, build the smallest slice that satisfies it, verify, and record the result. It covers two cases: a dispatched lane in a herdr worktree, and a cold session that takes a ticket from the frontier.

Acceptance criteria used to live in per-dispatch prompts, and a dispatch prompt dies with its session. The criteria now live in the ticket and in this protocol. If a line would have to appear in a dispatch prompt, put it in the ticket body or here.

## Read the ticket as a contract

A ticket on this map carries six sections:

| Section | What it holds |
|---|---|
| `## Question` | What this ticket decides or builds. |
| `## Erwartung` | The measurable end state, in one or two sentences. |
| `## Zu messen / Zu verifizieren` | The acceptance list: tests, smoke commands, negative controls. |
| `## Bewusst offen (prä-deklariert)` | Non-goals, declared at charting time. Done provably excludes them. |
| `## Verträge & Stacking` | Shared contracts: what this ticket may change, what is frozen, and the base branch. |
| `## Abhängigkeiten` | Decisions from other tickets that apply here. |

The section headings are the charting terms of this map and stay in German.

If a section is missing, derive the acceptance criteria from the sources the ticket links (RFC chapters, research documents) and record the derivation as a comment on the ticket.

## Gates

Run the gates from the tooling table in [AGENTS.md](../../AGENTS.md) before you close a ticket: format, compile with warnings as errors, credo strict, dialyzer, and tests. A red gate means the ticket stays open. Record what failed and what remains in a comment on the ticket.

## Traps that cost failed attempts

- When you work in a herdr worktree, run every `gh` command with `--repo croesnick/kommunalpolitik_ki`. Without `--repo`, gh returns empty output without an error, even for `gh issue view`.
- The bash deny-list of this harness blocks `grep`, `cat`, `echo`, `sed`, `awk`, and `rm`. Read and change files with the Read, Grep, Edit, and Write tools. Produce shell output with `printf`.
- Treat `apps/komki_policy/CONTRACT.md` as the binding boundary for Γ consumption: schemas, base facts, and blocker codes live there. `KomkiPolicy.Registry.compile/1` is the only schema instance. A store writes no schema checks of its own.

## Close the ticket

1. Commit on the lane branch. Reference the ticket number in the commit message.
2. Post a resolution comment on the ticket with three parts. `Gebaut` states what you built, where, and in which commit. `Bewusst offen` states what you deliberately left out and where the follow-up lives. `Verifiziert` states the gates and the smoke and test commands you ran.
3. Close the ticket and set its board status to Done. The project commands live in AGENTS.md under Projekt-Verwaltung.
4. Leave the map alone. The `wayfinder:map` issue is maintained by the orchestrator session that charted it.

## Escalate instead of reinterpreting

If the ticket's wording conflicts with what is implementable, comment on the ticket and leave it blocked. Decisions that belong to the human, such as pins, releases, and boundary raises, go into a comment as a proposal (GO-Prinzip, AGENTS.md). A lane proposes, the human decides.
