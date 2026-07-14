---
name: foerdermittel_recherche
description: |
  Orchestriert strukturierte Fördermittel-Recherche für kommunale Projekte.
  Nutze diesen Skill immer, wenn nach Fördergeldern, Finanzierung, Eigenanteilen,
  Fördertöpfen, Kumulierungsregeln, Fristen oder Förderkulissen für Projekte
  in der Kommune (insbesondere Buchloe/Bayern) gefragt wird. Auch bei Fragen
  wie „Was kostet das die Stadt?", „Können wir Förderung beantragen?", „Gibt
  es Geld für X?" oder „Können wir uns das leisten?" verwenden. Ebenso wenn
  es um Städtebauförderung, SUMP, KommKlimaFöR, BayFAG, BayGVFG, RZStra oder
  vergleichbare Programme geht. Verwende ihn auch dann, wenn nicht explizit
  das Wort „Förderung" fällt, aber die Frage darauf hinausläuft, wie ein
  kommunales Projekt finanziert werden kann.
---

# Fördermittel-Recherche

## Wann dieser Skill greift

Jede Frage nach Finanzierung, Förderung, Kosten-Eigenanteil oder Fristen für ein kommunales oder lokales Projekt. Auch wenn „Förderung" nicht explizit genannt wird — „Kann die Stadt das leisten?" ist oft eine Förderfrage.

Der Skill aktiviert sich bei konkreten kommunalen Finanzierungsfragen, nicht bei abstrakten „welche Förderungen gibt es generell". Das entspricht dem Problem-first-Prinzip: ein konkretes politisches Problem → KI als Werkzeug zur Lösung.

## Recherchemuster: 5 parallele Stränge

Der Bahnhofstraße-Case hat gezeigt, dass eine gute Fördermittel-Recherche aus fünf parallelen Recherchesträngen besteht. Führe alle fünf durch — einer einzelner Stadtrat kann das nicht sequenziell leisten, aber mit parallelen Tasks ist es in einer Session machbar.

### 1. Finanzierung & Trägerschaft
Wer ist Eigentümer? Wer ist Baulastträger? Welche Finanzierungsmodelle gibt es (Sonderbaulast, Zweckverband, Kommune)? Welche rechtlichen Grundlagen (BayStrWG, BayFAG, BayGO)? Beispiel: Für die Bahnhofstraße war die Schlüsselerkenntnis, dass eine Umstufung auf die Westtangente die Stadt zur Baulastträgerin macht und 85-90% Freistaatsförderung möglich ist.

### 2. Förderprogramme
Welche Förderungen existieren für diesen Projekttyp? Bund, Land, EU. Förderhöhe (%-Sätze), Fördervoraussetzungen, Antragsfristen. Beispiel: SUMP-Förderung (BMDV, bis 90%), Bayerische Städtebauförderung (StMB, 60-90%), KommKlimaFöR (bis 31.12.2026).

### 3. Stand vergleichbarer Konzepte
Gibt es schon ein Verkehrskonzept, ISEK, Bauleitplanung, die relevant sind? Wurde der Antrag schon gestellt? Wo hakt es? Beispiel: In Buchloe wurde 2023 ein Verkehrskonzept gefordert, das nie richtig kam — das ist ein Ansatzpunkt.

### 4. Best-Practices
Welche anderen Kommunen haben Ähnliches umgesetzt? Mit welchen Kosten und Förderungen? Welche Lehren ziehen sich daraus? Beispiel: Plochingen (BW) — Bahnhofstraße neu gestaltet für 890.000€, davon 476.724€ Förderung.

### 5. Rechtliche Rahmenbedingungen & Fristen
Welche Gesetze/Verordnungen sind relevant? Gibt es Antragsfristen? Können Fristen verpasst werden? Kumulierungsregeln prüfen. Beispiel: SUMP-Frist 1. Juni 2026 verstrichen → jetzt KommKlimaFöR und Städtebauförderung.

## Quellen

### Bundesförderung
- **foerderdatenbank.de** — Zentrale Förderdatenbank des Bundes
- **bmv.de** — BMDV (SUMP-Förderung, Radverkehrsprogramme, Lineare Förderung)
- **bafa.de** — Bundesamt für Wirtschaft und Ausfuhrkontrolle (Energie, Sanierung)
- **ktb.de** — Kompetenzzentrum Town & Land (Stadt-Land-Programme)

### Bayerische Förderung
- **stmb.bayern.de/buw/staedtebaufoerderung** — Bayerische Städtebauförderung (60-90%, Bedarfsmitteilung bis 1. Dezember)
- **mobilitaet.bayern.de** — Bayerisches Staatsministerium für Mobilität (BayGVFG, RZStra)
- **bayern.de/foerderwegweiser** — Bayerischer Förderwegweiser
- **art.bayern.de** — Amt für Digitalisierung, Breitbandförderung

