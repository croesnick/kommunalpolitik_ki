# Kommunalpolitik KI

Tools für die Stadtratsarbeit: RIS durchsuchen, PDFs ingesten, Fördermittel recherchieren, Lokalzeitung scrapen.

## Kontext

Carsten ist Stadtrat in Buchloe (Grüne, Listenplatz 3) und Co-Sprecher der Grünen Buchloe. Dieses Repo bündelt CLI-Tools und MCP-Server, die die kommunalpolitische Arbeit erleichtern. Der übergeordnete Spin ist der Talk „KI als Gemeinderat" — ein AI Harness für Ratsarbeit mit Quellenbindung, lokaler Datensouveränität und demokratischer Verantwortung.

## Projekt-Verwaltung

Zur Verwaltung dieses Projekts wird **GitHub Projects** genutzt. Das Board liegt unter https://github.com/users/croesnick/projects (Repo: `croesnick/kommunalpolitik_ki`). Aufgaben, Ideen und Meilensteine werden als Issues mit Labels organisiert, nicht in externen Tools.

## Architektur-Prinzipien

### 1. Elixir-first

Wenn nichts Prinzipielles dagegen spricht, wird ein Tool in Elixir gebaut. „Prinzipielles dagegen" heißt: das Ökosystem einer anderen Sprache bietet eine Bibliothek, die in Elixir keine Entsprechung hat und nicht sinnvoll als CLI/NIF angebunden werden kann. Beispiele: `trafilatura` (Python, Artikel-Extraktion), `PyMuPDF` (Python, PDF-Annotation-Extraktion), `Playwright` (Node, Headless-Browser). Dogmatismus ist nicht das Ziel — aber der Default ist Elixir.

### 2. Unix-Prinzip

Ein Tool pro Aufgabe. Tools sind composable und orthogonal. `ratsinfo` lädt PDFs herunter, `pdf_ingest` verarbeitet sie — aber `pdf_ingest` weiß nichts vom RIS. Kein Tool kennt die Interna eines anderen. Pipes und Verzeichnisübergabe als Schnittstellen, nicht direkte Code-Kopplung.

### 3. MVP vor Infrastruktur

Nicht in Pipeline-/Infra-/RAG-Komplexität fallen, bevor der einfache Fall funktioniert. `riski` (München) war die Warnung: ein professioneller Stack, der für den persönlichen Use Case zu schwer ist. Erst `sync/search/show/open`, dann RAG/OCR/UI. Der MVP muss beweisen, dass ein Stadtrat vor einer Sitzung schnell etwas findet — nicht, dass ein KI-Stack betrieben werden kann.

### 4. Problem-first, nicht tool-first

