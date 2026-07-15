---
name: sitzungsvorbereitung
description: >
  Eine Sitzungsmappe für eine konkrete Stadtratssitzung im Obsidian-Vault
  erstellen: Agenda (TOPs) aus dem RIS abrufen, Vorlagen-PDFs ingesten,
  Querverweise zu Ratsprojekten prüfen, passende AZ-Artikel und
  Vault-Notizen einsammeln, alles zu einer strukturierten Notiz bündeln.
  Nutze diesen Skill immer, wenn der Stadtrat vor einer Sitzung steht und
  wissen will "was drankommt, was muss ich lesen, was ist der Kontext".
  Typische Trigger: "Bereite die nächste Sitzung vor", "Ich brauche die
  Sitzungsmappe für ...", "Was steht in der nächsten Stadtratssitzung an?",
  "Mach mir eine Übersicht zur Sitzung am ...", "Was sind die TOPs der
  kommenden Sitzung und wo gibt es Querbezüge?".
  Der Skill endet mit der Sitzungsmappe im Vault. Anträge, Positionen oder
  Änderungsanträge sind NIC Teil der Sitzungsmappe — das ist WF 10.
---

# Sitzungsvorbereitung Skill

## Wann dieser Skill greift

Wenn der Stadtrat vor einer Stadtratssitzung steht und eine strukturierte
Vorbereitung braucht: Was steht auf der Agenda? Welche Vorlagen muss ich
lesen? Welcher TOP hängt an einem Ratsprojekt? Was hat die AZ dazu
geschrieben? Was habe ich selbst schon im Vault notiert?

Das Ergebnis ist eine **Sitzungsmappe** — eine Vault-Notiz pro Sitzung, die
alle Vorbereitungsergebnisse bündelt. Die Mappe ist ein Vorschlag, kein
Entscheid — der Stadtrat entscheidet, was er daraus macht.

> **Definition:** Siehe [`docs/nomenklatur.md`](../../docs/nomenklatur.md) —
> "Sitzungsmappe". **Workflow:** WF 1 in
> [`docs/workflows.md`](../../docs/workflows.md).

## Abgrenzung

**Nicht Teil der Sitzungsmappe (und damit nicht Teil dieses Skills):**

- Änderungsanträge, Anträge oder Fraktionspositionen formulieren → WF 10
  (Öffentlichkeitsarbeit) bzw. nachgelagerter Schritt.
- Beschlussnachverfolgung für zurückliegende Sitzungen → eigener Workflow
  (WF 4).
- Fraktionsmappe / Fraktionsvorbereitung → nicht priorisiert (WF 5).

Die Sitzungsmappe ist ein **Lese- und Kontextinstrument**, kein
Entscheidungsdokument.

## Konfiguration: Vault-Zugriff

Der Skill schreibt die Sitzungsmappe in den Obsidian-Vault. Wie bei
`vault_suche` kommt der Vault-Name aus einer lokalen, **nicht-getrackten**
Datei:

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
> aus `config.local.yml` (z.B. "All The Notes") oder — falls nicht gesetzt —
> aus der expliziten Antwort der nutzenden Person.

## Arbeitsweise

### 1. Konfiguration lesen

- `config.local.yml` im Repo-Root lesen
- `obsidian.vault` übernehmen; falls nicht gesetzt: nachfragen
- Vault-Namen für die Session merken

### 2. RIS-Sync (neue Sitzungen lokal speichern)

Bevor TOPs abgerufen werden, den lokalen RIS-Cache aktualisieren:

```bash
./apps/ratsinfo/ratsinfo sync
```

Damit werden neue Sitzungen, TOPs und Texte aus dem RIS lokal gespeichert.

> **Lücke:** `ratsinfo sessions --remote` wirft aktuell einen
> `FunctionClauseError` (Bug). Daher Sync via `ratsinfo sync` laufen lassen
> und anschließend die lokalen Sitzungen durchsuchen — nicht `--remote`.

### 3. Sitzung finden

Zwei Wege, je nachdem, was der Stadtrat genannt hat:

**a) Datum bekannt** (z.B. "Sitzung am 24.07.2025"):

```bash
./apps/ratsinfo/ratsinfo sessions   # lokale Sitzungen auflisten
```

