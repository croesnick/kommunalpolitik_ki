# Doku-Site und Bildband für komki

Stand und Quellenabrufe: 2026-10-24.

| Feld | Wert |
|---|---|
| Art | Research-Report mit Empfehlung. Er trifft keinen Beschluss und baut nichts |
| Frage | Braucht ein bebildertes Benutzerhandbuch für komki („Bildband“) einen Static-Site-Renderer, oder reichen eigenständige HTML-Seiten? Wie sieht der Band aus? |
| Basis | AGENTS.md (Prinzipien 1 bis 5, 8, Sprachregelung, Lizenz-Bewusstsein), [`docs/workflows.md`](../workflows.md), [`apps/komki_cli/README.md`](../../apps/komki_cli/README.md), Skills [`terminal_screenshot`](../../skills/terminal_screenshot/SKILL.md) und [`mermaid_vision_loop`](../../skills/mermaid_vision_loop/SKILL.md), die Beispielseite `docs/site/komki-ausprobieren.html` (lokal, noch nicht eingecheckt) |

## 1. Kurzantwort

**Vorerst kein Renderer.** Der Bildband entsteht als eigenständige HTML-Seiten unter `docs/site/`,
mit einem gemeinsamen Stylesheet und einem Bildordner. GitHub Pages liefert den Ordner über einen
kurzen Actions-Workflow ohne Build-Schritt aus.

Gründe in einem Satz je Prinzip:

- **MVP vor Infrastruktur:** Die erste Seite existiert schon und funktioniert. Ein Renderer brächte
  Node- oder Python-Abhängigkeiten, Konfiguration und Theme-Arbeit, bevor es fünf Seiten gibt.
- **Problem-first:** Das Problem ist „komki verständlich zeigen“, nicht „Doku-Plattform betreiben“.
  Ein Bildband lebt von freiem Layout (großes Bild, Schrittfolge, Gegenüberstellung). Doku-Themes
  geben ein Sidebar-Layout vor, gegen das man dann arbeitet.
- **Unix-Prinzip:** Seiten, Bilder und Bild-Rezepte sind getrennte Dateien. Jedes Werkzeug (Screenshot-Skill,
  Mermaid-Loop, später Pagefind) arbeitet auf Dateien, keins kennt die Interna eines anderen.
- **Elixir-first:** Es gibt kein Elixir-Werkzeug, das einen Bildband gut kann (Abschnitt 3.8). Kein
  Renderer heißt auch: keine Nicht-Elixir-Abhängigkeit.
- **AI-Enabled:** Ein AI-Harness schreibt HTML so zuverlässig wie Markdown, wenn eine Vorlage-Seite
  und ein Stylesheet die Bausteine festlegen.

**Schwelle für einen Renderer** (Abschnitt 5): ab etwa acht bis zehn Seiten, oder sobald eine
seitenübergreifende Navigation, eine Volltextsuche über den ganzen Band oder Markdown als Quelle für
Menschen ohne HTML-Kenntnis gebraucht wird. Dann ist **Astro Starlight** die erste Wahl.

## 2. Ausgangslage

- **Doku heute:** Etwa 9 000 Zeilen RFCs und Research-Reports, dazu App-READMEs. Sie begründen
  Entscheidungen. Für Nutzung gibt es den Schnellstart im komki-README und die neue Beispielseite.
- **Beispielseite** `docs/site/komki-ausprobieren.html`: 522 Zeilen, 39 KB, eine Datei. Inline-CSS mit
  Farb-Tokens und Dark Mode, zwei handgezeichnete Inline-SVG-Diagramme, Befehle mit Kopier-Knopf,
  Terminal-Ausgaben als gestaltete `<pre>`-Blöcke. Gliederung: Bild im Kopf, Ablauf einer Anfrage,
  Räume, Start in elf Schritten, Sicherheitsgrenze, Fehlerhilfe, Grenzen. Das ist schon das Muster
  für den Band.
