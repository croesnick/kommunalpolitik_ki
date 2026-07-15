# Kommunalpolitik KI

Ein AI-Harness für Ratsarbeit. Tools, die einem Stadtrat die tägliche politische
Arbeit erleichtern — RIS durchsuchen, PDFs ingesten, Fördermittel recherchieren,
Lokalzeitung scrapen, Projekte strukturieren. Jedes Tool ist AI-Enabled (CLI,
MCP oder Skill) und wird über [OpenCode](https://opencode.ai) als Harness
orchestriert. Quellenbindung, lokale Datensouveränität und demokratische
Verantwortung sind Kernprinzipien — nicht Afterthought.

## Quick Start

```bash
# Elixir-Apps (ratsinfo, ratsprojekte, shared)
mix deps.get
mix ecto.migrate                           # ratsprojekte (shared SQLite DB)
mix run priv/repo/seeds.exs                # ratsprojekte seed
mix phx.server                             # ratsprojekte auf :4000

# Python-Tools (pro Tool unter tools/)
uv sync
```

Das Repo ist für OpenCode als AI-Harness konfiguriert. `opencode.json` registriert
MCP-Server und lädt Skills aus `skills/`. Die AI kann dann RIS durchsuchen, das
Projekt-Dashboard lesen und Proposals einbringen, AZ-Artikel suchen, PDFs
verarbeiten, den Vault durchsuchen und Fördermittel recherchieren.

## Tool-Übersicht

| Tool | Sprache | Zweck | AI-Schnittstelle | Status |
|---|---|---|---|---|
| `apps/ratsinfo` | Elixir | RIS-Scraper + CLI + lokale Volltextsuche | CLI (`ratsinfo sync/search/show`) | ✅ |
| `apps/ratsprojekte` | Elixir (Phoenix LiveView) | Stadtrats-Projekt-Dashboard | LiveView + MCP (`/mcp`) | ✅ |
| `apps/shared` | Elixir | Geteilte Domain-Models | — (Bibliothek) | ✅ |
| `tools/allgaeuer_zeitung_mcp` | Python | AZ-Artikel suchen/lesen | MCP | ✅ |
| `tools/pdf_ingest` | Python | PDFs ingesten, Highlights extrahieren | MCP (`opencode.json`) | ✅ |
| `skills/foerdermittel_recherche` | Skill | Fördermittel-Recherche orchestrieren | Agent Skill | ✅ |
| `skills/ratsprojekt_delta` | Skill | Neue Infos gegen Projektstand halten | Agent Skill | ✅ |
| `skills/ratsprojekt_stand` | Skill | Projekt-Standortbestimmung aus ratsprojekte | Agent Skill | ✅ |
| `skills/ratsprojekt_proposal` | Skill | Proposal-Workflow: Vault → Gates → Proposal | Agent Skill | ✅ |
| `skills/sitzungsvorbereitung` | Skill | Sitzungsmappe erstellen (WF 1) | Agent Skill | ✅ |
| `skills/vault_suche` | Skill | Obsidian-Vault durchsuchen | Agent Skill | ✅ |

## Architektur-Prinzipien (Auszug)

- **Elixir-first** — Default Elixir, Ausnahmen nur bei fehlenden Libs.
- **Unix-Prinzip** — Ein Tool pro Aufgabe. Composable, orthogonal.
- **MVP vor Infrastruktur** — Erst der einfache Fall funktioniert, dann RAG/OCR/UI.
- **Problem-first** — Tools entstehen aus konkreten politischen Bedarfen.
- **AI-Enabled** — Jedes Tool hat eine AI-Schnittstelle (CLI, MCP, Skill).
- **Quellenpflicht** — Jede politisch relevante Aussage braucht eine Quelle.
- **GO-Prinzip** — AI berät, Mensch entscheidet. Tools read-only by design.
- **Vault = Source of Truth, ratsprojekte = Distillat** — Einseitiger Datenfluss.

Vollständige Prinzipien, Guardrails und Tooling-Vorgaben: [`AGENTS.md`](AGENTS.md).

## Verzeichnisstruktur

```
kommunalpolitik_ki/
├── apps/                   # Elixir-Apps (workspace-Pattern)
│   ├── ratsinfo/           # RIS-Scraper + CLI (AI: CLI)
│   ├── ratsprojekte/       # Projekt-Dashboard (AI: LiveView + MCP)
│   └── shared/             # Geteilte Domain-Models
├── tools/                  # Nicht-Elixir
│   ├── allgaeuer_zeitung_mcp/  # AZ-Artikel (AI: MCP)
│   └── pdf_ingest/         # PDF-Ingestion (AI: MCP)
├── skills/                 # AI-Harness-Skills
│   ├── foerdermittel_recherche/
│   ├── ratsprojekt_delta/
│   ├── ratsprojekt_stand/
│   ├── ratsprojekt_proposal/
│   ├── sitzungsvorbereitung/
│   └── vault_suche/
├── docs/                   # Kanonische Dokumentation
│   ├── ratsprojekte-lifecycle.md
│   ├── workflows.md
│   ├── nomenklatur.md
│   └── prerequisites.md
├── opencode.json           # MCP-Server + Skills-Konfiguration
├── AGENTS.md               # Projekt-Prinzipien & Architektur
└── mix.exs                 # workspace root
```

## Doku & Verweise

- [`AGENTS.md`](AGENTS.md) — Projekt-Prinzipien, Architektur, Guardrails, Tooling-Vorgaben
- [`docs/workflows.md`](docs/workflows.md) — 10 Workflows eines Stadtrats (Sitzungsvorbereitung, Projekt-Entwicklung, Beschlussnachverfolgung, Öffentlichkeitsarbeit, etc.)
- [`docs/nomenklatur.md`](docs/nomenklatur.md) — Fachbegriffe der Ratsarbeit
- [`docs/ratsprojekte-lifecycle.md`](docs/ratsprojekte-lifecycle.md) — Projektlebenszyklus (States, Transitions, Gates)
- [GitHub Projects Board](https://github.com/users/croesnick/projects) — Issues, Meilensteine, Priorisierung
