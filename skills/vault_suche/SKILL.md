---
name: vault_suche
description: >
  Obsidian-Vault nach thematisch relevanten Notizen durchsuchen, Treffer mit
  Kontext sammeln, dem Stadtrat zur Entscheidung vorlegen. Read-only — die AI
  berät, der Mensch entscheidet (GO-Prinzip). Nutze diesen Skill immer, wenn
  Carsten bittet, im Vault nach etwas zu suchen, Notizen zu einem Thema zu
  finden, oder den Vault nach Infos zu durchsuchen, die dann für etwas anderes
  (z.B. ratsprojekt anreichern, Förderrecherche) verwendet werden
  sollen. Typische Trigger: „Such im Vault nach…", „Guck mal in meinen Notizen
  nach…", „Was hab ich im Vault zu Thema X?", „Finde Notizen zur Bahnhofstraße
  / zum Verkehrskonzept / zum Bauhof", „Hol mal alles aus dem Vault zu…".
  Der Skill liefert eine strukturierte Trefferliste — was danach damit passiert,
  entscheidet Carsten. Oft folgt die Weiterverarbeitung ad-hoc: Treffer gegen
  einen Projektstand aus `projekt_tracker` halten, an `foerdermittel` anhängen,
  oder eine AZ-/Ratsinfo-Recherche nachschieben — aber nur auf Carstens
  ausdrücklichen Wunsch.
---

# Vault-Suche Skill

## Wann dieser Skill greift

Wenn Carsten bittet, den Obsidian-Vault nach einem Thema, Begriff oder Konzept
zu durchsuchen — um zu verstehen, was er schon an Notizen dazu hat, bevor es
weiterverarbeitet wird (z.B. um ein ratsprojekt anzureichern oder eine
Förderanfrage vorzubereiten).

Der Skill ist **Suche + Sammlung + Kontext**, nicht Auswertung oder
Verarbeitung. Was nach den Treffern passiert, entscheidet Carsten — der Skill
endet mit der Trefferliste und einem Vorschlag, was als Nächstes sinnvoll wäre.

## Konfiguration: Vault-Zugriff

Der Skill ist vault-agnostisch. Beim ersten Aufruf pro Session muss er wissen,
welcher Vault gemeint ist. Die Konfiguration kommt aus einer lokalen,
**nicht-getrackten** Datei:

```
config.local.yml   # im Repo-Root, nicht in Git
```

Format:

```yaml
obsidian:
  vault: "MeinVaultName"   # Name wie in Obsidian angezeigt
```

Fehlt die Datei oder der `vault`-Eintrag, fragt der Skill Carsten direkt nach
dem Vault-Namen und speichert ihn *nicht* automatisch (GO-Prinzip: die AI
schreibt keine Config, der Mensch entscheidet, was konfiguriert wird).

Der Skill merkt sich den Vault-Namen für die restliche Session.

## Arbeitsweise

### 1. Konfiguration lesen

- `config.local.yml` im Repo-Root lesen
- Wenn `obsidian.vault` gesetzt: Vault-Namen übernehmen
- Wenn nicht: Carsten fragen „Wie heißt dein Obsidian-Vault?" und für die
  Session merken. Hinweis geben, dass er ihn in `config.local.yml` (siehe
  `config.local.yml.example`) eintragen kann, um das erneute Fragen zu
  vermeiden.

### 2. Suchbegriffe ableiten

Aus Carstens Anfrage die Suchbegriffe ableiten. Meist reicht der genannte
Begriff („Bahnhofstraße", „Bauhof"), aber der Skill ergänzt sinnvolle Synonyme
und verwandte Begriffe:

- Orts- und Projektbezug: „Bahnhofstraße" → auch „Bahnhof", „BF-Straße",
  „Fußgängerzone"
- Sachbezug: „Verkehrskonzept" → auch „SUMP", „Verkehrsplanung"
- Personen: „Klimamanagerin" → auch deren Name, falls bekannt

Keine kryptischen Abkürzungen — die Obsidian-Volltextsuche verzeiht
Tippfehler nicht. Klare Begriffe, ggf. als mehrere Suchen nacheinander.

### 3. Volltext-Suche im Vault

Da der Vault keine definierte Ordner- oder Tag-Struktur für Stadtrats-Themen
hat, ist die Suche **Volltext über alles**. Mehrere Suchen parallel ausführen:

```bash
obsidian vault="MeinVault" search query="Bahnhofstraße" limit=15
obsidian vault="MeinVault" search query="Bauhof" limit=15
obsidian vault="MeinVault" search query="Verkehrskonzept" limit=15
```

