# GLOSSARY — Kanonische Nomenklatur des Repos

> **Zweck:** Dieses Dokument ist die kanonische Nomenklatur des Repos: die verbindlichen
> Begriffe aller Domänen — Ratsarbeit, IT-Sicherheit, lokales ML, Harness und Werkzeuge.
> Wer einen Begriff benutzt — Mensch oder AI-Harness — folgt hier der Definition.
> Neue Begriffe werden bei ihrer Ersteinführung hierher eingetragen.
>
> **Sprachregelung:** Etablierte englische Fachbegriffe bleiben englisch, etablierte
> deutsche Begriffe werden deutsch verwendet, Neuprägungen werden bei Ersteinführung
> definiert. Klassifikation, Quellenbelege und Entscheidungen stehen in
> [`docs/sprachinventur.md`](docs/sprachinventur.md).

## Kernbegriffe

### Sitzungsmappe

**Definition:** Eine Vault-Notiz, die alle Vorbereitungsergebnisse für eine
konkrete Stadtratssitzung bündelt: Agenda (TOPs), gelesene Vorlagen,
Querverweise zu Ratsprojekten, AZ-Artikel, Vault-Notizen und ggf.
Positionen/Fragen.

**Wo:** Im Vault. Pro Sitzung eine Notiz.

**Tool:** Vault-Write (externer Skill `obsidian-cli`). Aktuell nicht
integriert — siehe [`docs/workflows.md`](docs/workflows.md) WF 1.

**Verwandt:** *nicht* verwechseln mit Fraktionsmappe (nicht implementiert,
nicht priorisiert).

---

### Ratsprojekt

**Definition:** Ein politisches Projekt, das im ratsprojekte-Dashboard
erfasst ist: mit Realisierungssträngen, Vorbedingungen, Quellen, Status und
Beschlussvorschlag. Ein Ratsprojekt ist das strukturierte Distillat, nicht
das Rohmaterial.

**Wo:** In ratsprojekte (Datenbank + LiveView + MCP).

**Slug:** Jedes Ratsprojekt hat einen Slug (`/projekte/{slug}`), der
gleichzeitig Vault-Tag ist (`#ratsprojekt/{slug}`). Siehe AGENTS.md §
Slug-Konvention.

**Vault-Notiz:** Jedes Ratsprojekt hat eine eigene Notiz im Vault. Dort
werden Recherchen, Emails, Fördermittel-Reports etc. angehängt. Der
Datenfluss ist einseitig: Vault → ratsprojekte.

**Verwandt:** Realisierungsstrang, Vorbedingung, Proposal, Antragsreife.

---

### Realisierungsstrang

**Definition:** Ein möglicher Weg, ein Ratsprojekt umzusetzen. Jedes
Ratsprojekt hat mindestens einen, oft mehrere (A/B/C), die parallel
verfolgt oder gegeneinander abgewogen werden. Jeder Strang hat eine
rechtliche Grundlage, eine Bedingung und geordnete Schritte.

**Wo:** In ratsprojekte, verknüpft mit einem Ratsprojekt.

---

### Vorbedingung

**Definition:** Eine rechtliche oder sachliche Voraussetzung, die erfüllt
sein muss, bevor ein Realisierungsstrang weiterverfolgt werden kann.
Vorbedingungen können erfüllt oder offen sein. Der Status wird manuell
gesetzt (GO-Prinzip).

**Wo:** In ratsprojekte, verknüpft mit einem Realisierungsstrang.

---

### Vault

**Definition:** Der Obsidian-Vault des Stadtrats. Source of Truth — roh,
unstrukturiert, alles. Notizen, Emails, Recherchen, Bürgeranliegen,
Sitzungsmappen. Der Vault ist das Gedächtnis.

**Datenfluss:** Vault → ratsprojekte (einseitig). Nie umgekehrt. Siehe
AGENTS.md §10.

**Vault-Tag:** `#ratsprojekt/{slug}` verknüpft Vault-Notizen mit
Ratsprojekten.

---

### Destillat

**Definition:** Das konsolidierte, strukturierte Ergebnis, das aus dem
rohen Vault-Material destilliert wurde und in ratsprojekte einfließt. Ein
Destillat ist quellenbelegt, antragsreif (oder explizit nicht) und auf
einen Realisierungsstrang bezogen.

**Beziehung:** Vault = Source of Truth (roh), ratsprojekte = Destillat
(strukturiert).

**Sprache:** Kanonisch „Destillat“ (Duden/DWDS); die frühere Schreibweise
„Distillat“ ist eine Fehlform und wurde am 2026-10-14 im Korpus ersetzt.

---

### Kondensat

**Definition:** Das projektdeskriptive ODS-Digest in der
Nextcloud-Kollaborationsplattform („Projekt-Kondensat“), das
`ratsprojekt_delta` gegen den ratsprojekte-Stand hält.

**Abgrenzung:** Kondensat ≠ Destillat. Das Kondensat ist ein Zwischenstand
aus geteilten Tabellen (Input für den Delta-Abgleich); das Destillat ist
das konsolidierte Ergebnis, das aus dem Vault in ratsprojekte fließt. Das
Kondensat liefert Vergleichsdaten, keine Projekte.

---

### Proposal

