# Dev-Loop: Tickets unbeaufsichtigt abarbeiten

Stand: 2026-11-07, Ticket #389. Der Dev-Loop arbeitet freie Tickets ab, auch wenn niemand am Rechner sitzt. Für jedes Ticket setzt eine Agent-Session um, eine zweite prüft. Danach entscheidet das Skript nach festen Regeln: mergen, auf ein GO warten oder an die nutzende Person übergeben. Eine dritte Session, die Product-Owner-Rolle (PO), verfeinert unterdessen Tickets und macht nur Vorschläge. Die Regeln für die Agenten stehen nicht hier, sondern im [Lane-Protokoll](lane-protocol.md) und in den [AI-Stufen](ai-tiers.md). Der Loop setzt sie durch.

## Ablauf

```mermaid
stateDiagram-v2
    [*] --> Pick: ready-for-agent, Stufe A/B, Zielbild, kein offener Blocker, kein Assignee, nicht belegt
    Pick --> Implement: Assignee + Board "In Progress"
    Implement --> Review: Gates grün, PR mit "Closes #n", Board "In Review"
    Implement --> Human: blocked.md oder zweiter Fehlversuch
    Review --> Implement: rework (höchstens 2 Runden, je frische Session)
    Review --> Merge: B-Tier, approve, kein geschützter Pfad
    Review --> WartetGO: A-Tier, approve
    Review --> Human: human, S-Tier, geschützter Pfad oder Runde 3
    Merge --> Implement: Rebase-Konflikt oder CI rot (zählt als Rework-Runde)
    Merge --> Pick: CI grün auf dem Head-SHA, Squash-Merge
    WartetGO --> Pick: zugewiesen, Brief im Morgen-Kommentar
    Human --> Pick: ready-for-human statt ready-for-agent, Kommentar
```

- **Auswahl:** Ein Ticket braucht ein Zielbild im Text oder in einem Kommentar (`ai-tiers.md`). Ein Zielbild-Entwurf der PO zählt nicht, denn er hat noch kein GO. Zuerst kommen Tickets mit dem Label `next`, dann B vor A, dann die kleinste Nummer. Als *belegt* gelten Tickets, die zu einem offenen PR gehören, deren Nummer im Branch eines PR oder eines lokalen Worktrees steht (`lane-152-…`, `brave-mock-340`) oder die auf dem Board „In Progress“ stehen. So bleiben von Hand geöffnete Lanes unberührt.
- **Review:** Vor dem Review führt das Skript die Gates auf dem PR-Head selbst aus, außerhalb der Sandbox. Sind sie rot, zählt das ohne Review als Rework-Runde. Sind sie grün, bekommt das Review das Ergebnis als Beleg und prüft Abnahme und Diff. Was die Sandbox nicht messen lässt (etwa `lsof`, lokale Ports), führt nicht zu `human`. Das Review nennt den Punkt dann in seiner Zusammenfassung.
- **Merge:** B-Tier wird automatisch gemergt. A-Tier wartet zugewiesen auf „In Review“, die nutzende Person mergt von Hand. S-Tier wird nie automatisch gemergt.
- **Geschützte Pfade:** Neben den Pfaden aus `ai-tiers.md` schützt der Loop seine eigenen Regeln: `scripts/dev_loop*`, `.github/`, `docs/agents/` und `AGENTS.md`. Ein Diff, der einen dieser Pfade berührt, geht immer an die nutzende Person.
- **Fehler:** Scheitert eine Umsetzung (rote Gates, kein Commit, Zeitlimit, Absturz), versucht der Loop es einmal in einer frischen Session neu. Scheitert auch das, übergibt er das Ticket an die nutzende Person, ebenso bei einer Eskalation des Agenten (`.dev-loop/blocked.md`).
- **PO:** Die PO läuft zu Beginn jedes Laufs und noch einmal, wenn keine Tickets mehr zur Auswahl stehen. Je Lauf nimmt sie höchstens 5 Tickets, die `needs-triage` sind oder A/B ohne Zielbild. Sie schreibt einen Zielbild-Entwurf oder Rückfragen als Kommentar. Stufen, `ready-for-agent` und Abhängigkeiten schlägt sie nur im Morgen-Kommentar vor. `ai:s-tier`, `ready-for-human` und `wayfinder:*` fasst sie nicht an.
- **Morgen-Kommentar:** Am Ende jedes Laufs kommentiert der Loop auf #389, was gemergt wurde, was auf ein GO wartet, was an die nutzende Person übergeben wurde und was die PO vorschlägt.

