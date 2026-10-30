---
name: sitzungsvorbereitung
description: >
  Eine Sitzungsmappe für eine konkrete Stadtratssitzung im Obsidian-Vault
  erstellen: TOPs aus dem RIS, Vorlagen-PDFs, Bezüge zu Ratsprojekten,
  AZ-Artikel und Vault-Notizen in einer quellenbelegten Notiz bündeln.
  Nutze diesen Skill, wenn der Stadtrat vor einer Sitzung wissen will, was
  drankommt, was zu lesen ist und welcher Kontext dazugehört. Trigger:
  "Bereite die nächste Sitzung vor", "Ich brauche die Sitzungsmappe für ...",
  "Was steht in der nächsten Stadtratssitzung an?", "Was sind die TOPs der
  kommenden Sitzung und wo gibt es Querbezüge?". Anträge, Positionen und
  Änderungsanträge sind NICHT Teil der Mappe — dafür gibt es
  `antrag_generieren`.
---

# Sitzungsvorbereitung

Ergebnis: eine **Sitzungsmappe** (siehe [`GLOSSARY.md`](../../GLOSSARY.md),
WF 1 in [`docs/workflows.md`](../../docs/workflows.md)) — eine Vault-Notiz pro
Sitzung. Sie ist ein Lese- und Kontextinstrument, kein
Entscheidungsdokument.

**Nicht Teil dieses Skills:** Anträge und Positionen (`antrag_generieren`),
Beschlussnachverfolgung (WF 4), Fraktionsmappe (WF 5).

## Ablauf

1. **Vault-Name** aus `config.local.yml` im Repo-Root (`obsidian.vault`).
   Fehlt er: nachfragen, für die Session merken, nicht in die Config
   schreiben. Nie hartkodieren.
2. **RIS aktualisieren:** `./apps/ratsinfo/ratsinfo sync`
   (nicht `sessions --remote` — wirft `FunctionClauseError`).
3. **Sitzung finden:** `./apps/ratsinfo/ratsinfo sessions`. Ohne genanntes
   Datum die nächste anstehende Sitzung wählen und bestätigen lassen:
   „Ich bereite die Sitzung [Datum, Gremium] vor — richtig?"
4. **TOPs abrufen:** `./apps/ratsinfo/ratsinfo show <sitzungs_id>` — immer
   so, nicht über die Volltextsuche (die verfehlt TOPs).
5. **Vorlagen-PDFs** mit `pdf_ingest ingest(path: ...)` lesen. `ratsinfo
   open` ist ein Stub: PDFs ggf. manuell über den RIS-Link holen. Keine PDF
   verfügbar → in der Mappe „keine Vorlage gefunden".
6. **AZ-Artikel** (`allgaeuer_zeitung_mcp`: `search_articles`,
   `get_article`) nur für TOPs mit öffentlichem Bezug (Bau, Haushalt,
   Personal, Verkehr); höchstens 2–3 Artikel pro TOP.
7. **Vault-Notizen:** `obsidian vault="<v>" search query="<Begriff>" limit=10`,
   dann `read file="<Titel>"`. Treffer deduplizieren, höchstens 5–7 Notizen
   pro TOP.
8. **Ratsprojekte** (MCP, read-only): `search_projekte(query:)`,
   `show_projekt(slug:)`. Es gibt keinen automatischen RIS-Link — Bezüge
   sind Vermutungen und werden als „möglicher Bezug" mit
   `#ratsprojekt/<slug>` markiert.
9. **Querschnittsanalyse** nur bei großen Sitzungen (siehe unten).
10. **Mappe schreiben** — erst nach GO (siehe unten).

## Inhalt jedes TOP-Abschnitts

Gemessen: Ohne ausdrückliche Anforderung lässt das lokale Modell
Finanzierungsdetails weg, mit Checkliste liefert es sie. Deshalb gilt für
jeden inhaltlichen TOP:

- **Vorhaben** mit Namen, nicht „das Vorhaben".
- **Anliegen:** was die Vorlage will, mit den konkreten Maßnahmen.
- **Kosten und Finanzierung**, wenn der TOP Geld berührt: Gesamtkosten,
  Eigenanteil der Stadt, Förder- oder Restanteil — der Eigenanteil
  belastet den städtischen Haushalt.
- **Beschlussvorschlag** im Wortlaut oder mit allen Komponenten.
- **Zahlen nur aus der Vorlage.** Selbst berechnete Zahlen (z. B.
  Förderanteil als Differenz) als „abgeleitet" kennzeichnen.
- **Lücken benennen:** Fehlt eine erwartbare Angabe, „Angabe fehlt in der
  Vorlage" schreiben und als Frage aufnehmen — nie still weglassen.

Formale TOPs (Protokollgenehmigung, Bekanntgaben) bekommen eine Zeile.

## Quellenpflicht

Jede politisch relevante Aussage trägt eine Quelle (AGENTS.md §6):

- **RIS:** Sitzungs-ID, Datum, URL.
- **PDF:** Drucksachen-Nummer oder Dateiname, Seite bzw. Zeile.
- **AZ:** URL und Abrufdatum, je Artikel einzeln.
- **Vault:** Titel und Pfad, gekennzeichnet als „persönliche Notiz" — keine
  amtliche Quelle; unbelegte Behauptungen darin als solche markieren.
- Ohne Quelle: „nicht belegt" — nicht verschweigen.

## Querschnittsanalyse (nur große Sitzungen)

