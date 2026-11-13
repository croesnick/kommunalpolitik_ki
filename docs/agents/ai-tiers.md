# AI-Stufen: welches Modell welches Ticket bekommt

Stand: 2026-11-12. Die Labels `ai:s-tier`, `ai:a-tier` und `ai:b-tier` sagen, **was ein Ticket verlangt**, nicht welches Modell es bekommt. Welche Modelle eine Stufe heute tragen, steht in der Tabelle unten. Diese Tabelle veraltet schnell, die Stufen nicht.

Ein Ticket bekommt die Stufe seiner anspruchsvollsten Teilaufgabe. Im Zweifel gilt die höhere Stufe.

## Die drei Stufen

| Label | Kurz | Verlangt | Typische Tickets |
|---|---|---|---|
| `ai:s-tier` | Grenze und Urteil | Ändert die Sicherheitsgrenze oder entscheidet über sie (Policy, Γ, Journal, Sandbox-Profile, Zugangsdaten, Connector-Filter) oder trifft eine offene Entwurfsentscheidung über mehrere Apps oder gegen den RFC. Fehler bleiben leicht unbemerkt und wiegen schwer. | #205, #213, #215, #240, #148 |
| `ai:a-tier` | Feature mit Vertrag | Ein abgegrenztes Feature oder ein Bugfix in ein, zwei Apps, nach vorhandenen Mustern. Die Abnahme braucht einen echten Lauf, nicht nur Tests. Berührt keine geschützten Pfade (unten). | #242, #262, #164, #158, #151 |
| `ai:b-tier` | Handwerk | Lokal und eher mechanisch: Doku, Konfiguration, Felder, Python-Tools außerhalb von komki, Umbenennungen. Die Abnahme lässt sich vollständig mit Tests, Lint oder einem kurzen Befehl prüfen. | #172, #37, #43, #53 |

Tickets mit `ready-for-human` brauchen zuerst eine Entscheidung der nutzenden Person. Die Stufe gilt für die Umsetzung danach.

## Geschützte Pfade

Berührt ein `ai:a-tier`- oder `ai:b-tier`-Ticket einen dieser Pfade, hört die Session auf, schreibt einen Kommentar ins Ticket und schlägt `ai:s-tier` vor. Sie baut nicht weiter.

- `apps/komki_policy/`, beide `CONTRACT.md` (`apps/komki_policy/`, `apps/komki_connector/`)
- `apps/komki_mediator/lib/komki_mediator/` mit `gate.ex`, `connector_gate.ex`, `go.ex`, `go_stand.ex`, `pdr.ex`, `journal.ex`, `room.ex`, `gamma.ex`, `http.ex`
- `apps/seatbelt/`, `apps/sidecar/`, `apps/komki_egress/`
- in `apps/komki_cli/lib/komki_cli/`: `profile.ex`, `connector_profile.ex`, `mediator_profile.ex`, `escript_profile.ex`, `pins.ex`, `channel.ex`, `keychain.ex`, `secrets.ex`, `tresor.ex`, `tresor/`, `go_steps.ex`, `go_watcher.ex`
- die Filter der Connectoren: `apps/komki_connector_ris/lib/komki_connector_ris/top.ex` (öffentlich oder nicht), `apps/komki_connector_vault/lib/komki_connector_vault/paths.ex` und `note.ex` (Pfade und Labels)
- `docs/rfcs/`

## Zielbild für günstigere Modelle

Ein `ai:a-tier`- oder `ai:b-tier`-Ticket hat ein Zielbild. Es beschreibt das Ziel, nicht den Weg. Den Weg findet die Session selbst. Fehlt das Zielbild im Ticket, steht es als Kommentar darunter:

```markdown
## Zielbild
**Ziel:** ein bis zwei Sätze, was danach anders ist und für wen.
**Fertig, wenn:**
- [ ] prüfbare Punkte (Test, Befehl, echter Lauf, Doku-Seite)
**Nicht anfassen:** was außerhalb liegt, mindestens die geschützten Pfade
**Kontext:** nur, was man aus dem Repo nicht sieht (Entscheidungen, Richtung)
```

## Prüfung vor dem Merge

- `ai:s-tier`: Self-Review, ein unabhängiges Review mit frischem Kontext wie bei `ai:a-tier` und, wo das Ticket es verlangt, ein echter Lauf. Danach reviewt die nutzende Person.
- `ai:a-tier`: Self-Review, echter Lauf und ein unabhängiges Review mit frischem Kontext, bevor der PR als fertig gilt. Das Review macht eine frische Session, etwa der Skill `code-review` oder die Review-Rolle des Dev-Loops. Es prüft den Diff gegen das Zielbild, die [Prüfpunkte des Bereichs](pruefpunkte.md) und die Entscheidungen, die die Umsetzung angibt. Das Ergebnis steht im Prüfbericht. Jeder Befund wird behoben oder als Entscheidung an die nutzende Person übergeben. Ablauf in interaktiven Sessions: [Lane-Protokoll](lane-protocol.md#independent-review-before-the-pr-is-done).
- `ai:b-tier`: Ein Modell der Stufe S oder A oder die nutzende Person liest den Diff, bevor er gemergt wird. Günstige Modelle übersehen eher Nebenwirkungen als offensichtliche Fehler.

Der Dev-Loop ([dev-loop.md](dev-loop.md)) setzt diese Regeln im Code durch. Er mergt nur `ai:b-tier`, und nur nach einem Review durch ein S-Modell. Bei `ai:a-tier` endet er bei „In Review“ und wartet auf das GO. `ai:s-tier` und Diffs, die geschützte Pfade berühren, übergibt er an die nutzende Person.

## Welche Modelle heute welche Stufe tragen

Quelle: [Artificial Analysis, Leaderboard Models](https://artificialanalysis.ai/leaderboards/models), abgerufen am 2026-10-29. Der Intelligence Index ist ein zusammengesetzter Benchmark und kein Maß für Elixir-Kenntnis oder Deutsch. Die Zuordnung ist ein Startwert. Bewährt sich ein Modell in einer Stufe nicht, wird diese Tabelle angepasst, nicht das Label.

| Stufe | Intelligence Index | Beispiele (Index, Kosten je Aufgabe) |
|---|---|---|
| S | ab etwa 55 | Gemini 4 Carbon high (59, 7,76 USD), Claude Opus 5.5 xhigh (57, 6,05 USD), GPT-6 Astra xhigh (55, 3,66 USD) |
| A | etwa 45 bis 54 | GPT-6.1 Sol high (50, 0,59 USD), Claude Sonnet 5.5 xhigh (50, 4,09 USD), Kimi K3.1 Pro (46, 3,68 USD) |
| B | etwa 30 bis 44 | Qwen3.8 Max (34, 10,02 USD), GLM-5.3 max (32, 5,01 USD), DeepSeek V4.1 Flash max (32, 0,60 USD) |

Die Kosten je Aufgabe hängen stark vom Reasoning-Niveau ab. Ein günstiges Modell auf höchster Stufe ist nicht automatisch billiger als ein stärkeres auf mittlerer Stufe.
