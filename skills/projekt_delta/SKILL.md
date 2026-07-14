---
name: projekt_delta
description: >
  Neue Informationen (Emails, Förderrichtlinien, Zeitungsartikel, Obsidian-Notizen)
  gegen den aktuellen Stand eines Stadtratsprojekts halten und ein strukturiertes
  Delta produzieren. Zeigt auf, welche Vorbedingungen sich ändern würden, welche
  neuen Quellen entstehen, und ob die Antragsreife steigt oder sinkt. Read-only —
  die AI berät, der Mensch entscheidet (GO-Prinzip). Nutze diesen Skill immer, wenn
  Carsten neue Informationen zu einem bestehenden Projekt hat und wissen will, was
  sich dadurch ändert. Typische Trigger: „Hier ist eine Email von …", „Neue
  Förderrichtlinie ist raus", „Ich hab eine Notiz aus dem Vault", „Schau dir das
  mal an, was bedeutet das für Projekt X?", „Laut diesem Artikel soll die
  Bahnhofstraße umgestaltet werden — ändert das was für unser Projekt?".
  Auch bei „Was bedeutet diese Mail für…", „Wie reagieren wir auf…", „Ist das
  relevant für…", „Ist das Projekt noch aktuell angesichts…".
---

# Projekt-Delta Skill

## Wann dieser Skill greift

Wenn Carsten neue Informationen zu einem **bestehenden** ratsprojekt hat und
wissen will, was sich dadurch ändert — an Vorbedingungen, Quellen,
Realisierungssträngen, Status oder Antragsreife. Der Skill ist **Delta-Produktion**,
nicht Standortbestimmung (dafür: `projekt_tracker`) und nicht Proposal-Vorbereitung
(dafür: `proposal_vorbereitung`).

Der Skill endet mit einem strukturierten Delta-Report. Was danach passiert
(Vault-Notiz ergänzen, Proposal einbringen, Status ändern), entscheidet Carsten.

## Architekturprinzip: Drei Divergenz-Richtungen

Der Skill adressiert das zentrale Problem bei Vault = Source of Truth +
one-way flow (Vault → ratsprojekte): Divergenz zwischen Vault und ratsprojekte.

| Richtung | Ursache | Was der Skill prüft |
|---|---|---|
| **Vault ahead** | Neue Info im Vault, ratsprojekte nicht aktualisiert | Hat die Vault-Notiz Inhalte, die in ratsprojekte noch nicht als Quelle/Beschreibung erfasst sind? |
| **ratsprojekte ahead** | Proposal accepted, Status geändert, Vault weiß nichts | Hat ratsprojekte einen Status/Entscheidung, die der Vault nicht spiegelt? |
| **Beide stale** | Realität hat sich geändert (neue RIS-Sitzung, Artikel), keiner weiß es | Sind die Quellen in ratsprojekte noch aktuell (abrufdatum)? Gibt es neuere Erkenntnisse? |

## Workflow: Neue Info → Projekt-Stand → Delta

### Phase 1: Neue Info aufnehmen

Carsten liefert neue Informationen. Mögliche Formate:

- **Email / Brief / Gesprächsinhalt** — als Text oder Zusammenfassung
- **Zeitungsartikel** — URL oder Text (→ `allgaeuer_zeitung_mcp` für AZ, `web_fetch` für andere)
- **Förderrichtlinie / Beschluss** — URL oder PDF-Referenz
- **Vault-Notiz** — `vault_suche`-Skill aufrufen, um die Notiz zu finden
- **Ratsinfo-Sitzung** — `ratsinfo` CLI

Die AI fasst die neue Info in 2–3 Sätzen zusammen und identifiziert die
**Informationsart** (neue Quelle, neue Vorbedingung, Status-Änderung,
Widerspruch, Bestätigung).

### Phase 2: Projekt-Stand abrufen

- `search_projekte` oder `list_projekte` — welches Projekt ist gemeint?
- `show_projekt(slug)` — vollständiger Stand: Stränge, Vorbedingungen,
  Quellen, Status, Beschreibung
- Optional: `check_antragsreife(slug)` — aktuelle Antragsreife als Benchmark

### Phase 3: Vault-Notizen zum Projekt abrufen

