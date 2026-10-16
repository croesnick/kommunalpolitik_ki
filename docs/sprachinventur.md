# Sprachinventur — Begriffe und Phrasen des Repos

| Feld | Wert |
|---|---|
| Status | Entwurf; Wellen 1–3 abgeschlossen; Welle 4 (K4-Cross-Check) extrahiert, Sweeps und B2-Entscheidungen per GO 2026-10-16 ausgeführt |
| Stand | 2026-10-16 |
| Zweck | Inventur aller Fachbegriffe und Phrasen des Korpus, Klassifikation mit Quellenbelegen, Entscheidungsgrundlage für konsistente Verwendung |
| Korpus | Alle 39 Markdown-Dokumente des Repos (AGENTS.md, docs/, skills/, apps/, tools/). Code-Bezeichner (Funktionen, Module, CLI-Flags, MCP-Parameter) sind außen vor. RFC0001 ist historisch: es wird inventiert, Entscheidungen gelten nur für aktive Dokumente. |

## Der Weg (wiederholbarer Prozess)

1. **Korpus festlegen.** Derzeit 39 Markdown-Dateien, 12.789 Zeilen (siehe Kopfzeile).
2. **Extraktion.** Kandidaten werden in fünf Kategorien gesammelt: K1 Fachbegriff deutsch (etabliert wirkend), K2 englischer Term im deutschen Text, K3 Denglish-Mischform, K4 Eigenprägungs-Verdacht (deutsches Kompositum als vermutete Pseudo-Übersetzung), K5 wiederkehrende feste Phrase.
3. **Verifikation mit Quellenpflicht.** Jede last-tragende Klassifikation braucht einen Beleg: wörtliches Zitat, Quelle, URL, Datum — oder einen dokumentierten Negativbefund. Ohne Beleg: Status OFFEN. Keine Behauptung ohne Anker; korrupte Lane-Ausgaben überleben das nicht.
4. **Entscheidung.** Kanonische Form festlegen und hier eintragen. Ersetzungs-Sweeps im Korpus erst nach GO der nutzenden Person.
5. **Pflege.** Neue Begriffe wandern bei ihrer Ersteinführung direkt hierher — analog zur Fett-Konvention in RFC0003 (Begriffe werden bei erster Einführung fett markiert).

## Statuswerte

- **ETABLIERT_DE:** es gibt einen etablierten deutschen Fachbegriff für das Konzept → deutsch verwenden.
- **NUR_ENGLISCH:** nur der englische Begriff ist fachlich etabliert → englisch lassen, keine deutschen Komposita prägen.
- **EIGENE_PRÄGUNG_OK:** kein Begriff etabliert (weder deutsch noch englisch) → Neuprägung legitim, Definition bei Ersteinführung.
- **FEHLFORM:** keine lexikografische Basis; existiert in der Praxis höchstens als Versehen → ersetzen.
- **OFFEN:** Beleglage unklar → klären, bevor der Term last-tragend wird.

## Entscheidungen aus der Sprach-Session (per GO beschlossen, 2026-10-14)

### Formulierungen

| Alt (verboten) | Neu (festgelegt) | Kontext |
|---|---|---|
| Fähigkeitsfläche | Funktionsumfang (in einer festen Fassung festgehalten) | RFC0003, Connector |
| Oberflächendrift | „nach der Zulassung geänderter Funktionsumfang“ | RFC0003, D.9 |
| zugelassene Fähigkeiten | zugelassene Operationen | RFC0003, B.3-Feld |
| spezialisierte / generischere Operation | eng begrenzte / weiter gefasste Operation | RFC0003, R.4.3 + D.9 |
| Sicherheitspolitik | Sicherheitsregeln („neu gegliedert, führt aber keine neuen … ein“) | RFC0003, Z. 11 |

### Konventionen

| Regel | Gilt für |
|---|---|
| Erstdefinition fett: genau einmal bei Ersteinführung im Fließtext; Vertiefungen normal; Tabellen/Code/Formeln ausgenommen; Normsatz-Fett bleibt zweite, unterscheidbare Rolle | RFC0003 (Konventionssatz in der Intro); Übertragung auf weitere Dokumente vorgemerkt |

### Sweeps Paket 1 und 2 (per GO ausgeführt, 2026-10-14)

Umfassende Korpus-Ersetzungen, ausgeführt und doppelt gezählt (Fixer-Lane + Orchestrator-Nachzählung): Provenanz→Provenienz, Distillat→Destillat (inkl. Distillation, Plural), Auswerter-Orakel→Testorakel (CONTRACT + Test-Beschreibung), Goldset→Goldstandard-Datensatz, getagged→getaggt, Canarien→Kanarien, First-Party-Quelle→Primärquelle, Orchestrierer→Orchestrator; in RFC0003: R.8-Überschrift Garantien→Zusagen (inkl. Anker-Link), Bauauftrag→Bauanleitung, Simulationstool→Simulator (inkl. Anker-Link), Effektplan/Effektumfang→Wirkungsplan/Wirkungsumfang (8×), Vermittlungsstelle→Vermittler (D.9); AI→KI als Standardwort im deutschen Fließtext (~60 Stellen; Komposita AI-Harness/AI-Enabled/AI-Schnittstelle/AI-Session und englische Kontexte bleiben); AI-Sitzung→AI-Session (lifecycle); Trusted Base→vertrauenswürdige Basis (research-Notizen, 10×, mit minimalen Kasusanpassungen). Zwei Genus-Korrekturen nötig („der AI“→„die KI“). Grenzdateien unberührt: RFC0000, RFC0001, PACE-Bericht (englisch), AZ-README (englisch), dieses Inventur-Dokument.

### A–G-Sweeps (per GO ausgeführt, 2026-10-14)