- **Bildwerkzeuge im Repo:** `terminal_screenshot` erzeugt aus einer echten tmux-Sitzung ein SVG
  (Beispiel [`session-beispiel.svg`](../../apps/komki_cli/assets/session-beispiel.svg)).
  `mermaid_vision_loop` rendert Mermaid lokal mit mermaid@11 und lässt die Lesbarkeit per Vision prüfen.
- **Toolchain:** `.tool-versions` pinnt Python 3.14.8 und Node 24.22.1. uv ist vorhanden.
- **Link-Check:** lychee prüft offline nur Markdown (`extensions = ["md"]` in `lychee.toml`). HTML-Seiten
  unter `docs/site/` fallen heute durch das Raster.

## 3. Optionen

Gemeinsame Kriterien: Eignung für Bilder und Schrittfolgen, Deutsch (Oberfläche und Suche),
Wartbarkeit durch einen AI-Harness, Toolchain, Lizenz, Aufwand für GitHub Pages, Einbindung der
vorhandenen Markdown-Doku. Versionen und Lizenzen per GitHub- bzw. Hex-/PyPI-/npm-API, Abruf 2026-10-24.

### 3.1 Kein Renderer: eigenständige HTML-Seiten

- **Bilder und Layout:** volle Freiheit. Großformatige Bilder, Inline-SVG mit CSS-Tokens (Dark Mode
  ohne zweite Bilddatei), Schritt-Layouts, Gegenüberstellungen. Die Beispielseite zeigt das.
- **Deutsch:** `lang="de"`, Texte ohnehin deutsch. Suche fehlt, ist aber nachrüstbar: Pagefind indexiert
  jeden Ordner mit statischem HTML, erkennt die Sprache am `lang`-Attribut und hat deutsches Stemming
  und eine deutsche Oberfläche. Es gibt eine Python-Variante (`pagefind[extended]`), also ohne Node.
- **AI-Harness:** gut, solange es eine Vorlage-Seite und ein gemeinsames Stylesheet gibt. Ohne diese
  Disziplin driftet CSS zwischen Seiten auseinander.
- **Toolchain, Lizenz:** keine. Pagefind ist MIT.
- **GitHub Pages:** Branch-Publishing erlaubt nur `/` oder `/docs` als Quelle. `/docs` würde den ganzen
  Doku-Ordner veröffentlichen und per Jekyll rendern. Besser ein Workflow mit `actions/checkout`,
  `actions/upload-pages-artifact` (nur `docs/site/`) und `actions/deploy-pages`. Kein Build-Schritt.
- **Markdown-Doku:** wird nicht eingebunden, sondern auf GitHub verlinkt. GitHub rendert sie bereits.
- **Schwäche:** Kopf, Navigation und Fuß wiederholen sich in jeder Datei. Ab vielen Seiten wird das lästig.

### 3.2 MkDocs Material und Zensical

- **Material for MkDocs** (MIT, 9.8.0 vom 2026-10-24): Das Projekt ist im Wartungsmodus. Laut Release-Notiz
  endet die Pflege am 2027-05-05; danach gibt es keine Fixes mehr. Für ein neues Vorhaben scheidet es aus.
- **Zensical** (MIT, 0.0.72, Nachfolger vom selben Team): Am 2026-11-05 erscheint 0.1.0 als erste
  „dependable“ Linie, das Projekt bleibt auf 0.x. Die Suche ist eine Eigenentwicklung und laut Doku
  „currently only available in English“. Für einen deutschen Band heute nicht reif.
- **Pro:** Python über uv, Markdown, bewährte Admonitions und Bild-Erweiterungen, Mermaid eingebaut (in Material).
- **Fazit:** Beobachten. Kein Einstieg in eine auslaufende Linie, kein Einstieg in eine Beta mit englischer Suche.

### 3.3 Astro Starlight