- `vault_suche` mit dem Projekt-Slug als Suchbegriff (z.B. `#ratsprojekt/bahnhofstrasse`)
- Ziel: prüfen, ob der Vault Inhalte hat, die ratsprojekte noch nicht kennt
  (Divergenz-Richtung "Vault ahead")

### Phase 4: Delta produzieren

Das Delta ist ein strukturierter Vergleich: *was würde sich ändern, wenn die
neue Info in ratsprojekte einflösse?*

#### Delta-Kategorien

| Kategorie | Frage | Beispiel |
|---|---|---|
| **Neue Quelle** | Ist die Info eine taugliche Quelle für einen Strang oder das Projekt? | „Email vom Bauamt vom 14.07.2025 bestätigt KNA liegt vor" |
| **Vorbedingung erfüllt** | Wird eine offene Vorbedingung durch die Info erfüllt? | „KNA ist da → Vorbedingung 'KNA muss vorliegen' kann auf erfüllt gesetzt werden" |
| **Neue Vorbedingung** | Entsteht eine neue Vorbedingung, die vorher nicht sichtbar war? | „Laut Artikel muss erst eine Verkehrsuntersuchung beauftragt werden" |
| **Strang-Relevanz** | Ändert sich die Relevanz eines Realisierungsstrangs? | „Strang B ist durch neuen Beschluss hinfällig" |
| **Status-Änderung** | Sollte der Projektstatus wechseln? | „Beschluss gefasst → Status sollte auf 'abgeschlossen'" |
| **Antragsreife** | Steigt oder sinkt die Antragsreife? | „Quelle fehlt noch → Reife sinkt von 'antragsreif' auf 'nicht_antragsreif'" |
| **Widerspruch** | Widerspricht die Info dem ratsprojekte-Stand? | „ratsprojekte sagt: Frist ist Q3. Mail sagt: Frist ist Q2." |
| **Vault-Divergenz** | Hat der Vault Inhalte, die ratsprojekte nicht kennt (oder umgekehrt)? | „Vault-Notiz vom 10.07. erwähnt Bürgermeister-Zusage, ratsprojekte hat keine Quelle dafür" |

### Phase 5: Delta-Report ausgeben

Siehe Output-Format. Der Report ist **beratend** — die AI schlägt vor, was sich
ändern würde, aber sie ändert nichts. Carsten entscheidet, ob eine der
Änderungen als Proposal eingbracht wird (→ `proposal_vorbereitung`).

## GO-Prinzip: AI vergleicht, Mensch entscheidet

Der Skill ist **read-only**. Er liest ratsprojekte (via MCP), liest den Vault
(via `vault_suche`), liest die neue Info (von Carsten geliefert) und produziert
ein Delta. Er trägt nichts in die Datenbank ein, ändert keinen Status, markiert
keine Vorbedingungen als erfüllt. Das ist nicht nur eine Arbeitsregel, sondern
ethische Architektur: demokratische Verantwortung bleibt beim Stadtrat.

## Quellenpflicht

