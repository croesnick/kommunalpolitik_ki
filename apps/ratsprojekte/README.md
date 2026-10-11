# ratsprojekte

Rechtlich-inhaltliche Standortbestimmung für Stadtratsprojekte.
Phoenix LiveView + MCP-Server für AI-Zugriff.

## Starten

```bash
cd apps/ratsprojekte
mix deps.get
mix ecto.migrate
mix phx.server
```

Das Repo liefert keine Beispielprojekte. Ein lokaler Seed-Datensatz lässt
sich per `mix run priv/repo/seeds.exs` einspielen (Datei liegt nicht im
Repo).

## URLs (dev-only)

| Was | URL |
|---|---|
| Dashboard (Projekt-Übersicht) | http://localhost:4000 |
| Projekt-Detail | http://localhost:4000/projekte/<slug> |
| MCP-Endpoint (AI-Harness) | http://localhost:4000/mcp |
| Tidewave (Debugging) | http://localhost:4000/tidewave/mcp |

Projekte werden über Slugs adressiert, nicht über Datenbank-IDs. Derselbe
Slug ist im Vault der Tag `#ratsprojekt/<slug>`.

## DB

SQLite unter `~/.local/share/ratsinfo/ratsinfo.db` (geteilt mit ratsinfo).

```bash
mix ecto.reset    # DB droppen + neu migrieren + seeds
```

## MCP-Tools (GO-Prinzip)

### Lese-Tools (read-only)

| Tool | Beschreibung |
|---|---|
| `list_projekte` | Alle Projekte mit Status/Priorität, filterbar nach Status |
| `list_blockierte_projekte` | Projekte, bei denen kein Realisierungsstrang gangbar ist |
| `show_projekt` | Vollständige Standortbestimmung (Stränge, Vorbedingungen, Schritte, Quellen) |
| `search_projekte` | Volltextsuche in Titel/Beschreibung |
| `check_antragsreife` | Antragsreife prüfen: `nicht_antragsreif` / `antragsreif` / `antragsreif_mit_vorbehalten` |
| `list_pending_proposals` | Vorschläge auflisten, filterbar nach Projekt und Status |
| `show_pending_proposal` | Details eines Vorschlags |

### Propose-Tools (schreiben nur in `pending_proposals`)

Diese Tools legen Vorschläge in der Staging-Tabelle an. Sie schreiben nie
direkt in Projekte oder Stränge.

| Tool | Beschreibung |
|---|---|
| `propose_projekt` | Neues Projekt vorschlagen |
| `propose_realisierungsstrang` | Realisierungsstrang zu einem Projekt vorschlagen |
| `propose_status_change` | Statuswechsel vorschlagen |
| `propose_projekt_update` | Projektfelder als Vorschlag ändern |
| `propose_strang_update` | Strangfelder als Vorschlag ändern |

### GO-Execution

`decide_proposal` führt ein GO aus, das der Stadtrat im Chat gegeben hat.
Die AI ruft dieses Tool nie ohne explizites GO auf. Der Audit-Trail
unterscheidet über `entschieden_von` die Herkunft: `"stadtrat-via-ai"`
steht für ein GO aus dem Chat, `"stadtrat"` für eines aus dem Dashboard.
Beide Wege nutzen `Ratsprojekte.ProposalApplier` als gemeinsame Apply-Logik.

Registriert in `opencode.json` als remote MCP unter `ratsprojekte`.

## AI Skills

Drei Skills arbeiten gegen diesen Server: `ratsprojekt_stand`
(Standortbestimmung), `ratsprojekt_delta` (neue Informationen gegen den
Stand halten) und `ratsprojekt_proposal` (Vault konsolidieren, Gates prüfen,
Proposal einbringen). OpenCode lädt sie automatisch aus `skills/`.

## Architektur

- Phoenix LiveView für Dashboard
- `anubis_mcp` (LGPL-3.0) als MCP-Server, Plug in `router.ex` unter `/mcp`
- Ecto + SQLite3 (geteilte DB mit ratsinfo)
- Tidewave für Debugging (dev-only Plug in `endpoint.ex`)

## Roadmap

| # | Meilenstein | Status |
|---|---|---|
| 1 | MVP: Datenmodell + Seed + LiveView | fertig |
| 2 | Projekt-Detailansicht | fertig |
| 3 | MCP-Server mit Lese- und Propose-Tools | fertig |
| 4 | Slug-Routen (`/projekte/:slug`) | fertig |
| 5 | AI-Skills `ratsprojekt_stand`, `ratsprojekt_delta`, `ratsprojekt_proposal` | fertig |
| 6 | Antragsvorlagen-Generator (#15) | offen |
| 7 | Ratsinfo-Integration: Quellen mit Sitzung/TOP verlinken | offen |
| 8 | `value_proposition` + `success_metrics` als Antragsreife-Gates (#37) | offen |
