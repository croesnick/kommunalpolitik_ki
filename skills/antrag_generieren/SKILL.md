---
name: antrag_generieren
description: Einen Stadtratsantrag aus Projektmaterial oder einem politischen Anliegen generieren. Arbeitet mit einer Musterstruktur, die aus der Analyse Dutzender realer Stadtratsanträge destilliert wurde. Nutze diesen Skill immer, wenn ein Stadtratsantrag, eine Ratsanfrage, eine Dringlichkeitsantrag, ein interfraktioneller Antrag oder eine Resolution entworfen werden soll. Typische Trigger: „Ich brauche einen Antrag zu…“, „Schreib mir einen Antrag, der…“, „Wie würde ein Antrag aussehen, der… fordert?“, „Mach aus diesem Projekt einen Antrag“, „Antrag generieren für…“, „Wir brauchen einen Dringlichkeitsantrag zu…“, „Stell dir vor, ich will beantragen, dass die Stadt X tut — wie sähe der Antrag aus?“. Der Skill kann Output als Markdown-Antragsentwurf, als ratsprojekte-Proposal-Vorlage oder als Vault-Notiz liefern. GO-Prinzip: Die KI entwirft, der Mensch entscheidet und finalisiert.
---

# antrag_generieren

## Zweck

Einen Stadtratsantrag entwerfen — strukturiert, quellenbelegt, beschlussfähig. Die KI berät und entwirft (GO-Prinzip), die nutzende Person entscheidet und reicht ein.

Dieser Skill destilliert die Muster aus der Analyse von ~25 realen Stadtratsanträgen (Antragsart: Einzelfraktionsantrag, interfraktioneller Antrag, Dringlichkeitsantrag, Resolution, Musterantrag, Beschlussvorlage) über 15 Kategorien (Planen/Bauen/Wohnen, Energie/Klima, Umwelt, Mobilität, Haushalt/Finanzen, Demokratie/Beteiligung, Soziale Kommune, Verwaltung/Beschaffung, Feuerwehr/Katastrophenschutz, Bildung/Sport/Kultur, Digitalisierung u.a.).

## Kanonische Antragsstruktur

Jeder gute Stadtratsantrag folgt diesem Skelett (die Reihenfolge ist wichtig):

```
1. Kopf / Einleitung
2. Antragssatz (formaler Beschlussgegenstand)
3. Spezifizierung / Verwaltungsaufträge
4. Begründung
5. Quellen / Anlagen
6. Unterschriftenblock
```

### 1. Kopf / Einleitung

- Anrede: „Sehr geehrte/r Frau/Herr (Ober-)Bürgermeister*in,“
- Fraktionsnennung:
  - Einzelfraktion: „Die Fraktion [NAME] im [Gremium] von [Kommune] stellt folgenden Antrag:“
  - Interfraktionell: „Im Namen der Fraktionen X, Y, Z stellen wir folgenden Antrag:“ (alle Fraktionen explizit, später auch im Unterschriftenblock)
- Bei Dringlichkeit: „Dringlichkeitsantrag“ + Begründung der Dringlichkeit (warum nicht regulärer Weg)
- Bei Musterantrag: klarstellen, dass anpassbar für verschiedene Kommunen

### 2. Antragssatz (Beschlussgegenstand)

Der wichtigste Satz. Konkret, prüfbar, beschlussfähig.

Patterns:
- „Die Gemeinde/Stadt [Ort] möge beschließen, …“
- „Die Verwaltung wird beauftragt, … zu [erstellen/prüfen/erarbeiten/vorlegen]“
- „Der Marktgemeinderat beschließt:“
- „Der Stadtrat möge beschließen:“

Kein Statement, keine Meinung, kein „wir halten fest, dass“. Ein Satz, den die Verwaltung als Auftrag versteht und der Stadtrat als Beschluss fassen kann.

### 3. Spezifizierung / Verwaltungsaufträge

Aufzählung dessen, was konkret geprüft/erstellt/umgesetzt werden soll. Einzelpunkte, damit die Verwaltung abarbeiten kann und der Stadtrat im Follow-up prüfen kann.

Patterns:
- Nummerierte Liste („1. … 2. …“) oder Bullets
- „insbesondere folgende Punkte:“ / „Dabei sollen folgende Anpassungen evaluiert werden:“
- Konkrete Parameter, Bedarfe, Referenzkommunen
- Bei Konzepten: Frist („bis [Datum]“)
- Bei Prüfungen: Berichtspflicht („Der Verwaltung ist bis [Datum] ein Konzept vorzulegen“)

### 4. Begründung

Herzstück. Strukturiert nach:

