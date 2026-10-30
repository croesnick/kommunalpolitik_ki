# Realmodell-Smoke-Test (Ticket #158)

Fünf Aufgaben plus Compaction-Experiment gegen den **echten** llama-server
(Gemma 4 26B) der komki-Instanz — die Ergänzung der Mock-Experimente aus
[2026-10-24](../../../../../docs/research/2026-10-24-pi-package-experiments.md).
Ergebnisse: [Labbook 2026-10-30](../../../../../docs/research/2026-10-30-pi-realmodell-smoke-test.md).

Der Harness startet llama-server **nicht** selbst. Er erwartet die laufende
komki-Instanz (`KOMKI_HOME`, default `~/.local/share/komki`), liest Port und
API-Key aus ihr und verweigert den Lauf mit klarer Meldung, wenn
`/health` nicht antwortet. Zwischen pi und llama-server liegt ein
Logging-Forward-Proxy (`../lib/provider.mjs`): Er leitet Requests 1:1 weiter
und zeichnet jeden Request/Response als JSONL auf — der Messdatenbestand
(Latenz, Usage, Tool-Calls, Fehlerkorpus) für den Smoke-Test.

## Voraussetzungen

- pi 1.4.0, Node 24.22.1
- Laufende komki-Instanz mit llama-server: `komki up` (Health und API-Key-Pflicht werden geprüft)
- Die zwei vendored Packages (GO 2026-10-30, siehe Ticket #158):

```bash
export KOMKI_PI_EXPERIMENTS_DIR="${TMPDIR:-/tmp}/komki-pi-experiments"
mkdir -p "$KOMKI_PI_EXPERIMENTS_DIR/pkgs" "$KOMKI_PI_EXPERIMENTS_DIR/vendor"

npm pack @juicesharp/rpiv-todo@2.15.0 @juicesharp/rpiv-ask-user-question@2.15.0 \
  --pack-destination "$KOMKI_PI_EXPERIMENTS_DIR/pkgs"

cd "$KOMKI_PI_EXPERIMENTS_DIR/vendor"
printf '{\n  "name": "komki-pi-vendor",\n  "private": true,\n  "version": "0.0.0"\n}\n' > package.json
pnpm add --ignore-scripts \
  ../pkgs/juicesharp-rpiv-todo-2.15.0.tgz \
  ../pkgs/juicesharp-rpiv-ask-user-question-2.15.0.tgz
```

## Ausführen

```bash
# Aufgaben 1–4 und 6 (headless): TOP zusammenfassen, Quellen extrahieren,
# Text redigieren, Todo-Workflow, Compaction-Experiment
node apps/komki_cli/experiments/pi_packages/smoke/run-smoke.mjs

# Aufgabe 5 (interaktives TUI unter tmux): ask_user_question
node apps/komki_cli/experiments/pi_packages/smoke/run-tui.mjs --root <run-root>
```

Optionen von `run-smoke.mjs`: `--only 1,2,3,4,6` (Teilmenge) und
`--root <dir>` (eigenes Laufverzeichnis). Der Standard-Lauf schreibt unter
`$KOMKI_PI_EXPERIMENTS_DIR/runs/<timestamp>/`.

## Ergebnisse

- `<root>/results/<task>.json` — je Aufgabe Requirements, Messwerte, Captures
- `<root>/results.json`, `<root>/SMOKE.md` — Gesamtübersicht (Entwurf; das
  Labbook im Repo ist das Dokument)
- `<root>/task-*/harness/*/requests.jsonl` — vollständiger Request/Response-Mitschnitt

## Was gemessen wird

- Wandzeit je Lauf; Dauer, `usage` (inkl. `cached_tokens`) und `finishReason` je Proxy-Request
- Token-Summen aus Proxy (llama-Sicht) und Session (pi-Sicht)
- llama-server-Log-Segment je Aufgabe: prompt-/eval-Tokens und Tokens/s je Request
- RSS des llama-server vor/nach jeder Aufgabe (`ps`, Richtwert — Metal-Speicher wird nicht vollständig erfasst)
- Tool-Call-Validierung: jedes vom Modell gelieferte Argument gegen das JSON-Schema aus dem aufgezeichneten Request; Fehlerklassen inkl. Truncation-Erkennung (`invalid-json`, `unknown-tool`, `missing-required`, `wrong-type`, `extra-keys`)
- Session-Zustand: Persistenz (`rpiv-todo-state`), `--continue`-Verhalten, Compaction-Entries

## Grenzen

- Ein Lauf je Aufgabe; das Modell ist bei temp 1.0 nicht deterministisch — Varianz zwischen Läufen ist dokumentierter Befund, kein Rauschen im Weg.
- pis Default-System-Prompt (wie in den Mock-Experimenten), nicht der KomKI-Produktiv-Prompt; Mediator/MCP-Tools sind außen vor.
- Aufgabe 5 wird per tmux `send-keys` gesteuert (120×40, keine echte Interaktion).