Zweite GO-Runde, ausgeführt und per rg-Zählung verifiziert: **Effekt→Wirkung in RFC0003 komplett** (Wirkungsstrom, Wirkungszuordnung, Wirkungsbelege, Objekt- und Wirkungsbindung, Wirkungswiederholung, Wirkungsmodell plus rund zwanzig alleinstehende Nennungen mit Kasusangleichung; „Effektor“ bleibt als Rollenname); „Trust-Base-Trade-off“ → „Trade-off der vertrauenswürdigen Basis“; F.5-Überschrift „Verbindlicher Ausführungsautomat“ → „Verbindlicher Ausführer“; Prüflabel → Validierungslabel in CONTRACT.md; Payload-Artikel in der Burrito-Notiz („den Payload“ — Akkusativ korrekt gesetzt). **Fett:** vier Zweit-Fetts entfettet (Aktionsfreigabe, Offenlegungsfreigabe, Offenlegungsstand, Audit-Journal in R.6/R.11), fünf neue Erst-Fetts (Lockerung, Kontrollpunkt-Zeugen, Wiederanlaufbefund, Environment-Datensatz, Herabstufungsbefugnis). **RFC0002:** fünfzehn Erst-Fetts (u. a. System-1-Modelle, Hard/Soft Gates, Holdout, Gate-Policy, Shadow-Modus, Pilot, Score; begründete Belassungen: Rote Linien, Konfidenz-Gating, Frontier-LLM, Eskalationsquote, Backendadapter — kein Fließtext-Definitionssatz). Zusätzlich AI→KI in Elixir-Kommentaren, MCP-Docstrings, UI-Strings und im Shell-Script (21 Ersetzungen, `mix format` grün).

## Welle-1-Verdikte (Librarian-Verifikation, 2026-10-14)

Empfehlungen; Ersetzungs-Sweeps warten auf GO. Beleganker wie von der Verifikationslane gemeldet — vor Veröffentlichung Spot-Check der URLs.

### P1 — die drängenden Fälle

**Provenienz / Provenanz / field provenance**

| Term | Status | Empfehlung |
|---|---|---|
| Provenienz | ETABLIERT_DE | kanonisch für Herkunft im Fließtext; für Daten: Datenprovenienz |
| Provenanz | FEHLFORM | nie verwenden; durch Provenienz ersetzen |
| field provenance | NUR_ENGLISCH | englisch lassen; im deutschen Fließtext umschreiben („Provenienz auf Feldebene“) |
| Provenienzartefakte | ETABLIERT_DE-Muster | ok (transparentes Kompositum aus etablierten Bestandteilen); Identifikatoren englisch |
| Modellprovenienz | transparent, Definition nur englisch vorliegend | ok; bei Gewichten weight lineage vorziehen oder bei Ersteinführung definieren |

- Provenienz: Duden („Bereich, aus dem jemand, etwas stammt; Herkunft…“, duden.de/rechtschreibung/Provenienz); DWDS (Pfeifer: „Provenienz f. ‚Herkunft, Ursprung‘…“, dwds.de/wb/Provenienz); für Daten: eResearch Alliance Göttingen zur W3C-PROV-Familie („Die Datenprovenienz beantwortet die Fragen, warum und wie die Daten produziert wurden…“), NFDI4Culture-FAIR-Handreichung.
- Provenanz: Negativbefund Duden und DWDS → HTTP 404 (14.10.2026); Positivkontrolle Provenienz vorhanden. Randexistenz: ISO/TS 23494-1:2024 benutzt im deutschen Fließtext „Provenanz-Modell“, im deutschen Normtitel aber „Provenienz“ — selbst der Normtext ist inkonsistent. Kein Lexikoneintrag.
- field provenance: emergenter AI-Security-Begriff (u. a. arXiv 2605.24421 „Poisoning the Watchtower“; arXiv 2609.05269 „CONTINUITY“: „Continuity tracks provenance at the field level…“). Deutsche Form „Feldprovenienz“ nirgends belegt.

**Heilplan-Ausgabe / remedy plan**

- Status: doppelte Fehlprägung. Der englische Stamm ist schon falsch: etabliert in Security ist **remediation plan** (AWS Security Hub: „A remediation plan in AWS Security Hub groups related exposure findings that share a root cause…“); „remedy plan“ ist Rechtsjargon (Vertragsklauseln, Law Insider). „Heilplan“ existiert in keiner Fachdomäne — DWDS hat kein Lemma (schlägt „Heilsplan“ = „sich in der Heilsgeschichte offenbarender Plan Gottes mit der Welt“ vor); Duden → 404.
- Empfehlung: remediation plan (englisch); im deutschen Fließtext „Behebungsplan“ — nie „Heilplan“. Die Form „Heilplan-Ausgabe“ ist als Referenzfall einer gescheiterten Eindeutschung dokumentiert (nicht im Korpus gefunden; tauchte in einer externen Notiz auf).

**Weitere P1-Verdikte**

| Term | Status | Kernbeleg | Empfehlung |
|---|---|---|---|
| Nichtinterferenz | ETABLIERT_DE | KIT-Dissertation („Mit diesen lässt sich die Abwesenheit unerlaubter Informationsflüsse und verdeckter Informationskanäle beschreiben…“); DFG-Projekt „PolyNi“; KIT-Lehrveranstaltung („Nichtinterferenz-Eigenschaft (engl. noninterference)“) | deutsch verwenden; bei Erstnennung ggf. „(engl. noninterference)“ |
| Sitzungsmappe | ETABLIERT_DE (praxisbasiert) | ITEBO („Auch in der digitalen Gremienarbeit muss eine Sitzungsmappe erstellt und an die Beteiligten zugestellt werden…“); mandari.de; Bayerischer Landtag (URL-Pfad /sitzungsmappe/); GLOMAS. Duden → 404: etabliert über Praxis, nicht lexikografisch | deutsch verwenden, wie bisher |
| taint tracking | NUR_ENGLISCH | KTH/EuroS&P („Taint tracking is a striking success story in computer security…“); ACM PACMSE 2025 (taint tags) | englisch; bei Ersteinführung definiert einführen |
| paired execution | OFFEN, Prägeverdacht | existiert vereinzelt in Literatur (STTT 2004; alphaXiv 2603.28815), nicht standardisiert | englisch beibehalten; bei Ersteinführung definieren („parallel laufende Vergleichsausführung“); nicht als „etabliert“ behandeln |

### P2/P3 — kompakte Verdikte

