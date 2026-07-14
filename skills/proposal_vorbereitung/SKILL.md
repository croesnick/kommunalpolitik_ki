---
name: proposal_vorbereitung
description: >
  Leitfaden für die AI, um ein neues Stadtratsprojekt oder eine Projektänderung
  vorzubereiten und als Proposal in ratsprojekte einzubringen. Nutze diesen
  Skill immer, wenn Carsten ein neues Projekt vorschlagen will, eine Idee in
  ein ratsprojekt überführen will, oder einen Strang/Status zu einem
  bestehenden Projekt hinzufügen will. Auch bei „Ich will das als Projekt
  anlegen", „Kannst du das als Proposal einbringen?", „Mach daraus ein
  ratsprojekt" oder „Ich habe hier Material zu X — kann das ein Projekt werden?".
  Der Skill sorgt dafür, dass die Antragsreife-Gates *vor* dem Proposal
  geprüft werden — nicht erst danach.
---

# Proposal-Vorbereitung Skill

## Wann dieser Skill greift

Wenn Carsten Material, Ideen oder Recherchen hat, die in ein ratsprojekt
einfließen sollen — als neues Projekt, als neuer Realisierungsstrang, oder
als Statusänderung. Der Skill ist der **Strukturierungs- und
Qualitätssicherungsschritt** bevor der AI das `propose_projekt`- oder
`propose_realisierungsstrang`-MCP-Tool aufruft.

Der Skill aktiviert sich *nicht* bei reinen Standortabfragen (dafür:
`projekt_tracker`) oder Förderrecherchen (dafür: `foerdermittel`). Er
greift, wenn das Ziel ein **Proposal** ist.

## Architekturprinzip: Vault = Source of Truth, ratsprojekte = Distillat

```
Vault (Source of Truth — roh, unstrukturiert, alles)
  ↓  Konsolidierung & Distillation (durch AI, in OpenCode-Session)
  ↓  Pflicht: konsolidierte Notiz zurück in den Vault
  ↓
ratsprojekte (Distillat — strukturiert, antragsreif, quellenbelegt)
```

- **Vault** ist das Gedächtnis, nicht ratsprojekte.
- **ratsprojekte** ist das Distillat, nie die Datenquelle.
- **Datenfluss ist einseitig**: Vault → ratsprojekte. Nie umgekehrt.
- **Pflicht**: Alles, was in der OpenCode-Session entsteht, fließt als
  konsolidierte Notiz zurück in den Vault, *bevor* es als Proposal
  eingereicht wird. ratsprojekte ist das Endprodukt, nicht der Input.
- **Vault-Tag**: Vault-Notizen zu einem Projekt werden mit
  `#ratsprojekt/{slug}` getaggt. Der Slug ist der gleiche wie in der
  ratsprojekte-URL. So findet der AI über `vault_suche` alle Notizen
  zu einem Projekt und kann sie als Quellen in Proposals eintragen.

## Workflow: Idea → Vault-Notiz → Proposal

### Phase 1: Sammeln

Material sammeln aus allen verfügbaren Quellen:

1. **Vault durchsuchen** — `vault_suche`-Skill aufrufen, um bestehende
   Notizen zum Thema zu finden. Carsten hat oft schon Material im Vault,
   das er vergessen hat oder das an anderer Stelle liegt.

2. **Recherche ergänzen** — je nach Thema:
   - Förderung relevant? → `foerdermittel`-Skill
   - Lokalberichterstattung? → `allgaeuer_zeitung_mcp`
   - Ratsinformationen? → `ratsinfo` CLI
   - Web-Recherche? → `web_search` / `web_fetch`

3. **Bestehende Projekte prüfen** — `projekt_tracker` oder
   `search_projekte` MCP-Tool aufrufen. Gibt es schon ein Projekt, das
   dieses Thema abdeckt? Wenn ja: Proposal als `add_realisierungsstrang`
   oder `change_status` für das bestehende Projekt, nicht als neues.

### Phase 2: Konsolidieren

**Pflicht**: Das gesammelte Material wird zu einer konsolidierten Notiz
destilliert und in den Vault zurückgeschrieben. Das gilt auch für Material,
das in der OpenCode-Session entstanden ist (z.B. ein `foerdermittel`-Report).

