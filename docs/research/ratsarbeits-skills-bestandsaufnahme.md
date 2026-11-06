# Bestandsaufnahme: Ratsarbeits-Skills, ihre Quellen und vorhandene pi-Vorlagen

- **Ticket:** #374 (Kind der Karte #279), Grundlage für #375
- **Stand:** 2026-11-06, Repo-Stand `d995776` (origin/main), Ticketstände per `gh` am selben Tag
- **Frage:** Welche Ratsarbeits-Skills unter `skills/` gibt es, auf welche Quellen und Tools greifen sie zu, und welche davon deckt heute eine pi-Vorlage ab?

Alle Belege sind Primärquellen im Repo (`Datei:Zeile`) oder GitHub-Tickets. Wertungen und Entscheidungen fehlen bewusst. Sie gehören nach #375.

## Ausgangslage: was eine komki-Session heute anbietet

**Skills.** komki startet pi mit `--no-skills`, `--no-context-files` und `--no-prompt-templates` (`apps/komki_cli/lib/komki_cli/pi.ex:271-274`). In einer komki-Session ist also keiner der Skills aus `skills/` geladen. `opencode.json:72-74` bindet `skills/` nur für OpenCode ein, außerhalb von komki.

**Built-in tools.** pis eingebaute Werkzeuge (read, write, bash …) sind aus; erlaubt sind nur die MCP-Tools des Vermittlers (`pi.ex:308-315`, `--no-builtin-tools --tools mcp__komki__*`). CLI-Aufrufe wie `./apps/ratsinfo/ratsinfo`, `obsidian`, `curl` oder `uv run`, auf die die Skills bauen, kann eine komki-Session deshalb nicht ausführen.

**pi-Vorlagen.** komki lädt drei Prompt-Vorlagen aus `apps/komki_cli/priv/pi/komki-vorlagen` über einen expliziten Pfad (`apps/komki_cli/lib/komki_cli/anzeige.ex:53-66`, `pi.ex:301-306`) und schreibt sie vor jedem pi-Start neu ins pi-Home (`anzeige.ex:21-25`). Entstanden sind sie in #244 (geschlossen).

| Vorlage | Zweck (Frontmatter) | Werkzeuge, die die Vorlage nennt | Beleg |
|---|---|---|---|
| `/sitzungsmappe [Thema oder Kennungen]` | Sitzungsmappe aus den Dokumenten des Arbeitsraums | `list_documents`, `admit_document`; RIS/Vault nur bei offener Frage, Web nur auf Bitte | `komki-vorlagen/sitzungsmappe.md:2-18` |
| `/zusammenfassen <Dokument, TOP oder Notiz>` | Ein Dokument, einen TOP oder eine Notiz zusammenfassen | `admit_document`, `ris_show`, `vault_read` | `komki-vorlagen/zusammenfassen.md:2-15` |
| `/quellen` | Alle Quellen des Gesprächs als Liste, Abschnitt „Ohne Beleg“ | keins („Rufe dafür kein Werkzeug auf“) | `komki-vorlagen/quellen.md:2-13` |

**Werkzeuge des Vermittlers.** Eigene Tools sind `ping` und `list_documents` (`apps/komki_mediator/lib/komki_mediator/fassung.ex:16`). Die Connector-Tools stehen in den Manifesten `apps/komki_connector/lib/komki_connector/manifest.ex`:

| Connector (Fassung) | Tools | Einschränkungen laut Manifest/Code | Beleg |
|---|---|---|---|
| documents (`komki-documents/1`) | `admit_document` | nur Raumdokumente; PDFs nur in der Burrito-Einzeldatei (#288) | `manifest.ex:60-83` |
| ris (`komki-ris/2`) | `ris_search`, `ris_show` | nur öffentliche TOPs, nur TOP-Ebene (Suche nach Text, Lesen per `top_id`); keine Sitzungsliste, keine Anlagen; TOP-Texte fehlen über die Gast-API (#148) | `manifest.ex:85-119`; Felder `apps/komki_connector_ris/lib/komki_connector_ris.ex:167-171`, `192-198` |
| web (`komki-web/1`) | `web_search` | nur Suche (Titel, Link, Kurztext); kein Abruf einer Seite | `manifest.ex:121-144` |
| vault (`komki-vault/1`) | `vault_search`, `vault_read`, `vault_write_test` | Schreiben nur neue Notizen in `{vault_dir}/komki-test`; Suche nur in Notizen mit gültigem Label, Teilstring über Titel und Body ohne Frontmatter, höchstens 20 Treffer | `manifest.ex:146-191`; `apps/komki_connector_vault/lib/komki_connector_vault.ex:22`, `59-78`, `113-120`; `…/note.ex:26-29` |

**Bisherige Werkzeuge außerhalb von komki** (Rückbau-Liste in #279):

| Werkzeug | Tools | in `opencode.json` | Beleg |
|---|---|---|---|
| `tools/allgaeuer_zeitung_mcp` | `search_articles(query, limit)`, `get_article(url)`, `list_latest`, `list_sections` | ja (`:4-19`) | `tools/allgaeuer_zeitung_mcp/src/newspaper_mcp/server.py:76,93,110,128` |
| `tools/pdf_ingest` | `ingest`, `extract_text`, `extract_annotations`, `count_pages` | ja (`:20-32`) | `tools/pdf_ingest/src/pdf_ingest/server.py:125,158,189,222` |
| `tools/obsidian_mcp` | `search_notes`, `read_note`, `create_note`, `list_notes` | nein | `tools/obsidian_mcp/src/obsidian_mcp/server.py:148,189,210,234` |
| `tools/ratsinfo_mcp` | `search`, `show`, `sessions`, `sync`, `stats` | nein | `tools/ratsinfo_mcp/src/ratsinfo_mcp/server.py:71,89,105,119,134` |
| `tools/nextcloud_ods_mcp` | `list_sheets`, `read_sheet`, `read_cell`, `search_sheet` | ja (`:49-60`) | `tools/nextcloud_ods_mcp/src/nextcloud_ods_mcp/server.py:48,66,92,114` |
| Nextcloud-MCP (extern, `uvx`) | WebDAV, CalDAV, Notes, Deck, Talk | ja (`:33-48`) | `opencode.json:33-48` |
| ratsprojekte-MCP | `search_projekte`, `list_projekte`, `show_projekt(slug)`, `check_antragsreife`, `propose_*`, `decide_proposal` u. a. | ja (`:66-70`) | `apps/ratsprojekte/lib/ratsprojekte/mcp/server.ex:47-63`, `…/tools/show_projekt.ex:23-24` |
| `ratsinfo`-CLI, `obsidian`-CLI | Aufruf aus den Skills per Shell | — | siehe Skill-Tabellen |

## Ratsarbeits-Skills im Einzelnen

Im Bestand sind acht Ratsarbeits-Skills. Die Spalte „Connector“ nennt den Stand laut Karte #279 und `gh issue view` vom 2026-11-06.

### `sitzungsvorbereitung`

| | |
|---|---|
| **Zweck** | Sitzungsmappe für eine konkrete kommende Sitzung als Vault-Notiz: TOPs, Vorlagen-PDFs, AZ, Vault, Ratsprojekte, „Was die Vorlage nicht sagt“, Querschnittsanalyse bei großen Sitzungen (`skills/sitzungsvorbereitung/SKILL.md:1-24`, `54-151`) |
| **RIS** | `ratsinfo sync`, `ratsinfo sessions`, `ratsinfo show <sitzungs_id>`, ausdrücklich nicht über die Volltextsuche (`:31-37`) |
| **RIS-PDFs** | `pdf_ingest ingest(path)`; `ratsinfo open` ist ein Stub, PDFs „ggf. manuell“ (`:38-40`) |
| **AZ** | `allgaeuer_zeitung_mcp`: `search_articles`, `get_article` (`:41-43`) |
| **Vault lesen** | `obsidian … search`, `read` (`:44-46`); Vault-Name aus `config.local.yml` (`:28-30`) |
| **ratsprojekte** | MCP read-only `search_projekte`, `show_projekt(slug)` (`:47-50`) |
| **Web** | Links per `curl -sL … \| grep -c` verifizieren (`:165-173`) |
| **Vault schreiben** | nach GO per `obsidian eval … adapter.write` nach `1 - Projects/Stadtrat Buchloe/Sitzungsmappen/…` (`:155`, `174-179`) |
| **Passender Connector** | RIS öffentlich: gebaut, ohne TOP-Texte (#148), ohne Sitzungsebene (kein Ticket gefunden; am nächsten #378). RIS-PDFs: offen (#160, #289). AZ: offen (#275, #291). Vault lesen: gebaut. Vault schreiben: offen (#274, dazu #186, #376). ratsprojekte: offen (#277). Seitenabruf/Link-Prüfung: kein Connector, kein Ticket gefunden |
| **pi-Vorlage** | **teilweise:** `/sitzungsmappe` hat dieselbe Absicht, arbeitet aber auf Raumdokumenten statt auf einer RIS-Sitzung, gliedert in vier Punkte (`sitzungsmappe.md:9-14`), schreibt nicht in den Vault und nutzt weder AZ noch ratsprojekte. `/quellen` deckt die Quellenliste ab |

### `bericht_aus_dem_stadtrat`

| | |
|---|---|
| **Zweck** | Rückblick auf alle Sitzungen seit dem letzten Bericht, thematisch verdichtet für ein Laien-Publikum, als Vault-Notiz (`skills/bericht_aus_dem_stadtrat/SKILL.md:1-60`) |
| **Vault lesen** | letzten Bericht finden per `obsidian search` und `tags` auf `bericht-aus-dem-stadtrat`/`stammtisch`, Kriterium u. a. Frontmatter `type:` (`:102-121`); Querverweise per `search`/`read` (`:186-202`); Vault-Name aus `config.local.yml` (`:62-95`) |
| **RIS** | `ratsinfo sync`, `sessions` mit manueller Datumsfilterung, `show <sitzungs_id>` (`:134-182`); nicht-öffentliche TOPs mit 🔒 markieren (`:177`, `451-454`) |
| **AZ** | optional `search_articles(query)`, `get_article(id: …)` (`:212-229`); das Tool nimmt `url`, nicht `id` (`server.py:93`) |
| **ratsprojekte** | optional über `ratsprojekt_stand` (`:476`) |
| **Nextcloud** | nur als künftige Idee für Berichtstermine (`nc_calendar_list_events`, `:490`) |
| **Vault schreiben** | `obsidian create`/`eval` nach `1 - Projects/Stadtrat Buchloe/Berichte/…` (`:231-267`, `330`); „kein GO nötig fürs Schreiben der Berichtsnotiz“ (`:418-422`) |
| **Passender Connector** | RIS öffentlich: gebaut, ohne TOP-Texte (#148), ohne Sitzungsebene. RIS nicht-öffentlich: offen (#198, #377). AZ: offen (#275, #291). Vault lesen: gebaut, aber ohne Frontmatter- und Tag-Suche (siehe oben). Vault schreiben: offen (#274). ratsprojekte: offen (#277). Kalender: „Not yet specified“ in #279 |
| **pi-Vorlage** | **nein.** `/zusammenfassen` fasst einen einzelnen TOP zusammen (`zusammenfassen.md:7`), nicht einen Zeitraum aus mehreren Sitzungen. `/quellen` deckt die Quellenliste ab |

### `antrag_generieren`

| | |
|---|---|
| **Zweck** | Stadtratsantrag nach kanonischer Struktur entwerfen, mit Qualitäts-Gates; fraktionsneutral (`skills/antrag_generieren/SKILL.md:1-108`) |
| **ratsprojekte** | Material über `ratsprojekt_stand` (`:113`, `123`) |
| **Vault lesen** | `vault_suche`; Antragsvorlage über Tag `#antragsvorlage` per `vault_suche` oder `obsidian`-CLI (`:114`, `160-168`) |
| **Web / Förderung / AZ** | `foerdermittel_recherche`, `allgaeuer_zeitung_mcp` (`:114`); Referenzkommunen, Rechtsgrundlagen, Quellen mit URL und Abrufdatum verlangt (`:63-74`, `99-108`), ohne benanntes Web-Werkzeug |
| **Vault schreiben** | Entwurf als Vault-Notiz (`:129`) |
| **Passender Connector** | Vault lesen: gebaut (Tag nur auffindbar, wenn er im Body steht, nicht im Frontmatter: `note.ex:26-29`). Vault schreiben: offen (#274). ratsprojekte: offen (#277). Web-Suche: gebaut, Seitenabruf: kein Ticket gefunden. AZ: offen (#275, #291) |
| **pi-Vorlage** | **nein.** `/quellen` deckt die Quellenliste ab |

### `foerdermittel_recherche`

| | |
|---|---|
| **Zweck** | Fördermittel-Recherche in fünf Strängen mit Förderkulisse, Eigenanteil, Kumulierung und Fristen als Markdown-Report (`skills/foerdermittel_recherche/SKILL.md:1-41`, `105-140`) |
| **Web** | Quellenliste aus Bundes-, Landes- und EU-Portalen (Domains, `:43-71`); URL, Abrufdatum und Paragraf je Aussage (`:73-80`). Kein Werkzeug namentlich genannt; auch die Evals nennen keins (`evals/evals.json`) |
| **Andere Quellen** | keine; das Ergebnis bleibt im Chat (Persistenz im Vault ist #36, offen) |
| **Passender Connector** | Web-Suche: gebaut (`web_search`, nur Treffer mit Kurztext). Seiten lesen, Fristen und Fördersätze am Wortlaut prüfen: kein Connector, kein Ticket gefunden |
| **pi-Vorlage** | **nein.** `/quellen` deckt die Quellenliste ab |

### `ratsprojekt_stand`

| | |
|---|---|
| **Zweck** | Standortbestimmung eines Projekts aus ratsprojekte: Stränge, Vorbedingungen, Fristen, Quellen (`skills/ratsprojekt_stand/SKILL.md:1-28`, `80-113`) |
| **ratsprojekte** | MCP read-only `search_projekte`, `list_projekte`, `show_projekt` (`:30-50`); das Beispiel `show_projekt(id: 10)` (`:43`) passt nicht zum Tool, das `slug` nimmt (`show_projekt.ex:23-24`) |
| **Andere Quellen** | keine |
| **Passender Connector** | ratsprojekte: offen (#277) |
| **pi-Vorlage** | **nein** |

### `ratsprojekt_delta`

| | |
|---|---|
| **Zweck** | Neue Information gegen den Projektstand halten und ein Delta-Report erzeugen; read-only (`skills/ratsprojekt_delta/SKILL.md:1-40`, `95-101`) |
| **Eingaben** | E-Mail/Brief als Text der nutzenden Person; Zeitungsartikel über `allgaeuer_zeitung_mcp` oder `web_fetch`; Förderrichtlinie als URL oder PDF; Vault über `vault_suche`; RIS über `ratsinfo`-CLI (`:44-52`) |
| **ratsprojekte** | `search_projekte`/`list_projekte`, `show_projekt(slug)`, `check_antragsreife(slug)` (`:58-63`) |
| **Vault lesen** | `vault_suche` mit Tag `#ratsprojekt/<slug>` (`:65-69`) |
| **Schreiben** | keins; `propose_*` nur als vorgeschlagener Folgeschritt (`:170-176`) |
| **Passender Connector** | ratsprojekte: offen (#277). Vault lesen: gebaut. RIS öffentlich: gebaut, ohne TOP-Texte (#148). AZ: offen (#275, #291). Web-Suche: gebaut, Seitenabruf: kein Ticket gefunden. E-Mail: offen (#35), im Skill aber Eingabe der nutzenden Person. PDF: Raumdokumente gebaut (#290), RIS-PDFs offen (#160). Verwandt: #54 (pi-Vorlage Nextcloud-Kondensat gegen ratsprojekte, offen) |
| **pi-Vorlage** | **nein** |

### `ratsprojekt_proposal`

| | |
|---|---|
| **Zweck** | Material sammeln, im Vault konsolidieren, Antragsreife-Gates prüfen, Proposal in ratsprojekte einbringen (`skills/ratsprojekt_proposal/SKILL.md:1-48`) |
| **Quellen beim Sammeln** | `vault_suche`, `foerdermittel_recherche`, `allgaeuer_zeitung_mcp`, `ratsinfo`-CLI, `web_search`/`web_fetch` (`:52-64`) |
| **ratsprojekte lesen** | `ratsprojekt_stand` bzw. `search_projekte` (`:66-69`); Gates aus `apps/ratsprojekte/priv/antragsreife_kriterien.md` (`:80-85`) |
| **Vault schreiben** | konsolidierte Notiz vor jedem Proposal Pflicht, nur mit GO (`:71-78`, `188-190`) |
| **ratsprojekte schreiben** | `propose_projekt`, `propose_realisierungsstrang`, `propose_status_change`; `decide_proposal` nur nach GO im Chat (`:124-187`) |
| **Passender Connector** | ratsprojekte read + write: offen (#277). Vault schreiben: offen (#274, #186, #376). Vault lesen: gebaut. RIS: gebaut, ohne TOP-Texte (#148). AZ: offen (#275, #291). Web-Suche gebaut, Seitenabruf: kein Ticket gefunden |
| **pi-Vorlage** | **nein** |

### `vault_suche`

| | |
|---|---|
| **Zweck** | Vault nach einem Thema durchsuchen und eine Trefferliste mit Kontext ausgeben; read-only (`skills/vault_suche/SKILL.md:1-31`, `142-147`) |
| **Vault lesen** | Vault-Name aus `config.local.yml` (`:33-65`); „Volltext über alles“ per `obsidian search` (`:81-93`), dann `obsidian read` (`:95-105`) |
| **Andere Quellen** | keine; AZ, RIS und Web nur als vorgeschlagener Folgeschritt (`:139`, `170-177`) |
| **Passender Connector** | Vault lesen: gebaut (`vault_search`, `vault_read`). Unterschiede zum Skill: nur Notizen mit gültigem Label (`komki_connector_vault.ex:113-120`), höchstens 20 Treffer ohne `limit`-Parameter (`:22`, `manifest.ex:152-157`), kein Frontmatter in der Suche (`note.ex:26-29`). Unklassifizierte Notizen: #280 |
| **pi-Vorlage** | **nein**; die Tools selbst stehen in der Session direkt bereit. `/zusammenfassen` liest eine einzelne Notiz über `vault_read` (`zusammenfassen.md:7`) |

## Übersicht: Skill × Quelle

Legende: **G** Connector gebaut · **T** gebaut mit Lücke, die der Skill braucht · **O** offen, Ticket vorhanden · **—** kein Ticket gefunden · leer: nicht genutzt.

| Skill | RIS | RIS-PDF | Vault lesen | Vault schreiben | AZ | ratsprojekte | Web-Suche | Seite abrufen | pi-Vorlage |
|---|---|---|---|---|---|---|---|---|---|
| `sitzungsvorbereitung` | T (#148, Sitzungsebene —) | O (#160) | G | O (#274) | O (#275) | O (#277) | | — | teilweise (`/sitzungsmappe`) |
| `bericht_aus_dem_stadtrat` | T (#148, #198, Sitzungsebene —) | | T (Frontmatter/Tags) | O (#274) | O (#275) | O (#277) | | | nein |
| `antrag_generieren` | | | T (Tag im Frontmatter) | O (#274) | O (#275) | O (#277) | G (implizit) | — | nein |
| `foerdermittel_recherche` | | | | | | | G (implizit) | — | nein |
| `ratsprojekt_stand` | | | | | | O (#277) | | | nein |
| `ratsprojekt_delta` | T (#148) | O (#160) | G | | O (#275) | O (#277) | | — | nein |
| `ratsprojekt_proposal` | T (#148) | | G | O (#274) | O (#275) | O (#277, write) | G | — | nein |
| `vault_suche` | | | T (nur gelabelte Notizen, 20 Treffer) | | | | | | nein |

`/quellen` ist querschnittlich und für jeden Skill nutzbar; in der Spalte steht es nicht eigens.

**Zählung:** 8 Ratsarbeits-Skills. Davon decken pi-Vorlagen 1 teilweise ab (`sitzungsvorbereitung`) und 7 gar nicht. Kein Skill hat heute alle seine Quellen als gebauten Connector, wenn man „T“ als Lücke zählt. Ganz ohne gebauten Connector sind `ratsprojekt_stand` (nur ratsprojekte, #277) und `foerdermittel_recherche`, sobald neben der Suche auch Seiten gelesen werden müssen. 4 Skills schreiben (alle in den Vault, `ratsprojekt_proposal` zusätzlich in ratsprojekte), 4 lesen nur.

## Ausgeschlossen

Dev-Skills ohne Ratsquelle, out of scope laut #374 und #279: `terminal_screenshot`, `mermaid_vision_loop`, `sprachinventur`.

## Beobachtungen für #375

Nur Tatsachen aus den Belegen oben, ohne Entscheidung.

1. **Kein Skill wirkt heute in komki.** Die Session lädt keine Skills und keine Built-in tools (`pi.ex:271`, `315`). Jeder Shell-Schritt der Skills, also `ratsinfo`-CLI, `obsidian`-CLI, `curl`-Prüfung und `uv run`-Frontmatter-Check, ist dort nicht ausführbar. Erreichbar sind nur `list_documents` und die acht Connector-Tools.
2. **Vorlagen sind der einzige geladene Text.** Nur `komki-vorlagen/` kommt in die Session, und zwar unveränderlich, weil komki die Dateien vor jedem Start neu schreibt (`anzeige.ex:21-25`). Laut `anzeige.ex:12-14` sind Vorlagen „reiner Text, den die nutzende Person selbst abschickt; keine Befugnis“.
3. **Die RIS-Ebene passt nicht.** `sitzungsvorbereitung` und `bericht_aus_dem_stadtrat` arbeiten sitzungsweise (`sessions`, `show <sitzungs_id>`, Datumsfilter). Der RIS-Connector bietet nur TOP-weise Suche und TOP-Lesen (`manifest.ex:91-111`). Für eine Sitzungsliste oder eine Sitzung nach ID gibt es kein Ticket; #378 (RIS-Index) ist am nächsten. TOP-Texte fehlen über die Gast-API (#148).
4. **Nicht-öffentliche TOPs.** `bericht_aus_dem_stadtrat` sieht 🔒-TOPs vor (`SKILL.md:177`). Der Connector zeigt sie nicht, auch nicht in der Trefferzahl (AGENTS.md, Tool-Übersicht). Offen sind #198 und #377.
5. **Die Vault-Suche verhält sich anders.** Die Skills suchen im ganzen Vault, auch in Tags und Frontmatter-`type:` (`bericht…/SKILL.md:102-117`, `antrag…/SKILL.md:162-168`). Der Connector sucht nur in gelabelten Notizen, nur in Titel und Body und liefert höchstens 20 Treffer. Unklassifizierte Notizen bleiben unsichtbar (#280).
6. **Vier Skills schreiben, komki kann es noch nicht.** In komki schreibt nur `vault_write_test` in den Testordner (`manifest.ex:172-183`); offen sind #274, #186 und #376. Schreiben in ratsprojekte ist #277.
7. **Die GO-Regeln widersprechen sich.** `bericht_aus_dem_stadtrat` erlaubt das Schreiben ohne GO (`SKILL.md:418-422`). Die Entscheidung aus #205 („jeder Vault-Write nur nach GO mit Vorschau“, Karte #279) und `sitzungsvorbereitung` (`SKILL.md:174-175`) verlangen ein GO.
8. **Weitere Abweichungen zwischen Skill und Tool.** `ratsprojekt_stand` ruft `show_projekt(id:)` auf (`SKILL.md:43`), das Tool nimmt `slug`. `bericht_aus_dem_stadtrat` ruft `get_article(id:)` auf (`SKILL.md:225`), das Tool nimmt `url`. `ratsprojekt_delta` und `ratsprojekt_proposal` nennen `web_fetch`, das kein Connector anbietet. Die Zielpfade sind fest verdrahtet (`1 - Projects/Stadtrat Buchloe/…`).
9. **Die Vorlage `/sitzungsmappe` ist schmaler als der Skill.** Die Vorlage gliedert in „Worum es geht“, „Beschlussvorschlag“, „Kosten, Fristen, Zuständigkeit“ und „Offene Fragen“ (`sitzungsmappe.md:9-14`). Der Skill fordert zusätzlich Eigen- und Förderanteil, Gewissheit und Verben wie in der Vorlage, „Was die Vorlage nicht sagt“, Fragen für die Fraktion und die Querschnittsanalyse (`SKILL.md:54-151`). Diese Regeln stützt er auf Messungen am lokalen Modell (`:56-77`).
10. **Ein Teil des Inhalts hängt an keinem Werkzeug.** `antrag_generieren` (Antragsstruktur, Gates) und `foerdermittel_recherche` (fünf Stränge, Quellenportale, Kumulierung) bestehen überwiegend aus Methode und nennen kaum ein Werkzeug.
11. **Verwandte offene Tickets:** #36 (Förderrecherche-Persistenz im Vault), #41 (Skill Öffentlichkeitsarbeit), #54 (pi-Vorlage Nextcloud-Kondensat gegen ratsprojekte), #171 (Doku-Szenario Sitzungsmappe-light), #292 (Skill-Evals gegen das Zielmodell Gemma/pi).
12. **Den Weg außerhalb von komki gibt es weiter.** `opencode.json` registriert AZ, `pdf_ingest`, Nextcloud, `nextcloud_ods_mcp`, ratsprojekte und Tidewave sowie `skills/` (`opencode.json:3-74`). Nach ADR 0003 (PR #379) wird nur der Weg durch komki beworben.

## Quellen

Alle abgerufen am 2026-11-06, Repo-Stand `d995776`.

- Skills: `skills/{sitzungsvorbereitung,bericht_aus_dem_stadtrat,antrag_generieren,foerdermittel_recherche,ratsprojekt_stand,ratsprojekt_delta,ratsprojekt_proposal,vault_suche}/SKILL.md`, `skills/foerdermittel_recherche/evals/evals.json`
- pi-Vorlagen: `apps/komki_cli/priv/pi/komki-vorlagen/{sitzungsmappe,zusammenfassen,quellen}.md`
- Session-Start: `apps/komki_cli/lib/komki_cli/pi.ex`, `apps/komki_cli/lib/komki_cli/anzeige.ex`
- Manifeste und Connectoren: `apps/komki_connector/lib/komki_connector/manifest.ex`, `apps/komki_mediator/lib/komki_mediator/fassung.ex`, `apps/komki_connector_ris/lib/komki_connector_ris.ex`, `apps/komki_connector_vault/lib/komki_connector_vault.ex`, `apps/komki_connector_vault/lib/komki_connector_vault/note.ex`
- MCP-Tools: `tools/*/src/*/server.py`, `apps/ratsprojekte/lib/ratsprojekte/mcp/server.ex`, `apps/ratsprojekte/lib/ratsprojekte/mcp/tools/show_projekt.ex`, `opencode.json`
- Tickets: #279 (Karte, Bau-Tickets je Quelle), #244, #205, #148, #160, #186, #198, #274, #275, #276, #277, #280, #288, #289, #291, #35, #36, #41, #54, #171, #292, #373, #375, #376, #377, #378; PR #379 (ADR 0003)