Die neueste Sitzung mit dem passenden Datum auswählen.

**b) Kein Datum / "nächste Sitzung":**

```bash
./apps/ratsinfo/ratsinfo sessions
```

Die nächste anstehende (oder letzte synchronisierte) Sitzung identifizieren
und kurz bestätigen: "Ich bereite die Sitzung [Datum, Gremium] vor — richtig?".

Sitzungs-ID (`<sitzungs_id>`) für die folgenden Schritte merken.

### 4. TOPs abrufen

```bash
./apps/ratsinfo/ratsinfo show <sitzungs_id>
```

Liefert die TOPs mit Titel, Verfahren/Gegenstand, Status
(beschließend/beratend), Beschlussvorschlägen und referenzierten
Dokumenten (Drucksachen / PDFs).

> **Lücke:** Die RIS-Volltextsuche findet nicht immer alle TOPs (z.B.
> "Gansbichl" nicht gefunden trotz lokalem Cache). Daher immer `ratsinfo
> show <id>` für die konkrete Sitzung verwenden, nicht nur die Suche.

### 5. AZ-Artikel suchen

Für jeden **öffentlichen** TOP die Schlüsselbegriffe extrahieren
(Ortsbezug, Sachthema, beteiligte Akteure) und via `allgaeuer_zeitung_mcp`
suchen:

```
search_articles(query: "Bahnhofstraße Buchloe")
```

Für vielversprechende Treffer den Artikel lesen:

```
get_article(id: <article_id>)
```

Nicht jeder TOP braucht einen AZ-Artikel. Der Skill sucht gezielt bei
Themen mit öffentlichem Bezug (Bauprojekte, Haushalt, Personal,
Verkehr) und lässt kosmetische TOPs (z.B. Protokollnachträge) links liegen.
Overfetching vermeiden — max. 2–3 Artikel pro TOP, nur die relevanten
lesen.

### 6. Vault durchsuchen

Für jedes TOP-Thema den Vault nach Querverweisen durchsuchen (analog
`vault_suche`-Skill, aber ad-hoc ausgeführt):

```bash
obsidian vault="<vault-name>" search query="Bahnhofstraße" limit=10
obsidian vault="<vault-name>" search query="Verkehrskonzept" limit=10
```

Relevante Treffer lesen:

```bash
obsidian vault="<vault-name>" read file="Notiz Titel"
```

Treffer-Deduplizierung: dieselbe Notiz kann bei mehreren Suchen auftauchen
— einmal zusammenführen. Max. 5–7 Notizen pro TOP lesen, Overfetching
vermeiden.

### 7. Cross-Ref Ratsprojekte

Prüfen, ob ein TOP zu einem existierenden Ratsprojekt passt — über die
ratsprojekte-MCP-Tools (read-only):

```
list_projekte()                         # Überblick alle Projekte
search_projekte(query: "Bahnhof")       # gezielt nach Begriff
show_projekt(slug: "bahnhofstrasse")    # Vollstand des passenden Projekts
```

> **Lücke:** Es gibt keinen automatischen RIS↔Ratsprojekt-Link. Die
> Zuordnung erfolgt ad-hoc anhand von Titel/Begriffen. Sobald ein Bezug
> erkannt ist, in der Sitzungsmappe als Querverweis (mit Vault-Tag
> `#ratsprojekt/<slug>`) dokumentieren.

### 8. PDFs ingesten (wenn Vorlagen verfügbar)

Wenn `ratsinfo show` PDF-Vorlagen referenziert, diese via `pdf_ingest`
verarbeiten (PDF-Ingestion ist als MCP registriert):

```
pdf_ingest ingest(path: "/pfad/zur/vorlage.pdf")
```

> **Lücke:** `ratsinfo open` ist aktuell ein Stub und kann keine PDFs
> automatisch herunterladen oder öffnen. PDFs müssen ggf. manuell aus dem
> RIS (bzw. dem von `ratsinfo show` angezeigten Link) heruntergeladen und
> der lokale Pfad an `pdf_ingest` übergeben werden. Ist keine PDF
> verfügbar, diesen Schritt überspringen und in der Mappe als "keine
> Vorlage gefunden" kennzeichnen.