Jede Behauptung im Delta-Report braucht eine Quelle. Wenn die neue Info eine
Quelle ist (z.B. Email vom 14.07.2025), wird sie als solche identifiziert.
Wenn die AI eine Behauptung aufstellt (z.B. „diese Info widerspricht Strang A"),
muss sie auf den konkreten Strang/die konkrete Vorbedingung verweisen.

- **Neue Info** als Quelle kennzeichnen (Typ, Datum, Absender/URL)
- **Bestehende Quellen** in ratsprojekte gegen die neue Info halten
- **Ohne bestätigte Quelle**: als „nicht belegt" kennzeichnen

## Lifecycle-Referenz

Der vollständige Projektlebenszyklus ist in
[`docs/ratsprojekte-lifecycle.md`](../../docs/ratsprojekte-lifecycle.md)
als Mermaid-Chart dokumentiert. Das Delta bezieht sich auf die im Chart
modellierten Zustände und Übergänge — z.B. „Vorbedingung erfüllt" ist ein
Übergang innerhalb von `Projekt_Aktiv`, „Status-Änderung" ist ein Übergang
zwischen `Projekt_Idee` / `Projekt_Aktiv` / `Projekt_Abgeschlossen` /
`Projekt_Verworfen`.

## Output-Format

```markdown
## Projekt-Delta: [Projekttitel]

**Slug:** freibad-digitalisierung
**Antragsreife aktuell:** [nicht_antragsreif / antragsreif / antragsreif_mit_vorbehalten]
**Neue Info:** [Informationsart, 1–2 Sätze Zusammenfassung]
**Info-Quelle:** [Typ, Datum, URL/Absender]

### Was sich ändern würde

#### Neue Quellen
- [Quelle 1] → würde zu [Projekt / Strang X] als Quelle passen
- [Quelle 2] → [widerspricht / bestätigt] [Strang Y]

#### Vorbedingungen
- ⚠ [offene Vorbedingung] → **könnte erfüllt sein** durch [neue Info]
- ⚠ [neue Vorbedingung] → taucht auf durch [Hinweis aus Info]
- ✓ [erfüllte Vorbedingung] → bleibt erfüllt (keine Änderung)

#### Realisierungsstränge
- [Strang A] → [relevanz unverändert / hinfällig / gestärkt] — [Begründung]
- [Strang B] → [relevanz unverändert / hinfällig / gestärkt] — [Begründung]

#### Status
- Aktuell: [idee / aktiv / abgeschlossen / verworfen]
- Vorschlag: [keine Änderung / Wechsel zu X] — [Begründung]

#### Antragsreife
- Aktuell: [Reife-Status]
- Prognose bei Einpflegen der neuen Info: [Reife-Status] (↑ steigt / ↓ sinkt / = unverändert)
- Begründung: [1–2 Sätze]

### Vault-Divergenz

- **Vault ahead**: [Vault-Notiz XYZ hat Inhalt, den ratsprojekte nicht kennt] / [keine Divergenz]
- **ratsprojekte ahead**: [ratsprojekte hat Status/Quelle, die der Vault nicht spiegelt] / [keine Divergenz]
- **Beide stale**: [Quellen älter als X Monate, Realität hat sich geändert] / [keine Staleness]

### Zusammenfassung

- [Wichtigste Änderung 1]
- [Wichtigste Änderung 2]
- [Empfehlung: Proposal einbringen / Vault-Notiz ergänzen / Status ändern / nichts tun]

### Nächste Schritte (GO bei Carsten)

- [ ] Proposal einbringen für [Änderung]? → `proposal_vorbereitung`
- [ ] Vault-Notiz um neue Info ergänzen? → `vault_suche` + manuelle Notiz
- [ ] Quellen nachtragen? → `propose_*`-Tools
- [ ] Status ändern? → `propose_status_change`
- [ ] Nichts tun — Info ist notiert, aber keine Action nötig
```

## Komposition mit anderen Skills

| Vorheriger Schritt | Skill / Tool | Wann |
|---|---|---|
| Projekt-Stand abrufen | `projekt_tracker` oder `show_projekt` MCP | Phase 2 |
| Vault durchsuchen | `vault_suche` | Phase 3 — Vault-Inhalte zum Projekt finden |
| Antragsreife prüfen | `check_antragsreife` MCP | Phase 2 — Benchmark für Delta |
| AZ-Artikel lesen | `allgaeuer_zeitung_mcp` | Wenn die neue Info ein AZ-Artikel ist |
| Ratsinfo durchsuchen | `ratsinfo` CLI | Wenn die neue Info eine RIS-Sitzung ist |
| Förderrecherche | `foerdermittel` | Wenn die neue Info eine Förderrichtlinie ist |
| Projektlebenszyklus | [`docs/ratsprojekte-lifecycle.md`](../../docs/ratsprojekte-lifecycle.md) | Verbindliche Referenz für Status-Übergänge |

| Folgeschritt | Skill / Tool | Wann |
|---|---|---|
| Proposal einbringen | `proposal_vorbereitung` | Wenn Delta eine Änderung empfiehlt und Carsten GO gibt |
| Vault-Notiz ergänzen | `vault_suche` + manuell | Wenn neue Info im Vault ergänzt werden soll |
| Status ändern | `propose_status_change` | Wenn Delta einen Status-Wechsel empfiehlt und Carsten GO gibt |
| Nichts tun | — | Wenn Delta keine Action-relevanten Änderungen bringt |