- **Stand:** MIT, `@astrojs/starlight@0.42.7` vom 2026-10-23. Noch 0.x, aber sehr aktiv.
- **Deutsch:** Deutsche Oberfläche eingebaut. Einsprachige deutsche Site über `locales.root` mit `lang: 'de'`.
  Suche per Pagefind, damit deutsches Stemming.
- **Bilder:** Astro optimiert Bilder beim Build. Komponenten für Schritte, Karten und Tabs (MDX).
  Mermaid nicht eingebaut; Community-Plugin oder vorgerenderte SVGs.
- **AI-Harness:** Markdown/MDX in `src/content/docs/`, Konfiguration in einer Datei. Gut wartbar.
- **Toolchain:** Node (per asdf vorhanden), `package.json` mit Lockfile, Renovate kann es pflegen.
- **GitHub Pages:** Build-Schritt plus die drei Pages-Actions. Astro dokumentiert den Weg.
- **Fazit:** Beste Wahl, falls ein Renderer nötig wird.

### 3.4 VitePress

- **Stand:** MIT. Stabil ist 1.6.4 vom 2025-08-05. Die Doku-Site zeigt bereits 2.0.0-alpha.20 (2026-09-04).
  Über ein Jahr kein stabiles Release, die nächste Major-Version ist Alpha.
- **Deutsch:** Oberflächentexte müssen selbst übersetzt werden. Lokale Suche (MiniSearch) ohne deutsches Stemming.
- **Mermaid:** nur über Drittanbieter-Plugin.
- **Fazit:** Technisch schlank, aber der Versionsstand spricht heute dagegen.

### 3.5 Docusaurus

- **Stand:** MIT, 3.10.2 vom 2026-07-10.
- **Pro:** Mermaid offiziell über `@docusaurus/theme-mermaid`. Deutsche Oberflächentexte vorhanden.
- **Contra:** React-Stack, schwerere Konfiguration. Suche über Algolia oder ein Community-Plugin.
  Für einen kleinen Band überdimensioniert.

### 3.6 Quarto

- **Stand:** MIT, 1.10.19 vom 2026-10-06. Als PyPI-Paket `quarto-cli` installierbar, also per uv.
- **Pro:** Mermaid nativ (`{mermaid}`-Zellen, im HTML clientseitig gerendert). Abbildungen mit
  Bildunterschriften und Layout-Rastern sind Kernfunktion. Auch PDF-Ausgabe möglich. Deutsch über `lang: de`.
- **Contra:** Ausgelegt auf wissenschaftliches Publizieren. Pandoc-Werkzeugkette mit eigener Logik,
  großer Download. Das Erscheinungsbild ist eher Bericht als Bildband.
- **Fazit:** Zweite Wahl, wenn PDF-Ausgabe wichtig wird.

### 3.7 Hugo und Zola

- **Hugo:** Apache-2.0, v0.168.0 vom 2026-10-13. Eine Binärdatei, sehr schnell. Mermaid nur per
  selbstgeschriebenem Render-Hook. Templates in Go-Template-Syntax, Themes von Dritten. Für einen
  AI-Harness gut machbar, für Menschen ohne Hugo-Erfahrung zäh.
- **Zola:** EUPL-1.2 laut GitHub-API, v0.23.6 vom 2026-09-12. Eine Binärdatei, eingebaute Suche
  (elasticlunr). Mermaid nicht eingebaut.
- **Fazit:** Beide brächten Theme-Arbeit mit sich. Kein Vorteil gegenüber Starlight für diesen Zweck.

### 3.8 Elixir-nativ

- **ExDoc** (Apache-2.0, 0.40.4): Extras als Markdown, Cheatsheets oder Livebooks. Mermaid per
  eingefügtem Skript. Das Erscheinungsbild ist API-Dokumentation. Für einen Bildband ungeeignet,
  für die Engine-Verträge (`CONTRACT.md`) später denkbar.
