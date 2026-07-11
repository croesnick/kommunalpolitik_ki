# Kommunalpolitik KI

Tools für die Stadtratsarbeit: RIS durchsuchen, PDFs ingesten, Fördermittel recherchieren, Lokalzeitung scrapen.

## Kontext

Carsten ist Stadtrat in Buchloe (Grüne, Listenplatz 3) und Co-Sprecher der Grünen Buchloe. Dieses Repo bündelt CLI-Tools und MCP-Server, die die kommunalpolitische Arbeit erleichtern. Der übergeordnete Spin ist der Talk „KI als Gemeinderat" — ein AI Harness für Ratsarbeit mit Quellenbindung, lokaler Datensouveränität und demokratischer Verantwortung.

## Architektur-Prinzipien

### 1. Elixir-first

Wenn nichts Prinzipielles dagegen spricht, wird ein Tool in Elixir gebaut. „Prinzipielles dagegen" heißt: das Ökosystem einer anderen Sprache bietet eine Bibliothek, die in Elixir keine Entsprechung hat und nicht sinnvoll als CLI/NIF angebunden werden kann. Beispiele: `trafilatura` (Python, Artikel-Extraktion), `PyMuPDF` (Python, PDF-Annotation-Extraktion), `Playwright` (Node, Headless-Browser). Dogmatismus ist nicht das Ziel — aber der Default ist Elixir.

### 2. Unix-Prinzip

Ein Tool pro Aufgabe. Tools sind composable und orthogonal. `ratsinfo` lädt PDFs herunter, `pdf_ingest` verarbeitet sie — aber `pdf_ingest` weiß nichts vom RIS. Kein Tool kennt die Interna eines anderen. Pipes und Verzeichnisübergabe als Schnittstellen, nicht direkte Code-Kopplung.

### 3. MVP vor Infrastruktur

Nicht in Pipeline-/Infra-/RAG-Komplexität fallen, bevor der einfache Fall funktioniert. `riski` (München) war die Warnung: ein professioneller Stack, der für den persönlichen Use Case zu schwer ist. Erst `sync/search/show/open`, dann RAG/OCR/UI. Der MVP muss beweisen, dass ein Stadtrat vor einer Sitzung schnell etwas findet — nicht, dass ein KI-Stack betrieben werden kann.

### 4. Problem-first, nicht tool-first

Der Bahnhofstr-Case war problem-first (konkretes politisches Problem → KI als Werkzeug) und funktionierte besser als der tool-first-Ansatz („ich baue ein CLI für RAG"). Neue Tools sollen aus konkreten Bedarfen entstehen, nicht aus Technik-Faszination.

## Politische & ethische Guardrails

### 5. Quellenpflicht (nicht optional)

Jede Aussage, die ein Tool produziert und politisch relevant ist, braucht eine Quelle: URL, Abrufdatum, ggf. Paragraf. Ein Stadtrat ohne Quellen ist unglaubwürdig. Ein Stadtrat mit Quellen ist eine Bastion. Das gilt für den `foerdermittel`-Skill, `ratsinfo report`, und jeden anderen Output.

### 6. GO-Prinzip: AI berät, Mensch entscheidet

Die KI entscheidet nichts ohne GO. Keine Triage-Änderung, kein Vault-Eintrag, kein Task-Update ohne Bestätigung. Das ist nicht nur eine Arbeitsregel, sondern ethische Architektur: demokratische Verantwortung bleibt beim Menschen. Tools sind read-only by design, wo immer möglich.

### 7. Datenschutz-Grenze

Nur Zugriff auf das, was als Stadtrat bzw. öffentlich regulär abrufbar ist. Nicht-öffentliche Unterlagen bleiben lokal und kontrolliert. Keine Schreibzugriffe ins RIS. Keine öffentliche Bereitstellung ohne Prüfung.

### 8. Politisches Framing

Technische Tools nicht als „AI-Zugriff" oder „ich will RAG bauen" framen, sondern als „strukturierte öffentliche Ratsinformationen", „digitale Arbeitsfähigkeit", „Transparenz".

## Lizenz-Bewusstsein

Abhängigkeiten auf Lizenzkompatibilität prüfen. PyMuPDF ist AGPL-3.0 (oder kommerziell von Artifex). Für ein persönliches/Open-Source-Projekt ist AGPL in Ordnung; bei proprietärer Nutzung Alternative evaluieren (`pdfplumber` MIT, `pdf.js` Apache-2.0). Pro Tool in der Tool-Doku dokumentieren.

## Tool-Übersicht

| Tool | Sprache | Zweck | Status |
|---|---|---|---|
| `apps/ratsinfo` | Elixir | RIS-Scraper + CLI + lokale Volltextsuche | Geplant |
| `apps/shared` | Elixir | Geteilte Domain-Models (Sitzung, TOP, Dokument) | Geplant |
| `tools/allgaeuer_zeitung_mcp` | Python | AZ-Artikel suchen/lesen (MCP) | Bestehend |
| `tools/pdf_ingest` | Python | PDFs ingesten, Highlights extrahieren (MCP) | Geplant |
| `skills/foerdermittel` | Markdown-Skill | Fördermittel-Recherche orchestrieren | In Arbeit |

## Tooling-Vorgaben

### Elixir

| Werkzeug | Rolle | Befehl |
|---|---|---|
| Credo | Linter | `mix credo --strict` |
| Dialyzer | Static Type Checker | `mix dialyzer` |
| mix format | Formatter | `mix format --check-formatted` |
| mix test | Test-Runner | `mix workspace.run -t test --affected` |

### Python

| Werkzeug | Rolle | Befehl |
|---|---|---|
| ruff | Linter + Formatter | `uv run ruff check` / `uv run ruff format --check` |
| mypy | Static Type Checker | `uv run mypy src/` |
| pytest | Test-Runner | `uv run pytest` |

### CI

```bash
# Elixir
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
mix dialyzer
mix workspace.run -t test --affected -- --cover

# Python (pro Tool unter tools/)
uv sync
uv run ruff check
uv run ruff format --check
uv run mypy src/
uv run pytest
```

## Verzeichnisstruktur

```
kommunalpolitik_ki/
├── apps/                   # Elixir-Apps (workspace-Pattern)
│   ├── ratsinfo/
│   └── shared/
├── tools/                  # Nicht-Elixir
│   ├── allgaeuer_zeitung_mcp/
│   └── pdf_ingest/         # (geplant)
├── skills/                 # AI-Harness-Skills
│   └── foerdermittel/
├── artifacts/              # shared Elixir build output (gitignored)
├── mix.exs                 # workspace root
├── .workspace.exs
├── .credo.exs
├── .formatter.exs
├── opencode.json
├── AGENTS.md               # diese Datei
└── Makefile
```

## RIS-Datenquelle

Das Ratsinformationssystem der VGem Buchloe läuft unter:

```
https://ris.komuna.net/vgbuchloe/Meeting.mvc/Calendar?atDate=1.1.2025
```

Kein OParl, kein ICS gefunden → HTML-Scraping ist der realistische Weg. `riski` (it-at-m, München) dient als Referenzarchitektur, nicht als Codebasis.
