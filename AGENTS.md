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

### 10. Vault = Source of Truth, ratsprojekte = Distillat

Der Obsidian-Vault ist das Gedächtnis — roh, unstrukturiert, alles. ratsprojekte ist das Distillat — konsolidiert, strukturiert, antragsreif, quellenbelegt. Der Datenfluss ist **strikt einseitig**: Vault → ratsprojekte. Nie umgekehrt.

- **Vault** ist Source of Truth, nicht ratsprojekte.
- **ratsprojekte** bekommt nur Distillate, nie Rohmaterial.
- **Pflicht**: Alles, was in der OpenCode-Session entsteht, fließt als konsolidierte Notiz zurück in den Vault, *bevor* es als Proposal in ratsprojekte eingereicht wird.
- **Kein Rückfluss**: ratsprojekte schreibt nie zurück in den Vault. ratsprojekte ist das Endprodukt, nicht der Input.

Der `proposal_vorbereitung`-Skill orchestriert diesen Workflow: sammeln → konsolidieren (in den Vault) → Gates prüfen → Proposal einbringen.

### 11. Projektlebenszyklus (kanonisch)

Der vollständige Lifecycle von Vault-Idee über Proposal zum Projekt bis zum Abschluss/Archivierung ist in [`docs/ratsprojekte-lifecycle.md`](docs/ratsprojekte-lifecycle.md) als Mermaid-Chart dokumentiert. Dieses Dokument ist der **Single Source of Truth für den Projektlebenszyklus** — alle Skills, MCP-Tools und AI-Workflows richten sich nach ihm.

**Pflicht**: Bei Änderungen am Lifecycle (neue States, Übergänge, Gates) wird zuerst das Lifecycle-Dokument aktualisiert, *bevor* Code oder Skills angepasst werden. Jede OpenCode-Sitzung, die Workflow-Änderungen vornimmt, prüft und aktualisiert das Dokument.

## Lizenz-Bewusstsein

Abhängigkeiten auf Lizenzkompatibilität prüfen. PyMuPDF ist AGPL-3.0 (oder kommerziell von Artifex). Für ein persönliches/Open-Source-Projekt ist AGPL in Ordnung; bei proprietärer Nutzung Alternative evaluieren (`pdfplumber` MIT, `pdf.js` Apache-2.0). Pro Tool in der Tool-Doku dokumentieren.

## Tool-Übersicht

| Tool | Sprache | Zweck | AI-Schnittstelle | Status |
|---|---|---|---|---|
| `apps/ratsinfo` | Elixir | RIS-Scraper + CLI + lokale Volltextsuche | CLI (`ratsinfo sync/search/show`) | Funktionsfähig |
| `apps/ratsprojekte` | Elixir (Phoenix LiveView) | Stadtrats-Projekt-Dashboard | LiveView + MCP (`/mcp`) | Funktionsfähig |
| `apps/shared` | Elixir | Geteilte Domain-Models | — (Bibliothek) | Funktionsfähig |
| `tools/allgaeuer_zeitung_mcp` | Python | AZ-Artikel suchen/lesen | MCP | Bestehend |
| `tools/pdf_ingest` | Python | PDFs ingesten, Highlights extrahieren | MCP (geplant) | Geplant |
| `skills/foerdermittel` | Markdown-Skill | Fördermittel-Recherche orchestrieren | Agent Skill | Funktionsfähig |
| `skills/projekt_tracker` | Markdown-Skill | Projekt-Standortbestimmung aus ratsprojekte | Agent Skill | Funktionsfähig |
| `skills/proposal_vorbereitung` | Markdown-Skill | Proposal-Workflow: sammeln → Vault → Gates → Proposal | Agent Skill | Funktionsfähig |
| `skills/vault_suche` | Markdown-Skill | Obsidian-Vault durchsuchen | Agent Skill | Funktionsfähig |

## ratsprojekte — Planungsstand

### Konzept
Rechtlich-inhaltliche Standortbestimmung für Stadtratsprojekte. Kein Task-Tracker, keine Todo-Liste. Sondern: welche Realisierungsstränge gibt es, welche rechtlichen Vorbedingungen stehen, welcher Weg kann gegangen werden — und welcher nicht. Die AI kann lesen und Vorschläge machen (GO-Prinzip). Langfristig: Antragsvorlagen aus Projektdaten generieren.

