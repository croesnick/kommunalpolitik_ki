# Lane-Protokoll: Wayfinder-Tickets bearbeiten, verifizieren und abschließen

Stand: 2026-10-15. Dieses Protokoll legt fest, wie eine Session (Lane) ein Wayfinder-Ticket dieses Repos umsetzt und abschließt — mit selbst nachprüfbarem Abschluss statt Rückfrage. Es gilt für dispatched Lanes (herdr-Worktrees) und für Cold-Sessions, die ein Ticket vom Frontier nehmen. Ursprung: Lane-Review vom 2026-10-15 mit Oracle-Gegenprüfung — die Abnahmekriterien standen bisher in Dispatch-Prompts; künftig leben sie hier und im Ticket, für alle sichtbar.

## Ticket-Anatomie

Ein Ticket dieser Map trägt sechs Abschnitte, die zusammen das Ziel tragen:

| Abschnitt | Inhalt |
|---|---|
| `## Question` | Was dieses Ticket entscheidet oder baut |
| `## Erwartung` | Der messbare Endzustand in ein bis zwei Sätzen |
| `## Zu messen / Zu verifizieren` | Die Abnahmeliste: Tests, Smoke-Kommandos, Negativkontrollen |
| `## Bewusst offen (prä-deklariert)` | Nicht-Ziele bereits beim Charting; „fertig“ schließt sie nachweisbar aus |
| `## Verträge & Stacking` | Geteilte Verträge: was dieses Ticket ändern darf, was eingefroren ist, der Basis-Branch |
| `## Abhängigkeiten` | Entscheidungen aus anderen Tickets, die hier gelten |

Fehlt ein Abschnitt, ergänzt die Lane die Abnahme aus den im Ticket verlinkten Quellen (RFC-Kapitel, Forschungsdokumente) und schreibt die Ergänzung als Kommentar aufs Ticket. Nie still.

## Gates (Pflicht vor jedem Abschluss)

Maßgeblich ist die Tooling-Tabelle in [AGENTS.md](../../AGENTS.md): im Root `mix format --check-formatted` und `mix workspace.run -t compile -- --warnings-as-errors`, credo strict, Tests; dialyzer app-lokal. Ein rotes Gate ist kein Abschluss, sondern ein Rest im Ticket-Kommentar.

## Umgebungsfallen (kosten Fehlversuche, wenn unbekannt)

- `gh` in herdr-Worktrees: immer `gh <Befehl> --repo croesnick/kommunalpolitik_ki`. Ohne `--repo` kommt still nichts zurück, auch bei `gh issue view` nicht.
- Bash-Denyliste dieses Harness: `grep`, `cat`, `echo`, `sed`, `awk`, `rm` sind gesperrt. Dateiinhalte über die Read-, Grep-, Edit- und Write-Tools; Ausgaben über `printf`.
- Γ-Konsum von komki_policy: `apps/komki_policy/CONTRACT.md` ist die verbindliche Grenze (Schemas, Basisfakten, Blocker-Codes). Die Engine ist die einzige Schemainstanz; der Store schreibt keine eigenen Prüfungen.

## Abschluss-Protokoll

1. Commits auf dem Lane-Branch; die Ticket-Nummer steht in der Commit-Nachricht.
2. Resolution-Kommentar auf dem Ticket mit drei Abschnitten: **Gebaut** (was, wo, welcher Commit), **Bewusst offen** (was nicht, mit Folge-Zeiger), **Verifiziert** (Gates, Smoke- und Testbefehle).
3. Ticket schließen und den Board-Status auf Done setzen (Projektführung siehe AGENTS.md).
4. Die Map (das `wayfinder:map`-Issue) pflegt die Orchestrator-Session. Lanes editieren sie nicht.

## Eskalation statt Stillentscheidung

Eine Lane deutet eine Anforderung nie still um. Steht der Ticket-Wortlaut gegen die Umsetzbarkeit: Kommentar aufs Ticket, das Ticket bleibt blockiert. Entscheidungen, die dem Menschen gehören — Pins, Freigaben, Grenz-Anhebungen — werden vorgeschlagen, nie vollzogen (GO-Prinzip, AGENTS.md).
