# Nomenklatur — Fachbegriffe der Ratsarbeit

> **Zweck:** Dieses Dokument definiert die Begriffe, die in Skills, Tools,
> Doku und AI-Workflows konsistent verwendet werden. Es ist die
> Single Source of Truth für die Sprache des Projekts.
>
> Wenn ein Begriff in Code, Skills oder Doku auftaucht, muss er hier definiert
> sein. Wenn ein neuer Begriff eingeführt wird, wird er hier ergänzt.

---

## Kernbegriffe

### Sitzungsmappe

**Definition:** Eine Vault-Notiz, die alle Vorbereitungsergebnisse für eine
konkrete Stadtratssitzung bündelt: Agenda (TOPs), gelesene Vorlagen,
Querverweise zu Ratsprojekten, AZ-Artikel, Vault-Notizen und ggf.
Positionen/Fragen.

**Wo:** Im Vault. Pro Sitzung eine Notiz.

**Tool:** Vault-Write (externer Skill `obsidian-cli`). Aktuell nicht
integriert — siehe [`docs/workflows.md`](./workflows.md) WF 1.

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

### Distillat

**Definition:** Das konsolidierte, strukturierte Ergebnis, das aus dem
rohen Vault-Material destilliert wurde und in ratsprojekte einfließt. Ein
Distillat ist quellenbelegt, antragsreif (oder explizit nicht) und auf
einen Realisierungsstrang bezogen.

**Beziehung:** Vault = Source of Truth (roh), ratsprojekte = Distillat
(strukturiert).

---

### Proposal

**Definition:** Ein Vorschlag der AI, der in der
`pending_proposals`-Tabelle von ratsprojekte liegt und auf GO
(Genehmigung) durch den Stadtrat wartet. Die AI schlägt vor, der Mensch
entscheidet (GO-Prinzip).

**Typen:** `add_projekt` | `add_realisierungsstrang` | `change_status` |
`projekt_update` | `strang_update`.

**Status:** `pending` → `approved` | `rejected` (einmalig, irreversibel).

---

### GO

**Definition:** Das explizite Go (Genehmigung) des Stadtrats, ohne das die
AI keine schreibenden oder entscheidenden Aktionen ausführt. GO kann im
Chat erteilt werden — die AI führt es dann über das `decide_proposal`-MCP-
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
"gibt es seit dem letzten Sync neue Sitzungen/TOPs, die für eines meiner
Projekte relevant sind?" Basierend auf Schlagwörtern, Projekt-Titeln oder
verlinkten RIS-IDs. **Geplant**, nicht implementiert.

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
Die AI generiert den Text, das Posten bleibt beim Stadtrat (GO).

---

### Sitzungsnachbericht

**Definition:** Eine öffentlichkeitswirksame Nachricht nach einer
Stadtratssitzung, die die Ergebnisse und Beschlüsse zusammenfasst.
Berichtet, was beschlossen wurde und wie die Fraktion positioniert war.

**Erzeugung:** Aus den Beschlüssen (RIS-Daten / `ratsinfo show`).
Template-basiert. Die AI generiert den Text, das Posten bleibt beim
Stadtrat (GO).

---

## Querverweise

- [`docs/ratsprojekte-lifecycle.md`](./ratsprojekte-lifecycle.md) —
  Projektlebenszyklus (States, Transitions, Gates)
- [`docs/workflows.md`](./workflows.md) — Use Cases und Lückenanalyse
- [`AGENTS.md`](../AGENTS.md) — Projekt-Prinzipien, Architektur, Guardrails
