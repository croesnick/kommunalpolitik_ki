# Workflows — Use Cases für die Ratsarbeit

> **Zweck:** Dieses Dokument dokumentiert die typischen Workflows eines
> Stadtrats / Gemeinderats und zeigt, wo das Tool-Setup unterstützt und wo
> Lücken bestehen. Es ist die fachliche Referenz für Feature-Entwicklung und
> Priorisierung.
>
> **Prinzip:** Problem-first, nicht tool-first. Die Workflows entstehen aus
> konkreten politischen Bedarfen, nicht aus Technik-Faszination.
>
> **Lücken-Tracking:** Offene Lücken sind als GitHub-Issues erfasst und in
> diesem Dokument mit `#<nummer>` referenziert. Behobene Lücken werden aus
> dem Dokument entfernt — die Issue-Historie in GitHub bleibt erhalten. Dieses
> Dokument ist keine Todo-Liste.

## Begriffe

Siehe [`docs/nomenklatur.md`](./nomenklatur.md) für die Definition aller
Fachbegriffe (Sitzungsmappe, Ratsprojekt, Realisierungsstrang, Vault, etc.).

---

## WF 1: Sitzungsvorbereitung

**Situation:** Nächste Woche Stadtratssitzung. Der Stadtrat will wissen, was
drankommt, Vorlagen lesen, Positionen vorbereiten.

**Ziel:** Eine **Sitzungsmappe** im Vault — für jede Sitzung eine Notiz, die
Agenda, Vorlagen, Querverweise zu Ratsprojekten, AZ-Artikel und Vault-Notizen
bündelt. Die Sitzungsmappe ist ein Vault-Tool, nicht Teil von ratsprojekte.