**Definition:** Ein Vorschlag der KI, der in der
`pending_proposals`-Tabelle von ratsprojekte liegt und auf GO
(Genehmigung) durch den Stadtrat wartet. Die KI schlägt vor, der Mensch
entscheidet (GO-Prinzip).

**Typen:** `add_projekt` | `add_realisierungsstrang` | `change_status` |
`projekt_update` | `strang_update`.

**Status:** `pending` → `approved` | `rejected` (einmalig, irreversibel).

**Abgrenzung:** Proposal ≠ Antrag. Das Proposal ist der interne
ratsprojekte-Vorschlag mit GO-Gate (Tabelle `pending_proposals`); der
Antrag ist der Stadtratsantrag ins Ratsinformationssystem. „Antragsreife“
bewertet ein Ratsprojekt bzw. sein Proposal — nie den Stadtratsantrag.

**Sprache:** Proposal bleibt der Repo-Term (Code-Vokabular: `PendingProposal`,
`decide_proposal`). Der Nachbarbegriff der deutschen ITIL-Terminologie lautet
„Change-Vorschlag“, ist aber ITIL-methodisch vorgeprägt. „Änderungsantrag“ ist
tabu — kollidiert mit dem Stadtrats-Änderungsantrag.

---

### GO

**Definition:** Das explizite Go (Genehmigung) des Stadtrats, ohne das die
KI keine schreibenden oder entscheidenden Aktionen ausführt. GO kann im
Chat erteilt werden — die KI führt es dann über das `decide_proposal`-MCP-
Tool aus. GO ist nicht nur Arbeitsregel, sondern ethische Architektur:
demokratische Verantwortung bleibt beim Menschen.

**Siehe:** AGENTS.md §7.

---

### Antragsreife

**Definition:** Der Reifegrad eines Ratsprojekts oder Proposals. Wird über
Hard Gates (quellen_vorhanden, adressat_gesetzt, beschlussvorschlag_konkret,
realisierungsstrang_vorhanden, vorbedingungen_erfuellt,
value_proposition_vorhanden, success_metrics_vorhanden) deterministisch
geprüft. Drei Stufen: `nicht_antragsreif` / `antragsreif` /
`antragsreif_mit_vorbehalten`.

**Siehe:** `ratsprojekt_proposal`-Skill, `check_antragsreife`-MCP-Tool.

---

### Beschlussvorschlag

**Definition:** Der konkrete Text, der als Beschlussvorschlag in eine
Sitzung eingebracht wird. Muss > 20 Zeichen haben, sachlich formuliert
sein und einen klaren Adressaten haben (Stadtrat, Bürgermeister,
Vergabeausschuss).

**Wo:** In ratsprojekte als Feld am Ratsprojekt.

---

### Quelle

**Definition:** Eine belegbare Informationsquelle für eine Aussage, die ein
Tool produziert und politisch relevant ist. Jede Quelle braucht:
Angabe der Herkunft (URL, Paragraf, Sitzungsdatum+TOP) und Abrufdatum.

**Quellenpflicht ist nicht optional** — siehe AGENTS.md §6.

**Quellentypen:** Gesetz (Paragraf), Förderprogramm (URL+Programmname),
Sitzung (Datum+TOP), Email (Absender+Datum), Vault-Notiz (Titel+Pfad, keine
amtliche Quelle).

---

### Delta

**Definition:** Ein strukturierter Vergleich, der zeigt, was sich an einem
Ratsprojekt ändern würde, wenn neue Informationen einflössen. Produziert
vom `ratsprojekt_delta`-Skill. Read-only — beratend, nicht entscheidend.

**Kategorien:** Neue Quelle, Vorbedingung erfüllt/neu, Strang-Relevanz,
Status-Änderung, Antragsreife, Widerspruch, Vault-Divergenz.

---

### Standortbestimmung

**Definition:** Die fachliche Lage- und Machbarkeitsbewertung eines
Ratsprojekts: welche Realisierungsstränge existieren, welche rechtlichen
Vorbedingungen stehen, welcher Weg ist gangbar — und welcher nicht.
Erzeugt von `ratsprojekt_stand` (read-only, beratend).

**Sprache:** Im Duden als Übertragung der „politischen Standortbestimmung“
geführt; hier auf Projekte bezogen.

---

### Aktualitätsbezug

**Definition:** Das Warum-jetzt-Argument einer Antragsbegründung:
Gesetzesänderung, Krise, neue Studie, aktuelles Ereignis, Förderfrist.
Bestandteil des Antragsmusters von `antrag_generieren`.

**Sprache:** Kein belegter Fachterminus — bei Verwendung definieren oder
als „Aktualität“ phrasen.

---

## RIS-Begriffe

### Drucksache

**Definition:** Eine Vorlage, die im Ratsinformationssystem (RIS) der
Kommune veröffentlicht ist. Enthält meist ein PDF mit dem eigentlichen
Antrag/Bericht. Wird bei der RIS-Synchronisierung von `ratsinfo` erfasst.

---

### TOP (Tagesordnungspunkt)

**Definition:** Ein Punkt auf der Tagesordnung einer Sitzung. Ein TOP
kann eine Drucksache referenzieren. `ratsinfo` erfasst TOPs als
zugehörige Einträge zu einer Sitzung.

---

### Beschluss

**Definition:** Ein formal gefasster Beschluss des Stadtrats (oder eines
Gremiums), dokumentiert im RIS. Ein Beschluss hat ein Datum, eine
Beschlussnummer und ist einer Sitzung/einem TOP zugeordnet.