- **Tableau** (MIT, 0.30.0 vom 2026-01-24, rund 13 000 Downloads): echter Static-Site-Generator mit
  Markdown, Daten und Erweiterungen. Kein Doku-Theme, keine Suche, kleine Community. Man baute das
  Theme selbst. Das wäre Infrastruktur vor Inhalt.
- **NimblePublisher** (Apache-2.0, 2.1.0): Bibliothek, die Markdown zur Compile-Zeit in Elixir-Strukturen
  lädt. Kein Site-Generator, sondern ein Baustein für eine Phoenix-App.
- **Fazit:** Ernsthaft vorhanden ist nur Tableau. Es lohnt sich nicht, solange der Band ohne Generator auskommt.
  Elixir-first ist hier „prinzipiell dagegen“ erfüllt: Das Doku-Ökosystem liegt in Node und Python.

### 3.9 Übersicht

| Option | Lizenz | Stand | Bilder/Layout | Mermaid | Deutsch + Suche | Toolchain | Pages-Aufwand |
|---|---|---|---|---|---|---|---|
| Kein Renderer | — | — | frei | Inline-SVG, vorgerendert | `lang=de`, Suche über Pagefind nachrüstbar | keine | 1 Workflow, kein Build |
| Material for MkDocs | MIT | Pflegeende 2027-05-05 | gut | eingebaut | gut | Python/uv | Build + Deploy |
| Zensical | MIT | 0.0.x, Beta | gut | offen | Suche nur Englisch | Python/uv | Build + Deploy |
| Astro Starlight | MIT | 0.42, aktiv | gut | Plugin | deutsche UI, Pagefind mit Stemming | Node | Build + Deploy |
| VitePress | MIT | 1.6.4 stabil, 2.0 Alpha | mittel | Plugin | UI selbst übersetzen | Node | Build + Deploy |
| Docusaurus | MIT | 3.10 | gut | offiziell | UI ja, Suche extern | Node/React | Build + Deploy |
| Quarto | MIT | 1.10 | sehr gut (Abbildungen) | nativ | `lang: de` | uv (`quarto-cli`) | Build + Deploy |
| Hugo / Zola | Apache-2.0 / EUPL-1.2 | aktiv | Theme-abhängig | selbst bauen | Theme-abhängig | Binärdatei | Build + Deploy |
| Tableau | MIT | 0.30 | selbst bauen | selbst bauen | selbst bauen | Elixir | Build + Deploy |

## 4. Empfehlung im Detail

1. **Ordner** `docs/site/` mit `index.html` (Titelseite des Bands), je Szenario eine Seite,
   `assets/band.css` (aus der Beispielseite herausgelöst), `bilder/` für SVGs und `bilder/rezepte/`
   für die Entstehungsangaben (Abschnitt 7).
2. **Vorlage statt Generator:** Eine Seite gilt als Vorlage. Neue Seiten kopieren sie. Die Bausteine
   (`.figure`, `.cmd`, `.term`, Schrittliste, Hinweis-Kasten) sind im Stylesheet benannt und in einem
   Kommentar am Kopf der CSS-Datei beschrieben.
3. **Schriften selbst hosten.** Die Beispielseite lädt Google Fonts vom Google-Server. Das LG München I
   hat 2022 die dynamische Einbindung ohne Einwilligung als Rechtsverletzung gewertet (Az. 3 O 17493/20).
   Für ein Projekt mit Datenschutz-Grenze (Prinzip 8) gehört das nicht auf eine öffentliche Seite. Die drei
   Schriften stehen unter der SIL Open Font License und dürfen mitgeliefert werden.
4. **Ausliefern:** ein Workflow, der nur `docs/site/` als Pages-Artefakt hochlädt. Kein Jekyll, keine RFCs auf Pages.
5. **Prüfen:** lychee auf `docs/site/**/*.html` erweitern (eigener Aufruf oder `extensions` ergänzen),
   damit Bild- und Seitenlinks nicht still brechen.
6. **Suche:** erst, wenn sie fehlt. Dann Pagefind als Schritt im Workflow, ohne die Seiten zu ändern.