| Schritt | Tool / Skill | Status |
|---|---|---|
| Agenda abrufen (Sitzungen + TOPs) | `ratsinfo sessions --remote` + `ratsinfo show <id>` | ✅ |
| Vorlagen-PDFs lesen | `pdf_ingest ingest(path)` | ✅ |
| Querverweis: hängt ein TOP an einem Ratsprojekt? | `ratsinfo search` + `ratsprojekte search_projekte` | ❌ Kein automatischer Link RIS-Sitzung ↔ Ratsprojekt (#32) |
| AZ-Artikel zum Thema finden | `allgaeuer_zeitung_mcp search_articles` | ✅ |
| Vault-Notizen zum Thema | `vault_suche` | ✅ |
| Sitzungsmappe im Vault erstellen | `obsidian-cli` (externer Skill) | ✅ |

### Lücken

- **Kein RIS↔Ratsprojekt-Link** — TOPs und Projekte sind isoliert. → #32

### Datenfluss & Trust Boundaries

Die Pipeline führt externe Strings (AZ-Artikel-Titel, RIS-TOP-Titel,
PDF-Dateinamen) durch mehrere Stufen und serialisiert sie am Ende als
YAML-Frontmatter. Das Frontmatter ist die einzige strukturierte
Schnittstelle zum Vault — und genau da können Zeichen aus externen Quellen
das Format brechen.

```
RIS-API (HTML)  → ratsinfo (SQLite) → CLI-Output (Text)
AZ-MCP (JSON)   → Artikel-Titel (Strings)
Vault-Suche     → obsidian CLI (Text)
                         ↓
           AI komponiert → Markdown + YAML-Frontmatter
                         ↓
                  obsidian write → Vault-Datei
                         ↓
              ⚠ Validierung (Single-Quote-Regel)
```

**Bug-Klasse:** Deutsche typografische Anführungszeichen („...") in
double-quoted YAML-Strings werden als String-Ende interpretiert →
ungültiges YAML → Properties in Obsidian nicht sichtbar.

**Mitigation:** Single-Quote-Regel als Pflicht in Skills mit strukturiertem
Vault-Write. Post-Write-Validierung via `pyyaml`. Siehe #53.

> **Abgrenzung:** Anträge und Änderungsanträge formulieren ist *nicht* Teil
> der Sitzungsvorbereitung. Das ist ein nachgelagerter Schritt, der auf der
> Sitzungsmappe aufbaut.

---

## WF 2: Neues Projekt aus Idee entwickeln

**Situation:** Bürgerbeschwerde, Zeitungsartikel oder politische Initiative →
der Stadtrat denkt "das könnte ein Ratsprojekt werden".

**Ziel:** Eine konsolidierte Vault-Notiz und ein Proposal in ratsprojekte.

| Schritt | Tool / Skill | Status |
|---|---|---|
| Vault durchsuchen (bestehendes Material) | `vault_suche` | ✅ |
| Förderrecherche | `foerdermittel_recherche` | ✅ |
| Lokalberichterstattung | `allgaeuer_zeitung_mcp` | ✅ |
| RIS-Recherche | `ratsinfo search` | ✅ |
| Web-Recherche | `web_search` / `web_fetch` | ✅ |
| Konsolidierte Notiz in Vault schreiben | `obsidian-cli` (externer Skill) | ✅ |
| Gates prüfen (Antragsreife) | `ratsprojekt_proposal` Skill | ✅ |
| Proposal einbringen | `propose_projekt` MCP | ✅ |
| GO erteilen | `decide_proposal` MCP | ✅ |

> **Hinweis:** Der `ratsprojekt_proposal`-Skill schreibt vor: "Pflicht:
> konsolidierte Notiz zurück in den Vault". Der `obsidian-cli`-Skill ist als
> Voraussetzung in [`docs/prerequisites.md`](./prerequisites.md)
> dokumentiert.

---

## WF 3: Neue Info zu bestehendem Projekt

**Situation:** Email vom Bauamt, AZ-Artikel, neue Förderrichtlinie → "was
ändert das für Projekt X?"

**Ziel:** Ein strukturiertes Delta, das zeigt, welche Vorbedingungen, Quellen
und Realisierungsstränge sich ändern würden.

| Schritt | Tool / Skill | Status |
|---|---|---|
| Neue Info aufnehmen (Email, Artikel, PDF) | Copy-Paste / `allgaeuer_zeitung_mcp` / `pdf_ingest` | ⚠️ Keine Email-Ingestion (#35) |
| Projekt-Stand abrufen | `ratsprojekt_stand` / `show_projekt` MCP | ✅ |
| Delta produzieren | `ratsprojekt_delta` Skill | ✅ |
| AZ-Artikel lesen | `allgaeuer_zeitung_mcp` | ✅ |
| PDF verarbeiten | `pdf_ingest` | ✅ |
| RIS-Sitzung nachschlagen | `ratsinfo search` | ✅ |
| Vault-Divergenz prüfen | `vault_suche` | ✅ |

### Lücken

- **Email-Ingestion:** Aktuell muss jeder Email-Inhalt manuell in den Chat
  kopiert werden. Ein read-only Email-MCP wäre eine starke Ergänzung.
  Herausforderung: Konfiguration (IMAP-Zugang, mehrere Konten, Privatsphäre).
  Möglicher Ansatz: ein Skill, der bei Bedarf die Email-Konfiguration in die
  lokale `opencode.json` schreibt — aber nur mit explizitem GO. → #35

---

## WF 4: Beschlussnachverfolgung

**Situation:** Vor 3 Monaten wurde ein Antrag beschlossen. Wurde er umgesetzt?
Gibt es Verzug?

**Ziel:** Frist-Tracking und automatische Benachrichtigung bei neuen
RIS-Entwicklungen, die Ratsprojekte betreffen.

| Schritt | Tool / Skill | Status |
|---|---|---|
| Beschluss in RIS finden | `ratsinfo search` | ✅ |
| Projekt-Status checken | `ratsprojekte show_projekt` | ✅ |
| Beschluss mit Projekt verlinken | — | ❌ Kein Feld in ratsprojekte für RIS-Sitzung/TOP/Beschluss-ID (#32) |
| Frist-Tracking (Beschlussfrist abgelaufen?) | — | ❌ Keine Fristen-Tabelle, keine Alerts (#34) |
| RIS-Sync → "was ist neu zu meinen Projekten?" | — | ❌ Kein Diff bei Sync (#33) |

### Lücken

- **RIS↔Ratsprojekt-Link:** Ein Ratsprojekt kann nicht auf eine konkrete
  Sitzung/TOP/Beschlussnummer verweisen. Man kann nicht fragen "welcher
  Beschluss gehört zu Projekt X?" → #32
- **Frist-Tracking:** Beschlüsse haben oft Fristen ("umsetzen bis Q4"). Kein
  Tool erinnert daran. Relevant für die politische Nachbereitung. → #34
- **RIS-Sync mit ratsprojekte-Cross-Check:** Der RIS-Sync läuft unabhängig
  von ratsprojekte. Aber ratsprojekte sollte einen Sync-Trigger haben, der
  nach einem RIS-Sync prüft: "gibt es seit dem letzten Sync neue
  Sitzungen/TOPs, die für eines meiner Projekte relevant sind?" — basierend
  auf Schlagwörtern, Projekt-Titeln oder verlinkten RIS-IDs. → #33

> **Architektur:** RIS-Sync und ratsprojekte-Sync sind getrennte Operationen.
> RIS-Sync lädt rohe Sitzungsdaten. Der ratsprojekte-Sync ist ein
> nachgelagerter Schritt, der die frischen RIS-Daten gegen die
> Projekt-Datenbank hält und Treffer meldet.

---

## WF 5: Fraktionsvorbereitung

**Situation:** Vor der Fraktionssitzung: Projektübersicht, was steht an,
Prioritäten setzen.

> **Status:** Für eine kleine Fraktion in einer kleinen Kommune manuell
> machbar. Nicht priorisiert. Falls die Fraktion wächst oder der Aufwand
> steigt, kann hier ein Skill nachgelegt werden.

---

## WF 6: Fördermittel-Recherche

**Situation:** "Können wir Förderung für X beantragen?"

**Ziel:** Ein quellenbelegter Fördermittel-Report, der als Anhang an der
Vault-Notiz des jeweiligen Ratsprojekts gespeichert wird.

| Schritt | Tool / Skill | Status |
|---|---|---|
| 5-Strang-Recherche (Finanzierung, Programme, Stand, Best-Practices, Recht) | `foerdermittel_recherche` Skill | ✅ |
| Quellen mit URLs + Abrufdatum | Skill fordert es | ✅ |
| Fristen extrahieren | Skill macht TODO-Liste | ⚠️ Nur Markdown-TODOs, kein Tracking-Tool (#34) |
| Report an Vault-Notiz des Projekts anhängen | `obsidian-cli` (extern) | ❌ Nicht integriert (#36) |
| Kumulierungsrechnung | Manuell im Report | ⚠️ |

### Lücken

- **Förderrecherche-Persistenz:** Jedes Ratsprojekt hat eine eigene Notiz im
  Vault. Fördermittel-Recherchen werden als Anhang/Unterseite dieser Notiz
  gespeichert. Die Integration des `obsidian-cli` in den
  `foerdermittel_recherche`-Skill fehlt noch. → #36
- **Fristen sind tote Markdown-Checkboxen** — kein Tool tracked sie. Wenn eine
  Förderfrist in 6 Wochen abläuft, erinnert niemand. Mögliche Integration mit
  Todoist (globaler `todoist-triage`-Skill vorhanden). → #34

---

## WF 7: PDF-Vorlagen / Drucksachen verarbeiten

**Situation:** Neue Drucksache im RIS, der Stadtrat will sie schnell erfassen.

| Schritt | Tool / Skill | Status |
|---|---|---|
| PDF herunterladen | `ratsinfo show <id>` zeigt Dokumente, `ratsinfo open <id>` lädt herunter | ✅ |
| PDF ingesten (Text + Annotationen) | `pdf_ingest ingest(path)` | ✅ |
| Mit RIS-Sitzung verlinken | — | ❌ Keine Pipeline (siehe WF 4, #32) |
| Highlights/Annotationen extrahieren | `pdf_ingest extract_annotations` | ✅ |

### Lücken

- **Keine ratsinfo→pdf_ingest Pipeline:** ratsinfo sync lädt Metadaten,
  pdf_ingest verarbeitet PDFs, aber es gibt keinen automatischen Flow
  "sync → neue PDFs → ingest". Pragmatisch lösbar durch Skill-Orchestrierung;
  ein dediziertes Tool ist nicht zwingend nötig.

---

## WF 8: Bürgeranliegen

**Situation:** Bürger meldet Problem (Gefahrenstelle, Beleuchtung, etc.).

**Ziel:** Das Anliegen wird im Vault erfasst und mit Fraktionssitzungen /
Vorstandssitzungen verlinkt, damit es dort besprochen wird.

> **Abgrenzung:** Bürgeranliegen sind **nicht** Teil von ratsprojekte. Sie
> leben im Vault und werden mit Fraktions- und Vorstandssitzungen verlinkt.
> Falls ein Bürgeranliegen zu einem politischen Projekt reift, kann es über
> den `ratsprojekt_proposal`-Workflow zum Ratsprojekt werden.

| Schritt | Tool / Skill | Status |
|---|---|---|
| Recherche (RIS, AZ, Vault) | Einzelne Tools | ✅ |
| Anliegen im Vault erfassen | `obsidian-cli` (extern) | ❌ Nicht integriert (#38) |
| Mit Fraktionssitzung / Vorstandssitzung verlinken | Vault (Wikilinks) | ⚠️ Manuell (#38) |
| Anliegen → Ratsprojekt eskalieren | `ratsprojekt_proposal` Skill | ✅ (über Umweg) |
| Antwort formulieren (Brief/Email) | — | ❌ Kein Draft-Tool |

### Lücken

- **Bürgeranliegen-Tracking im Vault:** Eigene Notizen pro Anliegen, getaggt
  z.B. mit `#buergeranliegen/{datum-schlagwort}`. Verlinkt mit der nächsten
  Fraktionssitzung / Vorstandssitzung, wo es besprochen wird. → #38
- **Kein Brief-/Email-Draft-Tool.**

---

## WF 9: Kollaborationsplattform-Anbindung (Nextcloud)

**Situation:** Die Fraktion nutzt eine Nextcloud-Instanz als
Kollaborationsplattform (z.B. `wolke.netzbegruenung.de`). Dort liegen
geteilte Dokumente, Planungen und Tabellen (z.B. ein ODS-Sheet mit einem
Kondensat der Ratsprojekte).

**Ziel:** Die AI kann Dokumente und Tabellen aus der Nextcloud lesen
(read-only primär), um sie in Workflows einzubinden — z.B. das
Projekt-Kondensat gegen ratsprojekte halten, geteilte Planungen in die
Sitzungsvorbereitung einbeziehen.

| Schritt | Tool / Skill | Status |
|---|---|---|
| ODS/Excel-Sheet aus Nextcloud lesen | `nextcloud` (WebDAV) + `nextcloud_ods_mcp` (Parser) | ✅ |
| Geteilte Dokumente lesen | `nextcloud` (`nc_webdav_read_file`) | ✅ |
| Dateien hochladen (z.B. Sitzungsmappe) | `nextcloud` (`nc_webdav_write_file`) | ✅ |
| Nextcloud-Kondensat gegen ratsprojekte halten | ad-hoc / `ratsprojekt_delta` | ⚠️ Keine Pipeline (#54) |
| Kalender-Termine abrufen | `nextcloud` (`nc_calendar_list_events`) | ✅ |

### Lücken

- **Nextcloud-Kondensat gegen ratsprojekte:** Noch keine Pipeline. Workflow
  wäre: ODS herunterladen via `nextcloud`, parsen via `nextcloud_ods_mcp`,
  gegen `ratsprojekte`-Stand halten via `ratsprojekt_delta`. Bausteine da,
  Pipeline fehlt. → #54

> **Parteiübergreifend:** Andere Parteien und Fraktionen nutzen ähnliche
> Kollaborationsplattformen. Der Workflow ist nicht parteispezifisch —
> die Nextcloud-Anbindung ist generisch.

---

## WF 10: Öffentlichkeitsarbeit (Sitzungsankündigungen und -nachberichte)

**Situation:** Vor Sitzungen kündigt die Fraktion die relevanten TOPs an,
nach Sitzungen gibt es einen Nachbericht. Diese Ankündigungen und Nachberichte
werden in einem Kommunikationskanal geteilt (z.B. WhatsApp-Community,
Social Media, Website).

**Ziel:** Ein Tool/Workflow, der anhand von Templates aus der
Sitzungsvorbereitung (WF 1) eine Vorberichts-Nachricht generiert, und
nach der Sitzung (basierend auf Beschlüssen) einen Nachbericht.

| Schritt | Tool / Skill | Status |
|---|---|---|
| Vorbericht generieren (aus TOPs + Positionen) | Template + `sitzungsvorbereitung` (WF 1) | ❌ Kein Template-Tool (#41) |
| Nachbericht generieren (aus Beschlüssen) | Template + `ratsinfo show` / RIS-Daten | ❌ Kein Template-Tool (#41) |
| Nachricht in Kanal posten | WhatsApp / Social Media API | ❌ Keine Integration |
| Nachricht im Vault archivieren | Vault-Write | ❌ |

### Lücken

- **Kein Template-Tool für Öffentlichkeitsarbeit.** Die AI kann
  Sitzungsdaten lesen, aber es gibt keinen Skill, der daraus eine
  kanal-gerechte Nachricht (kurz, sachlich, verständlich) generiert. → #41
- **Keine Kanal-Integration:** WhatsApp hat keine offizielle API für
  Communities. Alternativen: Signal, Threema, E-Mail-Verteiler, Website.
  Die AI generiert die Nachricht, das Posten bleibt beim Stadtrat (GO).
- **Template-Variablen:** TOP-Liste, Datum, Positionen, Beschlüsse,
  Fraktionsname — alles soll aus vorhandenen Daten automatisch gefüllt
  werden.

> **Abstraktion:** Von konkreter Plattform (WhatsApp, spezifische Partei) abstrahiert:
> der Workflow ist "Sitzungsankündigung / -nachbericht generieren".
> Der Kanal ist austauschbar.

---

## WF 11: Bericht aus dem Stadtrat

**Situation:** Ein Termin steht an, bei dem als TOP "Bericht aus dem
Stadtrat" vorgesehen ist (Stammtisch, Fraktionssitzung, Vorstand,
Bürgerinfo, Podium). Der Stadtrat braucht einen kompakten Rückblick auf
alle Sitzungen und Themen seit dem letzten Bericht — verdichtet für ein
Laien-Publikum, nicht TOP-für-TOP, sondern nach thematischen Schwerpunkten.

**Ziel:** Eine **Berichtsnotiz** im Vault, die alle Sitzungen
seit dem letzten Bericht thematisch bündelt, Beschlüsse erwähnt,
optionale AZ-Artikel beilegt und Diskussionsthemen für den Termin
vorschlägt. Direkt als Vortragsgrundlage nutzbar.

| Schritt | Tool / Skill | Status |
|---|---|---|
| Letzten Bericht ermitteln (Vault-Suche nach Tag/Typ/Titel) | `obsidian-cli` search / tags | ✅ (Fallback: nutzende Person fragen) |
| RIS-Sync (lokalen Cache aktualisieren) | `ratsinfo sync` | ✅ |
| Sitzungen im Zeitraum filtern (Datum >= letzter Bericht, <= heute) | `ratsinfo sessions` | ✅ (manuelle Filterung nach Datum) |
| TOPs pro Sitzung abrufen | `ratsinfo show <id>` | ✅ |
| Vault-Notizen zu TOPs sammeln | `obsidian search` / `vault_suche` | ✅ (Fallback: nachfragen falls keine Treffer) |
| AZ-Artikel (optional, nur Top-Themen) | `allgaeuer_zeitung_mcp` | ✅ |
| Bericht im Vault persistieren | `obsidian-cli` write | ✅ |
| YAML-Frontmatter validieren | pyyaml-Check | ✅ (analog sitzungsvorbereitung) |

### Lücken

- **Bericht-Termine/Stichtage nicht persistent im Vault.** Es gibt keine
  Kalender-Notiz oder Termin-Liste der vergangenen Berichte. Jeder
  Bericht muss den letzten Bericht neu suchen (Tag `#bericht-aus-dem-stadtrat`,
  Frontmatter `type: bericht-aus-dem-stadtrat`) oder bei der nutzenden Person
  erfragen. Zukünftig: eigener Bericht-Kalender im Vault (Tabelle) oder
  Anbindung an Nextcloud-Kalender (WF 9, `nc_calendar_list_events`).
- **Kein automatischer Filter nach Zeitraum in `ratsinfo sessions`.** Die
  CLI listet alle lokal gespeicherten Sitzungen. Die Filterung nach
  "seit letztem Bericht" passiert manuell durch die AI anhand der
  Datums-Ausgabe.
- **Keine automatische Themen-Clusterung.** Die TOPs kommen chronologisch
  aus dem RIS. Die thematische Bündelung (Klima, Mobilität, Bauen, etc.)
  muss von der AI ad-hoc anhand der TOP-Titel passieren — kein Tool
  unterstützt hierbei strukturell.

> **Abgrenzung:** Der Bericht ist *rückblickend* und *verdichtet*. Die
> vorwärtsgerichtete **Sitzungsvorbereitung** für eine konkrete kommende
> Sitzung ist WF 1. **Anträge / Positionen / Fraktionsmappe** sind WF 10.
> **Detail-Beschlussnachverfolgung** (Fristen, Umsetzungsstand) ist WF 4 —
> hier werden nur Beschlüsse erwähnt, nicht nachverfolgt.

**Skill:** `bericht_aus_dem_stadtrat` — orchestriert RIS-Sync, Vault-Suche,
optional AZ und schreibt eine strukturierte Berichtsnotiz.

---

## Lückenübersicht

Alle offenen Lücken sind als GitHub-Issues erfasst. Diese Sektion listet sie
thematisch mit Issue-Nummer und primär betroffenem Workflow. Detaillierte
Beschreibungen stehen in den jeweiligen Issues unter
https://github.com/croesnick/kommunalpolitik_ki/issues.

### Datenmodell / Integration

| Issue | Lücke | Workflow |
|---|---|---|
| #32 | RIS↔Ratsprojekt-Link: Feld für `ris_sitzung_id` / `ris_top` / `beschluss_nr` | WF 1, 4, 7 |
| #34 | Fristen-Tracking: Beschluss- und Förderfristen (Tabelle oder Todoist-Integration) | WF 4, 6 |
| #37 | `value_proposition` + `success_metrics` als DB-Felder in ratsprojekte | alle |
| #22 | `propose_projekt_update`: `beschlussvorschlag` + `adressat` fehlen | ratsprojekte |

### Externe Tools / MCP-Anbindungen

| Issue | Lücke | Workflow |
|---|---|---|
| #35 | Email-MCP (read-only): IMAP-Zugang, Body-Extraktion | WF 3 |

### Skills / Workflow-Orchestrierung

| Issue | Lücke | Workflow |
|---|---|---|
| #33 | RIS-Sync Cross-Check: "was ist neu zu meinen Projekten?" | WF 4 |
| #36 | Förderrecherche-Persistenz: Reports an Vault-Notiz anhängen | WF 6 |
| #38 | Bürgeranliegen-Tracking: Notiz-Template + Tag-Konvention | WF 8 |
| #41 | Öffentlichkeitsarbeit: Vorbericht/Nachbericht aus Sitzungsdaten generieren | WF 10 |
| #53 | YAML-Frontmatter-Validierung nach Vault-Write | WF 1, 2, 6, 8 |
| #54 | Nextcloud-Kondensat-Pipeline: ODS gegen ratsprojekte halten | WF 9 |