### 9. Sitzungsmappe in den Vault schreiben

Die Mappe wird über die `obsidian`-CLI direkt in den Vault geschrieben.
Ziel-Pfad:

```
1 - Projects/Stadtrat Buchloe/Sitzungsmappen/<YYYY-MM-DD> <Sitzungsname>.md
```

Beispiel: `1 - Projects/Stadtrat Buchloe/Sitzungsmappen/2025-07-24 Stadtratssitzung.md`.

**Ordner sicherstellen** (falls noch nicht vorhanden):

```bash
obsidian vault="<vault-name>" eval code="require('fs').mkdirSync('1 - Projects/Stadtrat Buchloe/Sitzungsmappen', { recursive: true })"
```

**Datei schreiben** — zwei Varianten:

Variante A (Empfehlung, wenn der Inhalt sauber übergeben werden kann):

```bash
obsidian vault="<vault-name>" create path="1 - Projects/Stadtrat Buchloe/Sitzungsmappen/2025-07-24 Stadtratssitzung.md" content="..."
```

Dabei Newlines im Content als `\n` kodieren.

Variante B (für mehrzeilige Inhalte robuster):

```bash
obsidian vault="<vault-name>" eval code="app.vault.create('1 - Projects/Stadtrat Buchloe/Sitzungsmappen/2025-07-24 Stadtratssitzung.md', `<inhalt-mit-backticks>`)"
```

Vor dem Schreiben prüfen, ob die Datei bereits existiert — ggf. überschreiben
(nur nach Bestätigung, siehe GO-Prinzip) oder mit Suffix `_v2` anlegen.

### YAML-Frontmatter: Quoting-Regel

Das Frontmatter enthält externe Strings (AZ-Artikel-Titel, RIS-Titel,
Vault-Notiz-Titel). Diese sind **unkontrolliert** — sie können Zeichen
enthalten, die YAML bricht. Im deutschen Sprachraum sind typografische
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

### Validierung nach dem Vault-Write

Nach jedem Schreiben der Sitzungsmappe **muss** das Frontmatter
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
1. Mappe in eine Temp-Datei schreiben
2. YAML validieren (obiger Check)
3. Bei OK: Temp-Datei in den Vault übernehmen (`obsidian eval` + `adapter.write`)
4. Bei Fehler: Quoting fixen, wieder von vorne

 Dieser Check eliminiert eine ganze Bug-Klasse. Wenn andere Skills
ebenfalls strukturiertes Frontmatter in den Vault schreiben (z.B.
`ratsprojekt_proposal` bei Vault-Konsolidierung), gilt dort dieselbe Regel
und Validierung.

## Sitzungsmappe-Struktur

Die Mappe ist **Obsidian Flavored Markdown** mit YAML-Frontmatter. Pro TOP
ein Abschnitt; am Ende Querverweise, offene Fragen und nächste Schritte.

```markdown
---
type: sitzungsmappe
sitzung_id: <RIS-ID>
sitzung_datum: 2025-07-24
gremium: Stadtrat
ort: Buchloe
ris_url: https://ris.komuna.net/vgbuchloe/Meeting.mvc/...
quellen:
  - typ: sitzung
    titel: 'RIS-Sitzung <id> vom 2025-07-24'
    abrufdatum: 2025-07-15
  - typ: presse
    titel: '<artikel-titel>'  # Single-Quotes! Siehe Quoting-Regel
    url: <url>
    abrufdatum: 2025-07-15
  - typ: vault
    titel: '<notiz-titel>'
    pfad: '<vault-pfad>'
---

# Sitzungsmappe: Stadtratssitzung 2025-07-24

**Gremium:** Stadtrat Buchloe
**Datum:** 2025-07-24, 19:00 Uhr
**RIS:** [Sitzung](<ris_url>)
**Erstellt:** 2025-07-15 (Vorschlag, GO für Inhalte beim Stadtrat)

## TOP 1: <Titel>

- **Verfahren / Gegenstand:** <z.B. Beschluss über Bauvorhaben X>
- **Status:** beschließend | beratend
- **Beschlussvorschlag:** <Wortlaut oder Zusammenfassung aus RIS>
- **Dokumente:** <Drucksachen-Nummer / PDF-Verweis, falls vorhanden>

### Kontext

**RIS:** <1–2 Sätze, was die Vorlage will — aus `ratsinfo show` oder PDF>

**AZ-Berichterstattung:**
- "<Artikel-Titel>" — AZ, <Datum>
  - URL: <url>
  - Abrufdatum: 2025-07-15
  - Kern: <1–2 Sätze, was der Artikel dazu sagt>

**Vault-Notizen:**
- [[<notiz-titel>]] (persönliche Notiz, erstellt <datum>)
  - Kern: <1–2 Sätze>
- [[<weitere-notiz>]] (persönliche Notiz)

**Ratsprojekt-Bezug:**
- Möglicher Bezug zu [[#ratsprojekt/<slug>]] (ad-hoc, nicht bestätigt)
  - Projektstand siehe `ratsprojekt_stand` — ggf. nachreichen

### Fragen für die Fraktion

- [ ] <Frage 1>
- [ ] <Frage 2>
- [ ] <Was vor der Sitzung klären?>

## TOP 2: …

(wie oben)

…

## Querverweise

### Ratsprojekte (möglicher Bezug)
- `#ratsprojekt/<slug>` — <kurz warum Bezug>
- (kein Bezug erkannt)