a) **Ausgangslage / Problem** — was ist der Status quo, was läuft schief?
b) **Aktualitätsbezug** — warum *jetzt*? (Gesetzesänderung, Krise, neue Studie, aktuelles Ereignis, Förderprogramm-Frist)
c) **Wirkung des Antrags** — was bewirkt er? (Wirkungsorientierung, nicht Meinungsbekundung)
d) **Referenzkommunen** — Best-Practice anderer Städte (München, Freiburg, Tübingen wiederkehrend). Erzeugt Legitimation + Machbarkeitsbeweis.
e) **Rechtliche Grundlage** — wenn anwendbar: Satzung, Paragraf, Programm

### 5. Quellen / Anlagen

- Links zu Studien, Richtlinien, Satzungstexten
- PDFs als Anlage (Foerderaufrufe, Musteranträge, Leitfäden)
- Verweise auf bestehende Bestimmungen („die Vollzugsanweisung von 2019“, „§8 Abs.3 Abfallsatzung“)
- Quellenpflicht: jede Aussage mit Quelle + Abrufdatum

### 6. Unterschriftenblock

- „gez.“
- Name, Rolle (Stadträt*in / Fraktionsvorsitzende*r), Fraktion
- Bei interfraktionell: alle Fraktionsvorsitzenden
- Bei Musterantrag: leer für Anpassung

## Antragsarten (Varianten)

| Art | Charakteristik | Antragssatz-Typ |
|---|---|---|
| **Einzelfraktionsantrag** | Eine Fraktion beantragt allein | Standardmuster |
| **Interfraktioneller Antrag** | Mehrere Fraktionen gemeinsam, mehrheitsfähig | Standardmuster + alle Fraktionen im Kopf + Unterschriften |
| **Dringlichkeitsantrag** | Eilbedürftig, Aktualitätsbezug (Gesetzänderung, Krise) | Standardmuster + Dringlichkeitsbegründung |
| **Resolution / Willensbekundung** | Appell-Charakter, an BM gerichtet, kein Verwaltungsauftrag | „Der Rat der Stadt möge sich [X] anschließen / erklärt …“ |
| **Musterantrag** | Generisch, anpassbar für verschiedene Kommunen | Mit Platzhaltern wie „[Gemeinde XY]“ |
| **Antragspaket** | Mehrere verwandte Anträge gebündelt + Glossar | Einzelposten pro Teilantrag |
| **Leitantrag** | Strategische Positionierung, Ideensammlung | Übergeordnete Leitlinien |

## Qualitätskriterien (Gates vor GO)

Bevor der Entwurf der nutzenden Person vorgelegt wird, muss jeder Punkt erfüllt sein:

- [ ] **Beschlussfähiger Antragssatz** — ein Satz, der mit „Die Stadt/Gemeinde möge beschließen…“ oder „Die Verwaltung wird beauftragt…“ beginnt. Konkret genug für die Verwaltung als Auftrag.
- [ ] **Verwaltungsauftrag, nicht Meinungsäußerung** — „Die Verwaltung wird beauftragt, X zu prüfen/erstellen“. Self-Executing ist nicht Ziel — der Stadtrat beschließt den Auftrag, die Verwaltung führt aus.
- [ ] **Aktualitätsbezug** — warum *jetzt*? Wenn keiner erkennbar: Entweder begründen oder auf höhere Dringlichkeitsstufe setzen (Dringlichkeitsantrag).
- [ ] **Referenzkommunen** — Best-Practice anderer Städte (mindestens 1, idealerweise 2-3).
- [ ] **Strukturierte Auftragsliste** — konkrete Einzelpunkte, nicht „prüft mal alles“.
- [ ] **Wirkungsorientierte Begründung** — nicht „weil wir das wollen“, sondern „weil es X bewirkt“ (Wohnraum zurückgewinnen, Investitionshemmnis abbauen, etc.).
- [ ] **Quellen und Material** — Links, PDFs, externe Quellen. Quellenpflicht ist Standard.
- [ ] **Signatur-Block** — formal korrekt, mit Namen + Fraktionszugehörigkeit (oder Platzhalter für Musterantrag).
- [ ] **Adressat klar** — Verwaltungsauftrag vs. Ratsbeschluss vs. Resolution unterscheidbar.

## Workflow

1. **Bedarf aufnehmen** — Was soll beantragt werden? Aus welchem Anlass? Für welche Kommune/das Gremium?
   - Wenn ein `ratsprojekt` existiert: Material aus dem Projekt-Detail lesen (`ratsprojekt_stand`-Skill), das ist die Quellenbasis.
   - Wenn ad-hoc: Material aus Vault (`vault_suche`) oder externer Recherche (`foerdermittel_recherche`, `allgaeuer_zeitung_mcp`) sammeln.

2. **Antragsart bestimmen** — Einzelfraktion / interfraktionell / Dringlichkeit / Resolution / Musterantrag. Wenn unklar: nachfragen.

