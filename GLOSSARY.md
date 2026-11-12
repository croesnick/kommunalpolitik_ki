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

**Definition:** Ein politisches Vorhaben auf dem Weg von der Idee zum Antrag
und weiter bis zur Umsetzung, geführt im ratsprojekte-Hub. Es hat eine
[Phase](#phase), einen nächsten Schritt, einen Verlauf und kann in einer
[Ablage](#phase) liegen. Dazu kommen Meinungsbilder, [Fakten](#fakt),
[Varianten](#variante), Anträge und Querverweise.

**Wo:** Im Hub (`apps/ratsprojekte`, Kontext `Ratsprojekte.Projects`). Eine
Idee darf dort entstehen, ohne dass es eine Vault-Notiz gibt.

**Slug:** Jedes Ratsprojekt hat einen Slug (`/projekte/{slug}`), der
gleichzeitig Vault-Tag ist (`#ratsprojekt/{slug}`). Siehe AGENTS.md §
Slug-Konvention.

**Lebenszyklus:** [`docs/ratsprojekte-lifecycle.md`](docs/ratsprojekte-lifecycle.md).

**Siehe:** [ADR 0004](docs/adr/0004-ratsprojekte-als-lokaler-hub.md).

---

### Phase

**Definition:** Wo ein Ratsprojekt auf dem Weg zum Antrag steht: Idee,
Meinungsbildung, Ausarbeitung, Im Rat, Umsetzung. Phasen sind frei
wechselbar, weil der echte Ablauf Schleifen hat; den Grund hält der Verlauf
fest, nicht eine Sperre im Code.

**Ablage:** Daneben kann ein Ratsprojekt in einer Ablage liegen: Ruht,
Verworfen oder Abgeschlossen. Dann ist es nicht mehr aktiv und behält seine
Phase. Ablegen und Wiederaufnehmen brauchen einen Grund.

**Nicht:** Status (so hieß es im alten Modell mit `idee`/`aktiv`). „Ablage“
heißt im Hub auch der Ort, an dem ein Antragstext liegt (Querverweis).

**Siehe:** ADR 0004, „Das Modell ist klein“;
[`docs/ratsprojekte-lifecycle.md`](docs/ratsprojekte-lifecycle.md).

---

### Kreis

**Definition:** Eine Gruppe von Menschen, die der Hub unterscheidet. Für die
Fassungen ist ein Kreis, wer eine bestimmte Fassung zu sehen bekommt:
[Redaktion](#redaktion) (Arbeitsansicht), [Engerer Kreis](#engerer-kreis)
(Stand), Basis (Befragungstexte), Öffentlichkeit (eingereichter Antrag und
Beschluss). Bei Meinungsbildern sagt der Kreis, wessen Meinung es ist:
Fraktion, Vorstand, Basis oder Externe.

**Nicht:** Persona (ein Mensch mit einem Ziel), Entscheidungsrecht (gehört
einem Gremium, etwa der Fraktion). Rechte je Eintrag gibt es nicht, nur feste
Fassungen.

**Siehe:** ADR 0004, „Personas, Kreise und Entscheidungsrechte sind getrennt“.

---

### Redaktion

**Definition:** Die Person, die den Hub führt. Sie sieht die Arbeitsansicht
mit allem, auch privaten Einträgen und Querverweisen, trägt ein, übernimmt
Vorschläge aus komki oder lehnt sie ab und entscheidet bei jeder Ausgabe, ob
ein Stand weitergeht.

**Nicht:** Ein Gremium. Die Redaktion trägt Entscheidungen von Fraktion und
Vorstand ein, trifft sie aber nicht.

**Siehe:** ADR 0004, Tabellen der Kreise und Entscheidungsrechte.

---

### Engerer Kreis

**Definition:** Fraktion und Vorstand. Sie bekommen den
[Stand](#stand): was neu ist, wer dran ist, Entscheidungen, Meinungsbilder,
Fakten und Anträge.

**Nicht:** Basis (bekommt nur die Texte einer Befragung), Externe wie
Elternbeirat, Vereine oder andere Fraktionen (bekommen nichts aus dem Hub).

**Siehe:** ADR 0004, „Personas, Kreise und Entscheidungsrechte sind getrennt“.

---

### Fakt

**Definition:** Eine Aussage zu einem Ratsprojekt mit Beleg (Fundstelle und
Quelle), Abrufdatum und Prüfstatus. Was die KI findet, gilt als nicht
verifiziert, bis ein Mensch die Fundstelle nachgeschlagen hat. URL und
Abrufdatum eines Fakts aus komki setzt der Vermittler aus dem Journal ein,
nicht der Agent.

**Nicht:** Quelle (die Herkunft, auf die sich ein Fakt stützt).

**Siehe:** ADR 0004, „Das Modell ist klein“; Schreibweg
[`docs/schnittstellen/connector-socket.md`](docs/schnittstellen/connector-socket.md).

---

### Variante

**Definition:** Eine Alternative zum selben Ziel eines Ratsprojekts, mit
Kennbuchstabe, Vorbedingungen und dem Status offen, gewählt oder verworfen
samt Grund.

**Nicht:** Realisierungsstrang (so hieß sie im alten Modell).

**Siehe:** ADR 0004, „Das Modell ist klein“.

---

### Realisierungsstrang

**Definition:** Der frühere Name der [Variante](#variante), aus dem Modell vor
dem Hub. Neue Texte sagen Variante.

---

### Vorbedingung

**Definition:** Eine rechtliche oder sachliche Voraussetzung, die erfüllt
sein muss, bevor eine [Variante](#variante) weiterverfolgt werden kann:
Rechtsgrundlage oder Voraussetzung, erfüllt oder offen. Ein Mensch setzt den
Status im Hub.

**Wo:** Im Hub, an einer Variante.

---

### Vault

**Definition:** Der Obsidian-Vault des Stadtrats. Quelle für Material — roh,
unstrukturiert, alles: Notizen, Emails, Recherchen, Bürgeranliegen,
Sitzungsmappen. Der Vault ist das Gedächtnis.

**Verhältnis zum Hub:** Der Vault ist Quelle für das Material, der Hub für den
Stand. Der Hub schreibt nie in den Vault. Siehe AGENTS.md §10.

**Vault-Tag:** `#ratsprojekt/{slug}` verknüpft Vault-Notizen mit
Ratsprojekten.

---

### Destillat

**Definition:** Im Modell vor dem Hub das konsolidierte Ergebnis, das aus dem
Vault in ratsprojekte floss. Seit ADR 0004 abgelöst: Der Hub führt den
[Stand](#stand), kein Destillat, und Menschen schreiben direkt hinein.

**Sprache:** Kanonisch „Destillat“ (Duden/DWDS); die frühere Schreibweise
„Distillat“ ist eine Fehlform und wurde am 2026-10-14 im Korpus ersetzt.

---

### Kondensat

**Definition:** Das projektdeskriptive ODS-Digest in der
Nextcloud-Kollaborationsplattform („Projekt-Kondensat“), das
`ratsprojekt_delta` gegen den ratsprojekte-Stand hält.

**Abgrenzung:** Kondensat ≠ Destillat. Das Kondensat ist ein Zwischenstand
aus geteilten Tabellen (Input für den Delta-Abgleich); das Destillat ist
das konsolidierte Ergebnis, das im alten Modell aus dem Vault in ratsprojekte floss. Das
Kondensat liefert Vergleichsdaten, keine Projekte.

**Stand:** Entfällt mit dem Hub. Das Sheet der Fraktion wird am Tag des ersten
ausgegebenen Stands eingefroren (ADR 0004, #54).

---

### Vorschlag

**Definition:** Was komki dem Hub über den Connector anbietet: genau ein
Ereignis mit Teilen, nach einem GO in komki. Im Hub entscheidet die
[Redaktion](#redaktion), welche Teile zum Stand passen. Abgewählte Teile
werden gelöscht, der Verlauf hält nur fest, dass einer nicht übernommen wurde.

**Nicht:** Antrag (der Stadtratsantrag ins RIS). Ein offener Vorschlag ist für
komki unsichtbar, auch als Anzahl.

**Siehe:** ADR 0004, „Menschen schreiben direkt, die KI schlägt vor“;
[`docs/schnittstellen/connector-socket.md`](docs/schnittstellen/connector-socket.md).

---

### Proposal

**Definition:** Im Modell vor dem Hub ein Vorschlag der KI in der Tabelle
`pending_proposals`, über den im Chat per `decide_proposal` entschieden wurde.
Beides ist mit ADR 0004 entfallen; an seine Stelle tritt der
[Vorschlag](#vorschlag), über den die Redaktion im Hub entscheidet.

**Sprache:** „Änderungsantrag“ ist tabu — kollidiert mit dem
Stadtrats-Änderungsantrag.

---

### GO

**Definition:** Das explizite Go (Genehmigung) des Menschen, ohne das die
KI keine schreibenden oder entscheidenden Aktionen ausführt. GO ist nicht nur
Arbeitsregel, sondern ethische Architektur: demokratische Verantwortung bleibt
beim Menschen. In komki erteilt die nutzende Person das GO im Freigabefenster;
im Hub entscheidet die Redaktion selbst, eine KI führt dort keine
Entscheidung aus.

**Siehe:** AGENTS.md §7.

---

### Antragsreife

**Definition:** Eine Checkliste im Hub, die zeigt, wie weit ein Ratsprojekt
für einen Antrag ist: Nutzen, Erfolgsmaß, Beschlussvorschlag, Adressat,
verifizierte Fakten, gewählte Variante und erfüllte Vorbedingungen, Festlegung
der Fraktion. Sie sperrt nichts; ob ein Antrag eingereicht wird, entscheidet
die Fraktion.

**Siehe:** [`docs/ratsprojekte-lifecycle.md`](docs/ratsprojekte-lifecycle.md),
Abschnitt „Antragsreife“.

---

### Beschlussvorschlag

**Definition:** Der konkrete Text, der als Beschlussvorschlag in eine
Sitzung eingebracht wird. Sachlich formuliert, mit klarem Adressaten
(Stadtrat, Bürgermeister, Vergabeausschuss).

**Wo:** Im Hub als Feld am Antrag (`motion_text`). Der Antragstext selbst
liegt nicht im Hub.

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

**Referenz:** Ratsprojekte verweisen über eine Quelle vom Typ `sitzung`
auf Sitzung, TOP und Beschluss (`ris_sitzung_id`, `ris_top`,
`beschluss_nr`).

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

## Beteiligungsbegriffe

Das Format dieser Begriffe an der Grenze zwischen Hub und Plattform steht in
[`docs/schnittstellen/befragung.md`](docs/schnittstellen/befragung.md).

### Beteiligungsplattform

**Definition:** Das Werkzeug, das einen Kreis anonym zu mehreren Themen befragt.
Eigenständig und austauschbar; der Hub kennt weder Namen noch Adresse.

**Nicht:** Meinungsbildungstool, Umfragetool.

### Befragung

**Definition:** Eine Frage an einen Kreis zu mehreren Themen. Im Hub bündelt
sie mehrere Ratsprojekte, mit Frist. Sie ist der Übergabepunkt zwischen Hub und
Beteiligungsplattform und läuft erst, wenn die Redaktion das Hochladen bestätigt
hat. Danach bleibt sie als Ergebnisseite stehen, in der Reihenfolge der Ideen.

**Nicht:** Umfrage, Abstimmung, Runde.

### Befragungspaket

**Definition:** Die Datei mit den Texten einer Befragung, die vom Hub zur
Beteiligungsplattform getragen wird.

### Rücklauf

**Definition:** Die Datei mit Verteilungen und Argumenten einer Befragung, die
von der Beteiligungsplattform zum Hub getragen wird. Sie ist ein vollständiger
Schnappschuss und ersetzt den vorigen.

**Nicht:** Ergebnis (das ist die Ansicht im Hub), Export.

### Thema

**Definition:** Ein Eintrag einer Befragung, mit eigens geschriebenem Titel und
eigener Beschreibung. Es kann zu einem Ratsprojekt gehören, ist aber keins.

### Verteilung

**Definition:** Die Zahl der Personen je Stufe zu einem Thema, über fünf Stufen
von „klar dagegen“ bis „klar dafür“. Sie ist anonym und nicht bindend.

**Nicht:** Ergebnis, Punktestand, Votum.

### Beteiligung

**Definition:** Die Zahl der Personen mit mindestens einer Antwort in einer
Befragung.

**Nicht:** Quote.

### Argument

**Definition:** Ein Text dafür oder dagegen zu einem Thema, den eine teilnehmende
Person schreibt. Er geht wörtlich und ohne Bezug zu ihr an die Befragenden.

**Nicht:** Kommentar, Beitrag.

### Fremder Text

**Definition:** Text in ratsprojekte, den kein Mensch aus der Redaktion geschrieben
oder gelesen und gespeichert hat, etwa Argumente und noch nicht zugeordnete
Vorschläge aus einem Rücklauf. Menschen lesen ihn wörtlich, für komki bleibt er
unsichtbar.

### Meinungsbild

**Definition:** Der Eintrag im Hub, was ein Kreis zu einem Ratsprojekt denkt:
Datum, ein Satz, optional eine Verteilung. Es kann aus einem Rücklauf entstehen,
aber auch aus einem Handzeichen am Stammtisch.

**Nicht:** Stimmungsbild, Abstimmungsergebnis.

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

### Referenzszenario

**Definition:** Eine erfundene, durchgehende Geschichte aus der Ratsarbeit,
die alle kanonischen Workflows aus RFC 0003 und alle Quellen von komki
verbindet. Sie beschreibt, was komki können soll, und dient zugleich als
Spezifikation der Szenario-Tests und als Vorlage für die Doku-Site.

**Abgrenzung:** Ein kanonischer Workflow (RFC 0003, R.7.1–R.7.3) ist ein
einzelner normativer Ablauf; das Referenzszenario setzt die Workflows zu
einer Geschichte zusammen und erfindet keine eigenen Regeln.

**Siehe:** [Referenzszenario „Radweg Bahnhofstraße“](docs/szenarien/radweg-bahnhofstrasse.md).

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

### Gemeinsam gebundener Speicher

**Definition:** Ein Speicher, der seine Einträge nicht nachweisbar trennt und
deshalb als Ganzes genau ein Label trägt. Sein Empfängerkreis sind die
Beobachter des Bestands. Beispiel: ratsprojekte mit `ratsprojekte@1`.

**Nicht:** labelführender Speicher (der prüft je Eintrag).

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md), R.4.4.

---

### Stand

**Definition:** Die Fassung von ratsprojekte für den engeren Kreis, also
Fraktion und Vorstand: wer dran ist, was neu ist, Meinungsbilder, Fakten,
Anträge und alle aktiven Projekte. Private Einträge und Querverweise fehlen.

**Nicht:** GO-Stand oder Regelstand Γ (Zustände im Sicherheitsmodell);
Ausgabe (was ein Arbeitsraum erzeugt).

---

### Ausgegebener Stand

**Definition:** Ein einzelnes, datiertes Dokument aus dem Stand, das die
Redaktion bewusst an Fraktion und Vorstand weitergegeben hat. Es ändert sich
danach nicht mehr und lässt sich nicht zurückholen, eine Korrektur wirkt nur
nach vorn.

**Nicht:** Rückblick (dieselbe Fassung ab einem frei gewählten Tag, nur zur
Vorbereitung, nicht weitergegeben).

---

### Maschinenlesbarer Stand

**Definition:** Die Fassung des Stands, die komki lesen darf. Sie enthält nur
ausdrücklich erlaubte Felder, also weder private Einträge noch Querverweise,
offene Vorschläge oder fremden Text. Der Hub schreibt sie beim Ausgeben eines
Stands als Datei, versiegelt für komki; öffnen kann sie nur komki mit Touch ID.
Aufnehmen darf sie nur ein [Projektraum](#projektraum).

**Nicht:** Stand (die Fassung für Fraktion und Vorstand, sie zeigt auch Argumente).

**Siehe:** [`docs/schnittstellen/stand.md`](docs/schnittstellen/stand.md).

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
allein bildet noch keinen solchen Arbeitsraum. Ohne Startvertrag gibt es
keinen Arbeitsraum; seine Bindungen sind die einzige Angabe von B_W. Eine
andere Bindungsmenge heißt ein anderer Arbeitsraum, nie ein geänderter.

**Kennung und Titel:** Die Kennung ist ein inhaltsleeres Wortpaar wie
`stiller-reiher`. komki vergibt sie, sie ist je komki-Instanz eindeutig,
bleibt unverändert und wird nie neu vergeben. Der Titel, etwa „Mappe
Stadtrat 17.11.“, nennt das Thema. Weil schon die Themenwahl vertraulich
sein kann, trägt er die Bindungen des Raums und erscheint nur der
nutzenden Person, nie in technischen Spuren.

**Session im Raum:** Jede Session gehört zu genau einem Arbeitsraum. Ein
Raum kann beliebig viele Sessions haben. Eine Session in einem anderen Raum
fortzusetzen, ist eine Übergabe ihres Verlaufs und nur in einen Raum mit
mindestens denselben Bindungen zulässig.

**Offen und geschlossen:** Ein geschlossener Raum hat seine Aufgabe
erledigt. Er nimmt nichts mehr auf und startet keine Session mehr, bleibt
aber Quelle für spätere Übergaben. Schließen kann nur die nutzende Person,
ein Wiederöffnen gibt es nicht.

**Kurzform:** „Raum“ ist als Kurzform erlaubt, wo der Zusammenhang eindeutig
ist (Doku-Site, `komki raum`, Referenzszenario).

**Siehe:** [RFC 0003](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md).

In komki steht der Startvertrag als `contract`-Block in
`<base>/mediator/room.json` (Ticket #92).

---

### Projektraum

**Definition:** Ein Arbeitsraum, der `ratsprojekte@1` trägt und damit als
einziger den maschinenlesbaren Stand aufnehmen darf. Weil er den Stand
kennt, braucht dort jede Anfrage nach draußen ein GO.

**In komki:** Referenzraum `projektraum` (`komki raum projektraum`), der
Rechercheraum plus `ratsprojekte@1`.

**Siehe:** [Maschinenlesbarer Stand](#maschinenlesbarer-stand),
[Referenzszenario](docs/szenarien/radweg-bahnhofstrasse.md), Szene 12.

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

### Aufnahme

**Definition:** Der Schritt, mit dem ein Eingang Teil eines Arbeitsraums
wird. Zulässig nur, wenn das Label des Eingangs in der Bindungsmenge des
Raums liegt, der Raum gültig ist und die Aufnahme unter allen
Raumbindungen erlaubt ist. Auftrag, Verlauf, geladene Anweisungen und
Ergebnisse von Sub-Agenten sind ebenfalls Eingänge.

**Abgrenzung:** Eine Leseberechtigung an der Quelle ersetzt die Aufnahme
nicht. Im Vermittler heißt der Schritt `admit` (Gate 2).

**Nur-Aufnahme-Operation:** Eine Connector-Operation, deren Anfrage keine
Ausgabe ist: Sie hat keine Parameter, und ihre Umgebung zeigt sie niemandem
außerhalb des Raums. Der Vermittler entscheidet dann nur die Aufnahme, vor
dem Lesen und ohne GO-Weg. Einziges Beispiel ist das Lesen des
maschinenlesbaren Stands (`rp_stand_lesen`).

**Siehe:** RFC 0003 R.5.4, Connector-Vertrag §6.4 (`apps/komki_connector/CONTRACT.md`).

---

### Übergabe

**Definition:** Der Schritt, mit dem eine Ausgabe den Arbeitsraum verlässt:
an einen Empfänger, einen Speicher oder einen anderen Arbeitsraum.
Zulässig nur unter dem Label der Ausgabe; ein Zielraum prüft zusätzlich
seine eigene Aufnahme.

**Abgrenzung:** Eine Übergabe entfernt keine Bindung, dafür braucht es eine
Lockerung. Im Vermittler heißt der Schritt `transfer`, beim Schreiben in
einen Speicher `store` (beides Gate 1).

**Siehe:** RFC 0003 R.5.6, [Aufnahme](#aufnahme), [Lockerung und Lockerungsbefugnis](#lockerung-und-lockerungsbefugnis).

---

### Lockerung und Lockerungsbefugnis

**Definition:** Eine Lockerung erzeugt aus einer Ausgabe eine neue Ausgabe
mit weniger Bindungen, gedeckt durch eine konkrete Offenlegungsfreigabe.
Die Lockerungsbefugnis ist der Eintrag in einer Bindung, wer welche
Einschränkung für welche Ausgabe lockern darf. Ohne Eintrag ist keine
Lockerung zulässig.

**Abgrenzung:** Original und laufender Arbeitsraum behalten ihr Label. Ein
GO ersetzt keine fehlende Lockerungsbefugnis. Befugnisse sind strukturierte
Einträge `{authority, restriction, output}` im Γ (CONTRACT.md § 2.1); eine
Bindung, deren Empfängerkreis das Ziel ohnehin abdeckt, lockert nichts
und braucht keine Befugnis.

**Siehe:** RFC 0003 R.2.2, R.5.7; [Aktionsfreigabe und Offenlegungsfreigabe](#aktionsfreigabe-und-offenlegungsfreigabe), [Ausgabeart](#ausgabeart).

---

### Ausgabeart

**Definition:** Das `output` einer Lockerungsbefugnis und einer
Offenlegungsfreigabe: wofür eine Bindung gelockert werden darf — im
ersten gebauten Fall `ratsprojekte-essenz` (Arbeitstitel) für gegengelesene
Essenz aus dem Fraktionsraum in den ratsprojekte-Hub (Szene 13, #423).
Das Vokabular ist geschlossen (CONTRACT.md § 2.1), die Engine ordnet die
Ausgabeart der Zielumgebung zu und rechnet sie gegen die Freigabe nach;
der Agent benennt keine Ausgabeart.

**Abgrenzung:** Die Ausgabeart benennt den Zweck der Lockerung, nicht das
Ziellabel: `ratsprojekte-essenz` lockert auf `ratsprojekte@1`, aber das
Ziellabel steht in der Freigabe und wird separat geprüft (R.6.2).

_Vermeiden:_ Ausgabeform, Exportart.

**Siehe:** [Lockerung und Lockerungsbefugnis](#lockerung-und-lockerungsbefugnis), [Aktionsfreigabe und Offenlegungsfreigabe](#aktionsfreigabe-und-offenlegungsfreigabe).

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
Lockern von Bindungen (Herabstufungsbefugnis): Sie nennt Ausgabeart und
Ziellabel der Lockerung und wirkt nur, wenn jede lockerungsbedürftige
Bindung die Befugnis trägt (R.5.7). Seit #423 entscheidet die Engine
sie für `store` (`komki-release/2`, CONTRACT.md § 4.9), zuerst für
gegegengelesene Essenz aus dem Fraktionsraum in den ratsprojekte-Hub
(Szene 13).

**Siehe:** RFC 0003 R.6.1–R.6.3; [`CONTRACT.md`](apps/komki_policy/CONTRACT.md) § 2.6, § 4.6, § 4.9.

---

### Manuelle Inhaltsfreigabe und begrenzte Faktenfreigabe

**Definition:** Die zwei Modi kontrollierter Offenlegung. Bei der manuellen
Inhaltsfreigabe prüft eine berechtigte Person einen konkreten Text und gibt
genau ihn frei. Bei der begrenzten Faktenfreigabe werden Quelle, Version,
Fakten, Auswahl und Veröffentlichungsweise unabhängig vom geschützten
Agenten festgelegt; ein neuer Arbeitsraum schreibt den Text nur aus diesen
Fakten.

**Abgrenzung:** Die manuelle Inhaltsfreigabe sichert nur die unveränderte
Ausführung des freigegebenen Texts, nicht die Abwesenheit verdeckter
Kodierung. Die begrenzte Faktenfreigabe gibt die stärkere Zusage.

**Siehe:** RFC 0003 R.6.4, R.7.2.

---

### Essenz

**Definition:** Die gekürzte, gegengelesene Fassung eines vertraulichen
Texts für den ratsprojekte-Hub — etwa der Antragsentwurf aus dem
Fraktionsraum (Szene 13). Sie ist der einzige Inhalt, der aus
vertraulichen Räumen in den Hub gelangt: von Hand eingetragen oder,
seit #423, über komki als Lockerung mit Offenlegungsfreigabe und
Teileauswahl vor dem GO.

**Abgrenzung:** Die Essenz ist kein Zitat und kein Fakt mit Quelle, sie
trägt die eigene Substanz des Raums in der Wortwahl der nutzenden Person.
Nichtöffentliches gehört nie in die Essenz, auch nicht von Hand. Der
Faktenweg (G2) wäre die stärkere Form und ist für die Essenz noch
offen (#363).

_Vermeiden:_ Kurzfassung, Auszug, Zusammenfassung.

**Siehe:** [Manuelle Inhaltsfreigabe und begrenzte Faktenfreigabe](#manuelle-inhaltsfreigabe-und-begrenzte-faktenfreigabe), [Ausgabeart](#ausgabeart), [Gemeinsam gebundener Speicher](#gemeinsam-gebundener-speicher).

---

### Freigabefenster

**Definition:** Das Fenster außerhalb des Agenten, in dem die nutzende
Person ein GO für ein konkretes Ereignis erteilt oder verweigert. Der
Agent kann es weder öffnen noch beschreiben noch nachahmen.

_Vermeiden:_ komki-Fenster, GO-Fenster.

**Siehe:** [Freigabe und Freigabedienst](#freigabe-und-freigabedienst), [GO](#go).

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
je Release-Blocker genau den neu berechneten call-GO, während die
unüberbrückbaren Blocker (`workspace_invalid`, `label_not_preserved`, bei
`store` auch `recipient_not_allowed` und `recipients_unproven`) ihren
`neuer_raum`-Eintrag behalten — kein Befund einer solchen Entscheidung
bietet ein call-GO an. Dasselbe gilt im direkten Zweig bei `store` mit
unbelegter Beobachterliste (#432): Ein GO kann nicht belegen, wer mitliest.
Im Code als Remedy-Katalog (`KomkiPolicy.Remedies`,
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

**Definition:** Eine aufgezeichnete Anfrage samt Antwort an eine RIS-API,
als JSON-Datei, wie bei VCR oder ExVCR. Der Aufzeichnungs-Proxy (Recorder)
schreibt sie, der Mock spielt sie im Replay-Modus zurück, und aus mehreren
Kassetten entstehen inhaltsfreie Berichte: das inferred schema und das
Strukturprofil.

**Arten:** *Echte Kassetten* enthalten echte, auch nicht-öffentliche
Inhalte. Sie liegen nie im Repo und laufen nie durch eine Agenten-Session;
aufbewahrt werden sie verschlüsselt (`priv/ris_cassettes.exs`, Freigabe per
Touch ID) — Details im Connector-README, Abschnitt „Kassetten
verschlüsseln“; bis zur Verschlüsselung ist eine Kassette Klartext. Committbar
sind die inhaltsfreien Berichte (inferred schema, Strukturprofil) und
*synthetische Kassetten* aus dem Gartenstadt-Generator: erfundene Inhalte
im echten Format, per Konstruktion ohne echten Bezug und über den
N-Gramm-Abgleich freigegeben (`test/fixtures/gartenstadt/`).

**Wo:** [`apps/komki_connector_ris/README.md`](apps/komki_connector_ris/README.md)
§ „Aufzeichnung und Replay echter Antwortformate“.

---

### Inferred schema

**Definition:** Ein aus Beispieldaten abgeleitetes Formatschema (schema
inference): je RIS-Endpunkt die Schlüssel, Typen, Formen (ISO-Datum,
ID-Muster, Base64-HTML) und Array-Längen der Antworten, aber keine Inhalte.
Es entsteht aus Kassetten und ist der Vertrag zwischen echtem RIS und Mock;
`--compare` meldet Abweichungen zwischen zwei Aufnahmen (Schema-Drift).

**Abgrenzung:** Kein JSON Schema im Sinne des Standards, sondern ein eigenes,
committbares Berichtsformat. Datei- und Verzeichnisnamen heißen noch
`skeleton` (`priv/ris_skeleton.exs`, `priv/skeletons/`); früher hieß es
„Skelett-Bericht“.

**Wo:** [`apps/komki_connector_ris/README.md`](apps/komki_connector_ris/README.md)
§ „Schema inference: Format ohne Inhalte“.

---

### Strukturprofil

**Definition:** Der inhaltsfreie Bericht des Struktur-Extraktors
(`priv/ris_struktur.exs`) über die Belegung einer Aufzeichnung: je Sitzung
Teil-Layout und Status, je TOP restricted-Flag, Sichtbarkeit und Zähler für
Textblöcke, Abstimmungen und Dokumente. Tragbar ist nur, was Gäste am RIS
ebenfalls sehen könnten (fail-closed wie der Connector-Filter): Titellängen
nur für nachweislich öffentliche TOPs, Abstimmungsergebnisse nie, Gremien
nur als anonyme Indizes (`c1`, `c2`, …). Es ist die Vorlage des
Gartenstadt-Generators — die Antwortformate erzwingt der Konformitätstest
gegen das inferred schema.

**Wo:** committet unter `apps/komki_connector_ris/priv/strukturen/`.

---

### Gartenstadt

**Definition:** Das erfundene Datenuniversum der synthetischen Kassetten
(`priv/gartenstadt_daten.exs`): eine Kleinstadt mit erfundenen Gremien,
Themen, Straßen und Namen, deren Problemlagen nicht auf die Themen der
echten Aufzeichnungen zurückführbar sind (Negativliste — Sicherheit per
Konstruktion statt nur per Prüfung, Entscheidung in #313). Die Lindenallee
ist die reservierte Teststraße der Sonderfälle und fehlt im Straßenpool.

**Wo:** `apps/komki_connector_ris/priv/gartenstadt_daten.exs`;
Fixtures unter `apps/komki_connector_ris/test/fixtures/gartenstadt/`.

---

### N-Gramm-Abgleich

**Definition:** Das Freigabetor vor jedem Commit synthetischer Kassetten
(`priv/ris_ngramm.exs`): Wort-N-Gramm (Standard 6) über alle String-Werte
der Antwortkörper, Base64-HTML dekodiert, gegen die echten Aufzeichnungen.
Ein übereinstimmendes Gramm ist ein Fund (Exit 1). Läuft lokal bei der
nutzenden Person über die entschlüsselten echten Kassetten — echte Kassetten
liest kein Agent; die Fund-Zeile druckt den Streifen bewusst, er ist ja der
Leak.

**Wo:** `apps/komki_connector_ris/priv/ris_ngramm.exs`.

---

### Leak-Prüfung

**Definition:** Der Schritt zwischen Aufzeichnung und Versiegelung einer
Session: `ris_cassettes.exs check` durchsucht Klartext-Kassetten nach den
Geheimnissen aus `.env` und token-Datei (Auswertung exakt wie ratsinfo:
erste Fundstelle, auch auskommentierte oder `export`-Zeilen), im Rohtext
und in den Base64-dekodierten Bodies. Exit 1 gilt bei Funden und wenn die
Prüfung nicht vollständig war (unlesbare Dateien oder Verzeichnisse, kein
Geheimnis ladbar) — nichts geprüft ist nicht sauber.

**Wo:** `apps/komki_connector_ris/priv/ris_cassettes.exs`, Verb `check`
(#328).

---

### Sammel-Verzeichnis

**Definition:** Ein Kassettenverzeichnis ohne eigenen Klartext, das nur
Unterverzeichnisse hält — etwa die Kassetten-Basis
(`~/.local/share/kommunalpolitik_ki/ris-cassettes/`) mit ihren
Zeitstempel-Verzeichnissen. `check` steigt in es hinein und prüft die
Unterverzeichnisse statt seiner selbst.

**Wo:** `ris_cassettes.exs check` ohne Verzeichnisargument.

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
