# Workflows — Use Cases für die Ratsarbeit

> **Zweck:** Dieses Dokument dokumentiert die typischen Workflows eines
> Stadtrats / Gemeinderats und zeigt, wo das Tool-Setup unterstützt, wo
> Lücken bestehen und was geplant ist. Es ist die fachliche Referenz für
> Feature-Entwicklung und Priorisierung.
>
> **Prinzip:** Problem-first, nicht tool-first. Die Workflows entstehen aus
> konkreten politischen Bedarfen, nicht aus Technik-Faszination.

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
| Vorlagen-PDFs lesen | `pdf_ingest ingest(path)` | ✅ Registriert in opencode.json |
| Querverweis: hängt ein TOP an einem Ratsprojekt? | `ratsinfo search` + `ratsprojekte search_projekte` | ❌ Kein automatischer Link RIS-Sitzung ↔ Ratsprojekt |
| AZ-Artikel zum Thema finden | `allgaeuer_zeitung_mcp search_articles` | ✅ |
| Vault-Notizen zum Thema | `vault_suche` | ✅ |
| Sitzungsmappe im Vault erstellen | Vault-Write (externer Skill `obsidian-cli`) | ⚠️ Vault-Write via obsidian-cli möglich, Skill folgt |

### Lücken

- **~~pdf_ingest nicht als MCP registriert~~** — ✅ Behoben. pdf_ingest ist
  jetzt in `opencode.json` eingetragen.
- **Sitzungsvorbereitung-Skill fehlt noch** — Pipeline manuell getestet und
  funktioniert (sync → show → AZ → vault_suche → obsidian create). Skill unter
  `skills/sitzungsvorbereitung/` folgt.
- **Kein RIS↔Ratsprojekt-Link** — TOPs und Projekte sind isoliert.
- **Sitzungsmappe als Vault-Tool**: Für jede Sitzung soll eine Notiz im Vault
  entstehen, die alle Vorbereitungsergebnisse bündelt. Dafür brauchen wir
  Vault-Write-Fähigkeit (externer Skill `obsidian-cli` als Voraussetzung).

**Test 15.07.2026:** Pipeline manuell durchgespielt für 3. Stadtratssitzung
(21.07.2026). Sync: 2 neue Sitzungen gezogen (66→68). TOPs +
Beschlussvorschläge via `ratsinfo show`. AZ-Artikel zur Gansbichlstraße
gefunden und eingebunden. Vault-Suche lieferte Treffer zu Bahnhofstraße und
KinderKram. Sitzungsmappe in Vault geschrieben via `obsidian eval` (Ordner +
Datei erstellt). Bekannte Lücken: `ratsinfo sessions --remote` Bug,
`ratsinfo open` Stub, RIS-Volltextsuche findet "Gansbichl" nicht.

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
              ⚠ Validierung? (bisher: keine)
```

**Bug-Klasse:** Deutsche typografische Anführungszeichen („...") in
double-quoted YAML-Strings werden als String-Ende interpretiert →
ungültiges YAML → Properties in Obsidian nicht sichtbar.

**Gefunden am 15.07.2026:** AZ-Titel `„Völlig konsterniert" – Anwohner...`
brach das Frontmatter der Sitzungsmappe. Gefixt durch Single-Quotes als
YAML-Wrapper. Validierung in Skill `sitzungsvorbereitung` dokumentiert.

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
| Konsolidierte Notiz in Vault schreiben | `obsidian-cli` (externer Skill) | ❌ Nicht in Workflow integriert |
| Gates prüfen (Antragsreife) | `ratsprojekt_proposal` Skill | ✅ |
| Proposal einbringen | `propose_projekt` MCP | ✅ |
| GO erteilen | `decide_proposal` MCP | ✅ |

### Lücken

- **Vault-Write-Gap:** Der `ratsprojekt_proposal`-Skill schreibt vor:
  "Pflicht: konsolidierte Notiz zurück in den Vault". Aber kein Projekt-Tool
  kann in den Vault schreiben. Der externe Skill `obsidian-cli` existiert
  global, ist aber nicht als Voraussetzung im Workflow verankert.