3. **Material konsolidieren** — Bevor der Antrag entworfen wird, muss das Material vorliegen:
   - Aktualitätsbezug (Datum, Ereignis)
   - Referenzkommunen (Best-Practice)
   - Rechtliche Grundlagen (Satzung, Paragraf)
   - Quellen (URLs, Abrufdatum, PDFs)
   - Bei ratsprojekt: Stand aus `ratsprojekt_stand` + Quellen aus dem Projekt

4. **Entwurf generieren** — nach kanonischer Struktur (Kopf → Antragssatz → Spezifizierung → Begründung → Quellen → Unterschriften).

5. **Gates prüfen** — alle Qualitätskriterien oben. Fehlende Punkte → nachfragen oder ergänzen.

6. **Output als Vault-Notiz** — Entwurf als konsolidierte Vault-Notiz ablegen (Vault = Source of Truth). Noch kein Proposal in ratsprojekte — das ist ein separater Schritt (`ratsprojekt_proposal`-Skill), der auf dem Antrag aufbauen kann.

7. **GO** — Der Entwurf wird vorgelegt. Die nutzende Person entscheidet: anpassen, verwerfen, als Proposal einbringen, direkt beim Ratsbüro einreichen.

## Quellen

Die Muster in diesem Skill basieren auf der Analyse von ~25 realen
Stadtratsanträgen über 15 Kategorien. Die konkreten Volltexte sind bewusst
nicht Teil dieses Skills: Original-Anträge aus internen Antragsportalen
gehören nicht in ein öffentliches Repo. Die Musterbasis ist deshalb
synthetisch und trägt nur die Struktur-Typen der Analyse:

- Musterantrag kirchliche Liegenschaften
- Zweckentfremdungssatzung
- Stellplatzsatzung, interfraktionell
- Resolution nach überregionaler Vorbild-Erklärung
- Entsiegelung von Pausenhöfen
- Dringlichkeitsantrag Baurecht
- Balkon-PV-Förderung
- Klimaneutraler Fuhrpark
- Taschen-Aschenbecher
- Sanitärbus, interfraktionell
- Ratsinfo-System
- Streuobst, interfraktionell
- Ersthelfer-Apps (Musterantrag + Leitfaden)
- Beschaffungsrichtlinie
- Mehrweg-Geschirr
- Musterbausteine für Gemeinwohl und Barrierefreiheit

## Fraktionsspezifische Vorlage (Custom)

Dieser Skill ist bewusst fraktionsneutral. Für fraktionsspezifisches Wording, Unterschriftenblöcke und Programmbezug soll die nutzende Person eine eigene Vorlage im Vault pflegen und vor der Antragsgenerierung einlesen.

Die Vorlage ist über den kanonischen Tag `#antragsvorlage` im Vault auffindbar — unabhängig von Pfad oder Titel.

**Workflow bei Anträgen mit fraktionsspezifischer Vorlage:**

1. Dieser Skill liefert die kanonische Struktur + Qualitätskriterien.
2. Die fraktionsspezifische Vorlage (im Vault der nutzenden Person, getaggt mit `#antragsvorlage`, nicht in diesem Repo) liefert das Wording, den Unterschriftenblock und Varianten.
3. Workflow: zuerst die eigene Vorlage via `vault_suche` (Tag-Suche nach `#antragsvorlage`) oder `obsidian` CLI einlesen, dann mit diesem Skill die Struktur-Gates prüfen, dann befüllen.

## Hinweise

- **Fraktionsneutral als Skelett**: Dieser Skill liefert die Struktur. Eine fraktionsspezifische Vorlage im Vault (nicht Teil dieses Repos) liefert die Ausformulierung. Beide zusammen = vollständige Antragsgenerierung.
- **Tag-Konvention**: `#antragsvorlage` ist der kanonische Tag für fraktionsspezifische Antragsvorlagen. Mehrere Vorlagen (z.B. für unterschiedliche Gremien oder Fraktionen) können denselben Tag tragen — der Skill nimmt dann die erste Treffer oder die nutzende Person wählt explizit.
- **GO-Prinzip**: Die KI entwirft, der Mensch entscheidet. Keine Einreichung ohne GO.
- **Quellenpflicht**: Jede politisch relevante Aussage im Antrag braucht eine Quelle.
- **Keine Schreibzugriffe ins RIS** — Anträge werden beim Ratsbüro eingereicht, nicht im RIS geschrieben.
- **Composable**: Der Skill kann mit `ratsprojekt_stand` (Material aus Projekt), `foerdermittel_recherche` (Finanzierungsquellen), `vault_suche` (Vault-Material) und `ratsprojekt_proposal` (folgender Schritt) kombiniert werden.