### EU-Förderung
- **funding-register.ec.europa.eu** — EU Funding & Tenders Portal
- **eib.org** — Europäische Investitionsbank

### Kommunal-spezifisch
- **gkt-bayern.de** — Gesellschaft für kommunale Aufgaben (bayernweite Programme)
- ** Zukunftsfonds Bayern** — Stadt-Umland-Entwicklung

### Spezifische Programme (aus Bahnhofstr-Recherche)
- **KommKlimaFöR** — Bayerische Kommunale Klimaförderrichtlinie (bis 31.12.2026, bis 90%)
- **SUMP-Förderung** — BMDV „nachhaltig.mobil.planen." (Frist verstrichen 1. Juni 2026)
- **BayGVFG** — Bayerisches Gemeindeverkehrsfinanzierungsgesetz (30-80%)
- **Art. 13f BayFAG** — Sonderbaulast-Modell (70-80%)
- **Art. 13c BayFAG** — Geh-/Radwege an Staatsstraßen (30-80%)
- **Bund-Länder-Städtebauförderung „Lebendige Zentren"** — bis 90%

## Quellenpflicht (nicht optional)

Jede Aussage über Fördermittel muss eine Quelle haben:
- URL der Förderdatenbank / des Programms
- Abrufdatum
- Ggf. Paragrafen (z.B. „Art. 13f BayFAG")

Ein Stadtrat, der „es gibt Fördermittel" ohne Quelle behauptet, ist unglaubwürdig. Ein Stadtrat mit Quellen ist eine Bastion. Das ist nicht „AI generiert was", sondern „AI generiert was mit Beweisen". Bei jedem Förderprogramm, jedem %-Satz, jeder Frist: Quelle angeben. Wenn keine Quelle gefunden werden kann: explizit als „ohne bestätigte Quelle" markieren.

## Kumulierungsregeln prüfen

Förderungen können oft kumuliert werden, aber:
- Es bleibt meist ein Eigenanteil von mind. 10%
- Bundesförderung wird bei Kumulierung nachrangig berücksichtigt
- Frühzeitige Abstimmung mit Fördermittelgeber empfohlen
- SUMP-Bund + KommKlimaFöR-Bayern ist kumulierbar, aber Eigenanteil bleibt

Prüfe explizit, welche Kombinationen möglich sind und rechne den Eigenanteil durch.

## Fristen-Tracking

Extrahiere alle Fristen und markiere sie als TODO:
- Antragsfristen (z.B. „Bedarfsmitteilung bis 1. Dezember")
- Programm-Laufzeiten (z.B. „Förderperiode 2026-2028")
- Kumulierungsfristen

Wenn eine Frist verstrichen ist (wie SUMP 1. Juni 2026), prüfe Alternativen.

## GO-Prinzip: AI berät, Mensch entscheidet

Dieser Skill berät, er entscheidet nicht. Kein Antrag wird automatisch gestellt. Keine Förderung wird beantragt. Der Output ist ein Recherche-Ergebnis, das der Stadtrat prüft, mit der Fraktion diskutiert und dann ggf. in einen Antrag oder eine Anfrage umwandelt.

## Output-Format

Markdown-Report mit dieser Struktur:

```
# Fördermittel-Recherche: [Thema]

## Kurzfazit
(2-3 Sätze, was die Recherche ergeben hat)

## Förderkulisse
| Förderprogramm | Anbieter | Fördersatz | Frist | Quelle |
|---|---|---|---|---|
| ... | ... | ... | ... | URL + Abrufdatum |

## Eigenanteil
(Berechnung mit Beispiel: „Bei 90% Förderung und 120.000€ Bruttokosten
bleiben 12.000€ Eigenanteil")

## Kumulierungsregeln
(Was kann kombiniert werden? Was nicht? Welche Nachrangigkeit?)

## Best-Practices
(Andere Kommunen, die Ähnliches umgesetzt haben, mit Quelle)

## Fristen & nächste Schritte
- [ ] TODO: Bedarfsmitteilung bis 1. Dezember
- [ ] TODO: Abstimmung mit Fördermittelgeber
- [ ] TODO: ...

## Offene Fragen
(Was konnte nicht geklärt werden? Was braucht weitere Recherche?)

## Quellen
(Vollständige Liste aller URLs + Abrufdaten)
```

## Kontext: Wer diesen Skill nutzt

Carsten ist Stadtrat in Buchloe (Grüne, Listenplatz 3) und Co-Sprecher der Grünen Buchloe. Die Recherche dient der Sitzungsvorbereitung, Antragsformulierung und Fraktionsarbeit. Der Output muss für Fraktionskolleg:innen verständlich sein, die kein CLI/RAG nutzen.