- **Externe Skill-Abhängigkeit:** Wie referenzieren wir `obsidian-cli` als
  Voraussetzung, ohne ihn ins Repo zu clonen? Siehe
  [`docs/prerequisites.md`](./prerequisites.md) (geplant).

---

## WF 3: Neue Info zu bestehendem Projekt

**Situation:** Email vom Bauamt, AZ-Artikel, neue Förderrichtlinie → "was
ändert das für Projekt X?"

**Ziel:** Ein strukturiertes Delta, das zeigt, welche Vorbedingungen, Quellen
und Realisierungsstränge sich ändern würden.

| Schritt | Tool / Skill | Status |
|---|---|---|
| Neue Info aufnehmen (Email, Artikel, PDF) | Copy-Paste / `allgaeuer_zeitung_mcp` / `pdf_ingest` | ⚠️ Keine Email-Ingestion |
| Projekt-Stand abrufen | `ratsprojekt_stand` / `show_projekt` MCP | ✅ |
| Delta produzieren | `ratsprojekt_delta` Skill | ✅ |
| AZ-Artikel lesen | `allgaeuer_zeitung_mcp` | ✅ |
| PDF verarbeiten | `pdf_ingest` | ⚠️ Nicht als MCP registriert |
| RIS-Sitzung nachschlagen | `ratsinfo search` | ✅ |
| Vault-Divergenz prüfen | `vault_suche` | ✅ |

### Lücken

- **Email-Ingestion:** Aktuell muss jeder Email-Inhalt manuell in den Chat
  kopiert werden. Ein read-only Email-MCP wäre eine starke Ergänzung.
  Herausforderung: Konfiguration (IMAP-Zugang, mehrere Konten, Privatsphäre).
  Möglicher Ansatz: ein Skill, der bei Bedarf die Email-Konfiguration in die
  lokale `opencode.json` schreibt — aber nur mit explizitem GO.
- **pdf_ingest** (wieder): nicht als MCP registriert.

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
| Beschluss mit Projekt verlinken | — | ❌ Kein Feld in ratsprojekte für RIS-Sitzung/TOP/Beschluss-ID |
| Frist-Tracking (Beschlussfrist abgelaufen?) | — | ❌ Keine Fristen-Tabelle, keine Alerts |
| RIS-Sync → "was ist neu zu meinen Projekten?" | — | ❌ Kein Diff bei Sync |

### Lücken

- **RIS↔Ratsprojekt-Link:** Ein Ratsprojekt kann nicht auf eine konkrete
  Sitzung/TOP/Beschlussnummer verweisen. Man kann nicht fragen "welcher
  Beschluss gehört zu Projekt X?"
- **Frist-Tracking:** Beschlüsse haben oft Fristen ("umsetzen bis Q4"). Kein
  Tool erinnert daran. Relevant für die politische Nachbereitung.
- **RIS-Sync mit ratsprojekte-Cross-Check:** Der RIS-Sync läuft unabhängig
  von ratsprojekte (wie bisher). Aber ratsprojekte sollte einen Sync-Trigger
  haben, der nach einem RIS-Sync prüft: "gibt es seit dem letzten Sync neue
  Sitzungen/TOPs, die für eines meiner Projekte relevant sind?" — basierend
  auf Schlagwörtern, Projekt-Titeln oder verlinkten RIS-IDs.

> **Architektur:** RIS-Sync und ratsprojekte-Sync sind getrennte Operationen.
> RIS-Sync lädt rohe Sitzungsdaten. Der ratsprojekte-Sync ist ein
> nachgelagerter Schritt, der die frischen RIS-Daten gegen die
  Projekt-Datenbank hält und Treffer meldet.

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
| Fristen extrahieren | Skill macht TODO-Liste | ⚠️ Nur Markdown-TODOs, kein Tracking-Tool |
| Report an Vault-Notiz des Projekts anhängen | `obsidian-cli` (extern) | ❌ Nicht integriert |
| Kumulierungsrechnung | Manuell im Report | ⚠️ |

