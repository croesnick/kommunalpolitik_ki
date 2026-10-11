# ratsprojekte — Datenmodell und Planung

## Konzept

Rechtlich-inhaltliche Standortbestimmung für Stadtratsprojekte.
Kein Task-Tracker, keine Todo-Liste. Sondern: welche Realisierungsstränge
gibt es, welche rechtlichen Vorbedingungen stehen, welcher Weg kann
gegangen werden — und welcher nicht.

## Datenmodell

```
Projekt
├── titel, beschreibung, status (idee/aktiv/abgeschlossen), prioritaet
│
├── Realisierungsstrang (1..n, Alternativen — A ODER B ODER C)
│   ├── label (A/B/C/...), titel, beschreibung
│   ├── rechtliche_grundlage (Paragraf, Gesetz)
│   ├── bedingung (Wann kann dieser Weg gezogen werden?)
│   ├── bedingung_erfuellt (true/false — kann der Weg jetzt gegangen werden?)
│   │
│   ├── Vorbedingung (1..m)
│   │   ├── text (Was muss erfüllt sein?)
│   │   ├── erfuellt (true/false)
│   │   └── rechtliche_grundlage (Paragraf, Gesetz — optional)
│   │
│   └── Schritt (1..m, geordnete Liste)
│       ├── text (Was ist auf diesem Weg zu tun?)
│       └── frist (optional, Datum)
│
└── Quelle (0..n, auf Projektebene)
    ├── typ (sitzung/foerderprogramm/gesetz/url/zeitungsartikel)
    ├── titel, url, paragraf, abrufdatum
```

## UI-Prinzipien

- Projekt-Karten mit Status und Priorität
- Realisierungsstränge als Abschnitte, getrennt durch "— ODER —"
- Vorbedingungen als farbige Zeilen: ✓ grün (erfüllt), ⚠ rot (nicht erfüllt)
- Rechtliche Grundlagen als rote/grüne Paragrafen-Badges
- Schritte als Pfeil-Liste (→), keine Checkboxen, keine Todo-Optik
- Fristen als rote Badges (⏰)
- KISS: übersichtlich, lesbar, druckfreundlich

## Roadmap

1. ✅ UI-Mockup erstellt (priv/static/ui-mockup.html)
2. Datenmodell anpassen: Realisierungsstrang, Vorbedingung, Schritt
3. Schemas + Migration
4. Seed mit Beispielprojekten
5. LiveView implementieren
6. (später) Antragsvorlagen-Generator
7. (später) MCP-Server für AI-Zugriff
8. (später) Ratsinfo-Integration