## Rollen und Modelle

| Rolle | Erst | Fallback bei erschöpftem Konto |
|---|---|---|
| Umsetzung | `claude` mit Sonnet 5.5 | `tt` mit Default-Modell |
| Review | `claude` mit Opus 5.5 | `tt` mit Default-Modell, Effort `max` |
| PO | `claude` mit Opus 5.5 | `tt` mit Default-Modell, Effort `max` |

Jede Stufe läuft als frische Session ohne Oberfläche (`claude -p`). Die Prompts liegen unter `scripts/dev_loop/prompts/`. Sind beide Konten erschöpft, beendet sich der Lauf sauber und meldet sich per macOS-Notification.

## Sicherheitsgrenze

- **Nur das Skript schreibt nach GitHub.** Agenten bekommen kein Token. Sie arbeiten im Worktree und übergeben ihre Ergebnisse als Dateien unter `.dev-loop/` (gitignored): `pr.md`, `brief.md`, `blocked.md`, `review.json`, `po.json`.
- **PAT:** Fine-grained, nur für dieses Repo. Er liegt im Schlüsselbund unter `dev-loop-gh-pat`. Das Skript reicht ihn als `GH_TOKEN` nur an die eigenen `gh`-Aufrufe und an `git push` über HTTPS weiter.
- **Agenten:**
  - `--permission-mode auto --permission-prompts none`
  - Bash-Sandbox von Claude Code und Deny-Regeln aus `scripts/dev_loop/agent_settings.json` (`gh`, `git push`, `security`, `ssh`, `curl`, Lesen von `~/.ssh`, `~/.config/gh`, Schlüsselbund)
  - Schreiben darf die Sandbox nur im Worktree, in den Hex- und Mix-Caches und in `/tmp`. `/tmp` braucht die Test-Suite von komki_cli für kurze Socket-Pfade (103-Byte-Grenze). Dort liegt nichts Geheimes, andere Prozesse des Kontos können es aber lesen.
  - keine MCP-Server (`--strict-mcp-config`)
  - kein `GH_TOKEN` in der Umgebung
