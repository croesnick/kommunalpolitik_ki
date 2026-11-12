# ratsprojekte

Der lokale Hub für den Weg von der Idee zum Antrag ([ADR 0004](../../docs/adr/0004-ratsprojekte-als-lokaler-hub.md)).
Phoenix LiveView, läuft lokal für eine Person — die Redaktion führt, alle
anderen bekommen eine bewusst ausgegebene Fassung.

**Zustand: lokaler Betrieb, Schema, Kontext und Oberfläche.** Phoenix 1.8.16,
LiveView 1.2.13, Bandit, Tailwind v4, esbuild (Gerüst #435). Schema und Kontext
stehen (#436), die Oberfläche mit dem Main Flow „Was ist passiert?“ auch (#437),
beides unten beschrieben. Es folgen der Stand als Druck (#438), die Befragung
(#439) und der Connector-Schreibweg „Fakt vorschlagen“ (#277). Der lokale
Betrieb (#440) steht, siehe unten. Das Storyboard
[`storyboard/hub-desktop.html`](storyboard/hub-desktop.html) ist die
Durchklick-Referenz der Ziel-Oberfläche.

## Starten (Dev)

```bash
cd apps/ratsprojekte
mix setup        # Deps, Datenbank anlegen/migrieren, Assets
mix phx.server   # http://localhost:4000
```

## Datenbank

Eigene SQLCipher-Datei unter `~/Library/Application Support/ratsprojekte/`
statt der mit ratsinfo geteilten (ADR 0004):

| Umgebung | Datei | Schlüssel |
|---|---|---|
| Dev | `dev.db` | keiner — SQLCipher verhält sich ohne Schlüssel wie normales SQLite |
| Test | `ratsprojekte_test.db` (app-lokal) | keiner |
| Release | `ratsprojekte.db` im Home (siehe Betrieb) | versiegelt mit der Secure Enclave, kommt erst mit `ratsprojekte open` |

Dev trägt bewusst keine echten Daten: Mit echten Daten läuft der Hub nie im
Dev-Modus (ADR 0004, dort hängt Tidewave am Endpoint).

**exqlite baut im Workspace gegen die SQLCipher-Systembibliothek** (BSD),
geregelt über `config :exqlite` in `config/config.exs` — gilt auch für
ratsinfo und komki_cli. Voraussetzung und Nachbau:
[docs/prerequisites.md](../../docs/prerequisites.md). Der Test
`Ratsprojekte.SqlcipherTest` schlägt fehl, wenn exqlite ungepatcht gebaut
wurde.

## Betrieb (Release, #440)

Mit echten Daten läuft der Hub nur als Release (ADR 0004 „Lokal, ohne
Konten“). Er startet bei der Anmeldung **gesperrt**: ohne Schlüssel, ohne
offene Datenbank.

```bash
make ratsprojekte                # Release nach ~/.local/opt/ratsprojekte, Befehl ~/.local/bin/ratsprojekte
ratsprojekte einrichten          # Schlüssel versiegeln, Wiederherstellungscode EINMAL zeigen, LaunchAgent starten
komki secret erzeugen ratsprojekte-hub | ratsprojekte connector-token
```

Im Alltag: `http://localhost:4100` als Lesezeichen öffnen, „Entsperren“
klicken, Touch ID. Das Terminal braucht es dafür nicht. Ein späteres
`make ratsprojekte` (aus jedem Checkout) ersetzt die installierte Kopie und
startet den Hub gesperrt neu; Daten und Siegel bleiben, wo sie sind.

| Befehl | Was passiert |
|---|---|
| `einrichten` | Erzeugt den SQLCipher-Schlüssel, versiegelt ihn mit einem eigenen Schlüssel in der Secure Enclave (`komki-tresor`) und zeigt ihn einmal als Wiederherstellungscode. Der gehört in den Passwortmanager. Danach richtet es den LaunchAgent ein und wartet, bis der Hub antwortet. |
| Sperrseite „Entsperren“ | Im Browser: Der Hub fragt per Touch ID den Schlüssel ab, öffnet die Datenbank und setzt das Session-Cookie im selben Tab. Jeder weitere Klick fragt wieder nach Touch ID. |
| `open` | Dasselbe aus dem Terminal: Der Browser öffnet sich mit einem Link, der zwei Minuten und genau einmal gilt. |
| `sperren`, `status` | Sofort sperren, Zustand abfragen. Nach 30 Minuten ohne Handlung in der Oberfläche sperrt der Hub von selbst (`config :ratsprojekte, sperre_nach`). Aufrufe des Connectors zählen nicht. |
| `connector-token` | Liest den SHA-256 des Tokens von stdin. Den Token erzeugt komki und legt ihn versiegelt im Schlüsselbund ab, der Hub kennt nur den Hash. |
| `recover` | Versiegelt den Schlüssel aus dem Wiederherstellungscode neu, etwa nach einer Wiederherstellung aus Time Machine auf einem anderen Mac. Danach braucht der Connector einen neuen Token (Zeile oben). |
| `launchagent an\|aus` | Lädt `~/Library/LaunchAgents/ratsprojekte.hub.plist` neu (macht `einrichten` schon) oder entfernt ihn. Nach einem Absturz startet launchd den Hub neu, wieder gesperrt. |

**Was wo liegt.** Alles in `~/Library/Application Support/ratsprojekte/`
(Rechte 0700; `RATSPROJEKTE_HOME` setzt für Wegwerf-Instanzen ein anderes
Verzeichnis, der Pfad darf wegen der Sockets höchstens 87 Bytes lang sein): `ratsprojekte.db` (SQLCipher), `ratsprojekte.db.vor-migration` (die
Kopie vor der letzten Schemaänderung, nur die letzte bleibt),
`schluessel.ktv2` (das Siegel), `connector-token.sha256`, und die Sockets
`verwaltung.sock` (für den Befehl) und `connector.sock` (nur
Connector-Operationen), beide 0600. Log: `~/Library/Logs/ratsprojekte/hub.log`.

**Grenzen, die der Hub selbst zieht.** Die Oberfläche liegt auf
`127.0.0.1:4100` und nimmt nur Host `localhost` oder `127.0.0.1` an (andere
bekommen 421). Ohne Cookie zeigt sie nur die Sperrseite; „Entsperren“ ist
ein Formular mit CSRF-Token, eine fremde Website kann keine Touch-ID-Abfrage
auslösen (ohne Token 403).
Der Connector-Socket prüft zuerst den Token, dann die Sperre: gesperrt heißt
503 „gesperrt“, gepuffert wird nichts. Die BEAM läuft ohne Distribution
(kein Port, kein Cookie) und ohne Crash-Dump, mit `+sbwt none` auch für
dirty CPU und IO. Logs nur ab `:warning`, und `Ratsprojekte.Logfilter`
nimmt jedem Ereignis, das nicht ausdrücklich inhaltsfrei ist, die Meldung.
Sobelow meldet deshalb „HTTPS Not Enabled“ — bewusst ignoriert
(`.sobelow-conf`): Der Hub spricht nur HTTP auf Loopback.

**Gemessen am Release (12.11.2026, gesperrt, Mac mit 10 Kernen):** Leerlauf
rund 168 MB RSS (155 MB Physical Footprint), CPU im Mittel 0,08 % über eine
Minute. Weniger Scheduler sparen nur rund 9 MB und bleiben deshalb aus.

**Sicherung.** Time Machine auf einer verschlüsselten Platte sichert das
Verzeichnis mit; sie sieht nur Chiffretext (Beobachter `sicherung` in Γ).
Fällt der Rechner aus: aus Time Machine wiederherstellen,
`ratsprojekte recover`, neuen Connector-Token erzeugen.

Gegen Prozesse im eigenen Benutzerkonto schützt das nur begrenzt: Solange
der Hub entsperrt ist, liegt der Schlüssel im Speicher (ADR 0004).

## Regeln, kein Ausrüstungsgegenstand

Zurückgetragen aus dem alten Bestand und verbindlich:

- **CSP-Header**: gesetzt im Router (`@content_security_policy`), jede
  Seite testet sie — inklusive des SHA-256-Hashes für das Inline-Theme-Script
  (`test/ratsprojekte_web/content_security_policy_test.exs`).
- **Sobelow-Audit**: `mix sobelow --private --threshold high --exit` in der
  CI, keine Funde (`.sobelow-conf`).
- **Slug-Konvention**: Projekte werden über Slugs adressiert, nicht über
  Datenbank-IDs — kebab-case, ASCII, Umlaute als ae/oe/ue/ss; derselbe Slug
  ist im Vault der Tag `#ratsprojekt/<slug>` (Einzelheiten: AGENTS.md am
  Repo-Root). Umsetzung in den Routen mit #437.
- **Vorschlagsweg**: komki schlägt vor, die Redaktion entscheidet. Der Hub
  nimmt von der KI nichts direkt entgegen — der Schreibweg läuft über den
  Connector-Socket mit Token (Socket aus #440, Schreibweg #277). `decide_proposal` und der
  Dev-MCP-Endpoint sind entfallen (ADR 0004).

## Modell

Das kleine Modell aus ADR 0004, gebaut in #436. Die Domäne ist deutsch, der
Code englisch (Übersetzungstabelle in #414). Wer etwas liest oder ändert,
ruft die Kontexte und kennt die Tabellen nicht:

- `Ratsprojekte.Projects`: Ratsprojekte (`Project`) mit Verlauf (`TimelineEntry`),
  Meinungsbildern (`Opinion`), Fakten (`Fact`), Varianten (`Variant` mit
  `Prerequisite`), Anträgen (`Motion`) und Querverweisen (`CrossReference`).
  Der Main Flow „Was ist passiert?“ ist `record_event/2`, am Antrag
  `record_motion_event/3`. Was die Redaktion im Hub tut, schreibt sich von
  selbst in den Verlauf.
- `Ratsprojekte.Surveys`: Befragungen (`Survey`) mit opaken Kennungen je
  Thema (`SurveyTopic`), Hochladen bestätigen, Rücklauf zuordnen. Die
  Dateien nach `docs/schnittstellen/befragung.md` liest und schreibt #439.
- `Ratsprojekte.Text`: entfernt beim Speichern unsichtbare Steuerzeichen aus
  allen Freitextfeldern, Emojis und Schriftzeichen bleiben heil (#410,
  Gegenprobe 13.6).
- `Ratsprojekte.Labels`: die deutschen Namen der Atome (`:drafting` heißt
  „Ausarbeitung“).

`mix ecto.setup` trägt über dieselben Kontextfunktionen vier erfundene
Gartenstadt-Projekte ein (nur Dev; der Hub im Release startet leer).

## Oberfläche

Die Hauptaktion ist der neue Eintrag. Ein Dialog fragt „Was ist passiert?“,
Pflicht ist nur der Text. Darunter steht immer die Wahl, wer ihn lesen darf.
Phase, nächster Schritt und Datum sind eingeklappt. Am Antrag fragt derselbe
Dialog zusätzlich nach Status und Ergebnis.

- **Übersicht** (`/`): Karten in Spalten nach Phase, Filter „Du bist dran“
  und „Braucht Aufmerksamkeit“ (Frist in den nächsten 7 Tagen oder
  überfällig, oder seit vier Wochen nichts passiert und nichts vereinbart).
  Jede Karte hat „Eintragen“, so sind sechs Projekte nach einer Sitzung
  sechs Dialoge. „Neue Idee“ legt ein Projekt an, der Kurzname füllt sich
  aus dem Titel.
- **Projekt** (`/projekte/<kurzname>`): Phasen (ein Klick öffnet den
  Eintrag mit dieser Phase, weil ein Wechsel einen Grund im Verlauf
  braucht), nächster Schritt, Meinungsbild, Fakten, Varianten, Anträge,
  Nutzen und Erfolg, Antragsreife als Checkliste, Verlauf, Querverweise
  mit kopierbarem Vault-Tag, Ablegen und Wieder aufnehmen.

Die Oberfläche ruft nur die Kontextfunktionen auf. Eine Route, über die eine
KI im Hub über einen Vorschlag entscheidet (`decide_proposal`), gibt es nicht
(ADR 0004), ein Test hält das fest. „du“ oder „ich“ als zuständige Person
meint die Redaktion, die Arbeitsansicht zeigt dafür „Du“.

## Aufbau

```
apps/ratsprojekte
├── assets/                  # Tailwind v4 (CSS-first) + esbuild, Watcher in dev.exs
├── config/                  # Phoenix-Stand; DB-Pfade und exqlite-Build hier
├── lib/ratsprojekte/        # Kontexte Projects und Surveys, Text, Labels; Betrieb (#440)
├── lib/ratsprojekte_web/    # Router mit CSP, LiveViews (live/), Hub-Komponenten, Endpoint mit Tidewave (dev)
├── priv/repo/               # Migrationen (#436) + Seeds (erfundene Gartenstadt-Projekte)
├── priv/static/            # gebaute Assets landen in priv/static/assets/ (gitignored)
└── storyboard/             # Durchklick-Referenz der Oberfläche
```