### Architektur
- Phoenix LiveView für Dashboard
- `anubis_mcp` (LGPL-3.0) für AI-Zugriff — MCP-Endpoint unter `http://localhost:4000/mcp` (dev-only, read-only Tools)
- Ecto + SQLite3 (geteilte DB mit ratsinfo)

### Datenmodell
```
Projekt (titel, slug, beschreibung, status, prioritaet, beschlussvorschlag, adressat)
  status: idee | aktiv | abgeschlossen | verworfen  (siehe docs/ratsprojekte-lifecycle.md)
├── Realisierungsstrang (label A/B/C, titel, beschreibung, rechtliche_grundlage, bedingung, bedingung_erfuellt)
│   ├── Vorbedingung (text, erfuellt, rechtliche_grundlage, typ)
│   └── Schritt (text, frist) — geordnete Liste, keine Checkboxen
└── Quelle (typ, titel, url, paragraf, abrufdatum)

PendingProposal (projekt_id, typ, status)  — AI-Vorschläge, GO-Gate vor Mutation
  typ:    add_projekt | add_realisierungsstrang | change_status
  status: pending | approved | rejected
```

### Slug-Konvention

Projekte werden über Slugs identifiziert, nicht über DB-IDs. Der Slug ist der stabile Vertrag zwischen ratsprojekte und dem Obsidian-Vault:

- **Format**: kebab-case, lowercase, ASCII only (`^[a-z0-9]+(?:-[a-z0-9]+)*$`). Umlaute als ae/oe/ue/ss.
- **ratsprojekte URL**: `/projekte/freibad-digitalisierung` (Slug in der URL, nicht die ID)
- **Vault-Tag**: `#ratsprojekt/freibad-digitalisierung` (gleicher Slug als Obsidian-Tag)
- **MCP-Tools**: alle projektbezogenen Tools nehmen `slug` als Parameter, nie `id`
- **Intern**: DB-IDs bleiben als Primary Keys und Foreign Keys in `pending_proposals.projekt_id`. Slug→ID-Auflösung passiert an der Grenze (LiveView mount, MCP tool execute).
- **Copy-Button**: auf der Projekt-Detailseite kopiert ein Button den Vault-Tag `#ratsprojekt/{slug}` in die Zwischenablage

### Roadmap
1. **MVP**: Datenmodell + Seed + LiveView — Issues #12, #13, #14 ✅
2. **Projekt-Detailansicht**: Show-LiveView `/projekte/:id` — Issue #16 ✅
3. **MCP-Server**: AI-Tools für lesen (GO-Prinzip) — Issue #17 ✅
4. **AI-Skill**: „Frag den Projekt-Tracker" — `skills/projekt_tracker/` ✅
5. **Antragsvorlagen**: Markdown-Render aus Projektdaten — Issue #15
6. **Ratsinfo-Integration**: Quellen verlinken mit Sitzung/TOP
7. **Proposal-Workflow-Skill**: `skills/proposal_vorbereitung/` ✅
8. **Slug-basierte Projektrouten**: Slug statt ID in URLs, MCP-Tools, Vault-Tags ✅

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
│   ├── ratsprojekte/       # Projekt-Dashboard (AI: LiveView + MCP)
│   └── shared/             # Geteilte Domain-Models
├── tools/                  # Nicht-Elixir
│   ├── allgaeuer_zeitung_mcp/  # AZ-Artikel (AI: MCP)
│   └── pdf_ingest/         # PDF-Ingestion (AI: MCP, geplant)
├── skills/                 # AI-Harness-Skills
│   ├── foerdermittel/      # Fördermittel-Recherche (AI: Agent Skill)
│   ├── projekt_tracker/    # Projekt-Standortbestimmung (AI: Agent Skill)
│   ├── proposal_vorbereitung/ # Proposal-Workflow (AI: Agent Skill)
│   └── vault_suche/        # Vault-Volltextsuche (AI: Agent Skill)
├── docs/                   # Kanonische Dokumentation
│   └── ratsprojekte-lifecycle.md  # Projektlebenszyklus (Mermaid-Chart)
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