Treffer-Deduplizierung: dieselbe Notiz kann bei mehreren Suchen auftauchen —
einmal zusammenführen.

### 4. Relevante Treffer lesen

Für die vielversprechendsten Treffer (max. 5–7 Notizen) den Inhalt lesen:

```bash
obsidian vault="MeinVault" read file="Notiz Titel"
```

Nicht jede Treffer-Notiz muss ganz gelesen werden — der Skill bewertet anhand
der Snippets aus der Suche, welche Notizen relevant genug sind fürs
Vollständig-Lesen. Overfetching vermeiden.

### 5. Trefferliste mit Kontext ausgeben

Strukturierte Liste der relevanten Notizen:

```markdown
## Vault-Treffer: [Suchbegriff / Thema]

**Vault:** [Vault-Name]
**Gesucht nach:** [Begriffe, die verwendet wurden]
**Treffer:** [Anzahl] relevante Notizen von [Anzahl] Suchen

### Relevante Notizen

**1. [Notiz-Titel]** — [Erstelldatum / geändert am]
- Pfad: `folder/notiz.md`
- Relevanz: [Warum relevant? 1–2 Sätze, was die Notiz zum Thema beiträgt]
- Kerninhalt: [1–2 Sätze Zusammenfassung der relevanten Stelle]
- Quelle für ratsprojekt geeignet? [ja/nein/vielleicht — begründen]

**2. …**

### Weitere Treffer (weniger relevant)
- [Titel] — [kurzer Hinweis, warum weniger relevant]

### Nicht gefunden
- [Themen, zu denen der Vault nichts hergab — explizit benennen]

### Nächste Schritte
- Vorschlag: „Soll ich `projekt_tracker` aufrufen und schauen, welches Projekt
  zu den Treffern passt — und dann ad-hoc gegen den Projektstand halten?"
- Vorschlag: „Soll ich in `foerdermittel` recherchieren, weil im Vault
  Förderhinweise gefunden wurden?"
- Oder: „Die Notizen reichen nicht — soll ich woanders suchen (AZ, RIS, Web)?"
```

## GO-Prinzip: AI sucht, Mensch entscheidet

Der Skill schreibt nichts in den Vault, legt keine Notizen an, ändert keine
Properties. Er liest und präsentiert. Was mit den Treffern passiert, entscheidet
Carsten. Der Skill macht Vorschläge („soll ich das gegen den Stand von Projekt X
halten?"), aber er führt keinen Handoff ohne ausdrücklichen GO durch.

## Quellenpflicht

Vault-Notizen sind Quellen. Jeder Treffer, der später in eine Förderrecherche
oder einen Projektstand einfließt, muss als Quelle
identifiziert werden:

- **Welche Notiz?** Titel, Pfad
- **Wann erstellt/geändert?** Datum aus Obsidian
- **Art:** „persönliche Notiz" / „Vault-Notiz" (keine amtliche Quelle)

Vault-Notizen allein sind selten ausreichend als Quelle für politische
Aussagen — sie sind Hinweise, Erinnerungen, Vorab-Info. Der Skill markiert
explizit, wenn eine Notiz eine Behauptung ohne Beleg enthält und weist auf die
generelle Quellenpflicht im Projekt hin (siehe `AGENTS.md` §6).

## Komposition mit anderen Skills

Der Skill ist bewusst dünner Endpunkt: er sucht, sammelt, präsentiert. Die
Verarbeitung geschieht in nachfolgenden Skills oder ad-hoc durch den
Orchestrator, die Carsten ausdrücklich anfordert:

| Folgeschritt | Skill / Weg | Wann |
|---|---|---|
| Bestehendes Projekt anreichern | ad-hoc gegen `projekt_tracker`-Stand halten | Wenn Treffer zu einem existierenden ratsprojekt passen |
| Projektstand abrufen | `projekt_tracker` | Wenn unklar ist, welches Projekt gemeint ist |
| Förderrecherche | `foerdermittel` | Wenn Treffer Finanzierungshinweise enthalten |
| AZ-Artikel | `allgaeuer_zeitung_mcp` | Wenn Treffer auf einen Artikel verweisen |
| Ratsinfo | `ratsinfo` CLI | Wenn Treffer auf eine RIS-Sitzung/TOP verweisen |

Der Skill endet immer mit Vorschlägen aus dieser Tabelle, aber der GO liegt
bei Carsten.
