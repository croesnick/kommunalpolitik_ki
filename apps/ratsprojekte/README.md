# ratsprojekte

Der lokale Hub für den Weg von der Idee zum Antrag ([ADR 0004](../../docs/adr/0004-ratsprojekte-als-lokaler-hub.md)).
Phoenix LiveView, läuft lokal für eine Person — die Redaktion führt, alle
anderen bekommen eine bewusst ausgegebene Fassung.

**Zustand: Gerüst.** Dieses App ist das frische Phoenix-Grundgerüst
(Phoenix 1.8.16, LiveView 1.2.13, Bandit, Tailwind v4, esbuild — der von
`mix phx.new` gesetzte Stand, Ticket #435). Schema und Kontext baut #436,
die Oberfläche mit dem Main Flow „Was ist passiert?“ baut #437, der Stand
als Druck #438, die Befragung #439, der lokale Betrieb (LaunchAgent, Touch
ID, Unix-Socket) #440 und der Connector-Schreibweg „Fakt vorschlagen“ #277.
Das Storyboard [`storyboard/hub-desktop.html`](storyboard/hub-desktop.html)
ist die Durchklick-Referenz der Ziel-Oberfläche.

## Starten (Dev)

```bash
cd apps/ratsprojekte
mix setup        # Deps, Datenbank anlegen/migrieren, Assets
mix phx.server   # http://localhost:4000
```

## Datenbank

Eigene SQLCipher-Datei unter `~/Library/Application Support/ratsprojekte/`
statt der mit ratsinfo geteilten (ADR 0004):

| Umgebung | Datei | Schlüssel |
|---|---|---|
| Dev | `dev.db` | keiner — SQLCipher verhält sich ohne Schlüssel wie normales SQLite |
| Test | `ratsprojekte_test.db` (app-lokal) | keiner |
| Release | `ratsprojekte.db` (oder `DATABASE_PATH`) | `RATSPROJEKTE_DB_KEY` — verkabelt in #440 |

Dev trägt bewusst keine echten Daten: Mit echten Daten läuft der Hub nie im
Dev-Modus (ADR 0004, dort hängt Tidewave am Endpoint).

**exqlite baut im Workspace gegen die SQLCipher-Systembibliothek** (BSD),
geregelt über `config :exqlite` in `config/config.exs` — gilt auch für
ratsinfo und komki_cli. Voraussetzung und Nachbau:
[docs/prerequisites.md](../../docs/prerequisites.md). Der Test
`Ratsprojekte.SqlcipherTest` schlägt fehl, wenn exqlite ungepatcht gebaut
wurde.

## Regeln, kein Ausrüstungsgegenstand

Zurückgetragen aus dem alten Bestand und verbindlich:

- **CSP-Header**: gesetzt im Router (`@content_security_policy`), jede
  Seite testet sie — inklusive des SHA-256-Hashes für das Inline-Theme-Script
  (`test/ratsprojekte_web/content_security_policy_test.exs`).
- **Sobelow-Audit**: `mix sobelow --private --threshold high --exit` in der
  CI, keine Funde (`.sobelow-conf`).
- **Slug-Konvention**: Projekte werden über Slugs adressiert, nicht über
  Datenbank-IDs — kebab-case, ASCII, Umlaute als ae/oe/ue/ss; derselbe Slug
  ist im Vault der Tag `#ratsprojekt/<slug>` (Einzelheiten: AGENTS.md am
  Repo-Root). Umsetzung in den Routen mit #437.
- **Vorschlagsweg**: komki schlägt vor, die Redaktion entscheidet. Der Hub
  nimmt von der KI nichts direkt entgegen — der Schreibweg läuft über den
  Connector-Socket mit Token (#277, vorher #440). `decide_proposal` und der
  Dev-MCP-Endpoint sind entfallen (ADR 0004).

## Aufbau

```
apps/ratsprojekte
├── assets/                  # Tailwind v4 (CSS-first) + esbuild, Watcher in dev.exs
├── config/                  # Phoenix-Stand; DB-Pfade und exqlite-Build hier
├── lib/ratsprojekte/        # Kontext-Schicht (baut #436)
├── lib/ratsprojekte_web/    # Router mit CSP, Endpoint mit Tidewave (dev)
├── priv/repo/               # Migrationen (baut #436) + Seeds (erfundene Gartenstadt-Projekte)
├── priv/static/            # gebaute Assets landen in priv/static/assets/ (gitignored)
└── storyboard/             # Durchklick-Referenz für #437
```