Der Bahnhofstr-Case war problem-first (konkretes politisches Problem → KI als Werkzeug) und funktionierte besser als der tool-first-Ansatz („ich baue ein CLI für RAG"). Neue Tools sollen aus konkreten Bedarfen entstehen, nicht aus Technik-Faszination.

### 5. AI-Enabled: jedes Tool ist für den AI-Harness nutzbar

Jedes Tool in diesem Repo muss AI-Enabled sein — das heißt, ein AI-Harness (wie OpenCode) kann es nutzen. Mindestens eine der folgenden Schnittstellen pro Tool:

- **CLI**: das Tool ist als Kommandozeilen-Tool aufrufbar (z.B. `ratsinfo search "Bahnhofstraße"`)
- **MCP-Server**: das Tool stellt MCP-Tools bereit (z.B. `pdf_ingest.ingest(path)`)
- **Agent Skill**: das Tool hat einen Skill im `skills/`-Verzeichnis, der beschreibt wie der AI-Harness es nutzt

Ein Tool ohne AI-Schnittstelle gehört nicht in dieses Repo. Die AI-Schnittstelle wird von Anfang an mitgedacht, nicht nachträglich aufgesetzt.

## Politische & ethische Guardrails

### 6. Quellenpflicht (nicht optional)

Jede Aussage, die ein Tool produziert und politisch relevant ist, braucht eine Quelle: URL, Abrufdatum, ggf. Paragraf. Ein Stadtrat ohne Quellen ist unglaubwürdig. Ein Stadtrat mit Quellen ist eine Bastion. Das gilt für den `foerdermittel`-Skill, `ratsinfo report`, und jeden anderen Output.

### 7. GO-Prinzip: AI berät, Mensch entscheidet

Die KI entscheidet nichts ohne GO. Keine Triage-Änderung, kein Vault-Eintrag, kein Task-Update ohne Bestätigung. Das ist nicht nur eine Arbeitsregel, sondern ethische Architektur: demokratische Verantwortung bleibt beim Menschen. Tools sind read-only by design, wo immer möglich.

### 8. Datenschutz-Grenze

Nur Zugriff auf das, was als Stadtrat bzw. öffentlich regulär abrufbar ist. Nicht-öffentliche Unterlagen bleiben lokal und kontrolliert. Keine Schreibzugriffe ins RIS. Keine öffentliche Bereitstellung ohne Prüfung.

### 9. Politisches Framing

Technische Tools nicht als „AI-Zugriff" oder „ich will RAG bauen" framen, sondern als „strukturierte öffentliche Ratsinformationen", „digitale Arbeitsfähigkeit", „Transparenz".

## Lizenz-Bewusstsein

Abhängigkeiten auf Lizenzkompatibilität prüfen. PyMuPDF ist AGPL-3.0 (oder kommerziell von Artifex). Für ein persönliches/Open-Source-Projekt ist AGPL in Ordnung; bei proprietärer Nutzung Alternative evaluieren (`pdfplumber` MIT, `pdf.js` Apache-2.0). Pro Tool in der Tool-Doku dokumentieren.

## Tool-Übersicht

| Tool | Sprache | Zweck | AI-Schnittstelle | Status |
|---|---|---|---|---|
| `apps/ratsinfo` | Elixir | RIS-Scraper + CLI + lokale Volltextsuche | CLI (`ratsinfo sync/search/show`) | Funktionsfähig |
| `apps/ratsprojekte` | Elixir (Phoenix LiveView) | Stadtrats-Projekt-Dashboard | LiveView + MCP (geplant) | In Arbeit |
| `apps/shared` | Elixir | Geteilte Domain-Models | — (Bibliothek) | Funktionsfähig |
| `tools/allgaeuer_zeitung_mcp` | Python | AZ-Artikel suchen/lesen | MCP | Bestehend |
| `tools/pdf_ingest` | Python | PDFs ingesten, Highlights extrahieren | MCP (geplant) | Geplant |
| `skills/foerdermittel` | Markdown-Skill | Fördermittel-Recherche orchestrieren | Agent Skill | Funktionsfähig |

## ratsprojekte — Planungsstand

### Konzept
Rechtlich-inhaltliche Standortbestimmung für Stadtratsprojekte. Kein Task-Tracker, keine Todo-Liste. Sondern: welche Realisierungsstränge gibt es, welche rechtlichen Vorbedingungen stehen, welcher Weg kann gegangen werden — und welcher nicht. Die AI kann lesen und Vorschläge machen (GO-Prinzip). Langfristig: Antragsvorlagen aus Projektdaten generieren.

### Architektur
- Phoenix LiveView für Dashboard
- `anubis_mcp` für AI-Zugriff (später)
- Ecto + SQLite3 (geteilte DB mit ratsinfo)

### Datenmodell
```
Projekt (titel, beschreibung, status, prioritaet)
├── Realisierungsstrang (label A/B/C, titel, beschreibung, rechtliche_grundlage, bedingung, bedingung_erfuellt)
│   ├── Vorbedingung (text, erfuellt, rechtliche_grundlage)
│   └── Schritt (text, frist) — geordnete Liste, keine Checkboxen
└── Quelle (typ, titel, url, paragraf, abrufdatum)
```

### Roadmap
1. **MVP**: Datenmodell + Seed + LiveView — Issues #12, #13, #14
2. **Antragsvorlagen**: Markdown-Render aus Projektdaten — Issue #15
3. **MCP-Server**: AI-Tools für lesen/suggest (GO-Prinzip)
4. **Ratsinfo-Integration**: Quellen verlinken mit Sitzung/TOP
5. **AI-Skill**: „Frag den Projekt-Tracker"

## Tooling-Vorgaben

### Elixir

| Werkzeug | Rolle | Befehl |
|---|---|---|
| Credo | Linter | `mix credo --strict` |
| Dialyzer | Static Type Checker | `mix dialyzer` |
| mix format | Formatter | `mix format --check-formatted` |
| mix test | Test-Runner | `mix workspace.run -t test --affected` |

### Debugging (Phoenix-Apps mit Tidewave)

Phoenix-Apps mit Tidewave-MCP (wie ratsprojekte) werden grundsätzlich über
Tidewave gedebuggt, wenn sie lokal laufen. Der AI-Harness kann über den
Tidewave-MCP-Endpoint (`http://localhost:4000/tidewave/mcp`) direkt auf die
laufende App zugreifen: Evaluator ausführen, Logs inspizieren, Module
inspizieren. Voraussetzung: App läuft mit `mix phx.server` und Tidewave ist
in `endpoint.ex` als Plug eingetragen (nur `:dev`).

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
│   ├── ratsinfo/           # RIS-Scraper + CLI (AI: CLI)
│   ├── ratsprojekte/       # Projekt-Dashboard (AI: LiveView + MCP geplant)
│   └── shared/             # Geteilte Domain-Models
├── tools/                  # Nicht-Elixir
│   ├── allgaeuer_zeitung_mcp/  # AZ-Artikel (AI: MCP)
│   └── pdf_ingest/         # PDF-Ingestion (AI: MCP, geplant)
├── skills/                 # AI-Harness-Skills
│   └── foerdermittel/      # Fördermittel-Recherche (AI: Agent Skill)
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
