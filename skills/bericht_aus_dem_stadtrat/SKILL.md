---
name: bericht_aus_dem_stadtrat
description: >
  Einen "Bericht aus dem Stadtrat" für einen anstehenden Termin erstellen:
  alle Sitzungen und Vault-Notizen seit dem letzten Bericht (oder einem
  genannten Stichtag) sammeln, aus dem RIS die Top-Themen und Beschlüsse der
  vergangenen Wochen verdichten, optional AZ-Artikel beilegen, alles zu
  einer strukturierten Vault-Notiz bündeln, die direkt als TOP "Bericht aus
  dem Stadtrat" vorgetragen werden kann — sei es für einen Stammtisch, eine
  Fraktionssitzung, den Vorstand, eine Bürgerinfo oder eine Podiumsdiskussion.
  Nutze diesen Skill immer, wenn ein kompakter Rückblick auf die Ratsarbeit
  der letzten Wochen gebraucht wird. Typische Trigger: "Bericht aus dem
  Stadtrat", "Ich brauche einen Bericht für den Stammtisch / die
  Fraktionssitzung / den Vorstand", "Was ist seit dem letzten Bericht
  passiert?", "Fasse die letzten Ausschüsse zusammen", "Was gab es seit X
  im Stadtrat?". Der Skill endet mit der Berichtsnotiz im Vault. Keine
  Anträge, keine Positionen, keine Öffentlichkeitsarbeit — Anträge macht der
  Skill `antrag_generieren`, Öffentlichkeitsarbeit ist WF 10.
---

# Bericht aus dem Stadtrat Skill

## Wann dieser Skill greift

Wenn ein Termin ansteht, bei dem als TOP "Bericht aus dem Stadtrat"
vorgesehen ist — z.B. ein Stammtisch, eine Fraktionssitzung, eine
Vorstandssitzung, eine Bürgerinfo oder eine Podiumsdiskussion. Der Skill
blickt **rückblickend** auf die Ratsarbeit seit dem letzten Bericht (oder
einem genannten Stichtag): Welche Sitzungen gab es? Welche Themen standen
an? Was wurde beschlossen? Was ist für den Termin diskussionswürdig?

Das Ergebnis ist ein **Bericht aus dem Stadtrat** — eine Vault-Notiz, die
alle Sitzungen seit dem letzten Bericht thematisch verdichtet. Der Bericht
richtet sich an ein Laien-Publikum (Gäste des Termins, keine Ratsprofis)
und ist auf Verdichtung, nicht auf Vollständigkeit optimiert: wenige
Schwerpunkte statt TOP-für-TOP-Auflistung, kurze Sätze statt
Verfahrensdetails.

> **Definition:** Siehe [`docs/nomenklatur.md`](../../docs/nomenklatur.md)
> — "Sitzungsmappe", "Ratsprojekt", "Vault". **Workflow:** WF 11 in
> [`docs/workflows.md`](../../docs/workflows.md).

## Abgrenzung

**Nicht Teil des Berichts aus dem Stadtrat (und damit nicht Teil dieses Skills):**

- **Vorwärtsgerichtete Sitzungsvorbereitung** für eine konkrete kommende
  Sitzung → WF 1 (`sitzungsvorbereitung`). Der Bericht ist *rückblickend*,
  nicht *vorbereitend*.
- **Anträge und politische Forderungen** → Skill `antrag_generieren`. Der
  Bericht referenziert Beschlüsse, formuliert aber keine eigenen
  politischen Forderungen.
- **Öffentlichkeitsarbeit** (kanalgerechte Fassung des Berichts) → WF 10.
- **Detail-Beschlussnachverfolgung** (Fristen, Umsetzungsstand) → WF 4.
  Hier wird nur erwähnt, *was* beschlossen wurde, nicht *ob* es umgesetzt
  wurde.
- **Fraktionsvorbereitung / Priorisierung** → WF 5.

Der Bericht ist ein **Verdichtungs- und Kontextinstrument** für ein
allgemeines Publikum, kein Entscheidungsdokument.

## Konfiguration: Vault-Zugriff

Der Skill schreibt den Bericht in den Obsidian-Vault. Wie bei
`sitzungsvorbereitung` kommt der Vault-Name aus einer lokalen,
**nicht-getrackten** Datei:

