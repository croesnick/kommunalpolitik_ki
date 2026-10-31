# Realmodell-Smoke-Test (Ticket #158)

Fünf Aufgaben plus Compaction-Experiment gegen den **echten** llama-server
(Gemma 4 26B) der komki-Instanz — die Ergänzung der Mock-Experimente aus
[2026-10-24](../../../../../docs/research/2026-10-24-pi-package-experiments.md).
Ergebnisse: [Labbook 2026-10-30](../../../../../docs/research/2026-10-30-pi-realmodell-smoke-test.md).

Der Smoke-Test dokumentierte in Aufgabe 1 eine Qualitätslücke (Eigenanteil
fehlt in jeder Zusammenfassung unter natürlichem Prompt). Der
[`run-top-bench.mjs`](#benchmark-aufgabe-1) misst dagegen gegen explizit
definiertes gewünschtes Verhalten (Muss-Kriterien K1–K8) in zwei
Prompt-Varianten — natürlich vs. spec-explizit, je drei Läufe.

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
`$KOMKI_PI_EXPERIMENTS_DIR/runs/<timestamp>/`. Die Gesamtübersicht
(`results.json`, `SMOKE.md`) wird aus allen `results/*.json` des Roots
zusammengesetzt — Teil-Nachläufe mit `--only` überschreiben sie nicht.

## Benchmark: Aufgabe 1

```bash
# TOP-Benchmark gegen Muss-Kriterien K1–K8 (siehe Labbook): zwei
# Prompt-Varianten (natürlich / spec-explizit), je drei Läufe
node apps/komki_cli/experiments/pi_packages/smoke/run-top-bench.mjs --root <run-root> [--runs 3]
```

Gewünschtes Verhalten ist im Skript definiert und im Labbook begründet
(Sitzungsmappe-Vorlage, Finanzierungs-TOPs, Quellenpflicht). Verdikt-Maßstab:
Variante B (explizit) liefert alle Kriterien in jedem Lauf — sonst läge ein
Modelldefizit statt Prompt-Sensitivität vor.

## Modell als Parameter und Modell-A/B (Ticket #285)

Ohne `--gguf` läuft `run-smoke.mjs` unverändert gegen die komki-Instanz. Mit
`--gguf` startet der Harness einen eigenen Staging-llama-server
([`staging-server.mjs`](staging-server.mjs)): gleiche Flags wie der
Produktivstart, aber ohne Seatbelt-Profil, auf eigenem Port, mit eigenem Key
und Log unter `<root>/server/`. Er beendet ihn am Ende wieder.

```bash
node apps/komki_cli/experiments/pi_packages/smoke/run-smoke.mjs \
  --gguf ~/.local/share/komki/models-staging/<datei>.gguf --port 49611 \
  --sampling '{"temp":1.0,"top-p":0.95,"top-k":64}' --seed 285001 \
  [--ctx 131072] [--timeout-factor 6] [--only 1,2,3,4,6] [--root <dir>]
```

Der A/B selbst besteht aus drei Skripten:

```bash
# 1. Kandidaten stagen: feste Revision, SHA-256 vor und nach dem Download
node smoke/stage-gguf.mjs --repo <hf-repo> --revision <commit> --file <gguf> --sha256 <hex>

# 2. Preflight-Check, dann Warm-up + n Messläufe je Arm, interleaved (A B C …)
node smoke/run-ab.mjs --root <ab-root> --preflight
node smoke/run-ab.mjs --root <ab-root> [--runs 3] [--timeout-factor 6]

# 3. Verblinden, manuell bewerten (blind/grades.json), entblinden
node smoke/grade-ab.mjs blind  --root <ab-root>
node smoke/grade-ab.mjs report --root <ab-root>
```

Arme, Revisionen, Prüfsummen und Sampling stehen in [`ab-arms.mjs`](ab-arms.mjs),
die vorab registrierten Checklisten in [`grade-ab.mjs`](grade-ab.mjs) und
[`criteria.mjs`](criteria.mjs). `run-ab.mjs` ist fortsetzbar: Läufe mit
`results.json` werden übersprungen. Protokoll und Ergebnisse:
[Labbook 2026-10-31](../../../../../docs/research/2026-10-31-modell-ab.md).

Zusätzlich misst der Proxy seit #285 je Request die Zeit bis zum ersten
Delta (`firstTokenMs`, Thinking eingeschlossen) und bis zur ersten sichtbaren
Antwort (`firstAnswerMs`) und hält den Thinking-Text (`reasoning`) fest. Der
Harness zählt die Thinking-Token mit dem Tokenizer des laufenden Servers
(`/tokenize`) und misst den `phys_footprint` des llama-server.

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
- Benchmark (Aufgabe 1): Muss-Kriterien K1–K8 je Lauf, inkl. Erfindungs-Check — jede Zahl der Antwort muss aus der Quelle stammen oder als Summe/Differenz aus Quellenzahlen ableitbar sein
- Session-Zustand: Persistenz (`rpiv-todo-state`), `--continue`-Verhalten, Compaction-Entries

## Grenzen

- Ein Lauf je Aufgabe; das Modell ist bei temp 1.0 nicht deterministisch — Varianz zwischen Läufen ist dokumentierter Befund, kein Rauschen im Weg.
- pis Default-System-Prompt (wie in den Mock-Experimenten), nicht der KomKI-Produktiv-Prompt; Mediator/MCP-Tools sind außen vor.
- Aufgabe 5 wird per tmux `send-keys` gesteuert (120×40, keine echte Interaktion).