## 5. Schwelle für einen Renderer

Ein Renderer lohnt sich, sobald eines davon eintritt:

- **Mehr als acht bis zehn Seiten** und die wiederholten Köpfe, Navigationen und Füße kosten bei
  jeder Änderung mehr als eine Minute Abgleich.
- **Seitenübergreifende Navigation** (Sidebar, Vor/Zurück) wird gewünscht.
- **Menschen schreiben mit**, die Markdown können, HTML aber nicht.
- **Der Band soll Markdown aus dem Repo übernehmen** (etwa ein Glossar-Auszug), statt darauf zu verlinken.

Dann **Starlight**: deutsche Oberfläche ohne Eigenarbeit, Pagefind mit deutschem Stemming,
MIT, Node ist per asdf da. Die HTML-Seiten werden zu MDX-Seiten; Bilder und Rezepte bleiben unverändert.
Die Vorarbeit ist also nicht verloren.

**RFCs und Labbooks gehören auch dann nicht in den Band.** Sie sind Begründung und Arbeitsnachweis,
GitHub rendert sie gut, und 9 000 Zeilen würden den leichten Charakter erdrücken. Der Band verlinkt
gezielt auf einzelne Abschnitte (etwa RFC 0003, Abschnitt Arbeitsraum).

## 6. Konzept für den Bildband

### 6.1 Leitidee

Jede Seite ist **ein Szenario aus der Ratsarbeit**, nicht eine Funktion von komki. Die Überschrift ist
eine Situation („Nächste Woche tagt der Bauausschuss“), kein Befehl. Jede Seite hat ein großes Bild am
Anfang, eine Kernaussage in einem Satz, drei bis sechs Schritte mit Befehl und sichtbarer Ausgabe und
einen Kasten „Was komki hier nicht tut“. Lesezeit drei bis fünf Minuten.

Grundlage für die Szenarien: WF 1 (Sitzungsvorbereitung), WF 6 (Fördermittel-Recherche, hier als
Web-Recherche mit Quellen) und WF 11 (Bericht aus dem Stadtrat) aus [`docs/workflows.md`](../workflows.md),
die Skills [`sitzungsvorbereitung`](../../skills/sitzungsvorbereitung/SKILL.md) und
[`vault_suche`](../../skills/vault_suche/SKILL.md) sowie der heutige Funktionsumfang: RIS-, Web- und
Vault-Recherche über den Vermittler, die Räume recherche und vertraulich, Notizen nach `komki-test/`.

### 6.2 Gliederung