- **Prüfen:** `elixir scripts/dev_loop.exs --check-sandbox` lässt eine Session harmlose Befehle ausführen, die durchgehen müssen, und dann an Zugangsdaten scheitern. Die Befehle der Probe beweisen nur den Zugriff (Login-Name, Byte-Zahlen) und geben selbst bei einem Fehlschlag kein Geheimnis an das Modell. Zuletzt lief die Probe am 2026-11-07 auf `claude`, mit dem PAT im Schlüsselbund: alle vier Versuche abgelehnt, die Positivkontrollen (`git status`, `mix --version`, Schreiben in `/tmp`) liefen.
- **Grenze der Grenze:** Der Loop läuft im Konto `crn`. Sandbox und Deny-Regeln sind Policy von Claude Code, keine Trennung durch das Betriebssystem. Ein eigenes macOS-Konto wäre die härtere Variante, die bewusst nicht gewählt wurde (Grilling zu #389, Q3).
- **Branch Protection** auf `main` mit Pflicht-Checks: Eine rote CI blockiert den Merge auch dann, wenn das Skript einen Fehler hat.

## Bedienung

```bash
elixir scripts/dev_loop.exs --dry-run                   # Plan: Auswahl, Belegung, PO-Kandidaten; keine Agenten, keine Writes
elixir scripts/dev_loop.exs --only 392 --no-po          # ein Ticket, unter Aufsicht
elixir scripts/dev_loop.exs --until 07:00               # über Nacht, höchstens 5 Tickets (--max-tickets)
touch ~/.dev-loop/STOP                                   # Not-Aus: greift vor der nächsten Stufe; Datei danach löschen
```

- **Wach bleiben:** Solange das Skript läuft, hält es den Mac per `caffeinate` wach. Ein Lock in `~/.dev-loop/lock` verhindert einen zweiten Lauf.
- **Zeitfenster:** `--until` startet nach der angegebenen Uhrzeit kein neues Ticket mehr. Eine laufende Stufe darf bis zu 4 Stunden dauern.
- **Cockpit in Herdr:** Gemeint ist die Desktop-App Herdr auf herdr-core (`hc`), nicht das ältere Terminal-Programm `herdr`. Startet man das Skript in einem Herdr-Terminal, öffnet es für jede Stufe einen eigenen Tab im selben Space, etwa „loop-368-review-claude“. Der Tab zeigt die Session live: den Text des Agenten, jeden Tool-Aufruf mit Ergebnis, die Ablehnungen und am Ende Turns und Dauer. Am Ende der Stufe beendet das Skript den Tab wieder. Bricht ein Lauf ab (Ctrl-C, Absturz), bleibt der Tab mit dem letzten Stand stehen. Der nächste Lauf beendet ihn beim Start, erkennbar am hc-Label `dev-loop=viewer`.
  - Den ganzen Kontakt mit Herdr bündelt `scripts/dev_loop/herdr.exs`: `hc run` mit dem Label `herdr.space=<Space>` für den Tab, `herdr-app` für den Space und den Tab-Namen. Fällt Herdr aus, protokolliert der Loop das und arbeitet ohne Tab weiter.
  - Herdr zeigt im Tab keinen Agenten-Status (working/done), denn dort läuft `tail | jq` und kein Agent. Den Fortschritt zeigt der Tab-Inhalt.
  - Die Agenten bleiben Kindprozesse des Skripts ohne Oberfläche (`claude -p`). Die Pane liest nur das Log mit (`tail -F … | jq -f scripts/dev_loop/viewer.jq`). Eingreifen lässt sich dort nicht, dafür gilt die Sicherheitsgrenze unverändert.
  - Außerhalb von Herdr öffnet das Skript keinen Tab. Den Verlauf zeigt dann:
    ```bash
    tail -f "$(ls -td ~/.dev-loop/logs/*/ | head -1)"run.log
    ```
  - Die Logs jeder Stufe liegen als `*.jsonl` (stream-json von Claude Code) im selben Lauf-Verzeichnis. Eine abgeschlossene Stufe lässt sich nachlesen mit `jq -rR -f scripts/dev_loop/viewer.jq <stufe>.jsonl`.
- **Neustart:** Der ganze Zustand liegt auf GitHub. Dazu gehören der Board-Status und die Review-Marker `<!-- dev-loop:review verdict=… sha=… -->` in den PR-Kommentaren. Nach einem Absturz macht ein neuer Lauf zuerst offene Loop-PRs ohne Freigabe des aktuellen Heads weiter, dann Loop-Worktrees ohne PR (`.claude/worktrees/loop-<n>`).

## Einrichtung (einmalig)

1. **PAT anlegen:** github.com → Settings → Developer settings → Fine-grained tokens → Generate.
   - Name `dev-loop`, Ablauf 90 Tage
   - Repository access: *Only select* → `kommunalpolitik_ki`
   - Repository permissions:

     | Permission | Zugriff | Wofür |
     |---|---|---|
     | Contents | Read and write | Branch pushen, Squash-Merge, Branch nach dem Merge löschen |
     | Pull requests | Read and write | PR anlegen, Review-Kommentare, mergen |
     | Issues | Read and write | Tickets und Blocker lesen, kommentieren, zuweisen, `ready-for-human` setzen |
     | Actions | Read-only | CI-Läufe zum Head-SHA abfragen |
     | Metadata | Read-only | Pflicht, setzt GitHub automatisch |

   - Alles andere bleibt auf „No access“. **Workflows** fehlt mit Absicht: Ohne diese Permission lehnt GitHub jeden Push ab, der eine Datei unter `.github/workflows/` ändert. Ein Agent kann so keinen geänderten Workflow in die CI bringen.
   - **Board:** Ein fine-grained PAT erreicht keine Projects, die einem Nutzerkonto gehören. GitHub führt das als bekannte Lücke (Docs „Managing your personal access tokens“, abgerufen am 2026-11-07). Das Skript protokolliert dann eine Warnung und arbeitet weiter. Als belegt gilt ein Ticket trotzdem, weil der Loop es sich zuweist. `Done` setzt der Board-Workflow beim Schließen.
2. **PAT in den Schlüsselbund**, ohne Shell-History. `security` fragt den Wert interaktiv ab:
   ```bash
   security add-generic-password -a "$USER" -s dev-loop-gh-pat -w
   ```
3. **Board:** Das Feld Status hat die Option **„In Review“** zwischen „In Progress“ und „Done“, angelegt am 2026-11-07. Wer die Optionen über die API ändert, muss die IDs der bestehenden Optionen mitgeben. Sonst verlieren alle Items ihren Status.
4. **Branch Protection** für `main`, eingerichtet am 2026-11-07:
   - Pflicht-Checks „Elixir quality gates“ und „komki-anzeige (Node-Tests)“. Beide laufen bei jedem PR.
   - Die Regel gilt auch für Admins (`enforce_admins`). Der Loop handelt mit dem PAT als `croesnick`, also als Admin, und ohne diese Einstellung könnte er die Checks umgehen. Folge: Auch von Hand geht nichts mehr direkt auf `main`, alles läuft über einen PR.
   - Force-Push und Löschen von `main` sind gesperrt.
5. **Probe:** `elixir scripts/dev_loop.exs --check-sandbox`, danach einmal `--only <n>` unter Aufsicht.

## Bekannte Grenzen (v1)

- Seriell, eine Lane. Parallele Lanes sind bewusst offen.
- **A-Tier ohne echten Lauf:** Die Abnahme von A-Tier braucht einen echten Lauf. Ohne Aufsicht trägt das erst die Mock-Welt (#347). Bis dahin endet A-Tier bei „In Review“.
- **`DoctorBootTest`** startet auf einem Mac mit Staging-Modell einen echten llama-server, bis #392 ihn per Tag aus dem Standardlauf nimmt. Der Staging-Pfad hängt fest an `~/.local/share/komki`, `KOMKI_HOME` umgeht ihn nicht.
- **Erschöpftes Konto:** Die Erkennung beruht auf den dokumentierten Meldungen („You've hit your … limit“, „spend limit reached“; `code.claude.com/docs/en/errors`, abgerufen am 2026-11-07). An einem echten Limit ist sie noch nicht beobachtet.
- Die Sandbox-Probe lief bisher nur auf `claude`, nicht auf `tt`.
- **Board-Status:** Mit dem fine-grained PAT setzt der Loop weder „In Progress“ noch „In Review“ (siehe Einrichtung). Er prüft das einmal zu Beginn jedes Laufs und lässt das Board danach in Ruhe. Lanes, die nur auf dem Board auf „In Progress“ stehen, ohne Worktree und ohne PR, erkennt er deshalb nicht als belegt.
- **Rebase über Workflow-Änderungen:** Hat `main` seit dem Branch eine Datei unter `.github/workflows/` geändert, kann GitHub den Push nach dem Rebase ablehnen, weil der PAT keine Workflows-Permission hat. Der Lauf meldet das als Skriptfehler im Morgen-Kommentar.
