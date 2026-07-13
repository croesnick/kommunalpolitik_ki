# ratsprojekte

Rechtlich-inhaltliche Standortbestimmung für Stadtratsprojekte.
Phoenix LiveView + MCP-Server für AI-Zugriff.

## Starten

```bash
cd apps/ratsprojekte
mix deps.get
mix ecto.migrate
mix run priv/repo/seeds.exs
mix phx.server
```

## URLs (dev-only)

| Was | URL |
|---|---|
| Dashboard (Projekt-Übersicht) | http://localhost:4000 |
| Projekt-Detail (z.B. Bahnhofstraße) | http://localhost:4000/projekte/10 |
| MCP-Endpoint (AI-Harness) | http://localhost:4000/mcp |
| Tidewave (Debugging) | http://localhost:4000/tidewave/mcp |

## Seed-Projekte

| ID | Projekt | Status | Priorität |
|---|---|---|---|
| 10 | Bahnhofstraße umgestalten | aktiv | hoch |
| 11 | Gennachpark / Moorpark | aktiv | hoch |
| 12 | Freibad Digitalisierung | idee | mittel |

## DB

SQLite unter `~/.local/share/ratsinfo/ratsinfo.db` (geteilt mit ratsinfo).

```bash
mix ecto.reset    # DB droppen + neu migrieren + seeds
```

## MCP-Tools (read-only, GO-Prinzip)

| Tool | Beschreibung |
|---|---|
| `list_projekte` | Alle Projekte mit Status/Priorität |
| `show_projekt` | Vollständige Standortbestimmung (Stränge, Vorbedingungen, Schritte, Quellen) |
| `search_projekte` | Volltextsuche in Titel/Beschreibung |

Registriert in `opencode.json` als remote MCP unter `ratsprojekte`.

## AI Skill

`skills/projekt_tracker/SKILL.md` — "Frag den Projekt-Tracker".
Wird automatisch von OpenCode discovered (unter `skills/`).

## Architektur

- Phoenix LiveView für Dashboard
- `anubis_mcp` (LGPL-3.0) für MCP-Server — Plug in `router.ex` unter `/mcp`
- Ecto + SQLite3 (geteilte DB mit ratsinfo)
- Tidewave für Debugging (dev-only Plug in `endpoint.ex`)

## Roadmap

1. ✅ MVP: Datenmodell + Seed + LiveView
2. ✅ Projekt-Detailansicht (`/projekte/:id`)
3. ✅ MCP-Server (read-only Tools)
4. ✅ AI Skill "Frag den Projekt-Tracker"
5. ⬜ Antragsvorlagen-Generator (Issue #15)
6. ⬜ Ratsinfo-Integration (Quellen verlinken mit Sitzung/TOP)