| Term | Status | Empfehlung |
|---|---|---|
| Policy (auch Gate-Policy) | NUR_ENGLISCH (policy-as-code) | Policy für maschinenlesbare Regeln; „Sicherheitsrichtlinie“ nur, wenn die BSI-Bedeutung gemeint ist |
| Credential | NUR_ENGLISCH | in Identifikatoren Credential; im deutschen Fließtext sind „Anmeldeinformationen/Zugangsdaten“ möglich (BSI-Sprachgebrauch) |
| Snapshot | NUR_ENGLISCH | Snapshot |
| Label | NUR_ENGLISCH | Label (Beleglage dünn — nachprüfen) |
| Audit | ETABLIERT_DE | Audit (Duden: „das oder der“); Genus im Korpus konsistent wählen |
| Journal (technisch) | ETABLIERT_DE (praxisbasiert: IBM-i-Doku „Protokolle und Journale“) | Journal im Audit-Kontext; „Protokoll“ für generische Logs getrennt führen |
| Engine | NUR_ENGLISCH | Engine (keine „Maschine“-Ersatzprägung) |
| Review | NUR_ENGLISCH | Review |
| Session | NUR_ENGLISCH (Harness-Kontext) | Session für Harness-Chat; BSI nutzt „Sitzung“ für administrative Kontexte |
| Triage | ETABLIERT_DE | Triage (Duden; Medizin ist Ursprungsbedeutung, IT-Übertragung etabliert) |
| Score | NUR_ENGLISCH | Score |
| Abstention | NUR_ENGLISCH | Abstention (ACL „The Art of Abstention“ 2021); keine deutsche Erfindung |
| Holdout | NUR_ENGLISCH | Holdout (deutschsprachige Lehrtexte nutzen den englischen Begriff) |
| Recall | NUR_ENGLISCH | Recall (deutsche Lehrtexte nutzen englisch) |
| Gating | NUR_ENGLISCH | Gating/gate |
| Labbook | EIGENE_PRÄGUNG_OK, mit Vorbehalt | kollidiert mit „lab book/lab notebook“ der Forschungsdaten-Welt; bei Ersteinführung definieren oder zu session log/logbook ausweichen |
| Ingest | NUR_ENGLISCH | Ingest; keine „Einspeisung“ |
| Sync | NUR_ENGLISCH (Obsidian-Doku: „Obsidian Sync“; deutsche Alternativen nicht etabliert) | Sync; Verb im Fließtext darf „synchronisieren“ heißen |
| Runtime, Backend, Manifest, Prompt | NUR_ENGLISCH | englisch |
| Workflow, Dashboard | NUR_ENGLISCH | englisch (auch deutsche Microsoft-Doku nutzt sie) |
| Harness | NUR_ENGLISCH | Harness; bei Ersteinführung definieren |
| Sandbox | NUR_ENGLISCH | Sandbox |
| Threat Model | NUR_ENGLISCH | threat model („Gefährdungsmodell“ deckt das Konzept nicht) |
| Nonce | NUR_ENGLISCH | Nonce |
| Prover / Verifier | NUR_ENGLISCH | im Formal-Verification-Kontext englisch |

**Nach Welle 2 geklärt:** Connector, Journal (technisch), Sync, Board, Issue, Proposal, Vault, Skill, Tooling, Worktree, Orchestrierung — siehe Welle-2-Verdikte unten.

## Welle-2-Verdikte (Librarian-Verifikation, 2026-10-14, abgeschlossen)

**Fehlform-Funde — die wichtigsten Ergebnisse:**

| Term | Status | Empfehlung |
|---|---|---|
| Distillat | FEHLFORM — Duden 404, DWDS leitet auf Destillat weiter; deutsche KI-Fachtexte sagen Wissens-/Modelldestillation | kanonisch **Destillat** („ratsprojekte ist das Destillat“); Sweep wartet auf GO |
| Auswerter-Orakel | Etabliertes deutsches Pendant existiert: **Testorakel** (ISTQB-Glossar dt.: „Informationsquelle zur Ermittlung der jeweiligen vorausgesagten Ergebnisse, die mit den tatsächlichen Ergebnissen … zu vergleichen sind“) | kanonisch **Testorakel** (bei Erstnennung „engl. test oracle“); „Auswerter-Orakel“ ersetzen |

**Weitere Verdikte:**

| Term | Status | Empfehlung |
|---|---|---|
| Standortbestimmung | ETABLIERT_DE (Duden; Übertragung „politische Standortbestimmung“ gedeckt) | behalten; einmal klarstellen, dass die fachliche Projekt-Lagebewertung gemeint ist |
| Quellenpflicht | ETABLIERT_DE (Fachverwendung wissenschaftliches Arbeiten) | behalten (Repo-Norm) |
| Quellenbindung | ETABLIERT_DE im KI-Kontext (deutsche Fachtexte zu source grounding benutzen es) | behalten; ggf. Gloss „(engl. source grounding)“ — strikt von Quellenpflicht getrennt halten |
| Verdichtung | ETABLIERT_DE (Duden) | behalten |
| Datenvertrag | ETABLIERT_DE (deutsche Data-Engineering-Community) | behalten; Gloss „(Data Contract)“ bei Erstnennung |
| Referenzkommunen | ETABLIERT_DE (kommunalpolitische Praxis: AGJ/BMFSFJ, NRW-Evaluation, RIS Eisenach) | behalten — keine Repo-Prägung |
| hartkodiert | Praxisvarianten ohne Kanonform (hartkodiert / hart-kodiert / hart kodiert) | EINE Form festlegen: **hartkodiert**; Code-Bezeichner englisch (hard-coded) |
| Kanonität / Kanonizität | OFFEN (Nomen ohne belastbaren Beleg; das Konzept ist als „kanonische Form“ belegt) | **kanonische Form** verwenden; Nomen vermeiden oder als Repo-Term fett definieren |
| Boot-Gate / Grenz-Gates | EIGENE_PRÄGUNG_OK (Gate-Basis etabliert: Quality Gate in deutschen Fachtexten) | behalten; bei Ersteinführung definieren („Prüfschritt vor dem Systemstart“) |
| Connector | NUR_ENGLISCH (Microsoft-Doku dt. schwankt selbst zwischen Konnektor/Verbinder) | Connector |
| Sync | NUR_ENGLISCH (Obsidian-Doku) | Sync; Verb „synchronisieren“ erlaubt |
| Board | NUR_ENGLISCH (GitHub-Doku dt. pendelt Board/Tafel) | Board |
| Issue | NUR_ENGLISCH (GitHub-Doku) | Issue; „Ticket“ nur als Umschreibung |
| Vault | NUR_ENGLISCH (Obsidian-Doku; „Tresor“ ist Ausnahme, nicht Regel) | Vault |
| Skill | NUR_ENGLISCH (Anthropic-Doku dt.) | Skill |
| Tooling | NUR_ENGLISCH (heise benutzt den Term im deutschen Text) | Tooling |
| Worktree | NUR_ENGLISCH (git-scm.de: „Arbeitsbaum“ nur als Gloss, Worktree als Fachterm) | Worktree |
| Orchestrierung | ETABLIERT_DE (Duden-Verb mit EDV-Bedeutung deckt das Nomen mit) | Orchestrierung; die Orchestrator/Orchestrierer-Schwankung trotzdem vereinheitlichen (s. Widersprüche) |
| Frontier-LLM | NUR_ENGLISCH (heise: „KI-Modelle der Frontier-Klasse“) | Frontier-LLM / Frontier-Modell |
| Goldlabel | NUR_ENGLISCH (das einzelne Label) | Goldlabel; **Goldstandard** (ETABLIERT_DE) für Korpus/Referenz — „Goldset“ streichen |
| Gate | NUR_ENGLISCH (Quality Gate etabliert) | Gate (GO-Gate, Boot-Gate, Quality Gate); „Prüfpunkt“ nur als Fließtext-Umschreibung |
| Distillation (LLM-Sinn) | ETABLIERT_DE als Wissens-/Modelldestillation | deutsch Destillation; englisch nur bei Zitaten |
| Aktualitätsbezug | OFFEN (kein Fachterm-Beleg; verwandt: Newswert-Aktualität) | nicht last-tragend; „Aktualität“ phrasen oder bei Ersteinführung fett definieren |
| Prüflabel | OFFEN (kein Beleg; kollidiert mit dem Prüfzeichen-Wortfeld) | ersetzen durch „Validierungslabels“ oder umschreiben (GO) |
| Proposal | OFFEN (Such-API-Ratenlimit; ITIL-Verifikation ausstehend) | vorläufig Proposal + scharfe Glossar-Abgrenzung zum Stadtratsantrag |

