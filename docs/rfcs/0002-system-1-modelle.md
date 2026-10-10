# RFC 0002: System-1-Modelle für typisierte Entscheidungen im AI-Harness

| Feld | Wert |
|---|---|
| Status | Draft, Revision 4 |
| Stand | 2026-10-02 |
| Gegenstand | Einsatz nicht-generativer Entscheidungsmodelle („System-1-Modelle“) für die typisierten Urteile des AI-Harness |
| Modus | Entscheidungs- und Planungsdokument. Es wird kein Code gebaut. Die roten Linien (Abschnitt 5) gelten ab GO; die Pilotdurchführung (Abschnitt 7) braucht ein eigenes GO (Repo-Prinzip 7) |

> **Wo setzt dieses Projekt nicht-generative Entscheidungsmodelle ein, wo verbieten wir sie uns, und unter welchen Bedingungen?**

## Zusammenfassung

System-1-Modelle nehmen unstrukturierten Zustand auf (Snippet, Titel, Mail) und liefern typisierte Antworten statt frei generierter Prosa; Begründung und Quellenangabe fehlen bewusst.[^jev] Jev und Laya waren die Ausgangspunkte dieses RFC.[^laya] Die lokalen Versuche mit SemIf und Kev erweitern den Vergleich um eingefrorene LLM-Optionslogits und LoRA-Pointerheads (Anhang B). Typisierte Scores garantieren weder richtige noch kalibrierte oder wiederholbare Urteile.

Der Befund für dieses Repo weicht vom Hype ab. Die Antragsreife-Spezifikation definiert seit Monaten eine dreistufige Entscheidungsarchitektur aus deterministischen Regeln, einer ausdrücklich modellbewerteten Mittelstufe und einer menschlichen Stufe. Nur ist die Mittelstufe mit der Tagesform eines frontier LLM besetzt: unkalibriert, nicht reproduzierbar, nicht protokolliert. Ein System-1-Modell ist deshalb hier kein Paradigmenwechsel, sondern die disziplinierte Besetzung eines vorhandenen Slots.

Wir entscheiden uns für lokale Inferenz statt externer API; die Backendwahl bleibt vorläufig offen. Vault-Ausschnitte und Emails sind nicht-öffentlich und dürfen die Datenschutz-Grenze nicht verlassen. Laya bleibt eine versionierte experimentelle Baseline, SemIf und Kev sind explorativ getestet, keine freigegebenen Produktionsbackends. Der Einstieg ist die Relevanz-Triage beim Sammeln, nicht die Antragsreife. GO-Kette, politische Kriterien und Quellenpflicht bleiben vollständig beim bisherigen Verfahren. Backendwahl und automatisches Gating brauchen workloadbezogene Validierung auf einem unangetasteten Holdout und ein separates explizites GO. Die zunächst 30 bis 50 echten handgelabelten Fälle sind ein Entwicklungsbudget, kein Kalibrierungsnachweis. Ein Abbruch deaktiviert den tatsächlichen Adapter; private Eingaben bleiben auch im Fallback lokal.

Eine Grenze gehört in diese Zusammenfassung. Frequenz, Latenz und Kosten, die üblichen Verkaufsargumente der Klasse, tragen bei einem einzelnen Stadtrat am wenigsten. Konsistente und workloadgerecht kalibrierte Urteile sind prüfbare Ziele für die Sammel-Workflows, keine Eigenschaft der Klasse. Hintergrundbetrieb ohne laufende Session bleibt eine spätere Option (Abschnitt 4.3).

## 1. Kontext

### 1.1 Was System-1-Modelle sind

Der Name stammt von Daniel Kahneman: System 1 ist das schnelle, intuitive Urteil, System 2 das langsame, bewusste Schließen.[^jev] Hier bezeichnet er einen typisierten Readout gegen einen Eingangszustand, nicht bloß ein schnell antwortendes Sprachmodell. Dazu gehören Encoder mit Entscheidungsköpfen, eingefrorene LLMs mit Optionslogits und LoRA-Pointerheads.[^semif][^kev] Jev beschreibt den Dienst mit der Formel „unstructured state in, typed probabilistic decisions out“.[^jev] Frei generierte Prosa entfällt, Fehlklassifikationen bleiben möglich. Auch Begründung und fachlicher Quellenbeleg fehlen; Kalibrierung und Konsistenz müssen für die tatsächliche Konfiguration geprüft werden.

Der folgende Quellenvergleich ist auf Jev und Laya nach dem Abrufstand vom 2026-09-24 begrenzt. Die eigene lokale Vergleichsmessung weiterer Kandidaten steht in Anhang B.

| | Jev (TypeSafe) | Laya (offen) |
|---|---|---|
| Zugang | API, Early Access | offene Gewichte, Apache-2.0, `pip install laya` |
| Größe | nicht veröffentlicht | ModernBERT-large, 421 Mio. Parameter gesamt; mmBERT-base, 322 Mio. |
| Sprachen | offen | über 100, Deutsch eingeschlossen |
| Latenz | 70–500 ms End-to-End | 33 ms pro Frage auf einer T4; 193–464 ms auf CPU |
| Schnittstellen | `POST /v1/systemone` | CLI, FastAPI, optionaler MCP-Server, Jev-kompatibler Self-Host |
| Transparenz | Gewichte und Paper unveröffentlicht, Benchmarks gehedgt | Trainingsrezept, Daten und Benchmarks veröffentlicht |
| Trainingslabels | offen | ausschließlich menschliche Labels[^devto] |

Die damaligen Veröffentlichungen beschreiben RLCD (Reinforcement Learning for Calibrated Decisions), das Kalibrierung im Training belohnt.[^jev][^laya] Das ist kein gemeinsames Trainingsrezept aller Kandidaten. Layas eigener Benchmarkabstand zwischen Zero-Shot (0,362) und Fine-Tuning (0,766) betrifft dessen Testaufgaben, nicht unsere deutsche Triage oder eine universelle Grenze der Klasse.[^laya]

### 1.2 Warum das Thema dieses Repo erreicht

Der AI-Harness fällt in jeder Session Dutzende kleiner Urteile. Ist dieser Vault-Treffer relevant? Passt dieser Artikel zu diesem Tagesordnungspunkt? Eignet sich diese Quelle für ein ratsprojekt? Heute beantwortet das frontier LLM diese Fragen nebenbei, in Prosa, ohne dass die Antwort gespeichert oder später verglichen werden könnte. Die Sammel-Workflows schreiben bereits Obergrenzen gegen Overfetching vor (höchstens 5–7 Vault-Notizen, höchstens 2–3 Artikel je TOP), aber die Grenzen hält Prosa-Disziplin, nicht ein Messwert (skills/vault_suche/SKILL.md:96–105; skills/sitzungsvorbereitung/SKILL.md:150–154).

Gleichzeitig erzeugt das Projekt maschinenlesbare Entscheidungshistorie. Proposal-Annahme und -Ablehnung sind jedoch keine Relevanzlabels. Goldlabels entstehen nur durch menschliche Bewertung der tatsächlichen Triage-Frage in ihrem Kontext, etwa bei einer Korrektur von „ja/nein/vielleicht“. Bislang ist diese Historie nicht als Datensatz organisiert; Abschnitt 4.3 beschreibt eine spätere Möglichkeit.

## 2. Analyse

### 2.1 Die Architektur ist vorbereitet

Die Antragsreife-Spezifikation ist faktisch bereits ein Decision-Model-Entwurf mit drei Stufen:

| Stufe | Inhalt | Bewertung durch | Beleg |
|---|---|---|---|
| Deterministisch | Hard Gates: Quelle mit URL und Abrufdatum, Adressat, Beschlussvorschlag (mehr als 20 Zeichen), Realisierungsstrang vorhanden, Vorbedingungen erfüllt | Elixir-Code | check_antragsreife.ex:111–225 |
| Modell | Soft Gates: Finanzierung angesprochen, rechtliche Grundlagen genannt, Fristen gesetzt | ausdrücklich „der LLM des AI-Harness“ | antragsreife_kriterien.md:35–46; check_antragsreife.ex:254–272 |
| Mensch | Tonalität, Konsensfähigkeit, Widerspruch zur Fraktionsposition | Stadtrat; die KI bewertet sie nicht | check_antragsreife.ex:276–294 |

Die Modellstufe ist der natürliche Anknüpfungspunkt dieses RFC. Sie ist spezifiziert, aber nicht diszipliniert: Das große LLM beantwortet sie beiläufig, ohne Konfidenzangabe, ohne Protokoll. Wer dieselbe Frage nächste Woche stellt, kann eine andere Antwort erhalten, ohne dass es jemand bemerkt.

Zwei der sieben spezifizierten Hard Gates sind Code-Wirklichkeit noch nicht. Value Proposition und Success Metrics prüft bis zur Umsetzung von Roadmap-Punkt 9 (Issue #37) der Skill policy-seitig (AGENTS.md:163; workflows.md:389; skills/ratsprojekt_proposal/SKILL.md:102–103). Der unscharfe Mittelbau ist damit heute größer als die drei Soft Gates. An der Reihenfolge dieses RFC ändert das nichts.

Die Stufenarchitektur ist kein Einzelfall. Das gesamte Repo spricht typisierte Entscheidungen: `pass|fail|warn` im Antragsreife-Check, `pending` und `approved|rejected` im Proposal-Flow, `unchecked` für die politischen Kriterien, „ja/nein/vielleicht“ in den Triage-Skills, propose→decide als Eintrittspunkt für jedes menschliche GO. Ein System-1-Modell einzuziehen heißt daher, eine bestehende Schnittstelle anders zu besetzen. Es heißt nicht, eine neue Kategorie „KI-Entscheidung“ zu erfinden.

### 2.2 Das Frequenzproblem

Das Verkaufsargument der Modellklasse lautet Massenfrequenz bei Millisekundenlatenz zu Bruchteilen der LLM-Kosten. Für dieses Repo gilt das nur eingeschränkt. Ein einzelner Stadtrat erzeugt vielleicht ein bis fünf Proposals im Monat und eine handvoll Förderrecherchen im Quartal. Der klassische Massenbetrieb, für den Jev wirbt, existiert hier an genau einer Stelle: dem noch zu bauenden Sync-Diff (Abschnitt 4.3).

Die prüfbaren Ziele liegen woanders:

- **Konsistenz.** Gleiche Eingaben sollen unter eingefrorener Konfiguration zu gleichen Urteilen führen. Runtime-, Präzisions- oder Schemawechsel erfordern neue Prüfungen.
- **Kalibrierung.** Ein Score soll die Fehlerwahrscheinlichkeit im tatsächlichen Workload brauchbar abbilden. Ein typisierter Readout bedeutet nicht, dass das Modell „weiß nicht“ kennt. Eskalationsregeln brauchen eigene Validierung.
- **Protokoll.** Jedes Urteil ist ein Log-Eintrag statt einer vergessenen Prosa-Zeile. Aus dem Protokoll wächst die Label-Historie, die Abschnitt 6.4 als Option führt.

Latenz ist im laufenden Session-Betrieb kein Erfolgskriterium, und die Kosten sind bei diesem Volumen ein Nebenposten. Wer den Pilot mit einem dieser beiden Posten begründet, begründet ihn falsch.

## 3. Entscheidung

**E1. Lokale Inferenz statt externer API; Backendwahl vorläufig offen.** Die Datenschutz-Grenze (AGENTS.md, Prinzip 8) verbietet die Übermittlung nicht-öffentlicher Unterlagen an externe Dienste. Vault-Ausschnitte und Emails bleiben lokal; der Delta-Skill bindet ausdrücklich „Email / Brief / Gesprächsinhalt“ ein (skills/ratsprojekt_delta/SKILL.md:48–49). Laya bleibt die versionierte experimentelle Baseline. SemIf und Kev erweitern den lokalen Vergleich, sind aber keine freigegebenen Produktionsbackends. Auswahl und operatives Gating brauchen den workloadbezogenen Holdout aus Abschnitt 7 und ein separates explizites GO. Diese Aktualisierung erteilt keine Rollout-Freigabe.

**E2. Der Einstieg ist die Relevanz-Triage beim Sammeln** (Abschnitt 4.1), nicht die Antragsreife. Der Grund ist schlicht: nirgendwo sonst fällt so oft ein so scharf typisiertes Urteil.

**E3. Die roten Linien (Abschnitt 5) gelten ab GO unbefristet**, unabhängig vom Ausgang des Piloten. Sie sind das Ergebnis der Analyse, nicht der Ausbaustufe.

**E4. Die Schema-Arbeit für Querverweise (Lücke #32) wird modell-agnostisch und unabhängig von diesem Pilot gebaut** (Roadmap-Punkt 6; workflows.md:387). Das Modell ist ein austauschbarer Vorschlagserzeuger, nicht der Kern des Fixes.

**E5. Ein Pilot startet nur mit Instrumentierung.** Lokales Log ab Tag 1, zunächst 30 bis 50 echte, vor Einsicht in Modellscores handgelabelte Entwicklungsfälle und ein disjunkter unangetasteter finaler Holdout. Diese Startgröße belegt keine ausreichende Kalibrierung. Erfolgskriterien und Abbruch regelt Abschnitt 7.

**E6. Fine-Tuning ist Option, nicht Plan.** Nur menschliche Labels für den tatsächlichen Triage-Kontext bilden die Label-Historie; Proposal-Annahme oder -Ablehnung ist kein automatisches Goldlabel. Ein frontier-Urteil dient ausschließlich als Vergleich. Die grob geschätzten 200 bis 1500 Bewertungen pro Jahr garantieren keinen ausreichenden Trainingsdatensatz. Für eine spätere Anpassung wären getrennte Entwicklungsdaten und Holdout erforderlich; dieser RFC beschließt sie nicht.

## 4. Einsatzorte in Ausführungsreihenfolge

| Rang | Kandidat | Urteil | Frequenz | Phase |
|---|---|---|---|---|
| 1 | Relevanz-Triage beim Sammeln | relevant ja/nein, Score | 50–300 Urteile je Sitzungsvorbereitung | Pilot |
| 2 | Querverweise TOP und Ratsprojekt | passt ja/nein | 10–20 TOPs gegen 5–10 aktive Projekte je Sitzung | nach dem #32-Schema |
| 3 | Sync-Diff, „was ist neu für mich?“ | relevant je Paar | periodisch, ohne laufende Session | nach Pilot und #32 |
| 4 | Soft Gates der Antragsreife | dreimal erfüllt ja/nein | wenige Aufrufe pro Woche | Phase 2 |
| verworfen | Delta-Klassifikation, Fördertopf-Matching | siehe 4.5 | niedrig bzw. begründungslastig | kein Einsatz |

### 4.1 Relevanz-Triage beim Sammeln

Drei Aufrufstellen, ein Entscheidungstyp: die Vault-Treffer der Suche (höchstens 5–7 Notizen, skills/vault_suche/SKILL.md:97), die AZ-Artikel je TOP (höchstens 2–3, skills/sitzungsvorbereitung/SKILL.md:150–154) und der Vault-Durchlauf der Sitzungsvorbereitung (:172–174). Eine volle Sitzungsvorbereitung erzeugt 50 bis 300 Einzelurteile; das ist die höchste Frequenz im ganzen Repo.

Die Eignung hat drei Gründe. Das Urteil ist scharf typisiert und trotzdem unscharf definiert, genau die Kombination, für die Regeln zu spröde und frontier LLMs zu verschwenderisch sind. Der Schmerz ist vom Repo selbst dokumentiert: „Overfetching vermeiden“ steht an drei Stellen, die Obergrenzen werden aber von Prosa-Disziplin gehalten. Und die Begründungspflicht („Warum relevant? 1–2 Sätze“, vault_suche:123) bleibt beim LLM, denn das Modell hat keinen Erklärungskanal.

Die geplante Integration ruft den geprüften lokalen Adapter pro Snippet auf. `laya_predict` ist eine dokumentierte, hier ungetestete MCP-Option für Laya; SemIf wurde per CLI und Kev per typisiertem HTTP getestet (Anhang B). Ohne validierte modellbezogene Gate-Konfiguration bleibt der Treffer erhalten und geht zur menschlichen Prüfung. Unterhalb einer später validierten Schwelle oder im „vielleicht“-Band gilt Abschnitt 6.2: Für private Eingaben sind ausschließlich der Mensch oder eine ausdrücklich freigegebene lokale Alternative zulässig. Eine implizite Cloud-Frontier-Route ist verboten. Eine freigegebene Verwerfung erscheint weiterhin als sichtbare „ausgefiltert“-Zeile; das „Nicht gefunden“-Prinzip der Vault-Suche (vault_suche:131) bleibt erhalten.

### 4.2 Querverweise zwischen TOP und Ratsprojekt

Heute entsteht der Querverweis per Ad-hoc-Titelvergleich, dokumentiert als Lücke #32 (skills/sitzungsvorbereitung/SKILL.md:176–190; workflows.md:387). Dass dabei Treffer verloren gehen, ist belegt: Der Fall „Gansbichl“ scheiterte an der Titelähnlichkeit (sitzungsvorbereitung:130–132). Der Schaden bleibt klein, solange die Ausgabe als „(ad-hoc, nicht bestätigt)“ markiert wird (:369).

Wichtig ist die Einordnung: #32 ist primär eine Schema-Lücke (`ris_sitzung_id`, `ris_top`, `beschluss_nr` fehlen), keine Modell-Lücke. Der Entwurf lautet deshalb: deterministische Kandidaten-Generierung per Stichwortüberdeckung, dann Bewertung, dann menschliches Bestätigen. Bestätigte Links werden deterministische Datenbankeinträge. Ein Modell kann später als Bewertungskomponente einrücken, wenn der Pilot es validiert hat; es kann die Schema-Arbeit nicht ersetzen.

### 4.3 Sync-Diff, „was ist neu für mich?“

Hier könnte das Batch-Muster nützlich werden. Nach einem künftigen Hintergrundlauf von `ratsinfo sync` sollen neue Tagesordnungspunkte gegen aktive Projekte bewertet werden (workflows.md:155–159, Lücke #33). Titelregeln sind dokumentiert spröde; ein warmes LLM steht ohne Session nicht bereit. Die gemessenen lokalen Latenzen sind Hinweise für ein Zeitbudget, kein Nachweis eines unbeaufsichtigten Betriebs. Backend, Speicherbedarf und Adapter wären dafür gesondert zu prüfen.

Der Bestätigen-und-Verwerfen-Loop der Alerts könnte menschliche Relevanzlabels im größeren Maßstab liefern (geschätzt 50 bis 300 Paare je Sync), sofern Frage und Kontext mitgeführt werden. Weil die Pipeline noch nicht existiert, kann dieser Platz nicht der erste Schritt sein. Er ist ein Grund, die Labels ab Tag 1 sauber zu führen.

### 4.4 Soft Gates der Antragsreife

Der Slot existiert per Spezifikation, ist non-blocking (antragsreife_kriterien.md:99–100) und wird nur wenige Male pro Woche benutzt. Für den Pilot ist das zu wenig Frequenz. Später ließe sich die Wiederholbarkeit der „Antragsreife steigt oder sinkt“-Aussage des Delta-Skills (ratsprojekt_delta/SKILL.md:85) unter eingefrorener Konfiguration prüfen.

Vorab ist zu zerlegen, was gar kein Modell braucht. `fristen_gesetzt` ist halbdeterministisch: Das Vorhandensein einer Schrittfrist ist eine Datenbankabfrage, unscharf bleibt nur der Realismus der Frist (check_antragsreife.ex:269).

### 4.5 Verworfene Kandidaten

Die **Delta-Klassifikation** (acht Kategorien, ratsprojekt_delta/SKILL.md:78–87) verfällt. Es gibt wenige Deltas im Monat, die Kategorie ist das Ergebnis der eigentlichen Kreuzreferenzarbeit, die das LLM in jedem Fall leisten muss, und jede Zeile des Berichts trägt eine Begründung unter Quellenpflicht. Dazu kommt das schlechteste Verteilungsprofil: feine deutsche Verwaltungssemantik, acht feine Klassen, nie genug Label.

Das **Fördertopf-Matching** verfällt ebenfalls. Es ist selten, der harte Kern ist Arithmetik (Eigenanteil mindestens 10 Prozent, Nachrangigkeit) oder Datumsvergleich, und der Rest ist hochriskant und quellenpflichtig. Eligibility wird aus der Richtlinie argumentiert, nie aus einer Modellwahrscheinlichkeit (skills/foerdermittel_recherche/SKILL.md:73–90).

## 5. Rote Linien

In den folgenden Regeln bezeichnen MUSS und DARF NICHT Anforderungen an jede künftige Umsetzung, wie in RFC 0001, Abschnitt 1.3.

**R1. GO-Kette.** Ein Modell DARF NICHT an der GO-Entscheidung teilhaben, sie vorbereiten, gewichten oder verschönern. `decide_proposal` bleibt reines Elixir plus menschliches GO (pending_proposal.ex:78–83; server.ex:19–36). Das Modell MUSS vor der propose→decide-Kette sitzen, niemals darin. Auch ein „Proposal-Qualitätsscore“ ist unzulässig; die Hard Gates und die menschliche Prüfung machen ihn überflüssig.

**R2. Politische Kriterien.** Tonalität, Konsensfähigkeit und Widerspruch zur Fraktionsposition DARF kein Modell bewerten (check_antragsreife.ex:276–294). Konsensprognosen in einem kleinen Gremium sind unvalidierbar und berühren die Fraktionsposition. Diese Stufe ist dem Menschen vorbehalten, nicht als Kür, sondern per Spezifikation.

**R3. Quellenpflicht.** Keine Aussage mit politischem Gewicht DARF aus einem Modell stammen. Das Modell hat keinen Provenance-Kanal; URL und Abrufdatum kommen aus den Tools. Interne Triage (welche Notiz gelesen wird) ist Routing und damit quellenfrei. Trotzdem MUSS jede hoch-konfidente Verwerfung als „ausgefiltert“ sichtbar bleiben. Würde das Filtern still geschehen, könnte ein systematisch verzerrtes Modell ganze Quelltypen unbemerkt verschwinden lassen.

**R4. Deterministische Domänen.** Hard Gates bleiben Elixir. Der Wert für Value Proposition und Success Metrics wird über Roadmap-Punkt 9 (Datenbankfelder, Issue #37) gelöst und DARF NICHT durch ein weiches Modellurteil über „Konkretheit“ ersetzt werden. Eine Zeichenlängenprüfung plus menschliches Urteil ist einer Wahrscheinlichkeit von 0,8 überlegen.

**R5. Modellfreiheit der Elixir-Apps.** `check_antragsreife` verspricht „Keine LLM-Calls in diesem Tool“ (check_antragsreife.ex:14). Sollte die Modellstufe je maschinell bewertet werden, MUSS der Harness die Bewertung gegen den Report des Tools ausführen. Das Tool selbst bleibt deterministisch und erfährt nichts von der Existenz eines Modells (Unix-Prinzip).

**R6. Einzelfälle.** Seltene, kontextgesättigte Entscheidungen bleiben beim frontier LLM mit menschlichem GO: die Wahl des Proposal-Typs, Statuswechsel-Empfehlungen, die Antragsreife-Prognose. Ein typisierter Entscheidungskopf dafür wäre Technik-Faszination (Repo-Prinzip 4).

## 6. Integration

### 6.1 Beschaffung und Ablage

| Baustein | Ablage | Bemerkung |
|---|---|---|
| Modell und Runtime | externe Abhängigkeit außerhalb der Elixir-Apps | tatsächliche Gewichte, Backend und Schnittstelle vor Workflow-GO prüfen |
| Frage-Schemas | versioniert in den Skills und diesem RFC | vollständiger Triage-Kontext, Fragetext, Label-IDs, Beschreibungen und Reihenfolge |
| Pilot-Betrieb | Harness als Treiber, lokales Manifest und Log | CLI, HTTP oder geprüfter MCP-Adapter; noch keine Implementierung beschlossen |
| Ausbaustufe | optionaler backendbezogener Wrapper unter `tools/` | nur bei belegtem Bedarf; Python-Präzedenz: pdf_ingest, allgaeuer_zeitung_mcp |

„Null Repo-Code“ oder „ein MCP-Eintrag“ ist keine backendweite Zusage. Layas MCP-Pfad ist dokumentiert, aber hier nicht operativ geprüft. SemIfs CLI ist bereits eine AI-Schnittstelle; MCP würde einen zusätzlichen Adapter brauchen. Kevs lokales `POST /v1/systemone` ist getestet, eine MCP-Anbindung nicht. Ein einfacher Harness-Treiber genügt als Plan, ohne RAG oder Servicebus. Modell und Runtime bleiben außerhalb der Elixir-Apps. Vor einem genehmigten Rollout sind die nötigen Änderungen zuerst in docs/prerequisites.md und docs/workflows.md zu dokumentieren; dieser Draft ändert weder diese Dokumente noch tatsächliche Workflows, Lifecycle oder Konfiguration.

### 6.2 Konfidenz-Gating

Das Muster lautet Modell, benannter Score, validierte Schwelle, Eskalation. Technische Abstention ist ein Fallback, kein GO. Unbekannte Konfiguration, fehlende Provenienz oder unvalidiertes Gating bedeutet: keine automatische Filterung, alle Treffer behalten und menschlich prüfen. Eine Gate-Policy braucht Workload, vollständiges Schema, Konfiguration und Scoredefinition als eingefrorene Version. Recall und sichtbare Verwerfungen bleiben vorrangig.

Für das Laya-Beispiel MUSS ein später validiertes Gate auf dessen entropiebasierter `confidence` = 1 − H(p)/log k beruhen, nicht auf `act_probability`. Die dokumentierten AUROC-Werte 0,77 und 0,30 sowie das im lokalen Versuch konstante `act_probability` = 1,0 sind Laya-spezifische Befunde, keine Eigenschaft aller Modelle.[^laya][^laya-pilot] SemIf liefert einen unkalibrierten bedingten Options-Softmax. Kev berechnet die Choice-Confidence als (K·p_max − 1)/(K − 1), wobei p_max der größte Optionsscore und K die Zahl der Optionen ist. Sein gespeichertes englisches T = 2,406050072164233 validiert deutsche Confidence nicht.[^semif][^kev-card] Gemeinsame Schwellen oder ein τ-Transfer sind unzulässig; n12 liefert kein Gate.

Für nicht-öffentliche Vault- oder Mail-Eingaben MUSS die Eskalation menschlich oder über eine ausdrücklich freigegebene lokale Alternative erfolgen. Sie DARF NICHT implizit an einen Cloud-Frontier-Dienst routen. Nur öffentliche, für diesen Weg freigegebene Eingaben können den bisherigen Frontier-Pfad nutzen. Logs bleiben lokal und kontrolliert.

### 6.3 Bekannte Schwächen der Modellklasse

Vier dokumentierte Laya-Schwächen gehen ins Risiko-Register; sie sind keine allgemeine Eigenschaft der Modellklasse:

- Das `noul`-Problem: Das Modell folgt teils den Label-Wörtern statt dem Inhalt (Issue #156). Für ja/nein/vielleicht-Köpfe ist das eine direkt einschlägige Schwäche.
- Positions-Bias im mehrsprachigen `score` (Issue #131). Die Eingaben hier sind überwiegend kurze deutsche Titel, also genau das betroffene Profil.
- `score` ist der schwächste Fragetyp der Benchmark.
- Kalibrierung gilt pro Domäne. Eine auf Vault-Snippets validierte Schwelle überträgt sich nicht auf AZ-Schlagzeilen oder TOP-Titel; kurze Verwaltungstitel wie „Umbenennung Gansbichl“ gehören deshalb absichtlich in den Goldstandard.

Für Laya sind falsche Urteile mit hoher Konfidenz dokumentiert: 0,952 Konfidenz bei 0,000 Genauigkeit auf einer nicht trainierten Sprache.[^laya] Die Konsequenz steht in R3 und Abschnitt 7: nie still filtern, Verwerfungen sichtbar halten und bei Ausfall ohne implizite Cloudroute prüfen lassen.

Das Schema versioniert den vollständigen Fragetext samt Triage-Kontext, Label-IDs, Beschreibungen und Optionsreihenfolge. Laya reagierte auf Labelwörter. Bei SemIf wurden IDs nicht gerendert und ID-only-Scores blieben gleich; bei Kev stehen IDs im Optionstext und veränderten Scores. Orderwechsel änderten bei beiden Scores, auch wenn klare Kontrolllabels stabil blieben (Anhang B). Runtime-Ports erben daraus keine Wiederholungsgarantie.

Ein kleines lokales Manifest samt JSONL-Log hält tatsächliche Source- und Modellrevisionen mit Datei-Hashes, geladenes Backend, Runtime, dtype oder Quantisierung, T beziehungsweise Kalibrierungsrevision, vollständige Schemaversion, Scoredefinition, p-Vektor, Cachepolicy und -zustand sowie Timerdefinition fest. Technische Modellprovenienz ersetzt keinen fachlichen Quellenbeleg nach R3. Layas Routing wird wie in A.1 geprüft; Kevs `kev-latest` ist nur ein Alias und braucht die geladenen Metadaten mit unveränderlicher Revision. Keine erfundene normalisierte Universal-Confidence und keine zusätzliche Infrastruktur.

### 6.4 Ausbaustufe

Zwei Möglichkeiten bleiben ausdrücklich Optionen. Ein backendbezogener Wrapper für Presets, Logging und Schemaschutz wird nur bei Bedarf relevant; CLI ist bereits zulässig, MCP keine Pflicht. Das Fine-Tuning eigener Entscheidungsköpfe nach dem stuntd-Muster (eingefrorener Encoder, kleiner trainierter Kopf auf eigenen Labels) hängt an echten Triage-Labels aus E6. Die referenzierte Verbesserung von 89,5 Prozent auf 100 Prozent stammt aus einer zwölf-Klassen-Aufgabe ohne veröffentlichte Zeilenzahl und ist daher als Richtung lesbar, nicht als Versprechen.[^stuntd]

## 7. Der Pilot

Ein operativer Pilot läuft nach eigenem GO zwei bis vier Wochen in echten Sitzungsvorbereitungen (Workflow 1). Zunächst bleibt er im Shadow-Modus: alle Treffer behalten und menschlich prüfen, solange ein Gate nicht validiert ist. Er misst, ob weniger Overfetching ohne Recallverlust erreichbar ist. Die bereits eingesehenen zwölf synthetischen Titel aus Anhang B sind ausschließlich für Exploration und Regression verwendbar und vom finalen Test ausgeschlossen.

Drei Auflagen sind Bestandteil des Starts:

1. **Log je Entscheidung:** kontrolliertes lokales Log nach 6.3, möglichst Eingabereferenz statt Volltext, menschliches Triage-Label und gegebenenfalls das Frontier-Urteil als gesonderter Vergleich. Goldlabels bleiben menschlich.
2. **Entwicklung und finaler Holdout:** Zunächst 30 bis 50 echte Fälle aus dem jeweiligen Vault-, AZ- oder TOP-Kontext vor Einsicht in Modellscores menschlich labeln. Das ist ein Entwicklungsbudget, keine ausreichende Kalibrierungsmenge per Zusage. Auf Entwicklungsdaten Modell und Schema wählen, gegebenenfalls T und τ anpassen. Einen disjunkten unangetasteten finalen Holdout reservieren oder später sammeln, gruppiert nach Dokument, Ereignis und nahen Duplikaten. Konfiguration und Kriterien vor Test einfrieren. Wer nach Holdout-Ergebnissen nachjustiert, macht diese Fälle zu Entwicklungsdaten und braucht einen neuen Test.
3. **Prosa-Konformität:** Skills sind Text, nichts erzwingt die Konsultation des Modells bei jedem Schritt. Das Ausgabeformat MUSS die benannten modellbezogenen Scores und die Konfiguration verlangen; fehlende oder unvalidierte Angaben erlauben keine automatische Filterung.

Erfolgskriterien, in dieser Reihenfolge: Konsistenz unter eingefrorener Konfiguration; Recall und falsch verworfene relevante Treffer gegen menschliches Gold; Overfetching ohne Recallverlust; Coverage und Eskalationsquote. Der Recall darf gegenüber dem bisherigen freigegebenen Triagepfad nicht sinken. Beide werden auf denselben Holdout-Testfällen gegen menschliches Gold bewertet. Für private Eingaben gilt dabei unverändert die lokale Datenschutz-Grenze aus 6.2. Klassenfallzahlen und Unsicherheit gehören zum Bericht, das Frontier-LLM bleibt nur Vergleich. Eine Eskalationsquote unter etwa zwei Dritteln ist ein Planungsziel, kein Sicherheitsnachweis. Wenige Fälle oder unsichere Recallbefunde bedeuten Shadow-Betrieb und weitere Labels, kein zertifiziertes Gate. Schwellen übertragen sich nicht zwischen Vault, AZ und TOP.

Der Abbruch deaktiviert den tatsächlichen Backendadapter und dessen Gate-Konfiguration, ob CLI, HTTP oder MCP. Alle Treffer bleiben erhalten; private Eingaben gehen an den Menschen oder eine freigegebene lokale Alternative. Goldlabels und lokale Logs bleiben für spätere Versuche verwertbar. Ein MCP-Eintrag allein ist keine allgemeine Rückbauanleitung.

## 8. Konsequenzen

**Positiv.** Ein versionierter Readout und ein lokales Log können die Triage nachvollziehbarer machen. Wiederholbarkeit und Kalibrierung bleiben zu prüfende Ziele. Echte menschliche Triage-Labels helfen späteren Versuchen; Sync-Diff und Fristen- oder Beschlussverfolgung bleiben separate Vorhaben.

**Lasten.** Version, tatsächliche Gewichte, Runtime, Schema und workloadbezogene Gate-Policy des gewählten Backends wollen gepflegt sein. Das Loggen ist eine Disziplinpflicht, und das Erwartungsmanagement gehört dazu; „KI-Triage“ ist ein begrenzter Vorschlag, kein belegtes Ergebnis.

**Neutral.** Die Elixir-Apps bleiben modellfrei. Präzisere Skill-Formulierungen und benannte Scorefelder wären erst Teil einer gesondert genehmigten Integration; dieser Draft ändert keine Skills oder Konfiguration.

## 9. Offene Fragen

1. Welches lokale Backend erreicht auf echten kontextbezogenen deutschen Triage-Fällen genügend Recall? Anhang B beantwortet nur die synthetische Zwölfer-Fixture.
2. Tragen Obsidian-Suchsnippets genug Kontext für den gewählten Readout?
3. Folgt das Harness der Skill-Prosa zuverlässig, und funktioniert der gewählte CLI-, HTTP- oder MCP-Adapter? Konformität und Integration sind gesondert zu prüfen.
4. Welche Alert-Frequenz des Sync-Diffs erträgt ein einzelner Stadtrat (#33)?
5. Nebenbefund der Analyse: `skills/bericht_aus_dem_stadtrat` wird in workflows.md:371 referenziert, existiert aber nicht. Der Dokument-Drift ist unabhängig von diesem RFC zu beheben.

## Anhang A: Laya-Pilot-Skizze (am 2026-09-24 experimentell geprüft)

Dieser Anhang dokumentiert Laya 0.3.20 auf macOS arm64 und CPU, geprüft am 2026-09-24, nicht eine backendweite Betriebsvorgabe.[^laya-pilot] Die damaligen Quellen waren Laya-README[^laya], laya-serve[^layaserve], stuntd[^stuntd] und hs-jev[^hsjev]. Das Pip-Paket brachte `fastapi` und `uvicorn` nicht mit; beide waren für `python -m laya.serve` nachzuinstallieren. A.1 zeigt gemessene Request- und Responsewerte. A.3 ist ein Log-Beispiel mit ausdrücklich illustrativen menschlichen Feldern. Schwellen- und Datensatzplanung in A.2/A.4 folgt den korrigierten Bedingungen aus Abschnitt 7. Der Laya-MCP-Pfad wurde nicht getestet.

### A.1 Der Call

Die Skizze nimmt einen Vault-Treffer zur Anfrage „Bahnhofstraße“ an. Der tatsächlich geprüfte Call lief über lokales HTTP, nicht `laya_predict` oder den operativen Vault-Workflow. Er folgt dem Jev-Wire `POST /v1/systemone` mit `state`, `model`, `questions`:[^layaserve]

```json
{
  "state": "Notiz 2026-03: Bahnhofstraße — Verwaltung legt Verkehrsgutachten vor. Umbau der Gehwegzone zwischen Rathaus und Gansbichl geplant, Abstimmung mit Kanalsanierung 2027.",
  "model": "laya-multilingual",
  "questions": {
    "relevanz": {
      "type": "choice",
      "instructions": "Ist diese Notiz für ein Ratsprojekt zu Verkehr und Bau relevant?",
      "criteria": {
        "relevant": "Die Notiz behandelt ein konkretes Bau- oder Verkehrsvorhaben, einen Beschluss oder eine Planung der Kommune.",
        "irrelevant": "Die Notiz behandelt etwas anderes oder nennt das Thema nur beiläufig."
      }
    }
  }
}
```

Der Request trägt drei Festlegungen. Erstens wählt `laya-multilingual` die Modellfamilie explizit statt per Router; der Selektor ist kein unveränderlicher Gewichtsrevision-Pin. Tatsächliche Artefaktrevision und Hash gehören künftig ins Manifest. Die Router-Falle ist reproduziert: Ohne Selektor landet „Umbenennung Gansbichl“ still auf dem englischen Checkpoint, praktisch unentschieden bei Confidence 0,0015; explizit multilingual urteilt derselbe Text mit p(irrelevant) = 0,9456 bei Confidence 0,695.[^laya-pilot] Ein unbekannter `model`-Name schlägt nicht fehl, sondern autoroutet. Deshalb werden `routing.model` und `routing.reason` geprüft und geloggt; Fehlrouting kann einen zweiten Checkpoint in den Cache laden. Zweitens stehen Labels in der `criteria`-Map; ein „Kopf“ in E6 meint einen Fine-Tuning-Ausgang, kein Wire-Konzept. Gleiche Beschreibungen unter anderen Labelwörtern verschoben im Versuch die Verteilung um 0,17. Vollständige Frage, Kontext, IDs, Beschreibungen und Reihenfolge werden deshalb gemeinsam versioniert. Drittens teilen Labels und Eingabe das Token-Budget (damals 1024 Token Kontext, davon 256 für Labels laut ausgelieferter Config).[^laya] Der Versuch startet mit einer Frage.

Die Antwort trägt je Frage `choice` (Top-Label), `probabilities` (String-Keys je Option) und `confidence` (0 bis 1), dazu `answer_confidence` (die Wahrscheinlichkeit des Top-Labels), einen `usage`-Block, dessen `output_tokens` in jedem beobachteten Call bei 0 lag (das Modell generiert nichts), und einen `routing`-Block für die Pin-Verifikation aus A.1. Das Antwortfeld `model` liefert die generische Kennung `laya-rl-agent`. Erst die tatsächliche Gewichtsrevision und Datei-Hashes im Manifest belegen zusammen mit der Routingprüfung die geladene Konfiguration (6.3). Dies ist die wörtliche, beobachtete Antwort auf den Request oben (Labbook E02):

```json
{
  "model": "laya-rl-agent",
  "answers": {
    "relevanz": {
      "type": "choice",
      "choice": "irrelevant",
      "probabilities": { "relevant": 0.4528, "irrelevant": 0.5472 },
      "confidence": 0.0064,
      "answer_confidence": 0.5472,
      "action": { "act_probability": 1.0 }
    }
  },
  "usage": { "input_tokens": 112, "output_tokens": 0 },
  "routing": { "model": "multilingual", "repo": "convaiinnovations/laya/multilingual", "reason": "explicit model='multilingual'", "detection": null, "workflow": null }
}
```

`act_probability` stand in jedem beobachteten Laya-Urteil auf 1,0 und taugt hier nicht als Gate (6.2). Der Bahnhofstraße-Fall ist mit 0,5472 zu 0,4528 praktisch unentschieden, bei Confidence 0,0064; ohne validiertes Gate bleibt der Treffer zur Prüfung erhalten. Private Eingaben werden nicht implizit an eine Cloud eskaliert. Neun identische Requests über zwei Prozessgenerationen mit einem Neustart lieferten byte-identische Antworten. Das ist eine begrenzte Beobachtung dieser Konfiguration, keine intrinsische Checkpoint-Garantie.[^laya-pilot]

### A.2 Frage-Schema und Schwelle

Das Laya-Frage-Schema umfasst den vollständigen `questions`-Block aus A.1, Triage-Kontext, Label-IDs, Beschreibungen und Reihenfolge. Eine Gate-Policy ergänzt erst nach Validierung den benannten Score, die Konfiguration und τ (6.2). Drei Laya-spezifische Befunde:

- **τ wird entwickelt und getrennt getestet.** 0,85 im Laya-README und das Drei-Band-Muster bei hs-jev[^hsjev] sind Aufruferbeispiele, keine validierte Policy für dieses Repo. Für Laya bleibt `confidence`, nicht `act_probability`, der zu prüfende Score. 0,85 ist hier nur ein historischer Platzhalter und darf keinen automatischen Filter aktivieren. „Parkplätze am Bahnhof: Gebühren steigen“ lag falsch-negativ bei Confidence 0,8347; daraus wird keine neue Schwelle abgeleitet.
- **Kalibrierung ist workloadbezogen.** Laya berechnet Confidence als 1 − H(p)/log k. Die am 2026-09-24 geprüfte multilinguale Config enthielt [1.0, 1.0, 1.0] und leere Buckets, während der englische Checkpoint gefittete Werte mitbrachte.[^laya-pilot] Das gilt nicht automatisch für spätere Versionen. Modell, Schema und gegebenenfalls T/τ werden auf Entwicklungsdaten gewählt; ein disjunkter unangetasteter Holdout testet die zuvor eingefrorene Policy nach Abschnitt 7.
- **Laya zeigte einseitige Fehler.** E06 erkannte alle sechs irrelevanten, aber nur zwei von sechs relevanten synthetischen Titeln. Radweg, Kanalsanierung, Straßenbeleuchtung und Parkplätze waren falsch-negativ. Über dem historischen τ-Platzhalter lagen zwei korrekte Urteile; zwei Fälle belegen keine sichere Aussortierung. Der Befund ist Laya-spezifisch, kein Klassenmerkmal. Ohne weiteren Nachweis bleibt der Betrieb im Shadow-Modus.

Band-Verhalten darf erst eine workloadbezogen validierte und ausdrücklich freigegebene Policy aktivieren (6.2). Verwerfungen bleiben sichtbar. Unter der Schwelle oder ohne gültige Policy werden Treffer erhalten und geprüft. Nicht-öffentliche Eingaben bleiben beim Menschen oder einer freigegebenen lokalen Alternative; ein Cloud-Frontier-Fallback ist nicht implizit erlaubt.

### A.3 Das Log

Eine Zeile je Urteil; JSONL ist der Vorschlag dieses Anhangs (Abschnitt 7 verlangt nur ein einfaches Format, und JSONL vermeidet das Quoting-Problem von CSV bei Texteingaben):

```json
{"ts":"2026-09-24T17:10:51+02:00","workflow":"sitzungsvorbereitung","quelle":"vault","referenz":"Bahnhofstraße/Notiz 2026-03 Verkehrsgutachten","frage":"relevanz","frage_schema":"relevanz@v1","label":"irrelevant","confidence":0.0064,"answer_confidence":0.5472,"gate":"eskaliert","routing_model":"multilingual","routing_reason":"explicit model='multilingual'","llm_urteil":"relevant","menschkorrektur":"bestaetigt"}
```

Die Eingabe wird möglichst als Referenz statt Volltext geloggt, lokal und kontrolliert; Vault-Snippets verlassen die Maschine nicht. `frage_schema` verweist auf die vollständige versionierte Frage samt Kontext, IDs, Beschreibungen und Reihenfolge. `routing_model` und `routing_reason` prüfen ausschließlich die Familienwahl. Erst die Revision und Hashes im späteren Manifest belegen die Gewichtsprovenienz (6.3). Die modellseitigen Werte stammen aus A.1; `llm_urteil` und `menschkorrektur` sind ausdrücklich illustrative Felder, keine gemessenen menschlichen Urteile oder Goldlabels. Bei privaten Eingaben wäre ein Modellvergleich nur mit einer freigegebenen lokalen Alternative zulässig.

### A.4 Der Goldstandard

Zunächst 30 bis 50 echte kontextbezogene Entwicklungsfälle, vor Einsicht in Modellscores menschlich gelabelt. Modellwahl und mögliche T-/τ-Anpassung nutzen diese Entwicklungsdaten, nicht den disjunkten unangetasteten finalen Holdout aus Abschnitt 7. Die Startmenge allein belegt keine verlässliche Kalibrierung. Die folgende illustrative Zeile betrifft ein anderes Ratsprojekt als die Verkehr-und-Bau-Fixture:

```json
{"id":"g-011","eingabe":"Umbenennung Gansbichl — Beschlussvorlage 2026/042","human_label":"relevant","quelle":"ris","triage_kontext":"Projekt Umbenennung Gansbichl"}
```

Das Label „relevant“ gilt hier für den Kontext „Projekt Umbenennung Gansbichl“. Es widerspricht nicht dem eingefrorenen „irrelevant“ derselben Themenfamilie im Verkehr-und-Bau-Kontext von Anhang B. Dokumentierte Laya-Probleme wie Labelwort- und Positions-Bias motivieren solche Grenzfälle, sagen ihre Fehler aber nicht für alle Backends voraus.

### A.5 Lücken der Doku — Stand nach der Verifikation

1. Ein vollständiges Response-JSON war in den frei zugänglichen Quellen nicht abgedruckt; die Antwort war nur Feld für Feld belegt. Geschlossen: A.1 zeigt die wörtliche Antwort des lokalen Servers (Labbook E02).
2. Der Feldname der Option-Wahrscheinlichkeiten im HTTP-Body war unverifiziert. Geschlossen: `probabilities`, mit String-Keys, im CLI-Output wie im HTTP-Body beobachtet; der geplante Griff zur OpenAPI-Spec (cequence-io/openai-scala-client) erübrigt sich.
3. `routing` und `latency_ms` waren nur in der SDK- und MCP-Schicht dokumentiert. Teilweise geschlossen: `routing` steht im HTTP-Body, mit `reason` und Spracherkennung; `latency_ms` bleibt der SDK-Schicht vorbehalten. Der Pilot misst Latenz extern; auf der CPU blieb jeder Einzelrequest unter einer Sekunde.

Am 2026-09-24 änderte diese Verifikation die damaligen Entscheidungen nicht. Revision 4 hält die Messung historisch fest, öffnet E1 nach den späteren Vergleichen und korrigiert die Validierungsbedingungen. Einseitige Laya-Fehler waren beobachtet; ein sicher kalibriertes Gate war nicht nachgewiesen.

## Anhang B: Lokale Vergleichsversuche und Projektfolgen (2026-10-02)

### B.1 Gleiche Fixture, verschiedene Systeme

Die drei Labbooks vergleichen dieselben zwölf eingefrorenen synthetischen deutschen Verwaltungstitel. Die Frage lautet „Ist diese Notiz für ein Ratsprojekt zu Verkehr und Bau relevant?“; Zustand, Beschreibungen und Optionsreihenfolge blieben gleich. R1 bis R6 sind relevant, I1 bis I6 irrelevant. Die Erwartungen wurden vor den Läufen festgelegt und danach nicht geändert.[^laya-pilot][^semif-pilot][^kev-pilot] Es wurden keine echten Vault-Eingaben und kein operativer MCP-Workflow getestet.

| System und gemessener Pfad | Korrekt | Relevante erkannt | Irrelevante erkannt | Wiederholung |
|---|---:|---:|---:|---|
| Laya 0.3.20 multilingual, CPU | 8/12 | 2/6 | 6/6 | Baseline vom 2026-09-24 |
| SemIf, Qwen3.5-4B Q4_K_M, CPU mit zehn Threads | 12/12 | 6/6 | 6/6 | drei Durchgänge, Logits und p exakt gleich |
| Kev-4B, native MLX, bfloat16, gespeichertes T | 11/12 | 6/6 | 5/6 | drei Durchgänge, sichtbare vierstellige API-p und Labels gleich |

SemIf verwendete Source `23cf1f39fc95`, Referenztokenizer Qwen3.5-4B auf Revision `851bf6e806ef` und bartowskis GGUF Q4_K_M auf `4168f45a16a1`. Kev verwendete Source `84847f0a883d`, Release `139fdd94f1b6` und die tatsächlich aus `head.pt` geladene Base Qwen3.5-4B-Base auf `1001bb4d826a`. Die vollständigen Revisionen, Datei-SHA256, Runtimeversionen und Requests stehen in den lokalen Provenienzartefakten der Labbooks.[^semif-pilot][^kev-pilot] Der Alias `kev-latest` allein hätte diesen Nachweis nicht geliefert.

Kevs einziger Fehler war I1 „Umbenennung Gansbichl: Bürger protestieren“, als relevant statt irrelevant eingeordnet. p betrug 0,5114 zu 0,4886, die reskalierte Confidence 0,0228. Dieser Grenzfall ist fachlich diskutierbar, blieb aber entsprechend dem festgelegten Verkehr-und-Bau-Kontext irrelevant. R6 „Parkplätze am Bahnhof: Gebühren steigen“ blieb relevant. Die drei Durchgänge sind Wiederholungen derselben zwölf Fälle, keine 36 unabhängigen Beispiele. Die beobachteten 12/12 oder 11/12 sind deshalb keine allgemeine deutsche Genauigkeit.

SemIf bestand sechs deutsche Varianten eines expliziten Positiv- und Negativfalls. Kev bestand dieselben sechs Varianten und zwei separate englische Diagnosesätze. Die sechs deutschen Requests gehören zu zwei semantischen Fällen, die zwei englischen bilden eine zusätzliche Sprachdiagnose. Die gemappten Labels blieben bei Orderwechsel und ID-Rename korrekt. Scores änderten sich bei Orderwechsel; bei Kev auch bei ID-Rename, weil die IDs im Optionstext stehen. SemIf rendert sie nicht, dort blieb der ID-only-Prompt samt Scores unverändert. Diese Befunde verlangen Versionskontrolle für das vollständige Schema.

### B.2 Was davon für das Repo folgt

Die begrenzten Befunde rechtfertigen eine offene Backendwahl, keinen Produktionswechsel. Kev erfüllte das vorab gesetzte Explorationskriterium mindestens 9/12 korrekt, mindestens 4/6 relevante und 5/6 irrelevante; es übertraf SemIfs gemessene Obergrenze nicht. Deutsch ist beim Kev-Checkpoint außerhalb des dokumentierten Sprachumfangs.[^kev-card] Sein englisch gefittetes T = 2,406050072164233 ist keine deutsche Kalibrierung. SemIfs bedingter Options-Softmax ist ebenfalls keine kalibrierte Korrektheitswahrscheinlichkeit. Die zwölf bereits angesehenen Fälle sind als Exploration und Regression dokumentiert und für einen finalen Gate-Test verbraucht.

Die Schnittstellen sind konkret, aber nicht gleich: SemIf wurde per CLI ausgeführt, Kev über lokales typisiertes HTTP `/v1/systemone`. Layas MCP ist nur dokumentiert. CLI ist bereits für den Harness nutzbar; MCP ist kein Grund, vor dem einfachen Vergleich einen neuen Server zu bauen. Kevs R1-Antwort meldete `output_tokens: 54` als Billing-Schätzung der serialisierten Antwort, nicht als generierten Text. Solche Feldnamen müssen je Adapter erklärt werden, bevor Logs systemübergreifend ausgewertet werden.[^kev]

SemIfs gemessener CPU-Forward-Median war 2,54 s. Kevs spätere HTTP-Wall-Mediane lagen bei etwa 0,223 s, die Modellbatch-Mediane bei 215 bis 216 ms. Diese Werte haben unterschiedliche Timer, Backends und Präzision; daraus folgt kein kausaler Geschwindigkeitsfaktor. Kev brauchte 16,27 s bis Readiness, der erste Smoke 3,109 s HTTP-Wall. Vier Cacheplätze reichten nicht für zwölf zyklisch angefragte Zustände: R1 war im ersten Pass warm, Pass 2 und 3 hatten keine Cachehits. Gemessene Initialisierung und Cachezustände gehören deshalb in das Manifest.

Der Kev-Labbook-Footprint lag bei etwa 11,99 GiB für Umgebung, Modelle und Logs. Das ist Plattenbelegung, keine RAM-Anforderung. Der Host hatte 64 GiB RAM; diese einzelne Maschine definiert keine universellen Zielanforderungen. Beide neuen Versuche liefen nach Downloads mit Offline-Flags. Eine Netzwerksandbox wurde dabei nicht nachgewiesen. Die Runtime wurde beendet, Artefakte blieben zur Reproduzierbarkeit erhalten.

### B.3 Nächster Nachweis, noch keine Betriebsfreigabe

Die Folgen sind die Entwicklungs-/Holdout-Trennung aus Abschnitt 7, ein vollständiges lokales Manifest und backendbezogene Scores statt einer gemeinsamen Confidence-Schwelle. Zuerst echte kontextbezogene menschliche Labels sammeln, bevor neue Modellscores gesehen werden. Auf Entwicklungsdaten Schema und Backend wählen; danach unverändert auf disjunktem unangetastetem Holdout Recall, falsche Verwerfungen, Coverage und Unsicherheit prüfen. Nachjustieren verbraucht den Holdout und verlangt neue Testfälle. Bei zu wenig Evidenz bleiben alle Treffer im Shadow-Betrieb sichtbar.

Vor jedem operativen Schritt bleiben Schnittstellenprüfung, kanonische Voraussetzungen und ein eigenes GO nötig. Die [Recherche-Notiz vom 2026-10-02](../research/2026-10-02-jev-alternativen.md) liefert Hintergrund zu Alternativen und ging dem Kev-Versuch voraus. Sie ist keine Quelle dieser Messwerte; Sterne und Benchmarkplätze begründen keine Backendwahl. Private Eingaben dürfen auch bei technischer Abstention nicht implizit an Cloudmodelle gehen. Menschliches GO, Quellenpflicht und deterministische Berechtigungen bleiben unverändert.

## 10. Quellen

Die ursprünglichen externen Quellen wurden am 2026-09-24 abgerufen. SemIf-/Kev-Quellen und lokale Vergleichsbelege kamen am 2026-10-02 hinzu. Interne Belege stehen als `datei:zeile` im Text (Konvention wie RFC 0000, Abschnitt 1). Anhang A beruht auf der damaligen Wire-Recherche und Laya-Verifikation. Die Messwerte in Anhang B stammen ausschließlich aus den unten benannten privaten lokalen Labbooks. Herstellerbenchmarks und Recherche-Notiz liefern Hintergrund, aber keine Quelle dieser Zahlen. Die Labbooks sind keine im Repo geteilten Datensätze.

[^jev]: TypeSafe AI, „Introducing System One Models & Jev“, 2026-09-15. https://typesafe.ai/blog/introducing-system-one-models-and-jev
[^laya]: Laya, offene System-1-Entscheidungsmodelle (Apache-2.0): README, BENCHMARKS.md, Issues #131 und #156. https://github.com/NandhaKishorM/laya
[^devto]: Nanda Kishor M, „I built non-autoregressive decision models a year ago. Then a frontier lab called it a“ (Prior-Art-Statement). https://dev.to/nandakishor_m_6cc0adfde9f/i-built-non-autoregressive-decision-models-a-year-ago-then-a-frontier-lab-called-it-a-18me
[^stuntd]: stuntd, lokale Laya-Instanz hinter der Jev-API mit fine-tuned Entscheidungsköpfen; referenziert im Laya-README, Abschnitt Community Tools. https://github.com/bladedevoff/stuntd
[^layaserve]: stiermid/laya-serve, Jev-kompatibler HTTP-Server für Laya; vom stuntd-README als Wire-Format-Referenz benannt. https://github.com/stiermid/laya-serve
[^hsjev]: getmissionctrl/hs-jev, Haskell-Client für die Jev-API; dokumentiert das Drei-Band-Routing auf Konfidenz. https://github.com/getmissionctrl/hs-jev
[^semif]: SemIf, geprüfte Source-Revision 23cf1f39fc9534fe81437200959b6dfc7106e45a. https://github.com/TheoLeeCJ/SemIf-OpenJev/tree/23cf1f39fc9534fe81437200959b6dfc7106e45a . Abruf und lokale Quellenprüfung 2026-10-02.
[^kev]: Kev, geprüfte Source-Revision 84847f0a883d900f7de5b7a57eaa341ca7f9a6b4; insbesondere kev/api.py für Optionstexte, Confidence und Billing-Tokenzahl sowie kev/checkpoint.py und kev/serve.py für geladenes Modell und Metadaten. https://github.com/jaredpalmer/kev/tree/84847f0a883d900f7de5b7a57eaa341ca7f9a6b4 . Abruf und lokale Quellenprüfung 2026-10-02.
[^kev-card]: Kev-4B, Modellkarte des tatsächlich geprüften Releases 139fdd94f1b6a6ad80cc15e08fcb99cac885a101. https://huggingface.co/jaredpalmer/kev-4b/blob/139fdd94f1b6a6ad80cc15e08fcb99cac885a101/README.md . Abruf 2026-10-02; englischer Sprachumfang und Domänenwechselgrenzen sind Autorenangaben.
[^laya-pilot]: Privates lokales Messprotokoll vom 2026-09-24, `/Users/crn/labbooks/2026-09-24-laya-pilot/LABBOOK.md`; E06-Rohfixture und Antworten unter `experiments/E06-goldstandard/`. Nicht im Repo geteilt. Für Revision 4 abgeglichener Befundstand 2026-10-02.
[^semif-pilot]: Privates lokales Messprotokoll vom 2026-10-02, `/Users/crn/labbooks/2026-10-02-semif-pilot/LABBOOK.md`; vollständige Pins und Hashes in `artifacts/model-provenance.json`, Rohläufe `artifacts/laya12-result-01.jsonl` bis `03.jsonl`. Nicht im Repo geteilt.
[^kev-pilot]: Privates lokales Messprotokoll vom 2026-10-02, `/Users/crn/labbooks/2026-10-02-kev-pilot/LABBOOK.md`; vollständige Pins/Hashes in `artifacts/model-provenance.json`, `artifacts/head-meta.json` und `artifacts/runtime-versions.json`, Requests/Rohantworten sowie Vergleich/Kontrollen und Cleanupbelege unter `artifacts/`. Nicht im Repo geteilt.