**Lücke:** Ratsprojekte kann aktuell nicht auf eine konkrete
Beschlussnummer verweisen. Siehe `docs/workflows.md` WF 4.

---

## Vault-spezifische Begriffe

### Bürgeranliegen

**Definition:** Ein von einem Bürger gemeldetes Problem (Gefahrenstelle,
Beleuchtung, etc.). Wird im Vault erfasst und mit Fraktionssitzungen /
Vorstandssitzungen verlinkt, damit es dort besprochen wird.

**Wo:** Im Vault. **Nicht** in ratsprojekte (außer es reift zum
Ratsprojekt, dann über den `ratsprojekt_proposal`-Workflow).

**Tag-Konvention (geplant):** `#buergeranliegen/{datum-schlagwort}`.

---

### Fraktionssitzung / Vorstandssitzung

**Definition:** Interne Sitzungen der Fraktion bzw. des
Fraktionsvorstands. Nicht im RIS erfasst. Termine und Notizen im Vault.

**Beziehung:** Bürgeranliegen werden hier besprochen. Ratsprojekte werden
hier priorisiert. Sitzungsmappen werden hier vorbereitet (nicht für
Fraktionssitzungen — das wäre die Fraktionsmappe, nicht priorisiert).

---

## Workflow-Begriffe

### RIS-Sync

**Definition:** Der Vorgang, bei dem `ratsinfo sync` Sitzungen, TOPs und
Texte aus dem Ratsinformationssystem lokal speichert. Läuft unabhängig
von ratsprojekte.

### Ratsprojekte-Sync (Cross-Check)

**Definition:** Ein nachgelagerter Schritt nach dem RIS-Sync, der die
frischen RIS-Daten gegen die ratsprojekte-Datenbank hält und meldet:
„gibt es seit dem letzten Sync neue Sitzungen/TOPs, die für eines meiner
Projekte relevant sind?“ Basierend auf Schlagwörtern, Projekt-Titeln oder
verlinkten RIS-IDs. **Geplant**, nicht implementiert.

---

### Fördermittel-Recherche

**Definition:** Strukturierte Recherche nach Finanzierungsmöglichkeiten
kommunaler Projekte (Skill `foerdermittel_recherche`). Familienbegriffe:
Förderrichtlinie, Förderfrist, Kumulierungsregeln, Eigenanteil.

**Sprache:** Deutsch, Verwaltungsfachsprache — läuft nicht über die
KI/ML-Sprachregel.

---

## Kollaborations- und Kommunikationsbegriffe

### Kollaborationsplattform

**Definition:** Eine gemeinschaftlich genutzte Cloud-Plattform der Fraktion
(z.B. Nextcloud-Instanz). Dient als Ablage für geteilte Dokumente, Planungen,
Tabellen (z.B. Projekt-Kondensat als ODS) und Kalender.

**Anbindung:** Geplant via MCP (Nextcloud-MCP: WebDAV, CalDAV,
ODS-Parsing). Die Plattform ist parteiübergreifend — andere Fraktionen
nutzen ähnliche Setups.

**Datenschutz:** Zugangsdaten sind privat, Konfiguration lokal und
nicht-getrackt (wie `config.local.yml`).

---

### Sitzungsankündigung / Vorbericht

**Definition:** Eine öffentlichkeitswirksame Nachricht vor einer
Stadtratssitzung, die die relevanten TOPs und die Position der Fraktion
ankündigt. Kurz, sachlich, verständlich — für einen Kommunikationskanal
(WhatsApp, Social Media, Website) aufbereitet.

**Erzeugung:** Aus der Sitzungsmappe (WF 1) und den TOPs. Template-basiert.
Die KI generiert den Text, das Posten bleibt beim Stadtrat (GO).

---

### Sitzungsnachbericht

**Definition:** Eine öffentlichkeitswirksame Nachricht nach einer
Stadtratssitzung, die die Ergebnisse und Beschlüsse zusammenfasst.
Berichtet, was beschlossen wurde und wie die Fraktion positioniert war.

**Erzeugung:** Aus den Beschlüssen (RIS-Daten / `ratsinfo show`).
Template-basiert. Die KI generiert den Text, das Posten bleibt beim
Stadtrat (GO).

---

## KI-/ML-Begriffe

> **Sprachregel:** Fachbegriffe der KI/ML-Community werden nicht ad hoc
> übersetzt. Ohne akzeptierte deutsche Standardform bleiben sie englisch;
> existiert eine Standardform (wie „Goldstandard“), wird genau diese
> verwendet. Abgelehnt: „Null-Schuss“ für Zero-Shot, „Nachtraining“ für
> Fine-Tuning. Die Regel gilt für Skills, Tools und Doku.

### Zero-Shot

**Definition:** Ausführung eines Modells auf einer Aufgabe, für die es
nicht trainiert wurde — keine aufgabenspezifischen Beispiele, nur das
Vortraining. Layas Benchmark vergleicht Zero-Shot- gegen
Fine-Tuning-Genauigkeit.

**Sprache:** Bleibt unübersetzt; keine akzeptierte deutsche Form bekannt.

**Siehe:** [`RFC 0002`](docs/rfcs/0002-system-1-modelle.md), Abschnitt 1.1.

---

### Fine-Tuning

