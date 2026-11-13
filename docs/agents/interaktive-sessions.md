# Interaktive Sessions: Grenzen und Hooks

Stand: 2026-11-13. Für jede interaktive Claude-Code-Session in diesem Repo gilt `.claude/settings.json` (#462). Der Dev-Loop lädt diese Datei nicht (`--setting-sources user,local`). Er hat eigene Regeln, die Lesesperre unten eingeschlossen. Die Regeln folgen den Grenzen des [Dev-Loops](dev-loop.md), soweit sie zur interaktiven Arbeit passen. Faustregel: Was sich nach einem Fehler nicht zurückholen lässt, wird eine Regel. Was sich zurückholen lässt, darf das Modell entscheiden. Echte Ratsdaten in einem Transkript lassen sich nicht zurückholen.

## Lesesperre

Diese Orte sind für die Session gesperrt, für das Read-Tool (`permissions.deny`) und für jeden Befehl in der Bash-Sandbox samt Kindprozessen (`sandbox.filesystem.denyRead`):

- `~/Library/Application Support/ratsprojekte/`, der echte Hub mit Datenbank, Siegel, Connector-Hash und Sockets. Ausnahme ist die Entwicklungsdatenbank `dev.db` mit ihren Begleitdateien: In der Sandbox darf ein Befehl sie lesen und schreiben, für das Read-Tool bleibt sie gesperrt.
- `~/Library/Mobile Documents/iCloud~md~obsidian/`, alle Obsidian-Vaults in iCloud
- `~/.ssh`, `~/.config/gh` und `~/Library/Keychains`

Außerdem lehnen Deny-Regeln die Bash-Befehle `security`, `ssh` und `scp` ab, in genau dieser Schreibweise.

## Sandbox

Bash-Befehle laufen in der Sandbox von Claude Code (`sandbox.enabled`, `failIfUnavailable`). Ohne Sandbox startet die Session nicht.

- **Schreiben** geht im Worktree, in den Hex- und Mix-Caches, in `~/.cache`, in `/tmp` und auf `dev.db`.
- **Unix-Sockets** gehen unter `/tmp`, wo die Tests ihre Sockets anlegen (kurze Pfade wegen der 103-Byte-Grenze von macOS). Die Sockets des echten Hubs liegen nicht dort und bleiben zu.
- **Lokale Ports** gehen (`allowLocalBinding`), etwa für `mix phx.server`.
- **Netz:** Erreichbar sind Hex, npm, PyPI und GitHub. Für andere Ziele hängt es vom Modus ab: Im Auto-Modus lehnt die Sandbox ab, außer der Befehl nennt das Ziel und der Klassifikator stimmt zu. In den Modi mit Nachfrage fragt sie. `bypassPermissions` lässt ohne Nachfrage durch, `dontAsk` lehnt ab.
- **Außerhalb der Sandbox** laufen `gh` und `git push`, `git fetch` und `git pull`. Sie brauchen Zugangsdaten aus den gesperrten Orten. Sie gehen weiter durch die Regeln und den Auto-Modus. Das gilt nur für den nackten Aufruf: Mit `cd`, Umleitung, Heredoc oder `&&` davor bleibt er in der Sandbox und findet dort keine Zugangsdaten.
- **Seatbelt in der Sandbox:** Tests, die selbst `sandbox-exec` starten, scheitern in der Sandbox mit `sandbox_apply: Operation not permitted`. macOS lässt in einer laufenden Seatbelt-Sandbox kein zweites Profil zu. Das betrifft Teile von `apps/komki_cli` und `apps/seatbelt`. Der Stop-Hook läuft außerhalb der Sandbox und prüft sie trotzdem. Eine Session darf solche Befehle außerhalb der Sandbox wiederholen (Entscheidung der nutzenden Person vom 2026-11-12). Im Auto-Modus entscheidet der Klassifikator.

## Screenshots der Hub-Oberfläche

Prüfpunkte der Oberfläche belegt eine Session mit echten Screenshots, ohne dass die Sandbox dafür gelockert wird (#510). Das Werkzeug `scripts/screenshot.exs` startet den Hub aus einem Worktree auf einer Wegwerf-Datenbank mit den erfundenen Gartenstadt-Seeds, steuert einen Headless-Browser über das DevTools-Protokoll und schreibt PNGs samt `manifest.json` (URL, Theme, Breite, Commit):

```bash
elixir scripts/screenshot.exs --route /stand --navigate /:/stand --width 390,1280
elixir scripts/screenshot.exs --probe
```

- **Dauer:** Der erste Lauf in einem Worktree braucht bis zu einigen Minuten (Assets bauen, Downloads). Der Bash-Aufruf bekommt dafür ein Zeitlimit von 600 000 ms statt der üblichen 120 s.
- **Genau dieser Aufruf** läuft außerhalb der Claude-Sandbox (`excludedCommands` und Allow-Regel in `.claude/settings.json`), denn in der Sandbox greift kein zweites `sandbox-exec`. Wie bei `gh` gilt das nur für den nackten Aufruf: Mit Pipe, `&&` oder `cd` davor bleibt er in der Sandbox und scheitert an `sandbox_apply`.
- **Eigene Grenze:** Hub und Browser laufen gemeinsam unter einem deny-default-Profil aus `apps/seatbelt` (`scripts/screenshot/profile.exs`), in einer leeren Umgebung (`env -i`, `HOME` im Wegwerf-Ordner). Sie lesen den Worktree, die Laufzeit und die gepinnten Programme und schreiben nur die Build-Ausgabe des Hubs (`apps/ratsprojekte/_build/dev` und `priv/static/assets`, beide gitignored), den Wegwerf-Ordner und ihre Logs. Netz gibt es nur über Loopback und dort nur auf dem Port des Hubs, damit andere lokale Dienste (etwa Tidewave in einem laufenden `mix phx.server`) unerreichbar bleiben. Die Lesesperre oben steht zusätzlich als Deny-Regel am Ende des Profils. Der Hub spricht dort HTTPS mit einem Wegwerf-Zertifikat: Über reines HTTP schickt er Dateien per `sendfile`, und das ließe sich nur mit einer Regel erlauben, die vom Hub-Port aus auch das Internet erreicht.
- **Feste Eingaben:** Die Flags des Browsers stehen im Werkzeug. Routen nimmt es nur als lokale Pfade (`scripts/screenshot/spec.exs`), den Worktree nur als Worktree dieses Repos, eine Liste per `--spec` nur als Datei bis 64 KB im Worktree oder unter `/tmp`. Die Ausgabe liegt in einem Unterordner des Worktrees oder von `/tmp`, Standard ist `.screenshots/` im Worktree. Alte Ergebnisse löscht das Werkzeug nur in einem Ordner, den es selbst angelegt hat (Markierung `.komki-screenshot`).
- **Gepinnte Programme:** Browser (Playwrights `chrome-headless-shell`, Prüfsumme über den ganzen Paketordner), esbuild und tailwind stehen mit SHA-256 in `scripts/screenshot/pins.json`. esbuild und tailwind lädt das Werkzeug selbst nach `~/.cache/komki-screenshot/` und prüft sie bei jedem Lauf, weil Agenten diesen Ordner schreiben dürfen.
- **Nachweis:** `--probe` versucht mit genau diesem Profil aus BEAM und Browser heraus den Hub-Ordner und `~/.ssh` zu lesen, das Netz zu erreichen (auch vom Hub-Port aus) und einen anderen lokalen Port zu öffnen. Der Hub-Port ist die Positivkontrolle. Beim Browser hält schon das feste Flag `--host-resolver-rules` Netzadressen fern; dass Seatbelt ihn zusätzlich abweist, zeigt `denials.log` (`network-outbound` auf Port 443). Jeder Lauf legt außerdem `profile.sb` und die Verweigerungen des Laufs (`denials.log`) in die Ausgabe.
- **Grenze:** Die Allow-Regel vertraut dem Skript im Worktree der Session. Eine Session kann `scripts/screenshot.exs` ändern und es dann ohne jede Sandbox starten. Der Dev-Loop startet deshalb seine eigene Kopie.

## Hooks

- **Stop-Hook** (`.claude/hooks/stop_gates.exs`): Weicht der Stand des Worktrees von `origin/main` ab, endet ein Zug erst, wenn `mix format --check-formatted` und die Tests der betroffenen Apps grün sind (`mix workspace.run -t test --affected --base origin/main`). Bei Rot endet der Hook mit Exit-Code 2, und die Session arbeitet weiter, mit den fehlgeschlagenen Tests als Begründung. Ist sie schon wegen des Hooks weitergelaufen (`stop_hook_active`), blockiert er kein zweites Mal und meldet der nutzenden Person, dass die Gates rot bleiben. Ein grüner Stand wird gemerkt. Läuft der Hook wieder ohne Änderung, prüft er ihn nicht noch einmal. Wandert `origin/main` weiter, prüft er neu. Er läuft am Repo-Root, auch wenn die Session in einem App-Ordner steht. Ohne Git-Repo oder ohne `origin/main` tritt er zur Seite.
- **PreToolUse-Hook** (`.claude/hooks/pr_report.exs`): `gh pr create` und `gh pr new` werden abgelehnt, auch mit Flags wie `-R <repo>` dazwischen, solange der PR-Text keinen Prüfbericht nach dem [Lane-Protokoll](lane-protocol.md#prüfbericht-the-verification-report) hat: Überschrift, Tabelle, Abschnitt mit den Entscheidungen und den aktuellen Head-Commit. Der Hook sucht im ganzen Befehl und in der Datei aus `--body-file` oder `-F`. Scheitert der Hook selbst, etwa weil `elixir` fehlt, sperrt die Hülle in `.claude/settings.json` den Aufruf (Exit-Code 2). Die Hülle sucht grob nach „gh“ und „pr“ in der ganzen Eingabe. Ohne `elixir` sperrt sie deshalb auch andere Befehle, in deren Text beides vorkommt. Mit `elixir` kostet so ein Treffer einen Start (etwa 0,4 s), und das Skript entscheidet genau.

Gemessen am 2026-11-13 in einem Wegwerf-Worktree, ohne Last durch andere Läufe: keine Änderung oder unverändert seit dem letzten grünen Stand 0–1 s, nur Doku 2 s, eine Änderung nur in `apps/ratsprojekte` 5 s. Eine Änderung in `apps/sidecar`, die alle abhängigen Apps mitnimmt, braucht 73 s bei Rot (aus dem App-Ordner gestartet) und 74 s bei Grün. Tests: `elixir .claude/hooks/test/hooks_test.exs`.

## Was die Regeln garantieren und was nicht

- Sandbox, Deny-Regeln und Hooks sind Policy von Claude Code. Eine Trennung durch das Betriebssystem ist das nicht. Die Session läuft im Konto der nutzenden Person. Ein eigenes macOS-Konto wäre die härtere Variante, wie beim Dev-Loop bewusst nicht gewählt.
- Die Sandbox sperrt Bash und dessen Kindprozesse. Das Read-Tool sperren nur die Deny-Regeln. Ein Pfad, der in keiner der beiden Listen steht, ist lesbar.
- Hooks und MCP-Server laufen außerhalb der Sandbox, mit allen Rechten des Kontos. Deshalb ist `.claude/` ein geschützter Pfad ([ai-tiers.md](ai-tiers.md#geschützte-pfade)): Eine Änderung dort geht immer an die nutzende Person, auch im Dev-Loop.
- Ein Befehl kann die Sandbox verlassen (`dangerouslyDisableSandbox`). Im Auto-Modus entscheidet dann der Klassifikator, sonst fragt Claude Code nach. Die Deny-Regeln für Bash-Befehle und das Read-Tool gelten weiter, die Lesesperre der Sandbox aber nicht.
- Der PR-Hook prüft die Form des Prüfberichts. Ob ein Nachweis trägt und ob wirklich eine Session geprüft hat, die nicht gebaut hat, prüft er nicht. Das bleibt beim unabhängigen Review (#463). Er sieht nur `gh pr create` und `gh pr new`: `gh api`, eigene gh-Aliase und Skripte kommen an ihm vorbei.
- Die Socket-Freigabe für `/tmp` öffnet auch Sockets anderer Prozesse, die dort liegen: Claude-Daemon, andere Sessions, tmux, Postgres, Wegwerf-Hubs. Ob sich darüber die Sandbox verlassen lässt, ist nicht geprüft. Einengen lässt sich die Freigabe erst, wenn die Tests ihre Sockets in einem eigenen Verzeichnis anlegen (#503).
- Die Deny-Regeln für Bash greifen nur in der Schreibweise des Musters. `/usr/bin/security …` oder `sh -c '…'` erfassen sie nicht. Ob die Sandbox den Schlüsselbund auch über den Dienst `securityd` sperrt, ist nicht geprüft.
- Der Stop-Hook lässt durch, wenn er selbst scheitert (etwa `elixir` fehlt, Absturz, Zeitlimit von 600 s): Nur Exit-Code 2 hält eine Session an.
- Der Stop-Hook prüft Format und Tests. Compile-Warnungen, Credo und Dialyzer prüft weiter die CI.
- Für die Bash-Sandbox gelten die Muster von Claude Code. Neue Orte mit echten Daten kommen hier und in `.claude/settings.json` dazu, sobald es sie gibt.

## Prüfen

Nach jeder Änderung an `.claude/settings.json` läuft die Probe in `.claude/sandbox-probe.md`. Eine Session versucht dort, gesperrte Orte zu lesen, und führt die Positivkontrollen aus. Die Befehle zeigen nur Zähler und Byte-Zahlen, nie Inhalte. Aufruf im Worktree:

```bash
claude -p --permission-mode auto --output-format json "$(cat .claude/sandbox-probe.md)" < /dev/null | jq -r .result
```

Letzte Probe am 2026-11-12, Claude Code 2.1.311:

- **Abgelehnt:** `ls` und `wc -c` im Hub-Ordner, `ls` im iCloud-Ordner von Obsidian, `wc -c ~/.ssh/known_hosts`, `ls ~/Library/Keychains` (jeweils `Operation not permitted`). `security` (Deny-Regel). `curl` auf ein Ziel außerhalb der Liste (403 vom Proxy). Das Read-Tool auf `~/.ssh/id_ed25519.pub` und auf eine Datei im Hub-Ordner.
- **Nicht eindeutig:** `nc -U` auf den Connector-Socket des echten Hubs endet mit exit=1 ohne Meldung. Das trennt eine Sperre nicht von einem fehlenden Listener (Gegentest mit #503).
- **Erlaubt:** `git status`, `wc -c` auf `dev.db`, Schreiben im Worktree, `mix hex.info` (hex.pm). `mix test` in jeder App einzeln, mit der Socket-Freigabe für `/tmp`: 14 von 16 Apps grün. In `komki_cli` und `seatbelt` scheitern nur die Tests mit `sandbox-exec`, wie oben beschrieben. Probeweise eingeengt auf `/tmp/claude-502` (2026-11-13) scheiterten zusätzlich `komki_mediator` und vier Connectoren mit `:eperm` (#503).