### Lücken

- **Jedes Ratsprojekt hat eine eigene Notiz im Vault.** Fördermittel-Recherchen
  werden als Anhang/Unterseite dieser Notiz gespeichert. Dafür braucht es
  Vault-Write (wie bei WF 2).
- **Fristen sind tote Markdown-Checkboxen** — kein Tool tracked sie. Wenn eine
  Förderfrist in 6 Wochen abläuft, erinnert niemand. Mögliche Integration mit
  Todoist (globaler `todoist-triage`-Skill vorhanden).
- **Forschungsberichte sind nicht persistent:** Jede Recherche startet von
  null. Kein Speichern/Verlinken mit Ratsprojekt als Quelle.

---

## WF 7: PDF-Vorlagen / Drucksachen verarbeiten

**Situation:** Neue Drucksache im RIS, der Stadtrat will sie schnell erfassen.

| Schritt | Tool / Skill | Status |
|---|---|---|
| PDF herunterladen | `ratsinfo show <id>` zeigt Dokumente | ⚠️ `ratsinfo open <id>` ist Stub |
| PDF ingesten (Text + Annotationen) | `pdf_ingest ingest(path)` | ⚠️ Nicht als MCP registriert |
| Mit RIS-Sitzung verlinken | — | ❌ Keine Pipeline |
| Highlights/Annotationen extrahieren | `pdf_ingest extract_annotations` | ⚠️ Nicht registriert |

### Lücken

- **pdf_ingest ist der größte akute Blocker:** Code ist da, funktioniert, aber
  die AI kann ihn nicht nutzen, weil er nicht in `opencode.json` steht.
- **`ratsinfo open` ist Stub** — kann keine PDFs direkt
  öffnen/herunterladen.
- **Keine ratsinfo→pdf_ingest Pipeline:** ratsinfo sync lädt Metadaten,
  pdf_ingest verarbeitet PDFs, aber es gibt keinen automatischen Flow
  "sync → neue PDFs → ingest".

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
| Anliegen im Vault erfassen | `obsidian-cli` (extern) | ❌ Nicht integriert |
| Mit Fraktionssitzung / Vorstandssitzung verlinken | Vault (Wikilinks) | ⚠️ Manuell |
| Anliegen → Ratsprojekt eskalieren | `ratsprojekt_proposal` Skill | ✅ (über Umweg) |
| Antwort formulieren (Brief/Email) | — | ❌ Kein Draft-Tool |

### Lücken

- **Bürgeranliegen-Tracking im Vault:** Eigene Notizen pro Anliegen, getaggt
  z.B. mit `#buergeranliegen/{datum-schlagwort}`. Verlinkt mit der nächsten
  Fraktionssitzung / Vorstandssitzung, wo es besprochen wird.
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
| ODS/Excel-Sheet aus Nextcloud lesen | `nextcloud_mcp` (geplant) | ❌ Kein MCP |
| Geteilte Dokumente lesen | `nextcloud_mcp` | ❌ |
| Dateien hochladen (z.B. Sitzungsmappe) | `nextcloud_mcp` (write) | ❌ |
| Nextcloud-Kondensat gegen ratsprojekte halten | ad-hoc / `ratsprojekt_delta` | ❌ Keine Pipeline |
| Kalender-Termine abrufen | `nextcloud_mcp` (CalDAV) | ❌ |

### Lücken

- **Nextcloud-MCP fehlt komplett.** Entweder gibt es einen fertigen
  Open-Source-Nextcloud-MCP (zu prüfen), oder er muss gebaut werden.
  Use cases: Dateien lesen/schreiben (WebDAV), ODS/Excel parsen,
  Kalender (CalDAV), ggf. Nextcloud Talk.