**Definition:** Nachträgliches Training eines vortrainierten Modells auf
eigenen Daten — im stuntd-Muster: eingefrorener Encoder, kleiner
trainierter Kopf auf eigenen Labels. Im System-1-Pilot ausdrücklich
Option, nicht Plan.

**Sprache:** „Fine-Tuning“ ist die akzeptierte Form; „Nachtraining“ ist
keine.

**Siehe:** [`RFC 0002`](docs/rfcs/0002-system-1-modelle.md), E6 und 6.4.

---

### Goldstandard

**Definition:** Ein handgelabelter Referenzdatensatz, an dem gemessen
wird, ob ein Modell oder Filter das leistet, wofür es eingesetzt wird.
Im System-1-Pilot: 30 bis 50 echte Triage-Fälle.

**Sprache:** „Goldstandard“ ist die etablierte deutsche Standardform der
NLP-Community; keine Mischbildungen wie „Gold-Set“.

**Siehe:** [`RFC 0002`](docs/rfcs/0002-system-1-modelle.md), Abschnitt 7.

---

### Overfetching

**Definition:** Mehr Treffer aus einer Quelle (Vault-Suche, AZ-Suche,
RIS) ziehen, als die nutzende Person verarbeiten kann. Die
Sammel-Workflows schreiben Obergrenzen dagegen vor (z.B. höchstens 5–7
Vault-Notizen je Suche).

**Sprache:** Bleibt englisch; die Skills schreiben „Overfetch vermeiden“
und „Overfetch-Grenze“. Keine Germanisierung wie „Überfetchen“.

---

## Harness- und Werkzeugbegriffe

> **Sprachregel:** Diese Begriffe bleiben englisch — die deutschsprachige
> Fachdokumentation (Anthropic, GitHub, git-scm, heise) benutzt selbst die
> englischen Formen; deutsche Eindeutschungen („Befähigungen“ für Skills,
> „Tresor“ für Vault, „Anzeigetafel“ für Board) sind nicht etabliert.

### Skill

**Definition:** Dateisystembasierter Anweisungssatz für den AI-Harness
(`SKILL.md` plus Skripte und Ressourcen), den das Modell bei Bedarf lädt.
Format der Agent-Skills-Konvention.

**Siehe:** [`AGENTS.md`](AGENTS.md) § „Agent skills“, `skills/`.

---

### Harness

**Definition:** Die Laufzeitumgebung, die Modell, Tools und Skills
orchestriert — im Repo meist „AI-Harness“. Das Wort „Orchestrierung“ ist
durch die Duden-EDV-Bedeutung von „orchestrieren“ gedeckt.

**Sprache:** Harness bleibt englisch; Komposita wie AI-Harness,
AI-Enabled, AI-Schnittstelle sind Produktbegriffe und bleiben.

---

### Session

**Definition:** Eine Instanz eines Harness-, Chat- oder CLI-Kontexts
(OpenCode-Session, tmux-Session, AI-Session).

**Abgrenzung:** Session ≠ Sitzung. Session gehört zum Harness; Sitzung ist
die Ratsversammlung des Gremiums (Sitzungsmappe, Stadtratssitzung).
„AI-Sitzung“ ist verboten — es heißt AI-Session.

---

### Ausführer

**Definition:** Die Rolle aus RFC 0003, die geprüfte Operationen
verbindlich ausführt (Rollen-Tabelle; Ausführungspfad des Vermittlers).

**Sprache:** Eigenprägung des RFC, bewusst deutsch; bei Ersteinführung
definiert.

---

### Regel-Prüfkern

**Definition:** `komki_policy`: rechnet aus, ob eine Absicht nach den
Regeln zulässig ist, und verifiziert die Begründung unabhängig nach. Rein
rechnend — führt selbst nichts aus.

**Siehe:** [`CONTRACT.md`](apps/komki_policy/CONTRACT.md).

---

### Gate

**Definition:** Festlegungspunkt, an dem eine Freigabe an Bedingungen
gekoppelt ist. Zulässige Bildungen des Repos: GO-Gate, Boot-Gate,
Grenz-Gates, Antragsreife-Gates, Hard/Soft Gates, Vermittler-Gates
(Gate 1/Gate 2).

**Sprache:** Basis ist der etablierte Quality-Gate-Begriff (deutsche
Fachtexte nutzen ihn); bei Ersteinführung definieren. Verdeutschungen wie
„Tor“ sind Fehlformen.

---

### Testorakel

**Definition:** Informationsquelle zur Ermittlung der erwarteten
Ergebnisse, die mit den tatsächlichen Ergebnissen eines Systems zu
vergleichen sind (ISTQB-Glossar deutsch). Kanonische Form für test
oracle; ersetzt die frühere Prägung „Auswerter-Orakel“.

**Siehe:** `apps/komki_policy` (Fixture-Auswertung).

---

## Sicherheitsmodell

Die folgenden Begriffe beschreiben das Modell für vertrauliche
KI-Arbeitsräume in [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).
Einträge mit **Wo:**-Zeile verweisen auf die Stelle, an der der Begriff
bereits implementiert ist; Einträge ohne **Wo:**-Zeile bezeichnen
bisher nur das RFC-Modell, noch keine implementierte Funktion.

### Datenobjekt