```
config.local.yml   # im Repo-Root, nicht in Git
```

Format:

```yaml
obsidian:
  vault: "MeinVaultName"   # Name wie in Obsidian angezeigt
```

Fehlt die Datei oder der `vault`-Eintrag, fragt der Skill die nutzende
Person direkt nach dem Vault-Namen und speichert ihn *nicht* automatisch
(GO-Prinzip: die AI schreibt keine Config, der Mensch entscheidet, was
konfiguriert wird). Der Skill merkt sich den Vault-Namen für die restliche
Session.

> **WICHTIG:** Der Vault-Name ist **niemals hartkodiert**. Er kommt immer
> aus `config.local.yml` oder — falls nicht gesetzt — aus der expliziten
> Antwort der nutzenden Person.

## Arbeitsweise

### 1. Konfiguration lesen

- `config.local.yml` im Repo-Root lesen
- `obsidian.vault` übernehmen; falls nicht gesetzt: nachfragen
- Vault-Namen für die Session merken

### 2. Letzten Bericht ermitteln (oder Stichtag erfragen)

Der Berichtszeitraum beginnt am Tag nach dem letzten Bericht (oder einem
genannten Stichtag). Daher muss zuerst der letzte Bericht gefunden werden.

**Vault durchsuchen** nach Notizen, die auf einen Bericht hindeuten:

```bash
obsidian vault="<vault-name>" search query="bericht-aus-dem-stadtrat" limit=20
obsidian vault="<vault-name>" tags query="bericht-aus-dem-stadtrat"   # falls Tag-basiert
# Abwärtskompatibilität zu alten Stammtisch-Berichten:
obsidian vault="<vault-name>" search query="stammtisch" limit=20
obsidian vault="<vault-name>" tags query="stammtisch"
```

Treffer-Kriterien (mindestens eins erfüllt):
- Tag `#bericht-aus-dem-stadtrat` (neu) oder `#stammtisch` (Legacy)
- Frontmatter `type: bericht-aus-dem-stadtrat` (neu) bzw.
  `type: stammtisch-bericht` (Legacy)
- "bericht aus dem stadtrat" oder "stammtisch" im Titel
  (z.B. "Berichte/2026-07-01 Bericht aus dem Stadtrat")

Den Treffer mit dem **jüngsten Datum** als letzten Bericht nehmen.
Datum merken als `zeitraum_von` (Tag nach dem letzten Bericht) und
`letzter_bericht` (Datum des letzten Berichts).

**Falls kein Treffer:** nutzende Person fragen —
*"Wann war der letzte Bericht, oder ab welchem Stichtag soll erfasst
werden? (Datum)"*. Das ist explizit vom Nutzer so gewollt ("erfragen,
falls nicht gefunden"). Antwort als `zeitraum_von` und `letzter_bericht`
übernehmen.

**Falls die Frage nicht beantwortet wird:** Abbruch mit Hinweis
*"Kein Zeitraum ermittelbar — ohne Datum des letzten Berichts (oder einen
Stichtag) kann kein Bericht erstellt werden."*. Nicht raten, nicht auf
"alles" ausweichen.

### 3. RIS-Sync (lokalen Cache aktualisieren)

Bevor Sitzungen abgerufen werden, den lokalen RIS-Cache aktualisieren:

```bash
./apps/ratsinfo/ratsinfo sync
```

Damit werden neue Sitzungen, TOPs und Texte aus dem RIS lokal gespeichert.

> **Lücke:** `ratsinfo sessions --remote` wirft aktuell einen
> `FunctionClauseError` (Bug). Daher Sync via `ratsinfo sync` laufen lassen
> und anschließend die lokalen Sitzungen durchsuchen — nicht `--remote`.

### 4. Sitzungen im Zeitraum auflisten

```bash
./apps/ratsinfo/ratsinfo sessions
```

Listet alle lokal gespeicherten Sitzungen. Filtern nach Datum:

- `datum >= zeitraum_von` (Tag nach letztem Bericht/Stichtag)
- `datum <= heute`

Sitzungs-IDs (`<sitzungs_id>`) für die folgenden Schritte merken.

> **Lücke:** `ratsinfo sessions` kennt keinen Zeitraum-Filter. Die CLI
> listet alle Sitzungen, die Filterung nach Datum passiert manuell durch
> die AI. Bei vielen Sitzungen ggf. anhand der Ausgabe kennzeichnen, welche
> in den Zeitraum fallen.

