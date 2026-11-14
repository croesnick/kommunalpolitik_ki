# Pi-Package-Experimente

Deterministische Offline-Experimente für die pi.dev-Packages, die in [RFC 0005](../../../../docs/rfcs/0005-pi-packages.md) bewertet werden. Die Ergebnisse stehen im [Labbook](../../../../docs/research/2026-10-24-pi-package-experiments.md).

Die Ergänzung mit dem echten Modell (Gemma 4 26B, Ticket #158) liegt in [`smoke/`](smoke/README.md): fünf Aufgaben plus Compaction-Experiment gegen den llama-server der komki-Instanz, mit einem Logging-Forward-Proxy als Messweg. Ergebnisse: [Labbook 2026-10-30](../../../../docs/research/2026-10-30-pi-realmodell-smoke-test.md).

## Voraussetzungen

- pi 1.4.0 (`@earendil-works/pi-coding-agent`)
- Node 24.22.1 (mindestens 24.15 für `pi-context`)
- Die acht Package-Tarballs, entpackt und installiert unter `$KOMKI_PI_EXPERIMENTS_DIR/vendor/node_modules`

Der Harness nutzt keinen echten Modellserver. Ein OpenAI-kompatibler Mock-Provider liefert deterministische Antworten, Tool-Calls und malformed Argumente.

## Vendor-Verzeichnis vorbereiten

```bash
export KOMKI_PI_EXPERIMENTS_DIR="${TMPDIR:-/tmp}/komki-pi-experiments"
mkdir -p "$KOMKI_PI_EXPERIMENTS_DIR/pkgs" "$KOMKI_PI_EXPERIMENTS_DIR/vendor"

npm pack \
  @juicesharp/rpiv-todo@2.15.0 \
  @juicesharp/rpiv-ask-user-question@2.15.0 \
  pi-tool-repair@0.3.9 \
  @sting8k/pi-vcc@0.10.2 \
  @spences10/pi-context@0.1.16 \
  @gotgenes/pi-permission-system@41.0.0 \
  pi-quiver@6.14.2 \
  pi-hermes-memory@0.9.11 \
  --pack-destination "$KOMKI_PI_EXPERIMENTS_DIR/pkgs"

cd "$KOMKI_PI_EXPERIMENTS_DIR/vendor"
npm init -y
npm install --legacy-peer-deps --ignore-scripts --omit=dev \
  "$KOMKI_PI_EXPERIMENTS_DIR"/pkgs/*.tgz
```

`--ignore-scripts` ist Absicht: Es verhindert Installations-Lifecycle-Scripts. `pi-hermes-memory` bringt `better-sqlite3` als native Dependency mit; im Test trug die mitgelieferte Prebuild-Variante.

## Ausführen

```bash
node apps/komki_cli/experiments/pi_packages/run-all.mjs
```

Der Lauf schreibt `results.json`, pro Experiment ein JSON und ein generiertes `LABBOOK.md` unter:

```text
$KOMKI_PI_EXPERIMENTS_DIR/runs/<timestamp>/
```

Zwei Standalone-Tests ergänzen den Hauptlauf:

```bash
# Interaktives TUI-Overlay von ask_user_question unter tmux
node apps/komki_cli/experiments/pi_packages/experiments/02b-ask-user-tui.mjs

# Seatbelt-Canary: fetch, exec, Fremd-Write und Credential-Sicht
node apps/komki_cli/experiments/pi_packages/canary/run-canary.mjs
```

## Umgebungsvariablen

| Variable | Zweck |
|---|---|
| `KOMKI_PI_EXPERIMENTS_DIR` | Wurzel für Vendor-Pakete und Laufartefakte; Default ist `os.tmpdir()/komki-pi-experiments`. |
| `KOMKI_PI_CLI` | Pfad zu `@earendil-works/pi-coding-agent/dist/bundle/cli.js`; Default wird über `npm root -g` gesucht. |
| `KOMKI_PI_NODE_BIN` | Node-Binary; Default ist `process.execPath`. |

## Was geprüft wird

- Tool-Registrierung und Tool-Allowlist
- Persistenz über `--continue`
- Headless- und RPC-Verhalten von `ask_user_question`
- Tool-Call-Reparatur (dokumentierter Alias vs. beliebige malformed Argumente)
- Compaction ohne Summary-Request und deutsche Extractor-Qualität
- Schreibpfad-Gate des Permission-Systems
- PDF-Extraktion im Offline-Tier
- Anchor-Suche ohne Memory-Schreibvorgänge
- Interaktives TUI-Overlay und RPC-Dialog von `ask_user_question`
- Seatbelt-Canary für `fetch`, `exec`, Fremd-Write und Credential-Sicht
- Statischer Scan auf Netzwerk-, Exec-, Eval- und Allowlist-Risiken

Nicht geprüft: Antwortqualität des echten 26B-Modells, echte RIS-PDFs und OCR, künftige pi-Versionen.
