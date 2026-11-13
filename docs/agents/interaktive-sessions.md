# Interaktive Sessions: Grenzen und Hooks

Stand: 2026-11-12. Für jede Claude-Code-Session in diesem Repo gilt `.claude/settings.json` (#462). Die Regeln folgen den Grenzen des [Dev-Loops](dev-loop.md), soweit sie zur interaktiven Arbeit passen. Faustregel: Was sich nach einem Fehler nicht zurückholen lässt, wird eine Regel. Was sich zurückholen lässt, darf das Modell entscheiden. Echte Ratsdaten in einem Transkript lassen sich nicht zurückholen.

## Lesesperre

Diese Orte sind für die Session gesperrt, für das Read-Tool (`permissions.deny`) und für jeden Befehl in der Bash-Sandbox samt Kindprozessen (`sandbox.filesystem.denyRead`):

- `~/Library/Application Support/ratsprojekte/`, der echte Hub mit Datenbank, Siegel, Connector-Hash und Sockets. Ausnahme ist die Entwicklungsdatenbank `dev.db` mit ihren Begleitdateien: In der Sandbox darf ein Befehl sie lesen und schreiben, für das Read-Tool bleibt sie gesperrt.
- `~/Library/Mobile Documents/iCloud~md~obsidian/`, alle Obsidian-Vaults in iCloud
- `~/.ssh`, `~/.config/gh` und `~/Library/Keychains`

Außerdem verboten sind `security`, `ssh` und `scp` als Bash-Befehle.

## Sandbox

Bash-Befehle laufen in der Sandbox von Claude Code (`sandbox.enabled`, `failIfUnavailable`). Ohne Sandbox startet die Session nicht.

- **Schreiben** geht im Worktree, in den Hex- und Mix-Caches, in `~/.cache`, in `/tmp` und auf `dev.db`.
- **Unix-Sockets** gehen nur unter `/tmp`, wo die Tests ihre Sockets anlegen. Die Sockets des echten Hubs liegen nicht dort.
- **Lokale Ports** gehen (`allowLocalBinding`), etwa für `mix phx.server`.
- **Netz:** Erreichbar sind Hex, npm, PyPI und GitHub. Andere Ziele lehnt die Sandbox im Auto-Modus ab, in den übrigen Modi fragt sie nach.
- **Außerhalb der Sandbox** laufen `gh` und `git push`, `git fetch` und `git pull`. Sie brauchen Zugangsdaten aus den gesperrten Orten. Sie gehen weiter durch die Regeln und den Auto-Modus.
- **Seatbelt in der Sandbox:** Tests, die selbst `sandbox-exec` starten, scheitern in der Sandbox mit `sandbox_apply: Operation not permitted`. macOS lässt in einer laufenden Seatbelt-Sandbox kein zweites Profil zu. Das betrifft Teile von `apps/komki_cli` und `apps/seatbelt`. Der Stop-Hook läuft außerhalb der Sandbox und prüft sie trotzdem. Eine Session darf solche Befehle außerhalb der Sandbox wiederholen (Entscheidung der nutzenden Person vom 2026-11-12). Im Auto-Modus entscheidet der Klassifikator.

## Hooks

- **Stop-Hook** (`.claude/hooks/stop_gates.exs`): Weicht der Stand des Worktrees von `origin/main` ab, endet ein Zug erst, wenn `mix format --check-formatted` und die Tests der betroffenen Apps grün sind (`mix workspace.run -t test --affected --base origin/main`). Bei Rot endet der Hook mit Exit-Code 2, und die Session arbeitet weiter, mit den fehlgeschlagenen Tests als Begründung. Ist sie schon wegen des Hooks weitergelaufen (`stop_hook_active`), blockiert er kein zweites Mal und meldet der nutzenden Person, dass die Gates rot bleiben. Ein grüner Stand wird gemerkt. Läuft der Hook wieder ohne Änderung, prüft er ihn nicht noch einmal.
- **PreToolUse-Hook** (`.claude/hooks/pr_report.exs`): `gh pr create` wird abgelehnt, solange der PR-Text keinen Prüfbericht nach dem [Lane-Protokoll](lane-protocol.md#prüfbericht-the-verification-report) hat: Überschrift, Tabelle, Abschnitt mit den Entscheidungen und den aktuellen Head-Commit. Der Hook liest den Text aus `--body`, `--body-file` oder `-F`.

Gemessen am 2026-11-12, bei gleichzeitiger Last durch einen zweiten Testlauf: Nur Doku geändert oder keine Änderung gegenüber dem letzten grünen Stand, etwa 1 s. Eine Änderung nur in `apps/ratsprojekte`: 18 s. Eine Änderung in `apps/sidecar`, die alle abhängigen Apps mitnimmt: 74 s. Tests: `elixir .claude/hooks/test/hooks_test.exs`.

## Was die Regeln garantieren und was nicht

- Sandbox, Deny-Regeln und Hooks sind Policy von Claude Code. Eine Trennung durch das Betriebssystem ist das nicht. Die Session läuft im Konto der nutzenden Person. Ein eigenes macOS-Konto wäre die härtere Variante, wie beim Dev-Loop bewusst nicht gewählt.
- Die Sandbox sperrt Bash und dessen Kindprozesse. Das Read-Tool sperren nur die Deny-Regeln. Ein Pfad, der in keiner der beiden Listen steht, ist lesbar.
- Hooks und MCP-Server laufen außerhalb der Sandbox, mit allen Rechten des Kontos.
- Ein Befehl kann die Sandbox verlassen (`dangerouslyDisableSandbox`). Im Auto-Modus entscheidet dann der Klassifikator, sonst fragt Claude Code nach. Die Deny-Regeln für Bash-Befehle und das Read-Tool gelten weiter, die Lesesperre der Sandbox aber nicht.
- Der PR-Hook prüft die Form des Prüfberichts. Ob ein Nachweis trägt und ob wirklich eine Session geprüft hat, die nicht gebaut hat, prüft er nicht. Das bleibt beim unabhängigen Review (#463).
- Der Stop-Hook prüft Format und Tests. Compile-Warnungen, Credo und Dialyzer prüft weiter die CI.
- Für die Bash-Sandbox gelten die Muster von Claude Code. Neue Orte mit echten Daten kommen hier und in `.claude/settings.json` dazu, sobald es sie gibt.

## Prüfen

Nach jeder Änderung an `.claude/settings.json` läuft eine Probe wie `elixir scripts/dev_loop.exs --check-sandbox`: eine Session mit `claude -p --permission-mode auto` im Worktree, die gesperrte Orte zu lesen versucht und die Positivkontrollen ausführt. Die Befehle der Probe zeigen nur Zähler und Byte-Zahlen, nie Inhalte. Letzte Probe am 2026-11-12, Claude Code 2.1.311:

- **Abgelehnt:** `ls` und `wc -c` im Hub-Ordner, `ls` im iCloud-Ordner von Obsidian, `wc -c ~/.ssh/known_hosts`, `ls ~/Library/Keychains` (jeweils `Operation not permitted`). `security` (Deny-Regel). `curl` auf ein Ziel außerhalb der Liste (403 vom Proxy). `nc -U` auf den Connector-Socket des echten Hubs. Das Read-Tool auf `~/.ssh/id_ed25519.pub` und auf eine Datei im Hub-Ordner.
- **Erlaubt:** `git status`, `wc -c` auf `dev.db`, Schreiben im Worktree, `mix hex.info` (hex.pm). `mix test` in jeder App einzeln: 14 von 16 Apps grün. In `komki_cli` und `seatbelt` scheitern nur die Tests mit `sandbox-exec`, wie oben beschrieben.