### 5. TOPs pro Sitzung abrufen

Für jede Sitzung im Zeitraum die TOPs abrufen:

```bash
./apps/ratsinfo/ratsinfo show <sitzungs_id>
```

Sammeln pro Sitzung:
- Datum, Gremium (Stadtrat / Bauausschuss / etc.), Ort
- TOPs mit Titel und Verfahren/Gegenstand
- 🔒-Marker für nicht-öffentliche TOPs (restricted/nichtöffentlich)
- Beschlussvorschläge und Beschluss-Ergebnis (falls bereits entschieden)

> **Lücke:** Die RIS-Volltextsuche findet nicht immer alle TOPs. Daher
> immer `ratsinfo show <sitzungs_id>` für jede konkrete Sitzung verwenden,
> nicht nur die Suche.

### 6. Vault-Querverweise sammeln

Für jede Sitzung (anhand der Schlagwörter aus den TOPs) den Vault
durchsuchen, um persönliche Notizen, Vorab-Infos oder Querbezüge zu
finden:

```bash
obsidian vault="<vault-name>" search query="<schlagwort>" limit=10
```

Relevante Treffer lesen:

```bash
obsidian vault="<vault-name>" read file="<notiz-titel>"
```

Treffer-Deduplizierung: dieselbe Notiz kann bei mehreren Suchen auftauchen
— einmal zusammenführen. Max. 5–7 Notizen pro Sitzung lesen, Overfetching
vermeiden.

**Falls für eine Sitzung gar keine Vault-Notizen gefunden werden:** einmalig
bei der nutzenden Person nachfragen —
*"Für die Sitzung <Gremium> am <Datum> wurden keine Vault-Notizen gefunden
— gibt es welche, die ich einbinden soll?"*. Das ist explizit vom Nutzer
so gewollt ("ggf. einmal nachfragen"). Antwort einarbeiten; bei
Non-Antwort ohne Nachfrage weitermachen, in der Notiz als "keine
Vault-Notizen vorhanden" kennzeichnen.

### 7. AZ-Artikel (optional, nur bei Zeit / Öffentlichkeitsbezug)

Nicht für jede Sitzung — nur für 2–3 Top-Themen mit klarer
Öffentlichkeitsscheibe (Bauprojekte, Haushalt, Personal, Verkehr) via
`allgaeuer_zeitung_mcp` suchen:

```
search_articles(query: "Bahnhofstraße Buchloe")
```

Für vielversprechende Treffer den Artikel lesen:

```
get_article(id: <article_id>)
```

Overfetching vermeiden — max. 2–3 Artikel insgesamt, nur die relevanten
lesen. AZ-Artikel sind Belege, nicht Hauptinhalt.

### 8. Zusammenfassung in den Vault schreiben

Die Berichtsnotiz wird über die `obsidian`-CLI direkt in den Vault
geschrieben. Ziel-Pfad:

```
1 - Projects/Stadtrat Buchloe/Berichte/<YYYY-MM-DD> Bericht aus dem Stadtrat.md
```

Beispiel: `1 - Projects/Stadtrat Buchloe/Berichte/2026-07-16 Bericht aus dem Stadtrat.md`.

`<YYYY-MM-DD>` = Datum des anstehenden Termins.

**Ordner sicherstellen** (falls noch nicht vorhanden):

```bash
obsidian vault="<vault-name>" eval code="require('fs').mkdirSync('1 - Projects/Stadtrat Buchloe/Berichte', { recursive: true })"
```

**Datei schreiben** — zwei Varianten:

Variante A (Empfehlung, wenn der Inhalt sauber übergeben werden kann):

```bash
obsidian vault="<vault-name>" create path="1 - Projects/Stadtrat Buchloe/Berichte/2026-07-16 Bericht aus dem Stadtrat.md" content="..."
```

Dabei Newlines im Content als `\n` kodieren.

Variante B (für mehrzeilige Inhalte robuster):

```bash
obsidian vault="<vault-name>" eval code="app.vault.create('1 - Projects/Stadtrat Buchloe/Berichte/2026-07-16 Bericht aus dem Stadtrat.md', `<inhalt-mit-backticks>`)"
```

