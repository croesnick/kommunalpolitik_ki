#!/usr/bin/env bash
set -euo pipefail

# Skript: Erstellt die Issues 13-14 (Nachtrag: Nextcloud + Öffentlichkeitsarbeit)
# Repo: croesnick/kommunalpolitik_ki
# Ausführen: bash scripts/create-workflow-issues-2.sh

cd "$(git rev-parse --show-toplevel)"

echo "=== Issues 13-14 erstellen ==="

# --- Issue 13: Nextcloud-MCP ---
gh issue create \
  --title "[tools] Nextcloud-MCP: Kollaborationsplattform anbinden" \
  --label "tools,workflow" \
  --body '## Use Case

WF 9: Die Fraktion nutzt eine Nextcloud-Instanz als Kollaborationsplattform (z.B. wolke.netzbegruenung.de). Dort liegen geteilte Dokumente, Planungen und Tabellen (z.B. ein ODS-Sheet mit Projekt-Kondensat).

## Recherche-Ergebnis

Es gibt bereits ausgereifte Open-Source Nextcloud-MCP-Server:

### Empfehlung: `cbcoutinho/nextcloud-mcp-server`
- Repo: https://github.com/cbcoutinho/nextcloud-mcp-server
- 300 Stars, 110+ Tools, Python, AGPL-3.0, Docker
- Features: Files/WebDAV (12 Tools), Calendar (20+), Contacts, Notes, Deck, Tables, Talk, Collectives, Cookbook, Mail, Sharing
- Auth: BasicAuth mit App-Password, Login-Flow-v2 (OAuth)
- Deployment: `uvx`, Docker, Helm
- AGPL-3.0 — für interne Nutzung verschmerzbar

### Alternative: Offizielles Nextcloud `context_agent`
- Repo: https://github.com/nextcloud/context_agent
- Nextcloud 34+, via AppAPI, kombiniert mit Assistant-LLM
- Strategisch sauberste Wahl, aber schwerer aufzusetzen (AppAPI, Assistant-Stack)

### Minimal: `LaubPlusCo/mcp-webdav-server`
- Repo: https://github.com/LaubPlusCo/mcp-webdav-server
- TypeScript/Node, MIT, reines WebDAV (list, read, create, move, copy, search)
- Falls nur Files gebraucht werden

## Lücke: ODS-Parsing

Kein bestehender Server hat einen echten ODS-Reader. Optionen:
1. `cbcoutinho` nutzen + ODS als Datei lesen (AI parst den Text-Content)
2. Eigenes Mini-Add-On `tools/nextcloud_ods_mcp` (~50 Zeilen Python, `odfpy`, Apache-2.0)

Tools für das Add-On: `list_sheets(path)`, `read_sheet(path, sheet_name, range?)`, `read_cell(path, sheet_name, cell)`, `search_sheet(path, query)`

## Konfiguration

Nextcloud-URL und Zugangsdaten sind privat. Konfiguration in `config.local.yml` oder lokale `opencode.json`, nicht im Repo. Skill-basierte Einrichtung mit GO als Option (wie bei Email-MCP diskutiert).

## Datenschutz-Grenze

Nur Zugriff auf das, was als Stadtrat/Fraktionsmitglied regulaer abrufbar ist. Siehe AGENTS.md §8.

## Referenz

- `docs/workflows.md` WF 9
- `docs/nomenklatur.md` — Kollaborationsplattform
- @librarian-Report (Session lib-2): vollstaendige Recherche mit allen Repos'

echo "  -> Issue 13 erstellt"

# --- Issue 14: Öffentlichkeitsarbeit ---
gh issue create \
  --title "[skills] Öffentlichkeitsarbeit: Sitzungsankündigung und -nachbericht generieren" \
  --label "skills,workflow" \
  --body '## Use Case

WF 10: Vor Sitzungen kündigt die Fraktion die relevanten TOPs an, nach Sitzungen gibt es einen Nachbericht. Diese Nachrichten werden in einem Kommunikationskanal geteilt (WhatsApp-Community, Social Media, Website).

## Ziel

Ein Template-basierter Workflow, der aus vorhandenen Daten kanal-gerechte Nachrichten generiert:
- **Vorbericht**: aus TOPs + Positionen (aus Sitzungsvorbereitung WF 1)
- **Nachbericht**: aus Beschlüssen (aus RIS-Daten / `ratsinfo show`)

## Template-Variablen

- TOP-Liste mit kurzer Beschreibung
- Sitzungsdatum
- Fraktionspositionen (aus Sitzungsmappe)
- Beschlüsse (fuer Nachbericht)
- Fraktionsname

## Architektur

- Template-Engine: Markdown-Templates mit Platzhaltern
- Input: Sitzungsmappe (WF 1), RIS-Daten (`ratsinfo`), ggf. ratsprojekte
- Output: Kanal-gerechte Nachricht (kurz, sachlich, verstaendlich)
- **Das Posten bleibt beim Stadtrat (GO)** — die AI generiert nur den Text

## Abstraktion

Von konkreter Plattform (WhatsApp, Grüne) abstrahiert: der Workflow ist "Sitzungsankündigung / -nachbericht generieren". Der Kanal ist austauschbar. Keine WhatsApp-API-Integration (keine offizielle API fuer Communities).

## Voraussetzungen

- Sitzungsvorbereitung-Skill (separates Issue) fuer die Vorbericht-Datenbasis
- RIS-Daten via `ratsinfo` fuer die Nachbericht-Datenbasis

## Referenz

- `docs/workflows.md` WF 10
- `docs/nomenklatur.md` — Sitzungsankündigung/Vorbericht, Sitzungsnachbericht'

echo "  -> Issue 14 erstellt"

echo ""
echo "=== Fertig! Issues 13-14 erstellt. ==="