Beleganker wie von der Verifikationslane gemeldet (Duden/DWDS-, ISTQB-, Obsidian-, GitHub-, heise-, ISTQB-/SIGS-, IBM-i-, AGJ-Quellen; alle Abrufe 14.10.2026) — vor Veröffentlichung Spot-Check der URLs.

## Welle-3-Verdikte (Restoffen-Verifikation, 2026-10-14)

| Term | Status | Empfehlung |
|---|---|---|
| Proposal | Nachtrag: „Change-Vorschlag“ ist offizielle deutsche ITIL-Terminologie (ITIL-Glossar dt.; IT Process Wiki de), aber ITIL-methodisch vorgeprägt (großer Change/Service-Portfolio) — deckt das generische GO-Gate nicht | Proposal bleibt Repo-Term; GLOSSARY-Eintrag hat jetzt einen Sprache-Hinweis; „Änderungsantrag“ tabu (kollidiert mit dem Stadtrats-Änderungsantrag) |
| Kanonizität / Kanonität | „Kanonizität“ (mit z): Uni-Anker (Uni Bremen/Freiburg, JADE-Manual: „Die Eindeutigkeit (Kanonizität) dieser Repräsentation…“); „Kanonität“ (ohne z): keine IT-Fundstelle; Normalfall deutscher Fachtexte: „kanonische Form“/„Kanonisierung“ (TUM, Uni Ulm, Uni Lübeck) | CONTRACT.md:334 „Kanonitäts-Tripwire“ ist Sweep-Kandidat → „Kanonizitäts-Tripwire“ (GO-Frage gestellt) |
| Staging-Tabelle / Staging | ETABLIERT (IBM de „Staging-Bereich“, Informatica de „Staging-Tabelle“, Databricks de, Wikipedia de „Staging-Schicht“) | behalten — konform mit deutscher DWH-Fachpraxis |

**Nutzlast/Payload — Nutzerentscheidung (2026-10-14):** Kanonisch **„der Payload“** (maskulin), nicht „die Nutzlast“. Die Artikel-Fehler in den Research-Notizen („das Payload“) sind korrigiert; für die Angleichung von RFC0003 (neun Stellen, normativer Text) liegt das GO vor — Sweep läuft (fix-6).

**AI→KI in Code-Kommentaren (2026-10-14):** 21 Ersetzungen in Elixir-Kommentaren, MCP-Docstrings und UI-Strings sowie im Shell-Script (fix-5, verifiziert: 0 verbliebene Fließtext-Treffer, `mix format` grün); Bindestrich-Komposita (AI-Harness, AI-Begründung, AI-Vorschläge, AI-Zugriff) bleiben regelkonform. GLOSSARY.md wurde als Grenzdatei nachträglich selbst angeglichen (5 Stellen).

## Welle 4 — K4-Cross-Check und Sprach-Sweeps (2026-10-16)

**Anlass und Methode:** Der Root-Sweep („Root“ statt „Wurzel“, Commit `92da34a`) deckte ein Muster auf, das die Wellen 1–3 nicht systematisch gesucht hatten: deutsche Pseudo-Übersetzungen etablierter englischer Fachbegriffe (Kategorie K4). Extraktion in sechs parallelen Lanes über den Markdown-Korpus (~13.500 Zeilen; docs/, skills/, apps/, tools/, Root-Dateien; Eval-Artefakte und englische Dokumente ausgenommen). Jede gemeldete Fundstelle wurde vor der Adjudikation einzeln per Datei-`rg` verifiziert.

**GO-Runde 2026-10-16:** A-Verstöße gegen bereits beschlossene Regeln und B1-Ersetzungen komplett; RFC0001 angleichen; Root-Neufunde aus Ticket #123 fixen; Beleg-Welle für die kontroversen B2-Terme. Zweite GO-Runde 2026-10-16: Bedrohungsmodell als ETABLIERT_DE festgelegt, Entscheidungskopf-Sweep auf Head-Formen, Evidenz-Durchsetzung mit Ausnahmen.

**Ausgeführte Ersetzungen** (fix-1-Lane 59 Edits + 8 Orchestrator-Restfixe, doppelt gezählt per `rg`; alle Alt-Formen im getrackten Korpus danach null, `mix format` fehlerfrei):