Greift erst, wenn **mindestens zwei** zutreffen: Unterlagen über ~50 Seiten;
ein TOP mit mehr als 10 inhaltlichen Beschlussvorschlägen (BVS); zwei
substantielle TOPs (≥ 3 inhaltliche BVS) teilen Akteure oder Themen. Sonst
entfällt sie ganz.

Dann vor dem Schreiben intern erfassen, je mit Fundstelle (Seite/Zeile):

- **BVS** mit stabilem Slug `bvs-<top>-<nr>[-<träger>]`; Unterpunkte bleiben
  unter einem Slug; Satzungsbeschluss `bvs-<top>-satzung`.
- **Stellungnahmen** klassifiziert als Behörde (§ 4 BauGB) |
  Öffentlichkeit (§ 3 Abs. 2 BauGB) | verwaltungsintern | Anwohner.
  Weicht der Briefkopf vom Einreicher ab: beide Angaben stehen lassen,
  als Unklarheit markieren, die nutzende Person entscheidet.
- **Akteure**, die in mehreren TOPs auftreten, und **Themen**, die sich
  durchziehen (Klima, Wasser, Mobilität, Präzedenzfall, § 34/35 BauGB).
- **Muster:** gleiche Forderungen, die in mehreren TOPs übergangen werden;
  abgestufte Wortlaute derselben Behörde; Klagerisiken; Cluster von
  Stellungnahmen.

Ergebnis in der Mappe als **Anhang: Querschnitt** — ein Mermaid-Überblick
aller TOPs, ein Diagramm je substantiellem TOP (BVS → Akteure → Themen), ein
Diagramm der Querschnitts-Akteure, dazu 3–5 Befunde, die TOP für TOP
verborgen blieben. Befunde, die nach einem Antrag rufen, als Ansatzpunkt für
`antrag_generieren` notieren, nicht ausformulieren.

Mermaid, damit Obsidian rendert: Knoten-IDs nur ASCII; kein `&` in Labels;
`subgraph ID["Titel"]`; Kantenlabels `A -->|"Text"| B`; Themenkanten
gestrichelt `-.->`. Kein persistierter Graph, kein eigenes Tool.

## Mappe schreiben

Ziel: `1 - Projects/Stadtrat Buchloe/Sitzungsmappen/<YYYY-MM-DD> <Sitzungsname>.md`

1. Mappe in eine Temp-Datei schreiben.
2. Frontmatter prüfen:
   ```bash
   uv run --with pyyaml python3 -c "import yaml,sys; p=open(sys.argv[1]).read().split('---',2); d=yaml.safe_load(p[1]) if len(p)==3 else None; sys.exit(0 if isinstance(d,dict) else 'FEHLER: Frontmatter fehlt oder kaputt')" <temp-datei>
   ```
   Externe Titel (AZ, RIS, Vault) in YAML **immer in Single-Quotes**,
   `'` darin als `''` — deutsche Anführungszeichen brechen sonst
   Double-Quotes.
3. **GO einholen:** Zielpfad und Gliederung zeigen; bei existierender Datei
   ausdrücklich auf das Überschreiben hinweisen. Ohne GO kein Write.
4. Nach GO übernehmen:
   ```bash
   obsidian vault="<v>" eval code="app.vault.adapter.mkdir('<ordner>').then(() => app.vault.adapter.write('<zielpfad>', require('fs').readFileSync('<temp-datei>', 'utf8')))"
   ```

## Vorlage

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
    titel: '<artikel-titel>'
    url: <url>
    abrufdatum: 2025-07-15
  - typ: vault
    titel: '<notiz-titel>'
    pfad: '<vault-pfad>'
---

# Sitzungsmappe: <Gremium> <YYYY-MM-DD>

**Gremium:** … · **Datum:** … · **RIS:** [Sitzung](<ris_url>)
**Erstellt:** <datum> (Vorschlag — der Stadtrat entscheidet)

## TOP 1: <Titel>

- **Status:** beschließend | beratend
- **Vorhaben / Anliegen:** <Name; was die Vorlage will, Maßnahmen>
- **Kosten / Finanzierung:** <gesamt, Eigenanteil, Förderanteil — oder „Angabe fehlt in der Vorlage">
- **Beschlussvorschlag:** <Wortlaut oder alle Komponenten>
- **Dokumente:** <Drucksache / PDF — oder „keine Vorlage gefunden">

**AZ:** „<Titel>" — <url>, abgerufen <datum>. <Kern in 1–2 Sätzen>
**Vault:** [[<notiz>]] (persönliche Notiz) — <Kern>
**Ratsprojekt:** möglicher Bezug zu `#ratsprojekt/<slug>`

**Fragen für die Fraktion**
- [ ] <Frage, auch aus Lücken der Vorlage>

## Querverweise
<Ratsprojekte, AZ-Artikel, Vault-Notizen, RIS-Sitzung — je mit Quelle>

## Offene Fragen und nächste Schritte
- [ ] <z. B. PDF für TOP X lesen, Position zu TOP Y klären>
```

## Folgeschritte (nur vorschlagen, Start nach GO)

| Anlass | Skill |
|---|---|
| TOP berührt ein Ratsprojekt | `ratsprojekt_stand`, bei neuen Infos `ratsprojekt_delta` |
| Finanzierungs-TOP | `foerdermittel_recherche` |
| Befund ruft nach einem Antrag | `antrag_generieren` |

Jede Schreibaktion in ratsprojekte (`propose_*`, `decide_proposal`) und jede
Weitergabe der Mappe außerhalb des Vaults braucht ein eigenes GO.
