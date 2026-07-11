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
| `apps/ratsinfo` | Elixir | RIS-Scraper + CLI + lokale Volltextsuche | Funktionsfähig |
| `apps/ratsprojekte` | Elixir (Phoenix LiveView) | Stadtrats-Projekt-Dashboard mit DAG-Blockern | Geplant |
| `apps/shared` | Elixir | Geteilte Domain-Models (Sitzung, TOP, Dokument) | Funktionsfähig |
| `tools/allgaeuer_zeitung_mcp` | Python | AZ-Artikel suchen/lesen (MCP) | Bestehend |
| `tools/pdf_ingest` | Python | PDFs ingesten, Highlights extrahieren (MCP) | Geplant |
| `skills/foerdermittel` | Markdown-Skill | Fördermittel-Recherche orchestrieren | Funktionsfähig |

## ratsprojekte — Planungsstand

### Konzept
Agentic AI-first Projekt-Tracker für Stadtratsarbeit. Verwaltet politische Projekte mit Blockern, Abhängigkeiten (DAG), Fristen und Quellen. Die AI kann lesen und Vorschläge machen (GO-Prinzip), Carsten entscheidet und bestätigt im Dashboard. Langfristig: Antragsvorlagen aus Projektdaten generieren.

### Architektur
- Phoenix LiveView für Dashboard
- `anubis_mcp` für AI-Zugriff (später)
- Ecto + SQLite3 (geteilte DB mit ratsinfo)
- vis-network für Dependency-Graph (später)

### Datenmodell (DAG)
```
Projekt (titel, status, priorität, beschreibung)
├── Blocker (typ: rechtlich/finanziell/politisch/organisatorisch/infrastruktur,
│            status: offen/in_arbeit/geloest)
│   ├── depends_on: [Blocker] (n:m DAG — mehrere Parents)
│   └── Quellen (sitzung/foerderprogramm/gesetz/url/zeitungsartikel)
└── Quellen (strukturiert, für Antragsvorlagen-Generierung)
```

### Roadmap
1. **MVP**: Datenmodell + Seed + LiveView (Projekt-Liste, Blocker-Detail) — Issues #7-#10
2. **Antragsvorlagen**: Markdown-Render aus Projektdaten — Issue #11
3. **Dependency-Graph**: vis-network in LiveView
4. **MCP-Server**: AI-Tools für lesen/suggest (GO-Prinzip)
5. **Ratsinfo-Integration**: Quellen verlinken mit Sitzung/TOP
6. **AI-Skill**: „Frag den Projekt-Tracker"

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