Die Vault-Notiz ist die Voraussetzung für den Proposal — nicht optional.
ratsprojekte bekommt nur Distillate, nie Rohmaterial.

### Phase 3: Gates prüfen (vor dem Proposal)

Bevor das `propose_*`-MCP-Tool aufgerufen wird, muss die AI die Gates aus
`apps/ratsprojekte/priv/antragsreife_kriterien.md` durchgehen. Diese Gates
sind die gleichen, die später `check_antragsreife` deterministisch prüft —
aber *vor* dem Proposal, um sicherzustellen, dass der Proposal vollständig ist.

> **Lifecycle-Referenz**: Der vollständige Projektlebenszyklus
> (Vault-Idee → Proposal → Projekt → Stränge → Abschluss/Archivierung) ist
> in [`docs/ratsprojekte-lifecycle.md`](../../docs/ratsprojekte-lifecycle.md)
> als Mermaid-Chart dokumentiert. Jede Statusänderung muss dem Chart
> entsprechen — keine Übergänge vorschlagen, die der Chart nicht zeigt.

#### Hard Gates (Pflicht vor Proposal)

| Gate | Frage | Bei Nein |
|---|---|---|
| `quellen_vorhanden` | Hat das Projekt mindestens eine Quelle mit URL und Abrufdatum? | Quellen nachtragen, *dann* vorschlagen |
| `adressat_gesetzt` | Ist klar, an wen der Antrag gerichtet ist (Stadtrat, Bürgermeister, Vergabeausschuss)? | Mit Carsten klären |
| `beschlussvorschlag_konkret` | Gibt es einen konkreten Beschlussvorschlag (> 20 Zeichen)? | Mit Carsten formulieren |
| `realisierungsstrang_vorhanden` | Gibt es mindestens einen Realisierungsstrang? | Strang formulieren |
| `vorbedingungen_erfuellt` | Sind die Vorbedingungen bekannt (auch wenn offen)? | Vorbedingungen identifizieren |
| `value_proposition_vorhanden` | Welches konkrete Problem löst das Projekt? Für wen? Was ändert sich? (> 20 Zeichen, kein reines "Digitalisierung von X") | Mit Carsten konkretisieren — kein Proposal ohne VP |
| `success_metrics_vorhanden` | Woran wird gemessen, ob das Projekt erfolgreich war? Mindestens eine messbare Größe. | Mit Carsten definieren — kein Proposal ohne Metriken |

#### Soft Gates (im Proposal beantworten)

| Gate | Frage |
|---|---|
| `finanzierung_angesprochen` | Ist die Finanzierung erwähnt? (Beschlussvorschlag oder Beschreibung) |
| `rechtliche_grundlagen_genannt` | Sind rechtliche Grundlagen genannt? (Strang oder Vorbedingung) |
| `fristen_gesetzt` | Gibt es Fristen? (Schritte mit `frist`) |

#### Politische Kriterien (nur Mensch)

| Kriterium | Hinweis |
|---|---|
| `tonalitaet_sachlich` | Ist der Beschlussvorschlag sachlich? |
| `konsensfaehigkeit` | Ist der Antrag mehrheitsfähig? |
| `widerspruch_fraktionsposition` | Widerspricht der Antrag der Fraktionsposition? |

Die AI bewertet diese *nicht*. Sie weist Carsten darauf hin, dass diese
vor der finalen Einreichung geprüft werden müssen.

### Phase 4: Proposal einbringen

Erst wenn die Hard Gates beantwortet sind, wird das entsprechende
MCP-Tool aufgerufen:

#### Neues Projekt: `propose_projekt`

```
propose_projekt(
  titel: "…",
  slug: "freibad-digitalisierung",  # kebab-case, wird Vault-Tag #ratsprojekt/freibad-digitalisierung
  beschreibung: "…",
  prioritaet: "mittel",           # optional
  begruendung: "Warum … (min 10 Zeichen, Quellenpflicht)",
  quellen: "https://…, Art. 28 BayGO"  # optional, komma-getrennt
)
```

Das Tool liefert eine `review_url` (z.B.
`http://localhost:4000/proposals/5`). Carsten prüft dort und klickt
Accept oder Reject (GO-Gate).