Vor dem Schreiben prüfen, ob die Datei bereits existiert — ggf. überschreiben
(nur nach Bestätigung, siehe GO-Prinzip) oder mit Suffix `_v2` anlegen.

### YAML-Frontmatter: Quoting-Regel

Das Frontmatter enthält externe Strings (AZ-Artikel-Titel, RIS-Titel,
Vault-Notiz-Titel). Diese sind **unkontrolliert** — sie können Zeichen
enthalten, die YAML brechen. Im deutschen Sprachraum sind typografische
Anführungszeichen („...", »...«) der häufigste Fall: ein schließendes
deutsches Anführungszeichen `"` innerhalb eines double-quoted YAML-Strings
wird als String-Ende interpretiert → danach folgt unparserbarer Text → das
gesamte Frontmatter ist kaputt. Obsidian zeigt dann keine Properties mehr
an oder dropped sie still.

**Regel:** Alle YAML-String-Werte mit externem Text **immer in
Single-Quotes** (`'...'`) setzen, nie in Double-Quotes. Innerhalb von
Single-Quotes sind Double-Quotes, deutsche Anführungszeichen und
Sonderzeichen sicher. Der einzige Escape-Fall: ein `'` im Wert wird
durch Verdopplung `''` escaped.

```yaml
# FALSCH — bricht bei deutschen Anführungszeichen im Titel:
titel: "„Völlig konsterniert" – Anwohner zwischen Verzweiflung"

# RICHTIG — Single-Quotes als Wrapper:
titel: '„Völlig konsterniert" – Anwohner zwischen Verzweiflung'

# RICHTIG — einfache Werte ohne Sonderzeichen brauchen keine Quotes:
gremium: Stadtrat
ort: Buchloe
```

Ausnahme: Wenn ein Wert ein `'` (Apostroph) enthält, entweder mit
Double-Quotes wrappen (wenn der Wert sonst keine `"` hat) oder das `'`
verdoppeln: `'It''s a test'`.

### 9. Validierung nach dem Vault-Write

Nach jedem Schreiben der Berichtsnotiz **muss** das Frontmatter
re-validiert werden. Falls das YAML kaputt ist: nicht still weitermachen,
sondern Fehler melden und fixen.

```bash
# Validierung via Python (pyyaml):
uv run --with pyyaml python3 -c "
import yaml, sys
with open('<pfad zur temp-datei>') as f:
    content = f.read()
parts = content.split('---', 2)
if len(parts) < 3:
    print('FEHLER: Kein Frontmatter gefunden'); sys.exit(1)
try:
    data = yaml.safe_load(parts[1])
    if data is None:
        print('FEHLER: Frontmatter ist leer'); sys.exit(1)
    print('OK: ' + str(len(data)) + ' Keys geparst')
except yaml.YAMLError as e:
    print('FEHLER: YAML kaputt: ' + str(e)); sys.exit(1)
"
```

Praxis-Workflow:
1. Bericht in eine Temp-Datei schreiben
2. YAML validieren (obiger Check)
3. Bei OK: Temp-Datei in den Vault übernehmen (`obsidian eval` + `adapter.write`)
4. Bei Fehler: Quoting fixen, wieder von vorne

Dieser Check eliminiert eine ganze Bug-Klasse (siehe "Lücke" in
`sitzungsvorbereitung` / WF 1).

## Bericht-Struktur

Die Notiz ist **Obsidian Flavored Markdown** mit YAML-Frontmatter. Die
TOPs werden nach thematischen Schwerpunkten gebündelt, nicht nach Sitzung.
Ziel: der Stadtrat kann den Bericht in 5–10 Minuten überfliegen und die
Diskussionsthemen für den Termin identifizieren.

```markdown
---
type: bericht-aus-dem-stadtrat
tags:
  - <fraktion>
  - Buchloe
  - stadtrat
  - bericht
created: <ISO-Datum>
bericht_zeitraum: <YYYY-MM-DD> bis <YYYY-MM-DD>
letzter_bericht: <YYYY-MM-DD>
anlass: <Stammtisch | Fraktionssitzung | Vorstand | Bürgerinfo | Podium>
termin_datum: <YYYY-MM-DD>
quellen:
  - typ: ris
    titel: 'RIS Stadt Buchloe, synchronisiert <datum>'
    url: https://ris.komuna.net/vgbuchloe/Meeting.mvc/Calendar
    abrufdatum: <datum>
  - typ: bericht
    titel: 'Letzter Bericht <datum>'
    pfad: '<vault-pfad>'
---

# Bericht aus dem Stadtrat: Stadtrat & Ausschüsse seit <datum>

**Bericht für:** <anlass>, <datum>
**Zeitraum:** <von> bis <bis>
**Quelle:** [RIS](<url>), synchronisiert <datum>

---

## Kontext

(kurzer Rahmen, z.B. "neue Wahlperiode hat begonnen" oder "Sommerpause"
— wenn nichts auffällt, Abschnitt weglassen)

## Sitzungen im Zeitraum

| Datum | Gremium | Ort |
|---|---|---|
| ... | ... | ... |

## Themen nach Schwerpunkt

(Die TOPs werden nach thematischen Schwerpunkten gebündelt, nicht nach
Sitzung. Typische Cluster: Klima & Energie, Mobilität, Bauen & Planung,
Soziales & Kultur, Wasser & Umwelt, Haushalt. 🔒 markiert nicht-öffentliche
TOPs.)

### <Schwerpunkt 1>

- **<Sitzung> am <datum>:** <TOP-Titel> — <1–2 Sätze Kontext, ggf.
  Beschluss erwähnen>
- ...

### <Schwerpunkt N>
...

## Ausblick

(kommende Sitzungen, die für den nächsten Termin relevant sein
könnten)

## Diskussionsthemen / Gesprächsanknüpfung

1. <Thema 1>
2. ...
```

## GO-Prinzip: AI sammelt, strukturiert, schreibt Vorschlag

Der Bericht ist ein **Vorschlag**. Die AI sammelt (Sitzungen, TOPs, AZ,
Vault-Notizen), strukturiert thematisch und schlägt Diskussionsthemen vor.
Der Stadtrat entscheidet, was er daraus macht.

**Schreiben der Berichtsnotiz im Vault:** Die Notiz ist eine
Vorbereitungsunterlage für den Termin, kein entscheidender Eingriff in
ratsprojekte oder den RIS-Bestand. Daher ist **kein GO nötig fürs
Schreiben der Berichtsnotiz** — die AI darf sie direkt im Vault erstellen
(analog `sitzungsvorbereitung`).

**Aber — GO erforderlich für:**

- Überschreiben einer bereits existierenden Berichtsnotiz (vorher fragen)
- Anträge, Positionen oder politische Forderungen (sind nicht Teil des
  Berichts, siehe Abgrenzung)
- Jede schreibende Aktion in ratsprojekte (`propose_*`, `decide_proposal`)
- Jegliche Weitergabe des Berichts außerhalb des privaten Vaults (z.B.
  Posten im WhatsApp-Kanal → WF 10)

## Quellenpflicht

Jede politisch relevante Aussage im Bericht braucht eine Quelle. Der
Skill kennzeichnet die Quellentypen konsistent (siehe §6 `AGENTS.md` und
[`docs/nomenklatur.md`](../../docs/nomenklatur.md) "Quelle"):

- **RIS-Quelle:** RIS-Sync-Datum im Frontmatter (`quellen`-Eintrag
  `typ: ris` mit URL + Abrufdatum). Im Text pro TOP: Sitzung + Datum
  als Referenz.
- **AZ-Artikel:** URL + Abrufdatum, im Schwerpunkt-Absatz erwähnt. Jeder
  Artikel bekommt das Abrufdatum einzeln — nicht pauschal für den
  gesamten Bericht.
- **Vault-Notiz:** als Wikilink `[[<notiz-titel>]]` im Text, gekennzeichnet
  als "persönliche Notiz" (keine amtliche Quelle). Vault-Notizen allein
  sind selten ausreichend als Quelle für politische Aussagen — sie sind
  Hinweise, Erinnerungen, Vorab-Info. Der Skill markiert explizit, wenn
  eine Notiz eine Behauptung ohne Beleg enthält und weist auf die
  generelle Quellenpflicht hin (siehe `AGENTS.md` §6).
- **🔒 nicht-öffentliche TOPs:** klar markiert, aber inhaltlich nur soweit
  wiedergegeben, wie es für den Termin relevant und datenschutzmäßig
  vertretbar ist (siehe §8 `AGENTS.md`). Im Zweifel nur erwähnen, nicht
  ausführen.
- **Ohne bestätigte Quelle:** als "nicht belegt" kennzeichnen, nicht
  verschweigen.

## Komposition mit anderen Skills

Der Bericht ist ein orchestrierender Skill — er ruft die
Einzelwerkzeuge und ggf. Folgeskills auf. Komposition findet **nur auf
ausdrücklichen Wunsch** oder bei offensichtlichem Bedarf statt, nicht
automatisch ohne GO.

| Folgeschritt | Skill / Tool | Wann |
|---|---|---|
| Sitzungen + TOPs abrufen | `ratsinfo` CLI (`sync`, `sessions`, `show <id>`) | Immer — Hauptdatenquelle (Schritte 3–5) |
| Vault-Suche zu TOP-Themen | `vault_suche` (oder ad-hoc, wie in Schritt 6) | Bei jedem Schwerpunkt mit potenziellem Vault-Bezug |
| Vault-Read/Write | `obsidian-cli` (externer Skill) | Letzter Bericht ermitteln (Schritt 2), Notizen lesen (Schritt 6), Bericht schreiben (Schritt 8) |
| AZ-Artikel | `allgaeuer_zeitung_mcp` | Optional, nur bei 2–3 Top-Themen mit Öffentlichkeitsbezug (Schritt 7) |
| Projektstand zu einem TOP mit Ratsprojekt-Bezug | `ratsprojekt_stand` | Wenn ein TOP ein bekanntes Ratsprojekt betrifft und der Bericht den Projektstand erwähnen soll |
| Lebenszyklus-Referenz | [`docs/ratsprojekte-lifecycle.md`](../../docs/ratsprojekte-lifecycle.md) | Bei Status-Übergängen / Gates, falls Projekte erwähnt werden |
| Öffentlichkeitsarbeit (Vorbericht/Nachbericht aus dem Bericht) | WF 10 Skill (folgt) | Nur auf GO — der Bericht ist intern, nicht für Kanäle |

Der Skill endet immer mit der fertigen Berichtsnotiz im Vault und ggf.
Vorschlägen aus dieser Tabelle — der GO für Folgeschritte liegt bei der
nutzenden Person.

## Known Lücken

| # | Lücke | Auswirkung | Workaround |
|---|---|---|---|
| 1 | `ratsinfo sessions --remote` wirft `FunctionClauseError` (Bug) | Remote-Sitzungsliste nicht abrufbar | `ratsinfo sync` laufen lassen, dann `ratsinfo sessions` lokal |
| 2 | Kein automatischer RIS↔Bericht-Link | Berichtszeitraum muss anhand von Datum/Tags im Vault gesucht oder erfragt werden | Vault-Suche nach `#bericht-aus-dem-stadtrat` / `type: bericht-aus-dem-stadtrat` (bzw. `#stammtisch` / `type: stammtisch-bericht` für Legacy); Fallback: nutzende Person fragen |
| 3 | Keine persistente Liste der Bericht-Termine/Stichtage im Vault | Termine müssen jedes Mal gesucht/erfragt werden | Zukünftig: eigener Bericht-Kalender im Vault (Notiz-Tabelle) oder in Nextcloud (WF 9, `nc_calendar_list_events`) |
| 4 | Kein automatischer Zeitraum-Filter in `ratsinfo sessions` | CLI listet alle Sitzungen, Filterung nach Datum manuell | AI filtert die Ausgabe von `ratsinfo sessions` gegen `zeitraum_von`/`heute` |
| 5 | Keine automatische Themen-Clusterung | TOPs werden chronologisch gelistet, thematische Bündelung muss ad-hoc passieren | AI clustert manuell nach Schwerpunkten (Klima, Mobilität, Bauen, etc.) |
| 6 | YAML-Frontmatter kann durch externe Strings (deutsche Anführungszeichen in AZ-Titeln) brechen | Properties in Obsidian nicht sichtbar / kaputt | Single-Quotes für alle YAML-Strings mit externem Text; YAML nach Vault-Write re-validieren (siehe "Validierung nach dem Vault-Write") |

Siehe auch [`docs/workflows.md`](../../docs/workflows.md) WF 11 "Lücken"
für die strategische Einordnung.