**Definition:** Eine bestimmte, versionierte Fassung eines Inhalts mit
zugehörigen Sicherheitsmetadaten. Diese Metadaten werden außerhalb des
Agenten verwaltet und können nicht durch dessen Aussagen ersetzt werden.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Bindung und Kennung

**Definition:** Eine Bindung ist eine versionierte Regel, die die zuständige
Autorität, zulässige Empfänger und Bedingungen benennt. Ihre Kennung, etwa
`ratsarbeit@1`, identifiziert diese Regelfassung und ist nicht das Label
eines Datenobjekts.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Label

**Definition:** Die Menge der Bindungen eines Datenobjekts, keine Rangstufe
einer Klassifikation. Ein Objekt ohne Label ist nicht dasselbe wie ein
Objekt mit einem ausdrücklich leeren Label.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Quarantäne

**Definition:** Der abgesonderte Eingang für unklassifiziertes Material. Ein
Objekt in Quarantäne trägt kein reguläres Label und gilt nicht als leere
Bindungsmenge. Herausholen kann es nur ein gesondert autorisiertes
Einordnungsverfahren; im Minimum ist das die Erstklassifikation durch eine
berechtigte Person. Ein Agent darf eine Einordnung nur vorschlagen.

**Wo:** In der SQLite-Registry des `komki label`-CLI (apps/komki_cli); der
Zustand wird über die Klassifikationsentscheidung geführt.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md), R.2.5.

---

### Klassifikationsentscheidung

**Definition:** Der nachvollziehbar festgehaltene Akt, der einem Datenobjekt
sein Label zuordnet: wer entschieden hat, auf welcher Grundlage und wann.
Erstklassifikation und Neuklassifikation sind menschliche Akte; jede
Entscheidung wird unveränderlich an die Objektversion gehängt und getrennt vom
Inhalt geführt.

**Wo:** In der SQLite-Registry des `komki label`-CLI (apps/komki_cli) als
append-only-Historie je Objektversion.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md), R.2.1 und R.2.5.

---

### Registry und Regelstand Γ

**Definition:** Die Registry ist ein geschütztes Register für Regeln,
Sicherheitsmetadaten und Berechtigungsdaten, unabhängig vom Agenten.
Gemeint ist weder die kommunale Verwaltung noch der Vault. Der Regelstand
Γ bezeichnet einen bestimmten Stand dieses Registers.

**Wo:** In der SQLite-Registry des `komki label`-CLI (apps/komki_cli);
der Γ-Export als `komki-registry/2` übergibt den Regelstand an die
Engine (`komki-policy`).

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Beobachter und Empfängerkreis

**Definition:** Beobachter sind Personen, Dienste oder Systeme, die auf
ein Ereignis oder seine Auswirkungen zugreifen könnten. Der
Empfängerkreis umfasst dagegen diejenigen, die die Information erhalten
dürfen, und ist nicht mit einer technischen Zugriffsliste gleichzusetzen.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Betreiber- und Laufzeitumgebung

**Definition:** Der tatsächliche Hosting- und Verarbeitungsweg einschließlich
Betreibern, Logs und Backups. Die Umgebung ist vom Arbeitsraum zu
unterscheiden und wird für jeden gewählten Verarbeitungszweig betrachtet.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Arbeitsraum und Startvertrag

**Definition:** Ein Arbeitsraum ist eine abgeschlossene Verarbeitungseinheit
mit eigenem Zustand und einer festen Menge von Bindungen. Sein unveränderlicher
Startvertrag legt diese Bindungen, den Zweck, zulässige Operationen und den
Lebenszyklus fest. Ein Chatfenster
allein bildet noch keinen solchen Arbeitsraum.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