**Slug-Konvention**: Der Slug ist der stabile Vertrag zwischen ratsprojekte
und dem Vault. Er wird Teil der URL (`/projekte/freibad-digitalisierung`)
und ist das Vault-Tag (`#ratsprojekt/freibad-digitalisierung`). Format:
kebab-case, lowercase, ASCII only (`^[a-z0-9]+(?:-[a-z0-9]+)*$`). Umlaute
als ae/oe/ue/ss. Der Slug wird bei der Projekterstellung vergeben und
ändert sich nicht mehr.

#### Neuer Strang für bestehendes Projekt: `propose_realisierungsstrang`

```
propose_realisierungsstrang(
  projekt_slug: "freibad-digitalisierung",
  label: "B",
  titel: "…",
  beschreibung: "…",
  rechtliche_grundlage: "Art. 13f BayFAG",
  bedingung: "…",
  begruendung: "Warum dieser Strang …"
)
```

#### Statusänderung: `propose_status_change`

```
propose_status_change(
  projekt_slug: "freibad-digitalisierung",
  neuer_status: "aktiv",        # idee/aktiv/abgeschlossen/verworfen
  datum: "2025-07-14",          # optional
  verworfen_grund: "…",         # bei verworfen
  begruendung: "Warum …"
)
```

## Was die AI *nicht* tut

- **Kein `decide_proposal` ohne GO**: Die AI kann Proposals vorschlagen
  (`propose_*`-Tools) und — wenn der Stadtrat GO gibt — über
  `decide_proposal` ausführen. Aber sie ruft `decide_proposal` NIEMALS
  auf, ohne dass der Stadtrat im Chat explizit GO gegeben hat. Kein
  stillschweigendes Accept. Das GO muss vom Menschen kommen.
- **Kein Schreiben in ratsprojekte ohne Proposal**: Alle Writes gehen
  durch `pending_proposals`. Nie direktes `Repo.insert`.
- **Keine Vault-Änderung ohne GO**: Die AI schreibt nicht ungefragt in
  den Vault. Sie schlägt die konsolidierte Notiz vor und Carsten
  entscheidet, ob sie in den Vault kommt.
- **Keine politische Bewertung**: Die AI bewertet nicht, ob ein Antrag
  mehrheitsfähig ist oder der Fraktionsposition widerspricht. Das
  bleibt bei Carsten.

## Quellenpflicht

Jeder Proposal braucht Quellen. Vault-Notizen allein sind selten
ausreichend — sie sind Hinweise, keine Belege. Für jeden Proposal gilt:

- Mindestens eine Quelle mit URL und Abrufdatum
- Paragrafen bei rechtlichen Grundlagen (z.B. „Art. 13f BayFAG")
- Bei Sitzungsbeschlüssen: Datum und TOP
- Bei Förderprogrammen: Programmname, URL, Abrufdatum

Wenn eine Behauptung ohne Beleg im Proposal steht: als „ohne bestätigte
Quelle" markieren.

## Komposition mit anderen Skills

| Vorheriger Schritt | Skill | Wann |
|---|---|---|
| Vault durchsuchen | `vault_suche` | Immer — Materialbasis prüfen |
| Förderrecherche | `foerdermittel` | Wenn Finanzierung unklar |
| Projektstand abrufen | `projekt_tracker` | Wenn bestehendes Projekt relevant |
| Antragsreife prüfen (post-Proposal) | `check_antragsreife` MCP-Tool | Nach Accept, für Reife-Check |
| Projektlebenszyklus | [`docs/ratsprojekte-lifecycle.md`](../../docs/ratsprojekte-lifecycle.md) | Verbindliche Referenz für Status-Übergänge |

## Output

Der Skill endet mit:

1. **Konsolidierte Vault-Notiz** (Vorschlag an Carsten, mit GO)
2. **Proposal-Aufruf** (MCP-Tool), falls Gates erfüllt
3. **Review-URL** (`http://localhost:4000/proposals/:id`)
4. **Hinweis auf offene Gates** (welche Soft/Political Gates noch offen sind)

Wenn die Gates *nicht* erfüllt sind: kein Proposal, sondern eine
Liste der offenen Fragen an Carsten. Erst wenn alle Hard Gates
beantwortet sind, wird vorgeschlagen.