- **Konfiguration:** Wie bei der Email-MCP — Nextcloud-URL und
  Zugangsdaten sind privat. Konfiguration in `config.local.yml` oder
  lokale `opencode.json`, nicht im Repo. Skill-basierte Einrichtung mit
  GO als Option.
- **ODS-Parsing:** ODS-Dateien aus Nextcloud lesen und als strukturierte
  Daten verarbeiten (für das Projekt-Kondensat). Python: `pandas` oder
  `pyexcel-ods3`.

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
| Vorbericht generieren (aus TOPs + Positionen) | Template + `sitzungsvorbereitung` (WF 1) | ❌ Kein Template-Tool |
| Nachbericht generieren (aus Beschlüssen) | Template + `ratsinfo show` / RIS-Daten | ❌ Kein Template-Tool |
| Nachricht in Kanal posten | WhatsApp / Social Media API | ❌ Keine Integration |
| Nachricht im Vault archivieren | Vault-Write | ❌ |

### Lücken

- **Kein Template-Tool für Öffentlichkeitsarbeit.** Die AI kann
  Sitzungsdaten lesen, aber es gibt keinen Skill, der daraus eine
  kanal-gerechte Nachricht (kurz, sachlich, verständlich) generiert.
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

## Lückenübersicht nach Priorität

### 🔴 Akute Blocker (Quick Wins)

| # | Lücke | Fix | Workflow |
|---|---|---|---|
| ~~1~~ | ~~pdf_ingest nicht als MCP registriert~~ (erledigt) | ✅ In `opencode.json` eingetragen | WF 1, 3, 7 |
| 2 | `ratsinfo open` ist Stub | Implementieren: PDF-Download + Öffnen | WF 7 |
| 3 | Vault-Write-Gap | `obsidian-cli` erfolgreich getestet (Ordner + Datei via `obsidian eval`), Vault-Write funktioniert — Integration in Skill folgt | WF 1, 2, 6, 8 |

### 🟡 Workflow-Skills fehlen

| # | Skill / Feature | Beschreibung | Workflow |
|---|---|---|---|
| 4 | sitzungsvorbereitung | in Arbeit — Pipeline getestet, Skill folgt | WF 1 |
| 5 | beschluss_tracking | RIS-Beschluss-ID in ratsprojekt + Fristen-Tracking | WF 4 |
| 6 | ris_sync_cross_check | RIS-Sync → "was ist neu zu meinen Projekten?" | WF 4 |

### 🟢 Datenmodell / Integration

| # | Lücke | Beschreibung | Workflow |
|---|---|---|---|
| 7 | RIS↔Ratsprojekt-Link | Feld in ratsprojekte für `ris_sitzung_id` / `ris_top` / `beschluss_nr` | WF 1, 4, 7 |
| 8 | Fristen-Tracking | Eigene Tabelle oder Todoist-Integration | WF 4, 6 |
| 9 | Email-MCP (read-only) | IMAP-Zugang, Body-Extraktion, ggf. Skill-basierte Konfiguration | WF 3 |
| 10 | Förderrecherche-Persistenz | Reports als Vault-Notiz am Ratsprojekt speichern | WF 6 |
| 11 | value_proposition + success_metrics als DB-Felder | Roadmap #9, noch policy-level | alle |
| 12 | Bürgeranliegen im Vault | Notiz-Template + Tag-Konvention + Link zu Fraktionssitzungen | WF 8 |
| 13 | Nextcloud-MCP | WebDAV/CalDAV-Anbindung, ODS-Parsing, Datei-Read/Write | WF 9 |
| 14 | Öffentlichkeitsarbeit-Template-Tool | Vorbericht/Nachbericht aus Sitzungsdaten generieren | WF 10 |
| 15 | YAML-Frontmatter-Validierung nach Vault-Write | Single-Quote-Regel + Post-Write-Validierung in allen Skills mit strukturiertem Vault-Write (aktuell nur `sitzungsvorbereitung`, potenziell `ratsprojekt_proposal` bei Vault-Konsolidierung) | WF 1, 2, 6 |