| Alt → Neu | Stellen |
|---|---|
| Nutzlast → der Payload | research/2026-10-02-vermittelte-agent-netzwerkwege 8×; RFC0001 8× |
| „das/altes Payload“ → der/alter Payload | komki-burrito-pilot:27–28, 93; prerequisites:422 |
| fehlende/bekannte Evidenz → Belege | komki_policy CONTRACT:230, 288; derive.ex:167 |
| Tor → Gate | CONTRACT:340 |
| Freigabepolitik → Freigabe-Policy | RFC0003:699; RFC0001:348 (Zwillings-Satz) |
| Regelmaschine → Regel-Engine | RFC0003:169; RFC0001:41 |
| Grenzraten → Rate-Limits | RFC0003:2084; RFC0001:1696 |
| Zustandsfingerabdruck → Fingerprint | RFC0003:1738; RFC0001:1386 |
| Startwert/Zufallsstartwert → Seed | RFC0003:1746 2×; RFC0001:1394 2× |
| Heilweg/heilbar → Behebungsweg/behebbar | RFC0003:2005 |
| Sitzungsverläufe/Tool-Sitzungen/Sitzungsstart → Session-Formen | komki_cli README:120, 157; probe-harness:140; terminal_screenshot:24, 120 |
| Beweisprüfer → Ableitungsprüfer | komki_policy README:4; CONTRACT:12 |
| Arbeitsfläche → Arbeitsraum | prerequisites:351 |
| Clusterung → Clustering | workflows:360; bericht_aus_dem_stadtrat:487 |
| Werkzeugkette → Toolchain | komki-burrito-pilot:19 |
| Netzpolitik/Zielrichtlinie → Netz-/Ziel-Policy | vermittelte-agent-netzwerkwege 5× |
| Sandkasten → Sandbox | seatbelt-survey:36 |
| Rückfall → Fallback | probe-harness:16 |
| Fensterchrome → Fensterrahmen | terminal_screenshot:18 |
| Öffentlichkeitsscheibe → Öffentlichkeitsbezug | bericht_aus_dem_stadtrat:215 |
| separates File → Datei | sitzungsvorbereitung:243–244 |
| System-Häuser → Systemverzeichnisse | llama-server-confinement:45, 46 |
| zurückgehaltene Beispiele → Holdout-Beispiele | jev-alternativen:54 |
| „Reihenfolge matters“/„Recent Ereignis“ → deutsche Form | antrag_generieren:16, 64 |
| Wurzel → Root (Neufunde aus #123) | macho_deps.ex:51, 150; llama-server-confinement:38 |

**Welle-4-Verdikte** (Librarian-Beleg-Welle, Abruf 16.10.2026; Kernanker vom Orchestrator nachgeprüft):

| Term | Statusvorschlag | Kernbeleg | Konsequenz |
|---|---|---|---|
| Verhungern | ETABLIERT_DE | de-Wikipedia „Verhungern (Informatik)“: „Als Verhungern (englisch Starvation) bezeichnet man …“ (Nachprüfung bestanden); Vorlesungsskripte HH Düsseldorf, TU Dresden, Uni Hamburg, ETH Zürich mit deutscher Erstform und englischer Klammer | behalten (RFC0003:1325, RFC0001:973) |
| Seed | NUR_ENGLISCH | deutsche Python- und PyTorch-Doku nutzen „Seed“ unübersetzt; Duden/DWDS ohne Lemma (404) | Sweep ausgeführt (RFC0003 C.6 + RFC0001-Zwilling) |
| Fingerprint | NUR_ENGLISCH; „Zustandsfingerabdruck“ FEHLFORM | de-Wikipedia „Fingerprinting (Trackingtechnik)“, BSI „JavaScript, Cookies & Fingerprints“, heise; „Fingerabdruck“ läuft nur als erklärende Glosse daneben | Sweep ausgeführt; „Zustandsfingerprint“ als Variante zulässig |
| Bedrohungsmodell | ETABLIERT_DE (GO 2026-10-16) | BSI-Leitfaden Webanwendungen 4.3.4: „Die Bedrohungsmodellierung (engl. Threat Modeling) ist eines der zentralen Konzepte …“ (Nachprüfung bestanden); BSI TR-03185 §3.2.3.3 „Das Bedrohungsmodell MUSS …“; Duden- und Wikipedia-Lemma 404; MDN deutsch ist maschinell übersetzt (schwacher Anker) | ersetzt die Welle-2-Zuordnung threat model NUR_ENGLISCH; R.8-Überschrift bleibt korrekt; GLOSSARY-Regel ergänzt |
| Entscheidungskopf | FEHLFORM (GO 2026-10-16); head NUR_ENGLISCH | Uni-Skripte (Würzburg, Düsseldorf) bleiben bei head/classification head; „Entscheidungskopf“ ist österreichischer Rechtsterm (RIS-Handbuch); einziger deutscher ML-Beleg Ultralytics „Klassifikationskopf“ (kommerziell) | RFC0002 auf Head-Formen gesweept |

**Korrekturen zum Stand der Wellen 1–3:**

1. Die Schlusszählung „Nutzlast, Prüflabel und Kanonität im aktiven Korpus je null“ (2026-10-14) war für Nutzlast falsch: Die Forschungsnotiz 2026-10-02-vermittelte-agent-netzwerkwege trug weiterhin acht Fließtext-Instanzen. Ursache: Die Zählung erfasste nur die je Sweep angefassten Dateien.
2. Der „Grep-Werkzeug-Artefakt“ aus der Korrektur der Verifikationsgeschichte ist aufgeklärt: RFC0000 steht in `.gitignore` („private Infrastruktur-Topologie, bleibt lokal“). Rekursive rg- und Grep-Scans überspringen ignorierte Dateien, Einzel-Datei-Aufrufe nicht. Die Beobachtung bleibt gültig, die Ursache ist der Ignore-Mechanismus. Künftig pro Datei oder mit `rg -uu` zählen.
3. Parallel-Drift: Commit `5e23152` (Confinement-Review, Tickets #100/#111) hat nach dem Root-Sweep drei neue „Wurzel“-Stellen eingebracht (macho_deps.ex:51, 150; llama-server-confinement:38) — im Welle-4-Sweep mitfixt. Beschlossene Kanons gelten sessionübergreifend; aktive Parallel-Sessions kennen sie nicht automatisch.

**Offen nach Welle 4:**

1. **Evidenz-Durchsetzung:** Die GLOSSARY-Regel „Evidenz nur in wörtlichen englischen Zitaten“ (2026-10-14) war nie korpusweit durchgesetzt. GO 2026-10-16, mit Ausnahmen ausgeführt und per `rg` nachgezählt: 55 Ersetzungen Evidenz→Belege/Nachweis — RFC0003 22× (u. a. „fehlende Evidenz“→„fehlende Belege“ :578, :1542; „Evidenzlücken“→„Beleglücken“ :386, :1104; „No-Effect-Evidenz“→„No-Effect-Nachweis“ :1215, :2192), research-Notizen 6× („Belegstufen“, „Belegkennzeichnung“, Überschrift „Belegstatus“), RFC0002 1× (:337), komki_policy 8×, komki_mediator 4×, komki_cli 14× (u. a. Profil-Strings „Probe-Beleg“). Ausnahmen bleiben: historisches RFC0001 (18×, Inventar), die Beweislabel-Definitionen der Probeberichte („Kernel-Evidenz“ als [E]-Label) und Code-Bezeichner (`missing_evidence`). Schlusszählung 2026-10-16: null Fließtext-Instanzen außerhalb der Ausnahmen; `mix format` fehlerfrei.
2. Bedrohungsmodell-Reklassifikation und Entscheidungskopf-Sweep: per GO 2026-10-16 entschieden und ausgeführt (siehe Verdikt-Tabelle).
3. K3-Verbkorreps unentschieden (Welle 1 hatte ingesten bereits offen): gesandboxt, gepinnt/pinnt, pollen, trackt/tracked/getrackt, gestagte, committeden.
4. Schwache Grenzfälle belassen: Wegwerf-Sessions (terminal_screenshot:115), Vorschlagserzeuger (RFC0002:86), Netz-Auswärts (llama-server-confinement:62), einspeisen (komki_cli README:158).
5. Adjudiziert behalten: eingefroren (RFC0002, K5-Präzidenz „eingefrorene Konfiguration“), Rollenetiketten (RFC0003:504, bewusste Etikett-Metapher, nicht der Label-Term), Vortraining, Aufnahme (RFC-5.4-Kernbegriff), Beweisbaum (etablierte Logik-Form), Arbeitsabläufe (generisches Deutsch, in RFC0003:736 bewusst von „kanonischen Workflows“ abgesetzt), Dissektion (Lehnwort, bei Ersteinführung definieren).
6. RFC0000 (lokal, gitignored): Wurzel-Grenzen :422, Sitzung/Sitzungsgedächtnis :67, :91, :369, Lesemaschine :76, :457 — Inventar, historisch, bleibt lokal unkorrigiert.

## Bestätigte Korpus-Befunde (Extraktion Welle 1, per Grep verifiziert)

### Widersprüche im Korpus (konsolidieren, GO abwarten)

- **Provenance-Familie:** „Provenienz“ (RFC0002:165, 184, 287, 319), „Provenanz“ (research/2026-10-04-probe-harness-sandbox.md:9, 161), „field provenance“ (research/2026-10-13-…-pace.md, englisch) — drei Formen für ein Konzeptfeld. Empfehlung liegt oben; Sweep wartet auf GO.
- **Wirkung vs. Effekt:** normativ bevorzugt „Wirkung“; daneben Effektplan (RFC0003:1411, 2059, 2097, 2187), Effektumfang (RFC0003:1206, 1402, 1415, 2099), in Tabellen-Eventnamen (`ExecutionCommitted`).
- **Bauanleitung vs. Bauauftrag:** Anhang-Überschriften „Bauanleitung für …“ (RFC0003:1647 u. a.), aber R.11.4 „Anhang F enthält den Bauauftrag“ (RFC0003:1152; RFC0001:800).
- **Simulator vs. Simulationstool:** §12 didaktisch „Simulator“; Anhang-C-Überschrift „Bauanleitung für das Simulationstool“ (RFC0003:1647); RFC0001 nutzt Simulationstool (RFC0001:42, 53, 1295).
- **Ausführungsautomat vs. Ausführer:** F.5-Überschrift „Verbindlicher Ausführungsautomat“ (RFC0003:2166); Rollentabelle „Ausführer“ (RFC0003:2059).
- **Garantien vs. Zusagen:** R.8-Überschrift „Bedrohungsmodell und Garantien“ (RFC0003:1074), Abschnitt R.8.3 heißt „Zusagen“ (RFC0003:1096), der Vorverweis sagt „benennt die Zusagen“ (RFC0003:353) — Überschrift und Inhalt auseinander.
- **Beleg / Nachweis / Evidenz:** drei Beweis-Vokabeln im selben Korpus, nicht scharf getrennt (Belegablage, Nachweispflicht, Evidenzlücken).
- **Vermittler vs. Vermittlungsstelle:** definierter Begriff „Vermittler“; einmalig „zugelassene Vermittlungsstelle“ in der D.9-Testtabelle (RFC0003:1935).
- **Genus bei Audit:** Duden erlaubt „das oder der“; Korpus schwankt („ein bestandener Audit“ R.11; „Audit-Journal“ Kompositum) — eine Form wählen.
- **Proposal vs. Antrag:** „Antragsreife“ bewertet das ratsprojekte-Proposal (PendingProposal mit GO-Gate), nicht den Stadtratsantrag — beide Wörter laufen in den Skills nebeneinander; Glossar-Abgrenzung nötig.
- **Session vs. Sitzung:** Session = Harness-/CLI-/tmux-Kontext (komki_cli), Sitzung = Ratsversammlung (Skills) — beide aktiv; im Ratskontext Verwechslungsgefahr.
- **Schreibdrift:** getaggt (ratsprojekt_proposal:46) vs. getagged (antrag_generieren:166); read-only / Nur-lesen / nur-lesen; Sync vs. synchronisieren; Cross-Ref vs. Querverweis.
- **Hybride Textreste:** „## Known Lücken“ (sitzungsvorbereitung:821), „dropped sie still“ (:507), „unparserbarer Text“ (:505); tools/allgaeuer_zeitung_mcp/README.md ist komplett englisch, während AGENTS.md alle Tools deutsch beschreibt.
- **Positivbefund:** „Bericht aus dem Stadtrat“ wird nie zu „Stadtratsbericht“ verkürzt; Kurzform ist „Berichtsnotiz“ — Konsistenz erhalten und in GLOSSARY.md festhalten.
- **Distillat vs. Kondensat:** AGENTS.md §10 und das Glossar sagen „ratsprojekte ist das Distillat“; workflows.md und prerequisites.md nutzen „(Nextcloud-)Kondensat“ für das ODS-Projektdigest (workflows.md:260–409, prerequisites.md:165,226, GLOSSARY.md — ehem. nomenklatur.md:254) — zwei verwandte Destillations-Metaphern, deren Verhältnis zueinander nirgends erklärt ist. Welle-2-Befund: „Distillat“ ist eine FEHLFORM — kanonisch „Destillat“ (Duden 404 für Distillat, DWDS leitet auf Destillat weiter; deutsche KI-Fachtexte sagen Wissens-/Modelldestillation). Sweep wartet auf GO; „Kondensat“ bleibt als eigener Begriff (Nextcloud-ODS-Digest) und bekommt eine definierende Abgrenzung zum Destillat.
- **AI vs. KI:** AGENTS.md mischt beide Reihen („ein AI-Harness für Ratsarbeit“ :5, „Die KI entscheidet nichts ohne GO“ :83, „AI-Enabled“ §5); ratsprojekte-lifecycle.md sagt „AI-Sitzung“ (:157), RFC0002 durchgängig „Session“ im Harness-Sinn. Eine Reihe wählen.
- **Trusted Base vs. vertrauenswürdige Basis:** RFC0003 konsequent deutsch („vertrauenswürdige Basis“, :348, :1082); research-Notizen konsequent englisch („Trusted Base“/„Trusted-Base“, burrito-packaging:22–227, elixir-cli:10–187) — Doppelreihe, eine festlegen.
- **Orchestrator vs. Orchestrierer:** vault_suche:168, vermittelte-agent-netzwerkwege:22–375 und komki_cli-Code sagen Orchestrator; agent-runtime-sandbox-optionen:346 sagt Orchestrierer.
- **Kleindrifthäufung:** „Canarien“ (probe-harness:108) vs. „Kanarien“ (:148); „Goldstandard“ (NOM-Regel, lehnt „Gold-Set“ ab) vs. „Goldset“ (jev-alternativen:82); „First-Party-Quelle“ (agent-runtime-sandbox-optionen:19) vs. „Primärquelle“ (RFC0003 und research, weit verbreitet).
- **Label-Doppelbenutzung:** RFC0003/NOM „Label“ = Sicherheits-Label; GitHub-Kontext „Label“ = Issue-Label (triage-labels.md) — bei Mischtext riskant, Kontext muss disambiguieren.

### Einzelne bestätigte Begriffe (für die Vollständigkeit; Klassifikation teils Welle 2)

Kontrollpunkt-Zeuge (RFC0003:1199, 2062), Wiederanlaufbefund (RFC0003:2086), Potenzmengenverband (RFC0003:1995, im DLM-Quellenkontext), Graduelle Freigabe (RFC0003:2019, als fett markierter Quellenbegriff), Vermittlungsstelle (RFC0003:1935).

### Domain- und Werkzeugbegriffe aus Skills, Apps und Tools (Extraktion Welle 1, per Grep verifiziert)

**Repo-Prägungen (Kandidaten für EIGENE_PRÄGUNG_OK oder Ersatz — Welle-2-Prüfung läuft):** Standortbestimmung (ratsprojekte-Domäne; AGENTS.md:150,180), Distillat (Vault→ratsprojekte-Metapher; AGENTS.md §10, README:13, ratsprojekt_proposal), Quellenpflicht (Repo-Norm, AGENTS.md §6, 8 Skills), Quellenbindung (komki_cli — anderes Konzept als Quellenpflicht), Verdichtung (bericht_aus_dem_stadtrat), hartkodiert (sitzungsvorbereitung:72, komki_cli-Kommentare und Tests), Kanonität/Kanonitäts-Tripwire (komki_policy-Vertrag:334), Datenvertrag (CONTRACT), Prüflabel (CONTRACT), Auswerter-Orakel (CONTRACT:328; Kalque-Verdacht zu test oracle), Aktualitätsbezug und Referenzkommunen (antrag_generieren), Boot-Gate und Grenz-Gates (komki_cli, auch README:39), Claim-Lock (terminal_screenshot:98).

**Denglish-Formen (K3, zur Entscheidung):** Vault-Write (sitzungsvorbereitung:531), Vault-Komposita (Vault-Notiz, Vault-Tag, Vault-Zugriff), ingesten/ingestet (AGENTS.md:3,143; Skills — als Verb deutsch flektiert), getaggt/getagged (Drift, s.o.), „Known Lücken“ (Hybrid-Überschrift, s.o.).

**Feste Phrasen (K5, verifiziert):** „Die KI berät, der Mensch entscheidet“ (GO-Slogan in 6+ Skills), „ohne bestätigte Quelle/nicht belegt“ (5 Skills, teils wörtlich kopiert), „Vault = Source of Truth, ratsprojekte = Distillat“ (AGENTS.md §10, ratsprojekt_proposal:29–44), „Problem-first, nicht tool-first“ und „MVP vor Infrastruktur“ (AGENTS-Prinzipien), „Lese- und Kontextinstrument“ (sitzungsvorbereitung:46), „ethische Architektur“ (AGENTS.md:83, ratsprojekt_stand:58, ratsprojekt_delta:101). Mehrere Phrasen sind wörtlich zwischen Skills kopiert — Kopie ist kein Beleg für getrennte Konzepte; eine bewusste Kanonisierung wäre die sauberere Pflege.

### Docs- und Root-Korpus (Extraktion Welle 1, per Grep verifiziert)

**Strukturhinweis:** GLOSSARY.md im Repo-Root (hervorgegangen aus docs/nomenklatur.md) definiert bereits rund zwanzig Kernbegriffe (Sitzungsmappe, Ratsprojekt, Realisierungsstrang, Vorbedingung, Antragsreife, Beschlussvorschlag, Delta, Kollaborationsplattform, Vorbericht/Sitzungsnachbericht, Arbeitsraum, Bindung, Beobachter/Empfängerkreis, Betreiber- und Laufzeitumgebung, Ereignis, Vermittler/Inferenz-Engine, Freigabe, Connector u. a.). Die Sprachinventur dupliziert diese Definitionen nicht — sie klassifiziert und verweist dorthin.

**Das Glossar praktiziert die Inventur-Disziplin bereits punktuell** — Vorläufer dieses Dokuments: GLOSSARY.md lehnt „Null-Schuss“ für Zero-Shot und „Nachtraining“ für Fine-Tuning ausdrücklich ab, hält Fine-Tuning als akzeptierte Form fest und hält Overfetch(ing) englisch („Bleibt englisch; die Skills schreiben ‚Overfetch vermeiden‘“) — jeweils mit eigener Ablehnungsnotiz im Eintrag. Die Sprachinventur generalisiert dieses Muster.

**Repo-Prägungen (Welle-2-Prüfung läuft):** Regel-Prüfkern (AGENTS.md:141,276), Ausführer (RFC0003:2059 u. a.), Agentenhoheit (RFC0003:175,550), Erstklassifikation (R.2.5), Umgebungszulassung (agent-runtime-sandbox-optionen:34 u. a.), Vorbeleg (research-Notizen), Sandkasteninsasse (seatbelt-survey:90), 5-Strang-Recherche (workflows.md:188), Lerniteration (vermittelte-agent-netzwerkwege:15).

**Feste Phrasen (K5, verifiziert):** „kein stiller Fallback“ (RFC0003:1537, RFC0001:1185, research-Notizen — systematische Infrastruktur-Warnphrase), „Leseberechtigung ist keine Sendeberechtigung“ (RFC0003:201,540; RFC0001:191; mit dt./engl. Spiegelformel in den research-Notizen), „der Slug ist der stabile Vertrag“ (AGENTS.md Slug-Konvention), GO-Formel in Varianten („AI berät, Mensch entscheidet“ / „Die KI berät, der Mensch entscheidet“ / „Die KI entscheidet nichts ohne GO“) — keine Variante ist als kanonische Formel fixiert; Empfehlung: eine festlegen.

**Glossar-Lücken (Begriffe werden genutzt, aber in GLOSSARY.md nicht definiert):** Skill, Harness, Session, Ausführer, Kondensat, Regel-Prüfkern, Gate-Familie, Fördermittel-Serie.

### RFC0000 und RFC0001 — historische Dokumente (Nachextraktion exp-4, per Lektüre und rg verifiziert)

**RFC0000 (Sandbox-Threat-Modell, Outdated) trägt eine eigene Begriffswelt:** Senke(n)/Senken-Klasse, Schutzklasse, Treppe S1–S5, Gate („Als Gate zählt nur eine technische Hürde, die eine injizierte Anweisung nicht überwinden kann“), untrusted, Exfiltration, Whitelist, rw-Mounts, Deklassierung, handoff, Injektionsfläche, Nachher-Filter, Eingangsfilter-Pflicht, Klickpfad, Universalwerkzeuge, Vollzugriffs-Session, S1-Zwang, Musterbasis, Hausschlüssel, Container-Schmalbau, Kontextebene, Erbschaftsregel/-Default, Session-Klasse(n-Regel), Credential-Streuung, Werkzeugmacht, K7-Fracht, un-entgifbar, Abfluss-Dach, verletzende Paare — dazu als einziger RFC Schweizer Rechtschreibung (Massnahme, Verstösse, grösste, gemäss). Sprachbruch zur Nachfolge-Welt: RFC0001/0003 übernahmen die Konzepte, aber fast keines dieser Wörter.

**RFC0001 (Vorgänger von RFC0003):** Evidenz (~19×), Kontrollpunkt (≥14×), Orakel, Replay, append-only, Journalpartition, Ereignisplan (eigener Begriff neben dem früheren Effekt-/heutigen Wirkungsplan), Faktenfreigabe/Inhaltsfreigabe, Bindungserhaltung, Ableitungsprüfer, fehlgesteuert/fehlsteuerbar, Empfängertest, geheimnisabhängig, Außenkanal/Rückkanal, Stil-/Fakten-/Reihenfolgekanal, Kompositionsleck, geschützte/autoritative Verwaltung (der alte Name der Registry — die Umbenennung dokumentiert RFC0003:394), Hyperproperty, Idempotenz, Freigabeverbrauch, Journalstrecke, deklassiert, Exfiltration. RFC0001 ist historisch: keine Korrekturen, nur Inventar.

### Feste Phrasen (K5, aus der Extraktion — Trends, in Welle 2 zu vervollständigen)

„stille/stillschweigende Umgehung/Aufnahme“ (systematische Warn-Phrase, RFC0003 + RFC0001), „als benannte Grenze ausweisen“ (D.9-Umfeld), „führt keine neuen Befugnisse, Zustandsklassen oder Freigaben ein“ (Revisionsrefrain), „alle Treffer behalten und menschlich prüfen“ (RFC0002), „eingefrorene Konfiguration“ (RFC0002), „unangetasteter Holdout“ (RFC0002), „ist kein … -nachweis / reicht nicht“ (rhetorisches Negativmuster in beiden aktiven RFCs).

## Korrektur der Verifikationsgeschichte (2026-10-14)

**Rücknahme:** Die acht als „widerlegt“ vermerkten exp-1-Funde sind real. Die direkte Lektüre von RFC0000 (plus Verifikation mit rg als unabhängigem Werkzeug) bestätigt sie wörtlich: „Massnahme“ (0000:7, 409 f.), „Werkzeugmacht“ (:17), „un-entgifbar“ (:30), „Credential-Streuung“ (:56, 88, 174, 235, 375), „K7-Fracht“ (:74), „Abfluss-Dach“ (:332), „Session-Klasse(n-Regel)“ (:42, 332, 391 u. ö.), „Erbschaftsregel/-Default“ (:52, 63, 65 u. ö.), Schweizer Rechtschreibung („Massnahme“, „Verstösse“, „grösste“, „gemäss“ — RFC0000 ist der einzige RFC mit dieser Konvention).

Die ursprüngliche Widerlegung beruhte auf einem Suchwerkzeug-Artefakt: Das eingesetzte Grep-Werkzeug durchsuchte RFC0000 schlicht nicht — die kontrollierten Treffer stammten aus 0003/0001. exp-4 hatte die Funde wiedergefunden und exakt lokalisiert; die Zeilenangaben stimmen auf die Zeile.

**Zwei Lehren, jetzt doppelt gültig:** (1) Auch Negativbefunde brauchen Quellenpflicht — eine Widerlegung ist selbst eine last-tragende Behauptung und muss mit einem unabhängigen Werkzeug geprüft werden. (2) Korrupte Darstellung (Garbles in Lane-Ausgaben) heißt nicht automatisch falsche Daten: exp-1 präsentierte die RFC0000-Funde inhaltlich korrekt, nur unleserlich. Die Begriffe stehen jetzt unter den bestätigten Funden; RFC0000 ist historisch und wird nicht korrigiert.

## Offene Posten (Welle 2)

1. Alle Sprach-Sweeps sind ausgeführt und doppelt verifiziert — Paket 1+2, A–G, AI→KI in Code-Kommentaren und die Rest-Sweeps: RFC0003 Nutzlast→der Payload (neun Stellen), Kanonizitäts-Tripwire im CONTRACT, Validierungslabel-Reste inkl. evaluator.ex-Docstring. Schlusszählung 2026-10-14: Nutzlast, Prüflabel und Kanonität im aktiven Korpus je null; Payload 9×, Validierungslabel 12×; `mix format` fehlerfrei.
2. RFC0000/0001-Nachextraktion abgeschlossen; RFC0000-Begriffswelt und RFC0001-Vokabular inventiert (siehe Korrektur und historische Funde oben).
3. Glossar-Lücken sind gefüllt (Paket 3); neue Begriffe wandern bei Ersteinführung ins GLOSSARY.
4. Vor Veröffentlichung/Commit: humanizer-de-Pass über neue deutsche Textpassagen (Repo-Regel) und Spot-Check der Beleg-URLs.