### AZ-Artikel
- "<titel>" (<url>, abgerufen 2025-07-15)
- "<titel>" (<url>, abgerufen 2025-07-15)

### Vault-Notizen
- [[<notiz-titel>]] (persönliche Notiz)
- [[<notiz-titel>]] (persönliche Notiz)

### RIS-Sitzung
- Sitzung <id> vom 2025-07-24 — [Link](<ris_url>)

## Offene Fragen / Vorbereitung

- [ ] PDF für TOP X lesen (Vorlage <drucksachen-nr>)
- [ ] Position zu TOP Y klären (Fraktion / Vorstand)
- [ ] Bürgermeister-Anfrage zu TOP Z vorbereiten
- [ ] …

## Nächste Schritte

- [ ] Fraktionssitzung: TOPs mit Bezug durchgehen
- [ ] Bei TOP X: `ratsprojekt_delta` aufrufen, falls neue Infos den Stand
      eines Ratsprojekts ändern
- [ ] Bei Finanzierungs-TOP: `foerdermittel_recherche` anhängen
- [ ] Nach der Sitzung: Beschlüsse nachtragen (WF 4)
```

## GO-Prinzip: AI sammelt und strukturiert, Mensch entscheidet

Die Sitzungsmappe ist ein **Vorschlag**. Die AI sammelt (TOPs, AZ, Vault,
PDFs), strukturiert und schlägt Fragen vor. Der Stadtrat entscheidet, was
er daraus macht.

**Schreiben der Mappe im Vault:** Die Mappe ist eine
Vorbereitungsunterlage, kein entscheidender Eingriff in ratsprojekte oder
den RIS-Bestand. Daher ist **kein GO nötig fürs Schreiben der
Vorbereitungsmappe** — die AI darf sie direkt im Vault erstellen.

**Aber — GO erforderlich für:**

- Überschreiben einer bereits existierenden Sitzungsmappe (vorher fragen)
- Änderungsanträge / Positionen (sind nicht Teil der Mappe, siehe Abgrenzung)
- Jede schreibende Aktion in ratsprojekte (`propose_*`, `decide_proposal`)
- Jegliche Weitergabe der Mappe außerhalb des privaten Vaults

## Quellenpflicht

Jede politisch relevante Aussage in der Mappe braucht eine Quelle. Der
Skill kennzeichnet die Quellentypen konsistent (siehe
[`docs/nomenklatur.md`](../../docs/nomenklatur.md) "Quelle"):

- **RIS-Quelle:** `sitzung_id` + `sitzung_datum` + RIS-URL. Im Frontmatter
  unter `quellen` und im jeweiligen TOP unter "RIS".
- **AZ-Artikel:** URL + Abrufdatum. Im TOP unter "AZ-Berichterstattung"
  und am Ende unter "AZ-Artikel". Jeder Artikel bekommt das Abrufdatum
  einzeln — nicht pauschal für die ganze Mappe.
- **Vault-Notiz:** Titel + Pfad, gekennzeichnet als
  "persönliche Notiz" (keine amtliche Quelle). Vault-Notizen allein sind
  selten ausreichend als Quelle für politische Aussagen — sie sind
  Hinweise, Erinnerungen, Vorab-Info. Der Skill markiert explizit, wenn
  eine Notiz eine Behauptung ohne Beleg enthält und weist auf die
  generelle Quellenpflicht hin (siehe `AGENTS.md` §6).
- **PDF-Vorlage:** Drucksachen-Nummer / Dateiname + RIS-Bezug. Falls
  ingestet, Hinweis auf `pdf_ingest`-Ergebnis.
- **Ohne bestätigte Quelle:** als "nicht belegt" kennzeichnen, nicht
  verschweigen.

## Komposition mit anderen Skills

Die Sitzungsvorbereitung ist ein orchestrierender Skill — er ruft die
Einzelwerkzeuge und ggf. Folgeskills auf. Komposition findet **nur auf
ausdrücklichen Wunsch** oder bei offensichtlichem Bedarf statt, nicht
automatisch ohne GO.

| Folgeschritt | Skill / Tool | Wann |
|---|---|---|
| Vault-Suche zu einem TOP-Thema | `vault_suche` (oder ad-hoc, wie oben) | Wenn ein TOPthematisch passt und der Skill noch nicht durchgelaufen ist |
| Förderrecherche zu einem Finanzierungs-TOP | `foerdermittel_recherche` | Wenn ein TOP Förderung / Haushalt / Finanzierung betrifft |
| Projektstand zu einem TOP mit Ratsprojekt-Bezug | `ratsprojekt_stand` | Wenn ein TOP ein bekanntes Ratsprojekt betrifft |
| Delta gegen einen Projektstand | `ratsprojekt_delta` | Wenn neue Infos aus dem TOP den Stand eines Ratsprojekts ändern könnten |
| Lebenszyklus-Referenz | [`docs/ratsprojekte-lifecycle.md`](../../docs/ratsprojekte-lifecycle.md) | Bei Status-Übergängen / Gates |
| PDFs verarbeiten | `pdf_ingest` MCP | Bei verfügbaren Vorlagen-PDFs (siehe Schritt 8) |
| AZ-Artikel | `allgaeuer_zeitung_mcp` | Bei jedem TOP mit öffentlichem Bezug (siehe Schritt 5) |
| RIS-Sitzung | `ratsinfo` CLI | Agenda, TOPs, Dokumente (Schritte 2–4) |

Der Skill endet immer mit der fertigen Sitzungsmappe im Vault und
Vorschlägen aus dieser Tabelle — der GO für Folgeschritte liegt bei der
nutzenden Person.

## Known Lücken

| # | Lücke | Auswirkung | Workaround |
|---|---|---|---|
| 1 | `ratsinfo sessions --remote` wirft `FunctionClauseError` (Bug) | Remote-Sitzungsliste nicht abrufbar | `ratsinfo sync` laufen lassen, dann `ratsinfo sessions` lokal |
| 2 | `ratsinfo open` ist Stub | Kein automatischer PDF-Download aus ratsinfo | PDFs ggf. manuell aus dem RIS herunterladen, Pfad an `pdf_ingest` übergeben |
| 3 | Kein automatischer RIS↔Ratsprojekt-Link | TOPs und Projekte sind isoliert | Ad-hoc-Zuordnung über Titel/Begriffe; in der Mappe als Querverweis dokumentieren |
| 4 | RIS-Volltextsuche findet nicht immer alle TOPs (z.B. "Gansbichl" nicht gefunden trotz lokalem Cache) | Cross-Ref kann TOPs verfehlen | Statt Suche immer `ratsinfo show <sitzungs_id>` für die konkrete Sitzung verwenden |
| 5 | YAML-Frontmatter kann durch externe Strings (deutsche Anführungszeichen in AZ-Titeln) brechen | Properties in Obsidian nicht sichtbar / kaputt | Single-Quotes für alle YAML-Strings mit externem Text; YAML nach Vault-Write re-validieren (siehe "Validierung nach dem Vault-Write") |

Siehe auch [`docs/workflows.md`](../../docs/workflows.md) WF 1 "Lücken"
für die strategische Einordnung.