| Nr. | Seite | Kernaussage | Bilder | Umfang |
|---|---|---|---|---|
| 0 | **komki in einem Bild** (Titelseite) | Ein lokales Modell arbeitet in einem abgeschlossenen Raum; jeder Zugriff nach außen geht durch den Vermittler, der entscheidet und mitschreibt. | Großes Architektur-Bild (Mac, Sandbox, Vermittler, drei Connectoren); Kacheln zu den Szenarien | 1 Bildschirm |
| 1 | **komki in Betrieb nehmen** | In elf Schritten von null zur ersten Antwort, ohne Cloud. | Vorhanden in der Beispielseite; dazu ein echtes Session-SVG | bestehende Seite, gekürzt |
| 2 | **Nächste Woche tagt der Ausschuss** (Sitzungsvorbereitung, WF 1) | komki sucht die TOPs im RIS, findet passende Vault-Notizen und legt eine Vorbereitungsnotiz mit Quellen an. | Ablaufbild RIS → Vault → Notiz; Session-SVG mit Tool-Aufrufen; die fertige Notiz als Bild | 4 bis 5 Schritte |
| 3 | **Ein Thema schnell einordnen** (Web-Recherche, WF 6 light) | Websuche und RIS zusammen, jede Aussage mit URL und Abrufdatum (Quellenpflicht). | Session-SVG; Ausschnitt der Antwort mit hervorgehobenen Quellen | 3 bis 4 Schritte |
| 4 | **Was weiß ich schon?** (Vault lesen und schreiben) | komki sieht nur gelabelte Notizen und schreibt nur in einen eigenen Ordner. | Vorher/Nachher: Vault-Ordner mit sichtbaren und unsichtbaren Notizen; Frontmatter mit `komki_labels` | 3 Schritte |
| 5 | **Vertraulich arbeiten** (Raum vertraulich) | Im vertraulichen Raum sind vertrauliche Notizen lesbar und jede Web- und RIS-Suche gesperrt. | Gegenüberstellung der zwei Räume als Doppelbild; Terminal-Ausschnitt mit der Ablehnung | 3 Schritte |
| 6 | **Was hat die KI getan?** (Journal) | Jede Entscheidung steht im Journal, die Hash-Kette lässt sich prüfen. | Ein Journaleintrag, beschriftet; Ausgabe von `verify-journal` | 2 bis 3 Schritte |
| 7 | **Wenn etwas hakt, und was komki nicht kann** | `komki doctor` nennt den fehlenden Teil; Grenzen ehrlich benannt (lokales Modell, RIS-Gastzugang nur mit Titeln, #148). | Doctor-Ausgabe rot und grün nebeneinander | 1 Seite |

**Ausblick-Seiten**, sobald komki sie trägt: „Bericht aus dem Stadtrat“ (WF 11), „Antrag entwerfen“
(Skill `antrag_generieren`), Fördermittel-Recherche in voller Breite (WF 6). Sie entstehen erst, wenn
der Ablauf über den Vermittler läuft. Der Band zeigt nur, was heute funktioniert.

### 6.3 Bildsprache

- **Ein Bild pro Aussage.** Kein Bild nur zur Zierde.
- **Echte Ausgaben, erfundene Daten.** Terminal-Bilder stammen aus echten Läufen, aber gegen den
  Test-Vault (`apps/komki_connector_vault/priv/test-vault`) und den RIS-Mock
  (`apps/komki_connector_ris/priv/mock_ris.exs`). So sind sie reproduzierbar und enthalten keine
  personenbezogenen oder nicht-öffentlichen Inhalte (Prinzip 8).
- **Einheitliche Farben:** Erlaubt grün, gesperrt rot, Vermittler in Akzentfarbe. Dieselben Tokens in
  CSS, Inline-SVG und Terminal-Rendering.
- **Hell und dunkel:** Diagramme als Inline-SVG mit CSS-Variablen, damit sie dem Farbschema folgen.
  Terminal-SVGs sind von Natur aus dunkel und dürfen das bleiben.
- **Illustrationen sparsam:** einfache SVG-Piktogramme (Rathaus, Ordner, Schloss). Keine generierten
  Bilder mit erfundener Oberfläche, weil sie eine Funktion vortäuschen könnten.

## 7. Wie die Bilder reproduzierbar entstehen

| Bildart | Werkzeug | Quelle im Repo | Ergebnis |
|---|---|---|---|
| Terminal-Sitzung (pi-TUI) | Skill `terminal_screenshot` (tmux-Capture → `render_terminal_svg.py` → Browser-Prüfung) | Rezept: Prompt, Fenstergröße, Instanz-Setup | SVG in `docs/site/bilder/` |
| Befehl und kurze Ausgabe | gestalteter `<pre>`-Block wie in der Beispielseite | Ausgabe aus einem echten Lauf, gekürzt mit `…` | Text im HTML, kopierbar und durchsuchbar |
| Ablauf- und Strukturdiagramm | Mermaid-Quelle (`.mmd`), geprüft mit `mermaid_vision_loop`, als SVG eingecheckt | `docs/site/bilder/*.mmd` | SVG, kein Mermaid-JavaScript zur Laufzeit |
| Leitbild (Architektur, Räume) | handgezeichnetes Inline-SVG mit CSS-Tokens | direkt in der Seite | folgt Hell/Dunkel |

**Rezept-Datei** je Terminal-Bild (`bilder/rezepte/<bild>.md`): komki-Commit, Datum, Instanz-Setup
(Test-Vault, RIS-Mock, Raum), Fenstergröße, exakter Prompt, Schritte des Skills. Ein AI-Harness kann
ein Bild damit ohne Rückfrage neu erzeugen.

Hinweis: Der Mermaid-Skill pinnt mermaid@11, weil GitHub diese Major-Version rendert. Mermaid 12 ist
erschienen (Release vom 2026-10-13). Für vorgerenderte SVGs im Band ist die Version frei wählbar;
sie sollte im Rezept stehen.

## 8. Wie der Band aktuell bleibt

- **Stand-Zeile auf jeder Seite:** „Stand: komki `<commit>`, `<Datum>`“. Veraltete Seiten fallen so auf.
- **Abhängigkeiten sichtbar machen:** Jede Seite nennt im Kopf (`<meta name="komki-befehle">`) die Befehle
  und Dateien, die sie zeigt (`komki up`, `room.json`, `vault_search`). Ein `grep` findet bei einer
  Änderung am CLI die betroffenen Seiten.
- **Ticket-Disziplin:** Ändert ein Ticket sichtbares Verhalten von komki, prüft die Lane die betroffenen
  Seiten und nennt sie im Ticket. Das passt als eine Zeile ins [Lane-Protokoll](../agents/lane-protocol.md).
- **Neu erzeugen statt nachbessern:** Bilder werden aus dem Rezept neu gemacht, nicht von Hand retuschiert.
- **Später, wenn es sich lohnt:** ein Skript, das die Befehle der Seiten gegen Test-Vault und RIS-Mock
  ausführt und meldet, wo die Ausgabe abweicht. Erst ab mehreren Szenario-Seiten sinnvoll.

## 9. Abgrenzung zur bestehenden Doku

| | Bildband (`docs/site/`) | READMEs | RFCs, Handbuch, Research |
|---|---|---|---|
| Frage | Wie benutze ich komki in der Ratsarbeit? | Wie baue und bediene ich diese App? | Warum ist komki so gebaut? |
| Publikum | Ratsmitglieder, Interessierte, Mitstreitende | Entwickelnde | Entwickelnde, Prüfende |
| Form | Szenarien, Bilder, kurze Sätze | Befehlsreferenz | Argumentation, Belege |
| Ort | GitHub Pages | GitHub | GitHub |
| Verweise | verlinkt nach rechts | verlinkt nach rechts | verlinkt nicht zurück in den Band |

Der Band wiederholt keine Begründungen. Wo eine Seite ein „warum“ braucht, steht ein Satz und ein Link.
Sprachregelung und Glossar gelten auch im Band (Raum, Vermittler, Connector, Label, Vault).

## 10. Offene Punkte

- **Öffentlichkeit:** Der Band liegt dann auf einer öffentlichen Pages-Adresse. Inhalte nur mit erfundenen
  Daten (Abschnitt 6.3); vor dem ersten Deploy einmal prüfen (Prinzip 8, „keine öffentliche Bereitstellung
  ohne Prüfung“).
- **Titel und Ton:** „Bildband“ ist der Arbeitstitel. Ein Name für die Titelseite steht aus.
- **Beispielseite:** `docs/site/komki-ausprobieren.html` liegt nur lokal und ist noch nicht eingecheckt.

## 11. Nächste Schritte (Ticket-Vorschläge)

1. **Bildband-Gerüst in `docs/site/` anlegen.** Beispielseite einchecken, CSS nach `assets/band.css`
   herauslösen, Schriften selbst hosten und eine Titelseite `index.html` mit Szenario-Kacheln bauen.
2. **GitHub-Pages-Workflow für `docs/site/` ohne Build.** Ein Workflow mit `upload-pages-artifact` und
   `deploy-pages`, der nur den Bildband veröffentlicht; vorher Prüfung auf öffentliche Inhalte.
3. **Szenario-Seite „Nächste Woche tagt der Ausschuss“.** Erste Szenario-Seite gegen Test-Vault und
   RIS-Mock, mit Terminal-SVG aus dem Skill und Rezept-Datei als Muster für alle weiteren Seiten.
4. **Link-Check auf HTML ausweiten.** lychee prüft zusätzlich `docs/site/**/*.html`, in CI und im Pre-commit-Hook.
5. **Lane-Protokoll um den Bildband-Bezug ergänzen.** Tickets mit sichtbarer Verhaltensänderung nennen
   die betroffenen Bildband-Seiten und erneuern deren Bilder aus den Rezepten.

## 12. Quellen

Alle abgerufen am 2026-10-24.

- Material for MkDocs, Release 9.8.0 mit Pflegeende 2027-05-05:
  <https://github.com/squidfunk/mkdocs-material/releases/tag/9.8.0>
- Zensical, Änderungen zum 2026-11-05 (0.1.0, Beta-Status): <https://zensical.org/upcoming-changes/>
- Zensical, Suche („currently only available in English“): <https://zensical.org/docs/setup/search/>
- Zensical auf PyPI (0.0.72): <https://pypi.org/project/zensical/>
- Astro Starlight, Internationalisierung (deutsche UI, `locales.root`): <https://starlight.astro.build/guides/i18n/>
- Astro Starlight, Plugins und Integrationen: <https://starlight.astro.build/resources/plugins/>
- Astro Starlight, Releases (0.42.7): <https://github.com/withastro/starlight/releases>
- Pagefind, Arbeitsweise mit beliebigem statischem HTML und Python-Paket: <https://pagefind.app/docs/>
- Pagefind, Mehrsprachigkeit (deutsches Stemming, `lang`-Attribut): <https://pagefind.app/docs/multilingual/>
- VitePress, Getting Started (2.0.0-alpha.20): <https://vitepress.dev/guide/getting-started>
- VitePress auf npm (latest 1.6.4, next 2.0.0-alpha.20): <https://www.npmjs.com/package/vitepress>
- Docusaurus, Diagramme (`@docusaurus/theme-mermaid`): <https://docusaurus.io/docs/markdown-features/diagrams>
- Docusaurus, Releases (3.10.2): <https://github.com/facebook/docusaurus/releases>
- Quarto, Diagramme (Mermaid nativ): <https://quarto.org/docs/authoring/diagrams.html>
- Quarto, Lizenz (MIT): <https://github.com/quarto-dev/quarto-cli/blob/main/COPYING.md>
- Quarto auf PyPI (`quarto-cli` 1.10.19): <https://pypi.org/project/quarto-cli/>
- Hugo, Diagramme (Mermaid per eigenem Render-Hook): <https://gohugo.io/content-management/diagrams/>
- Hugo, Releases (v0.168.0): <https://github.com/gohugoio/hugo/releases>
- Zola, Repository und Lizenz (EUPL-1.2 laut GitHub-API), Releases (v0.23.6): <https://github.com/getzola/zola>
- ExDoc, README (Extras, Mermaid): <https://ex-doc.hexdocs.pm/readme.html>
- Tableau auf Hex (0.30.0, MIT): <https://hex.pm/packages/tableau>
- NimblePublisher auf Hex (2.1.0, Apache-2.0): <https://hex.pm/packages/nimble_publisher>
- Mermaid, Releases (12.x): <https://github.com/mermaid-js/mermaid/releases>
- GitHub Docs, Veröffentlichungsquelle für Pages (Branch `/` oder `/docs`, Actions-Weg):
  <https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site>
- LG München I, Urteil vom 20.01.2022, Az. 3 O 17493/20 (Google Fonts), Besprechung:
  <https://www.ra-plutte.de/lg-muenchen-dynamische-einbindung-google-web-fonts-ist-dsgvo/>
