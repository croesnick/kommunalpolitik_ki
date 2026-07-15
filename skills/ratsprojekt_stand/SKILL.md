---
name: ratsprojekt_stand
description: >
  Standortbestimmung für Stadtratsprojekte aus dem ratsprojekte-Dashboard abrufen.
  Zeigt Realisierungsstränge, rechtliche Vorbedingungen, offene Fristen und Quellen.
  Nutze diesen Skill immer, wenn nach dem Stand, der Machbarkeit, den Vorbedingungen
  oder Realisierungssträngen eines konkreten kommunalen Projekts gefragt wird.
  Auch bei Fragen wie "Wo steht Projekt X?", "Welche Optionen haben wir für…?",
  "Was steht der Bahnhofstraße entgegen?", "Welche rechtlichen Grundlagen brauchen wir für…?"
  oder "Gibt es einen Plan B für…?" verwenden.
---

# Projekt-Tracker Skill

## Wann dieser Skill greift

Wenn der Stadtrat nach dem Stand eines Projekts, nach Realisierungsoptionen,
nach Vorbedingungen oder nach rechtlichen Grundlagen fragt — für Projekte,
die im ratsprojekte-Tracker erfasst sind (Bahnhofstraße, Gennachpark,
Freibad, und zukünftige).

Typische Fragen:

- "Wo steht die Bahnhofstraße?"
- "Welche Realisierungsstränge haben wir für den Gennachpark?"
- "Was blockiert die Bahnhofstraße-Umgestaltung?"
- "Gibt es einen Plan B für die Bahnhofstraße?"
- "Welche rechtlichen Vorbedingungen fehlen für Städtebauförderung?"
- "Welche Fristen haben wir beim BMUV-Antrag?"

## MCP-Tools

Dieser Skill nutzt die ratsprojekte-MCP-Tools (read-only):

1. **`search_projekte`** — Finde Projekte nach Suchbegriff
   - Verwende zuerst, wenn der Projektname nicht genau bekannt ist
   - Beispiel: `search_projekte(query: "Bahnhof")` → Liste passender Projekte

2. **`list_projekte`** — Alle Projekte mit Status/Priorität
   - Verwende für einen Überblick über alle Projekte

3. **`show_projekt`** — Vollständige Details zu einem Projekt
   - Liefert alle Stränge, Vorbedingungen, Schritte, Quellen
   - Beispiel: `show_projekt(id: 10)` → Vollständige Standortbestimmung

## Arbeitsweise

1. **Identifizieren**: Wenn ein Projektname genannt wird, mit `search_projekte`
   suchen. Wenn unklar welches Projekt gemeint ist, `list_projekte` aufrufen.
2. **Details laden**: `show_projekt` mit der gefundenen ID aufrufen.
3. **Standortbestimmung erstellen**: Aus den Daten eine strukturierte
   Standortbestimmung generieren (siehe Output-Format).

## GO-Prinzip: AI berät, Mensch entscheidet

Die AI entscheidet nichts. Sie liest die Projektdaten und erstellt eine
Standortbestimmung — sie trägt nichts in die Datenbank ein, ändert keinen
Status, markiert keine Vorbedingungen als erfüllt. Das ist nicht nur eine
Arbeitsregel, sondern ethische Architektur: demokratische Verantwortung
bleibt beim Stadtrat.

## Quellenpflicht

Jede Aussage, die ein Tool produziert und politisch relevant ist, braucht
eine Quelle. Bei ratsprojekte sind Quellen an Realisierungsstränge und
Projekte angehängt — nutze sie:

- **Gesetz**: Paragraf angeben (z.B. "Art. 13f BayFAG")
- **Förderprogramm**: URL und Programmname
- **Sitzung**: Sitzungsdatum und TOP
- **Ohne bestätigte Quelle**: als "nicht belegt" kennzeichnen

## Lifecycle-Referenz

Der vollständige Projektlebenszyklus ist in
[`docs/ratsprojekte-lifecycle.md`](../../docs/ratsprojekte-lifecycle.md)
als Mermaid-Chart dokumentiert. Das ist die verbindliche Referenz für
Statuswerte und gültige Übergänge. Die Statusliste
(`idee/aktiv/abgeschlossen/verworfen`) richtet sich nach dem Chart.

## Output-Format

```markdown
## Projektstand: [Projekttitel]

**Status:** [idee/aktiv/abgeschlossen/verworfen] | **Priorität:** [hoch/mittel/niedrig]

### Realisierungsstränge

**Strang A: [Titel]**
- Beschreibung: …
- Strang-Bedingung: … ([✓ erfüllt / ⚠ offen])
- Vorbedingungen: X/Y erfüllt
  - ✓ [erfüllte Vorbedingung] (Paragraf)
  - ⚠ [offene Vorbedingung] (Paragraf)
- Schritte:
  - → [Schritt 1]
  - → [Schritt 2] ⏰ [Frist]
- Quellen: …

— ODER —

**Strang B: [Titel]**
…

### Zusammenfassung
- [Strang mit besten Aussichten]: …
- [Haupthindernis]: …
- [Nächste Schritte]: …

### Quellen
- [Quelle 1 mit URL/Paragraf]
- [Quelle 2]
```