In komki steht der Startvertrag als `contract`-Block in
`<base>/mediator/room.json` (Ticket #92).

---

### Raumdokument

**Definition:** Ein Dokument, das zum Arbeitsraum gehört: als Datei unter
`<base>/mediator/documents/`, als Objekt mit Typ `document`, Version und
Labels in `room.json`. pi liest es nur über `admit_document`; der Vermittler
entscheidet jede Aufnahme, der Dokument-Connector liest die Datei. Neue
Raumdokumente kommen über die Dateiaufnahme beim Session-Start
(`komki session DATEI`, Ticket #92).

**Siehe:** [Arbeitsraum und Startvertrag](#arbeitsraum-und-startvertrag),
[Quarantäne](#quarantäne).

---

### Raumbild

**Definition:** Die Beschreibung des Raums für die pi-Oberfläche: Name
(„recherche“, „vertraulich“ oder eigener Raum), Zweck, die Labels in B_W
mit ihren Bezeichnungen und für jeden Empfänger außerhalb des Rechners, ob
der Empfängerkreis aller Bindungen ihn einschließt („nach draußen offen“).
komki schreibt es vor jedem pi-Start als `raum.json` aus `room.json`, Γ und
dem Label-Store (Ticket #242).

**Abgrenzung:** Reine Anzeige. Was pi darf, entscheidet weiter der
Vermittler mit der Engine, Aufruf für Aufruf. Ins Modell gelangt das
Raumbild nicht.

**Wo:** `KomkiCli.Raumbild`; angezeigt von
`apps/komki_cli/priv/pi/komki-anzeige/raum.ts`.

---

### Ereignis

**Definition:** Die gesamte beobachtbare Wirkung eines Vorgangs, nicht nur
sein Nutzinhalt. Dazu gehören die Auswahl, das Ziel, Metadaten sowie das
Auftreten und die Reihenfolge des Vorgangs.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Vermittler und Inferenz-Engine

**Definition:** Der Vermittler kontrolliert und vermittelt die Ausführung
von Vorgängen. Die Inferenz-Engine entscheidet deterministisch anhand
logischer Regeln über deren Zulässigkeit. Sie ist hier kein LLM-Server.

**Abgrenzung:** Kein Router — der leitet transparent weiter, ohne zu
prüfen, zu filtern oder ein Journal zu schreiben. Kein Mediator im Sinn
des Entwurfsmusters — das koordiniert Peers untereinander. Der Vermittler
ist nicht umgehbar: Der Agent erreicht Operationen nur durch ihn,
Zugangsdaten bleiben in seinem Prozess.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md);
implementiert als `apps/komki_mediator` (Modul `KomkiMediator`) —
Codebezeichner englisch, Domänenbegriff deutsch wie bei `komki_policy`
(„Regel-Prüfkern“). Im Rollenmodell ist der Vermittler der PEP.

---

### Policy Enforcement Point (PEP) und Policy Decision Point (PDP)

**Definition:** Rollenpaar aus der Zugriffskontrolle. Der PDP entscheidet
über die Zulässigkeit einer Anfrage; der PEP setzt die Entscheidung an der
Ausführungsstelle durch und ist der einzige Weg dorthin. Im Modell ist die
Inferenz-Engine der PDP, der Vermittler der PEP.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md);
im Repo entscheidet `komki_policy` (PDP), der Vermittler
`apps/komki_mediator` setzt durch (PEP).

---

### Fassung

**Definition:** Die fest versionierte Gestalt des Angebots eines Vermittlers:
die Menge der Tools, die er bereitstellt. Jede Änderung erzeugt eine neue
Fassung; ein Rollover auf eine „aktuelle“ Fassung gibt es nicht. Der
allgemeine Wortgebrauch (versionierte Fassung eines Datenobjekts) bleibt
davon unberührt.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Connector

**Definition:** Eine begrenzte Schnittstelle zu einer Quelle oder einem
Ziel, deren Nutzung der Vermittler kontrolliert. Zugangsdaten bleiben
außerhalb des Agenten. Auch eine Suchanfrage ist ein ausgehendes Ereignis.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Freigabe und Freigabedienst

**Definition:** Eine Freigabe ist eine ausdrückliche Erlaubnis für einen
konkreten Fall, die der Freigabedienst prüft und festhält. Die Erlaubnis
einer Aktion erlaubt nicht automatisch eine Offenlegung oder die Lockerung
von Bindungen. Menschliches GO ist eine Zustimmung, ersetzt aber keine
fehlende Befugnis der zustimmenden Person.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Offenlegungsstand

**Definition:** Ein versionierter Nachweis zusammengehöriger geplanter
und bereits ausgelöster Offenlegungen. Er hält fest, welche Offenlegungen
bei einer weiteren Entscheidung gemeinsam zu berücksichtigen sind.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### Aktionsfreigabe und Offenlegungsfreigabe

**Definition:** Eine Aktionsfreigabe erlaubt eine bestimmte verbindliche
Wirkung (R.6.1) — eine Transaktion, nicht nur einen Text; sie wird an
den exakten call hash gebunden, mit Frische-Fenster und einmalig
verbrauchter Nonce (R.6.3). Eine Offenlegungsfreigabe erlaubt zusätzlich das
Lockern von Bindungen (Herabstufungsbefugnis); sie ist in
`komki_policy` bewusst nicht implementiert (`unsupported`).

**Siehe:** RFC 0003 R.6.1–R.6.3; [`CONTRACT.md`](apps/komki_policy/CONTRACT.md) § 2.6, § 4.6.

---

### Call Hash

**Definition:** SHA-256 (Hex, kleingeschrieben) über die kanonische
JSON-Darstellung des Objekts `{content_digest, object, operation,
workspace}` inklusive des finalen Newlines — die verbindliche Bindung
eines GO an den exakten Call (R.6.2: autorisiert wird ein Ereignis).

**Siehe:** [`CONTRACT.md`](apps/komki_policy/CONTRACT.md) § 2.6 (verbindliche Formel), § 6 (kanonische Darstellung).

---

### Erstklassifikation

**Definition:** Das gesondert autorisierte Einordnungsverfahren nach
R.2.5: nur ein reguläres Verfahren darf ein Quarantäne-Objekt einordnen;
die Erstklassifikation darf nicht durch vorherige Übermittlung an eine
nicht zugelassene externe KI erfolgen. In `komki_policy` als
`aktionsfreigabe` scope `object` im Remedy-Katalog abgebildet:
genau ein Objekt-Level-GO, danach laufende Aufnahmen ohne weiteres GO.

**Siehe:** RFC 0003 R.2.5; [`CONTRACT.md`](apps/komki_policy/CONTRACT.md) § 2.8.

---

### Remedy-Plan

**Definition:** (engl. remedy plan, APPA Theorem 5) Der begrenzte Katalog
legaler Fortsetzungen aus **genau vier Übergangstypen** — `fakt_nachreichen`,
`aktionsfreigabe`, `registrierte_transformation`, `neuer_raum` — den die
Engine zu jeder `deny`-/`indeterminate`-Entscheidung mitliefert. Der Katalog ist **beratend,
erzeugt keine Autorität**: keine Eingabe akzeptiert ihn, keine Fortsetzung
wird ausgeführt. Normative Ordnung: fakt < transformation < neuer Raum <
aktionsfreigabe — ein GO steht nie an erster Stelle. Die Norm gilt für die
deny-/indeterminate-Kataloge (§ 2.8); zwei bewusste Ausnahmen: Bei
`object_quarantine` ist das Objekt-Level-GO der Erstklassifikation der
einzige Katalog-Eintrag — es gibt für ein Quarantäne-Objekt keine
nicht-verletzende Fortsetzung —, und der Aktionsfreigabe-Zweig (§ 4.6) nennt
je Release-Blocker genau den neu berechneten call-GO (nur `workspace_invalid`
behält `neuer_raum`). Im Code als Remedy-Katalog (`KomkiPolicy.Remedies`,
CONTRACT § 2.8).

**Siehe:** [`CONTRACT.md`](apps/komki_policy/CONTRACT.md) § 2.8; RFC 0003 R.6;
`docs/research/2026-10-13-agent-policy-models-openappa-pace.md` (Move 1).

---

### Audit-Journal

**Definition:** Eine geschützte Historie von Entscheidungen, verbindlich
festgehaltenen Ausführungsaufträgen und zugehörigen Belegen. Ein Eintrag allein
beweist weder die tatsächliche Ausführung noch das Ausbleiben von
Auswirkungen.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

### PDR (Policy Decision Record)

**Definition:** Der einzelne Entscheidungsnachweis eines Vermittlungsaufrufs
im Audit-Journal: Intent-Hash, Payload-Hash und Γ-Stand-Hash des Aufrufs.

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

---

## komki-Bausteine

Begriffe aus der Umsetzung von komki, die über eine App hinaus vorkommen.

### Seatbelt-Profil

**Definition:** Die Sandbox-Regeln (SBPL, Sandbox Profile Language), unter
denen macOS einen komki-Prozess startet. Jeder Prozess hat ein eigenes
Profil: pi, llama-server, Vermittler, Egress-Proxy und jeder Connector.
komki erzeugt die Profile deterministisch, und `komki doctor` prüft, dass
die Neuerzeugung byte-gleich ist. Eine Abweichung (Drift) heißt: Das Profil
wurde verändert oder stammt aus einer anderen komki-Version.

**Wo:** `apps/seatbelt` (Library), Profile unter `<base>/profile/`.

**Sprache:** Seatbelt und Sandbox bleiben englisch.

---

### Programm-Pin

**Definition:** Die festgehaltene SHA-256-Prüfsumme eines Programms, das
komki startet (komki, escript, node, llama-server, komki-tresor, das
pi-Paket). Weicht die Prüfsumme ab, verweigert komki den Start, bis
`komki setup` die neue Prüfsumme nach Rückfrage übernimmt.

**Wo:** `pins` in `config.json`; `Seatbelt.Pins`.

---

### Socket-Token

**Definition:** Das geheime Zufallstoken (32 Byte, als Hex), mit dem sich pi
am Unix-Socket des Vermittlers ausweist. `komki up` schreibt es nach
`<base>/run/mediator.token` (0600). pi bekommt es über die Umgebung
(`KOMKI_MEDIATOR_TOKEN`) und reicht es an `komki-relay.js` weiter. Jede
Anfrage an den Socket trägt es als `Authorization: Bearer <token>`; ohne
oder mit falschem Token antwortet der Vermittler mit 401.

**Abgrenzung:** Nicht zu verwechseln mit dem Capability-Token des
[Sidecar](#sidecar)-Protokolls, das der Vermittler je Aufruf an einen
Connector gibt.

**Sprache:** „Kanal-Token“ ist eine Fehlform, ebenso „Kanal“ für die
Verbindung pi → Vermittler: Das Wort sagt nicht, was gemeint ist. Es heißt
Socket-Token bzw. Unix-Socket (Entscheidung 2026-10-29). Code-Bezeichner
wie `KomkiCli.Channel` bleiben englisch.

**Wo:** `KomkiCli.Channel`; Vertrag in
[`apps/komki_connector/CONTRACT.md`](apps/komki_connector/CONTRACT.md) § 8.

---

### komki-tresor

**Definition:** Das kleine Swift-Programm, das Schlüssel (etwa den
Brave-API-Key) mit der Secure Enclave versiegelt und nur nach Freigabe per
Touch ID oder Passwort öffnet. Im Schlüsselbund liegt nur das Siegel.

**Abgrenzung:** Ein Programmname, keine Übersetzung von Vault. Der Vault
bleibt Vault (siehe Sprachregel unter „Harness- und Werkzeugbegriffe“).

**Wo:** `apps/komki_cli/native/komki-tresor/`, gebaut von `mix compile`.

---

### Sidecar

**Definition:** Das Frame-Protokoll zwischen Vermittler und Connector als
eigene Library: Frames über Unix-Sockets, ein Capability-Token je Aufruf,
geschlossene Fehlercodes. Der Name folgt dem etablierten Sidecar-Muster: Ein
Hilfsprozess läuft neben dem Hauptprozess und spricht mit ihm über eine
schmale Schnittstelle.

**Wo:** `apps/sidecar`; Vertrag in
[`apps/komki_connector/CONTRACT.md`](apps/komki_connector/CONTRACT.md) § 3.

**Sprache:** Bleibt englisch, Code und Doku der Library sind englisch.

---

### Kassette

**Definition:** Eine aufgezeichnete Anfrage samt Antwort an das echte RIS,
als JSON-Datei, wie bei VCR oder ExVCR. Der Aufzeichnungs-Proxy (Recorder)
schreibt sie, der Mock spielt sie im Replay-Modus zurück, der
Skelett-Extraktor gewinnt daraus einen inhaltsfreien Formatbericht
(Skelett-Bericht).

**Abgrenzung:** Kassetten enthalten echte, auch nicht-öffentliche Inhalte.
Sie liegen nie im Repo; committbar ist nur der Skelett-Bericht.

**Wo:** [`apps/komki_connector_ris/README.md`](apps/komki_connector_ris/README.md)
§ „Aufzeichnung und Replay echter Antwortformate“.

---

### Bau aus dem Checkout

**Definition:** Der heute gültige Weg zu komki: Repo klonen, `make komki`
baut das Escript im Clone und legt einen Link nach `~/.local/bin`, danach
`komki setup`. Wer schon Homebrew nutzt, kann mit `make komki-tap` dasselbe
lokal als Homebrew-Paket installieren (Tap nur auf diesem Rechner).

**Abgrenzung:** Kein Release. Es gibt keinen veröffentlichten Tap und keine
heruntergeladene Datei.

**Wo:** [`docs/release.md`](docs/release.md) § „Lokaler Bau aus dem Checkout“.

---

### Wegwerf-Instanz

**Definition:** Eine zweite komki-Instanz mit eigenem `KOMKI_HOME` und
eigenem Port neben der Hauptinstanz, für echte Läufe, die die Hauptinstanz
nicht berühren sollen. Der Pfad muss kurz sein, weil Unix-Sockets höchstens
103 Byte lang sein dürfen (etwa `/private/tmp/komki-test`).

---

### Release

**Definition:** Ein veröffentlichter GitHub-Release eines Tools, getaggt
`<tool>-v<semver>` (z. B. `komki-v0.1.0`). Für komki ist der Ablauf in
[`docs/release.md`](docs/release.md) beschrieben, aber noch nicht in Kraft:
Bis auf Weiteres gilt der Bau aus dem Checkout.

**Begriffe im Release-Ablauf:** *Payload-Staleness* (eine neu gebaute
Burrito-Einzeldatei derselben Version nutzt den schon entpackten alten
Inhalt weiter), *Smoke-Matrix* (feste Prüfschritte gegen die Datei, die
veröffentlicht werden soll), *Publish-GO* (das eine GO, das Tag und
Veröffentlichung abdeckt).

---

## Sprachregeln und Festlegungen

Beschlossen in der Sprach-Session am 2026-10-14; Belege und
Entscheidungsgrundlagen: [`docs/sprachinventur.md`](docs/sprachinventur.md).

- **KI oder AI:** Im deutschen Fließtext: KI. Produktbegriffe bleiben
  englisch: AI-Harness, AI-Enabled, AI-Schnittstelle, AI-Session.
- **Session oder Sitzung:** Session = Harness-, Chat- oder CLI-Kontext;
  Sitzung = Ratsversammlung des Gremiums. Nie mischen.
- **GO-Formel (kanonisch):** „Die KI berät, der Mensch entscheidet.“
  Abweichende Varianten in Skills werden auf diese Formel zurückgeführt.
- **Beleg, Nachweis, Evidenz:** Beleg = einzelnes Quellenstück oder
  Quittung (receipt). Nachweis = der erbrachte Nachweis einer Pflicht.
  „Evidenz“ nur in wörtlichen englischen Zitaten; sonst Beleg oder
  Nachweis wählen.
- **Genus:** der Audit (der Duden erlaubt auch „das“; das Repo legt sich
  auf „der“ fest).
- **Provenance:** kanonisch „Provenienz“; „Provenanz“ ist eine Fehlform
  (Duden/DWDS ohne Eintrag). „field provenance“ bleibt englisch — eine
  deutsche Form ist nicht etabliert.
- **Destillation:** deutsch „Wissens-/Modelldestillation“; die Schreibweise
  „Distillat“ war eine Fehlform und ist ersetzt.
- **Payload:** kanonisch „der Payload“ (maskulin); „Nutzlast“ ist im
  Korpus ersetzt. Code-Bezeichner bleiben.
- **Bedrohungsmodell:** kanonisch deutsch „Bedrohungsmodell(ierung)“
  (BSI-Sprachgebrauch: Leitfaden Webanwendungen 4.3.4, TR-03185 §3.2.3.3);
  bei Erstnennung Klammer „(engl. threat modeling)“ möglich; Methoden- und
  Code-Bezeichner (STRIDE, `threat_model`) bleiben englisch. Ersetzt die
  Welle-2-Zuordnung threat model NUR_ENGLISCH (GO 2026-10-16).

## Querverweise

- [`docs/ratsprojekte-lifecycle.md`](docs/ratsprojekte-lifecycle.md) —
  Projektlebenszyklus (States, Transitions, Gates)
- [`docs/workflows.md`](docs/workflows.md) — Use Cases und Lückenanalyse
- [`AGENTS.md`](AGENTS.md) — Projekt-Prinzipien, Architektur, Guardrails
