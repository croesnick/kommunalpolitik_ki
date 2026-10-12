# KomKI-CLI — abgeschlossener Arbeitsraum für lokale KI-Sessions

Die KomKI-CLI (`komki`) richtet einen abgeschlossenen Arbeitsraum für
KI-Arbeit auf dem eigenen Rechner ein. Ein Sprachmodell (llama-server) und
ein Agenten-Frontend (pi) laufen vollständig lokal, eingebettet in eine
macOS-Sandbox, die erst einmal alles verweigert: Schreibzugriffe nur
innerhalb des Arbeitsraums, Netzwerk nur eine einzige Verbindung zum lokalen
Modellserver. Damit eignet sich der Raum für vertrauliche Ausarbeitungen,
denn nichts verlässt das Gerät, und vor jedem Lauf prüft ein Boot-Gate, dass
die Sandbox noch dicht ist.

Entstanden ist das Tool aus der zugehörigen Recherche (GitHub-Tickets #70
und #74). Die Sandbox-Evidenz der Grenz-Gates steht im Probebericht des
#70-Beschlusses (Issue-Kommentar) und im Research-Report
`docs/research/2026-10-05-seatbelt-survey.md`.

## Die gepinnte Kombination

komki lädt nichts dynamisch nach, sondern startet immer dieselben
Komponenten mit denselben Pins:

* **Modell:** Gemma 4 26B-A4B-it (unsloth UD-Q4_K_XL-GGUF), per SHA-256
  verifiziert. Das 26B-MoE (3.8B aktiv) ist für produktive deutsche Arbeit
  gewählt: starke Deutsch-Community-Reports, sauberes Tool-Calling seit den
  Template- und Parser-Fixes von April 2026. Kontext-Standard: 128K
  (Nutzer-Präferenz große Kontexte bei 64 GB RAM).
* **Server:** `llama-server` auf Loopback, Port 49524, mit festen Flags
  (`--jinja`, `--offline`, ohne Web-UI, ohne Slots; Sampling nach der
  offiziellen Gemma-4-Empfehlung: temp 1.0, top-p 0.95, top-k 64).
* **Agent:** pi unter Node 24. Der Start umgeht den asdf-Versionsmanager:
  Dessen Shim bricht unter der Sandbox still ab, deshalb ruft komki die
  aufgelösten Pfade direkt auf (`node <pfad> <cli.js>`).
* **Sandbox:** Jedes pi startet unter einem frisch generierten
  Seatbelt-Profil (deny-default mit Whitelist). Schreibbereich ist der
  Arbeitsraum selbst, die einzige Netzwerk-Exception ist der lokale
  Modellserver.

Die Assets (GGUF, pi-Bundle, llama-server) liegen bereits lokal; komki
verbindet sich ausschließlich mit Loopback.

## Voraussetzungen und Installation

komki läuft nur unter macOS (Seatbelt-Sandbox). Drei Werkzeuge müssen
vorhanden sein, `init` entdeckt sie selbst und pinnt die aufgelösten Pfade
in die `config.json` der Instanz: ein node-Interpreter (asdf, Homebrew oder
nvm — bei asdf wird der echte Installationspfad hinter dem Shim benutzt,
weil der Shim unter der Sandbox still scheitert), das pi-Bundle als globales
npm-Paket (`npm install -g @earendil-works/pi-coding-agent`) und
`llama-server` (llama.cpp, etwa via `brew install llama.cpp`). Fehlt eins,
verweigert `init` mit klarer Meldung.

Optional: `fd` und `ripgrep` (etwa via `brew install fd ripgrep`). `init`
kopiert beide in den Bin-Fundus von pi (`pi-home/.pi/agent/bin`) — pi
findet sie offline, ohne Download-Warnung, und die Session bekommt die
Tools `find`/`grep` für die Dateisuche. Fehlen sie, verzichtet pi auf
Dateisuche und warnt beim Start.

Details und Fallbacks: [`docs/prerequisites.md`](../../docs/prerequisites.md).

```sh
mix escript.build   # erzeugt ./komki (Dev-Weg; braucht Elixir/OTP auf dem Host)
```

## Verteilen: eine Datei statt Ordner (Burrito)

Für Rechner ohne installiertes Elixir baut Burrito das Release in eine einzige
ausführbare Datei mit eingebettetem Erlang-Runtime (macOS arm64):

```sh
PATH="$HOME/.local/opt/zig-aarch64-macos-0.16.0:$PATH" \
  MIX_ENV=prod BURRITO_TARGET=macos_silicon mix release
# → burrito_out/komki_macos_silicon (eine Datei, ~10 MB)
```

Beim ersten Start entpackt die Datei ihr Payload nach
`~/Library/Application Support/.burrito/` und läuft danach ohne jede
Elixir-Installation. Eingebaute Wartungsbefehle:
`komki maintenance directory` (Entpackpfad), `maintenance meta`,
`maintenance uninstall` (Payload löschen, mit y/n-Rückfrage).

Bau-Voraussetzungen und Details: [`docs/prerequisites.md`](../../docs/prerequisites.md);
Pilot-Bericht mit allen Messungen:
[`docs/research/2026-10-11-komki-burrito-pilot.md`](../../docs/research/2026-10-11-komki-burrito-pilot.md).

Zwei Hinweise für die verteilte Datei:

- **Gatekeeper:** Die lokal gebaute Datei ist ad-hoc signiert und läuft ohne
  Nachfrage. Wer sie aus einem GitHub-Release herunterlädt, bekommt beim
  ersten Start den Gatekeeper-Dialog („Entwickler nicht verifiziert“) —
  einmalig `xattr -d com.apple.quarantine komki_macos_silicon` ausführen
  oder unter Systemeinstellungen › Datenschutz & Sicherheit freigeben.
- **Interaktive Session:** `session` läuft derzeit nur unter dem Escript.
  Unter der Standalone-Binary schließt die tmux-Pane sofort — die
  Wrapper-Schicht leitet stdout als Pipe weiter, und pi beendet sich
  ohne echtes Terminal darauf (Burrito-Regression #234; Analyse im
  Pilot-Bericht). `run` und alle übrigen Befehle sind davon nicht betroffen.

## Befehle

```sh
./komki version
./komki init                        # Instanz anlegen (config, Profil, pi-home, GGUF mit SHA-Gate)
./komki init --gguf-from PFAD       # GGUF-Quelle explizit angeben
./komki doctor                      # alle Checks (Werkzeuge, Profil, GGUF-SHA, Boot-Gate, Port)
./komki up                          # llama-server starten
./komki run "PROMPT"                # einmaliger pi-Lauf unter dem Profil
./komki session                     # interaktive pi-Session in tmux
./komki session --continue          # letzte Session fortsetzen
./komki session --detach            # im Hintergrund; attach via 'tmux attach -t komki'
./komki down                        # llama-server stoppen
./komki status                      # Zustand (base, gguf, port, llama)
```

Weitere Flags: `init --port N --ctx N --force`, `up --ctx N`,
`run --mode text|json --scratch PFAD`. Exit-Codes: `0` Erfolg, `2` Nutzungs-,
Konfigurations- oder Bereitschaftsfehler (etwa: llama-server nicht aktiv),
`3` Doctor-/Boot-Gate-Fehlschlag, `4` Laufzeitfehler.

Interaktive Sessions laufen in der tmux-Session `komki`, jeweils eine
gleichzeitig. Dateien aus der Session landen im Verzeichnis `arbeit`
innerhalb der Instanz, die Sitzungsverläufe unter `pi-home/sessions` und
lassen sich mit `session --continue` fortsetzen. pi startet mit einem
knappen deutschen System-Prompt (Deutsch als Default, durchgehende
Du-Form), Thinking-Blöcke sind eingeklappt; liegen `fd`/`ripgrep` vor,
stehen `find`/`grep` für die Dateisuche bereit. Aus der Session kopieren:
`Ctrl+B` und
dann `[` öffnet den tmux-Copy-Modus (Pfeiltasten bewegen, `Space` startet
die Auswahl, `Enter` übernimmt).

Unter `~/.local/share/komki` liegen die Instanzdaten, überschreibbar via
`KOMKI_HOME`.

## So sieht eine Session aus

Aufgezeichnet aus einer echten Session: Der Prompt bittet um eine kleine
Checkliste, pi schreibt `notiz.md` in den Arbeitsraum, das Modell fasst den
Inhalt zusammen. Im Footer stehen das Arbeitsverzeichnis, der Kontextverbrauch
und mit `local-model` der Hinweis, dass nichts das Gerät verlassen hat.

![komki-Session in tmux: Prompt, eingeklappte Thinking-Blöcke, write notiz.md, Antwort, Footer mit local-model](assets/session-beispiel.svg)

Nachvollziehen:

```sh
./komki session
```

Dann im Eingabefeld von pi:

```text
Erstelle notiz.md mit einer kurzen Checkliste für eine Spielplatzbegehung (fiktive Inhalte).
```

## Ehrliche Grenzen

Das Modell ist leistungsfähig, aber lokal: Antworten erscheinen ohne
Quellenbindung und ohne Gewähr — vor jeder Verwendung in Ratsarbeit gilt
es, sie zu prüfen. Ein bekannter Gemma-4-Randfall: bei langen Tool-Sitzungen
kann das Chat-Template Reasoning-Inhalte wiederholt einspeisen (Unsloth-
Diskussion #43); fällt das auf, existiert ein dokumentierter Template-Fix
ohne Neuquantisierung.

llama läuft ausschließlich auf Loopback, das Profil erlaubt genau eine
TCP-Verbindung zum Modellserver. Vermittlungs- oder Remote-Wege sind
bewusst nicht vorgesehen.

Im Arbeitsraum arbeiten nur synthetische oder autorisierte öffentliche Daten.
Geschützte oder vertrauliche Daten gehören nicht hinein.

Das Boot-Gate ist vor jedem Lauf Pflicht: Ist `doctor` rot, verweigern
`up`, `down`, `run` und `session` den Dienst. deny-default-Profile sind auf
macOS hierfür spröde, deshalb wird vor jedem Lauf neu geprüft statt blind
vertraut.

Eine Eigenheit auf diesem System (macOS 27.2 Beta): Unter dem Profil startet
node aus gewöhnlichen fork-Ketten nicht zuverlässig (SIGABRT beim Init; eine
branchenweit auf neueren macOS-Builds beobachtete Klasse, siehe
`docs/research/2026-10-05-seatbelt-survey.md`). Deshalb läuft in der
tmux-Pane der Session das komki-Programm als Mini-BEAM (Escript oder
Standalone-Binary), das die pi-Kette als Port-Kind startet und die
Pane-PTY durchreicht; der Headless-Lauf nutzt denselben Port-Weg ohnehin.
Einschränkung der Standalone-Binary: die Wrapper-Schicht von Burrito reicht
stdout als Pipe weiter, pi verlangt für die TUI aber ein echtes Terminal —
die Pane schließt daher sofort. Interaktive Sessions bis auf Weiteres über
den Escript starten; alle übrigen Befehle laufen auch mit der Binary.

Der `--ctx`-Override beim `up` gilt nur für den jeweiligen Start; die
gepinnte Konfiguration bleibt unangetastet.
