# Burrito-Pilot komki: Einzeldatei-Bau und Regressionsprüfung (Ticket #75)

Pilot und Bau der komki-Standalone-Binary nach Burrito 1.6.0. Alle Messungen
vom 11.10.2026 auf dem Bau-Rechner (macOS 27.2, arm64). Primärquellen: das
Burrito-Repo v1.6.0 (Tag `v1.6.0`, lokal geklont), die zig-0.16.0-Standardbibliothek
sowie die eigenen Messungen unten. [D] = durch Quelle oder Messung belegt.

## Auftrag und Tor

Vorgabe aus Ticket #75: Vor dem eigentlichen Bau besteht ein Pilot gegen die
drei offenen Burrito-Regressionen (#229 argv, #234 stdout/TTY, #233 embedded
mode). Bei Negativbefund gilt Rückmeldung statt stiller Pfadänderung. Der
Pilot bestand mit drei Nacharbeiten in der eigenen CLI-Schicht; ein
Negativbefund bleibt für interaktive Sessions (unten). Danach lief die
komplette Smoke-Matrix aus Ticket #74 gegen die Einzeldatei.

## Bau

- Toolchain: zig exakt 0.16.0 (Burrito prüft die Version auf
  Gleichheit und bricht sonst ab, `lib/burrito.ex:5,49-61`), xz im PATH;
  7z wird für darwin-Ziele nicht gebraucht (nur Warnung). [D]
- Der offene Punkt aus der Recherche vom 04.10. ist beantwortet: zig 0.16.0
  baut sauber gegen das macOS-27.2-SDK des Hosts (Wrapper-Kompilierung ohne
  Link-Fehler). [D]
- Aufruf: `MIX_ENV=prod BURRITO_TARGET=macos_silicon mix release` →
  `apps/komki_cli/burrito_out/komki_macos_silicon`, rund 9,6 MB, Mach-O
  arm64. `MIX_ENV=prod` ist Pflicht: Nur prod-Builds nutzen den einmal
  entpackten Payload wieder (dev re-extrahiert bei jedem Lauf). [D]
- Burrito legt :burrito als benannten Payload-Bestandteil in die Binary
  (`Burrito.Util.Args` läuft zur Laufzeit mit); dokumentiert in mix.exs und
  `KomkiCli.Runtime`. Keine unbenannten Zusätze. [D]

## Pilot-Block gegen die drei Regressionen

### #229 argv-Beanspruchung beim Boot (bestanden)

Mit dem Muster der Burrito-Beispiel-App (synchrones CLI in
`Application.start/2`, Ende via `System.halt(exit_code)`, kein Rückkehrwert)
gewinnt komki deterministisch: `-boot` läuft vor `elixir start_cli`, unsere
Ausgabe und unser Exit-Code kommen zuerst. Gemessen an der Binary:

| Aufruf | Ergebnis |
|---|---|
| `komki --help` | eigene optimus-Usage, exit 0 [D] |
| `komki --version` | `komki 0.1.0`, exit 0 [D] |
| `komki definitiv-nicht-ein-befehl` | `Error: - unrecognized arguments …`, exit 2 [D] |
| `komki init --gguf-from /nonexistent` | Optionswert kommt an, `Pfad nicht gefunden`, exit 2 [D] |
| `komki run x --mode bogus` | Unterbefehl und Wert kommen an, exit 2 [D] |

### #234 stdout als Pipe, ANSI erzwungen (bestanden nach drei Funden)

Der Wrapper startet den BEAM mit stdout als Pipe und erzwingt
`ansi_enabled true` (`src/erlang_launcher.zig:53-57,111-117`). Daraus drei
Befunde, alle in der eigenen CLI-Schicht behoben und unit-getestet:

1. Eigene Farbgates: Verdict-Zeilen lesen jetzt `_IS_TTY` (`"1"`/`"0"`,
   setzt der Wrapper für den BEAM, `wrapper.zig:108-116`), Fallback
   `IO.ANSI.enabled?/0` für Escript/mix (`KomkiCli.Runtime.ansi_enabled?/0`).
   Gepipet: keine Escapes; Terminal: Farben. [D Messung, od-Bytes]
2. Optimus-Formatierung: `Optimus.Errors.format_errors/1` schreibt
   `IO.ANSI.red()/bright()/reset()` bedingungslos in die Fehlerzeile, ohne
   enabled?-Prüfung (Quelltext optimus 0.6.1). Das traf Escript und Binary
   gleichermäßig (kein Burrito-Schaden, aber durch den Pilot sichtbar
   geworden): Gepipete Fehlerzeilen enthielten Escapes. Fix am eigenen
   Render-Ort (`KomkiCli.CLI.format_errors/1`): Ohne Farben dieselbe Form,
   schlicht. [D od-Vergleich vorher/nachher, Tests in cli_test]
3. VM-weite Synchronisation: `KomkiCli.Runtime.sync_ansi!/0` richtet
   `:elixir :ansi_enabled` beim Release-Start nach `_IS_TTY`, damit jede
   VM-weite Formatierung konsistent bleibt (verifiziert: put_env kippt
   `IO.ANSI.enabled?/0` zur Laufzeit). [D]
4. up-Spinner: Die `\r`-Frames schrieb die CLI bedingungslos, gepipet
   landeten Frame- und ANSI-Reste im Log. Der Spinner läuft jetzt nur mit
   aktivierten Farben; gepipet bleibt `up` stumm. [D od-Vergleich:
   115 → 33 Bytes]

### #233 `-mode embedded` als totes Flag (bestätigt, folgenlos)

Der Launcher übergibt `-mode embedded` als EIN argv-Element
(`erlang_launcher.zig:62`); `erl` splittet Elemente nicht, die VM bootet
interaktiv. komki nutzt kein `function_exported?/3` (Suche über lib/ leer),
also bleibt es bei minimalem Boot-Zeit-Nachteil. Dokumentiert, kein Fix
nötig. [D]

## Exit-Codes und Randfälle

- 0 (`version`), 2 (Usage/ohne config), 3 (Profil-Drift beim doctor),
  4 (llama-health-timeout beim up mit absurdem ctx): alle vier reichen
  durch den Zig-Wrapper bis zur Shell (`std.process.exit(code)`,
  erlang_launcher.zig:135-138). [D je Messung]
- `komki --help | head -2` → exit 0: Der EPIPE-Kill-Pfad des Wrappers wird
  bei unseren kleinen Ausgaben nicht erreicht. [D]

## Gleiche Version, alter Payload

Der Wrapper überspringt das Entpacken, sobald `_metadata.json` im
Installationsverzeichnis liegt (wrapper.zig:73-102). Das Verzeichnis heißt
`komki_erts-16.2_0.1.0`; Rebuilds derselben Version laufen also mit dem
ALTEN Payload. Wer eine neu gebaute Binary derselben Version testet, muss
zuvor `./komki maintenance uninstall` ausführen (oder `KOMKI_INSTALL_DIR`
auf ein frisches Verzeichnis zeigen lassen), sonst testet man den alten
Stand. Pilot-Fund mit Folgen: Frühere Re-Pilot-Läufe in dieser Session waren
teilweise vom ersten Bau; nach dem Uninstall wurde alles gegen den
tatsächlichen Stand erneut gemessen. [D]

## Interaktive Session unter der Binary (Negativbefund, per Fix abgeschlossen)

`session` startet die tmux-Pane mit dem Programm-Pfad aus
`KomkiCli.Runtime.self_path/0`, unter Burrito also korrekt die Binary. Der
erste Pilot-Lauf endete negativ: Die Pane starb sofort (Kette exit 0, keine
TUI-Ausgabe). Ursachen-Kette:

- Escript-Kontrolle auf derselben Instanz, demselben Profil: pi bootet und
  rendert die volle TUI (Probe-Mitschnitt). [D]
- zig-Probe mit exakt der Spawn-Konfiguration des Launchers (nur
  `.stdout = .pipe`): stdin wird vererbt und lebt. [D]
- Differenz ist stdout: Unter dem Escript ist das BEAM-stdout die Pane-PTY,
  unter der Binary die Wrapper-Pipe (erlang_launcher.zig:111-117). pi braucht
  für die TUI ein echtes TTY auf stdout und beendet sofort, still, mit 0. [D]

Das ist die dokumentierte #234-Klasse des Upstream. Rückmeldung an den
Menschen mit drei Optionen; das GO fiel am 12.10. auf Option 1 (Fix in
eigener Regie). Umgesetzt und verifiziert:

- `Pi.argv_session/3` biegt unter Burrito (`KomkiCli.Runtime.burrito?/0`)
  stdout der Kette per `/bin/sh -c` auf `/dev/fd/0` um — Dup des lebenden
  stdin-PTY. Der Escript-Pfad behält die Direktkette (stdout ist dort die
  Pane-PTY); Unit-Tests pinnen beide Formen.
- Zwei kontextfreie Seatbelt-Regeln erlauben das Öffnen von /dev/fd/0
  (`tui_rules` in `KomkiCli.Profile`). Kontextfrei heißt: Die
  Profil-Identität hängt nicht vom Laufkontext ab; bestehende Instanzen
  driften einmalig und brauchen einmalig `init --force`.
- Nachweis an der Binary: Pane bleibt offen, pi rendert die TUI,
  Tasteneingabe kommt durch (Modell-Round-Trip), Teardown über tmux schließt
  die Kette. [D, 12.10.]
- Escript-Regression mit dem neuen Profil: Direktkette bootet pi wie bisher. [D]

Der Fix bleibt vorwärtsverträglich: Sollte der Upstream #234 heilen, ist
BEAM-stdout die echte Pane-PTY und der Redirect dupliziert dasselbe Gerät —
kein Verhalten ändert sich. Ein Upstream-Beitrag (stdout nur pipen, wenn
kein TTY; die isTty-Erkennung existiert im Wrapper schon für _IS_TTY) bleibt
als Follow-up denkbar; für komki ist er nicht mehr nötig.

## Smoke-Matrix der Einzeldatei (alles ohne host-Elixir im PATH)

Frische Instanz in einem temporären KOMKI_HOME, eigener Port 49531 (der
laufende llama der Nutzer-Instanz auf 49524 blieb unberührt):

1. `init`: GGUF-Kopie SHA-geprüft, exit 0. [D]
2. `doctor`: 9/9 Checks grün, exit 0. [D]
3. `up`: llama-Boot, health 200, exit 0. [D]
4. `run "Antworte mit exakt einem Wort: ok"`: Modellantwort `ok`, exit 0. [D]
5. `run --help`: eigene Usage, exit 0, kein pi-Lauf. [D]
6. Write-Werkzeug-Lauf: pi legt per Write-Tool die Datei mit exakt
   `komki-smoke` im Scratch an (od-Verifikation), exit 0. [D]
7. `down`: pidfile entfernt, Port frei, Prozess weg, exit 0. [D]

Störproben: Profil-Drift → doctor exit 3; absurd großer ctx
(profilneutral) → up mit health-timeout exit 4; je Wiederherstellung grün. [D]

## Gatekeeper und Signierung

- Die gebaute Datei ist ad-hoc linker-signiert (arm64-Pflicht; zig/clang
  signieren automatisch): `codesign -dv` zeigt `Signature=adhoc`. [D]
- Lokal gebaut: keine Quarantäne-Attribute, läuft ohne Gatekeeper-Dialog;
  alle Messungen oben liefen so. [D]
- Heruntergeladen (etwa vom GitHub-Release) hängt macOS
  `com.apple.quarantine` an: Gatekeeper blockiert den ersten Start
  („Entwickler nicht verifiziert“). Abhilfe einmalig
  `xattr -d com.apple.quarantine <datei>` oder Freigabe in den
  Systemeinstellungen; Developer-ID plus Notarisierung wäre der saubere
  Weg, ist aber nicht Teil dieses Tickets. [D Burrito-README +
  macOS-Verhalten]

## Entpack-Verhalten und Wartung

- Entpacken beim ersten Lauf nach
  `~/Library/Application Support/.burrito/komki_erts-16.2_0.1.0`. [D]
- `KOMKI_INSTALL_DIR` (Release-Name großgeschrieben) überschreibt den Ort
  (Wrapper hängt `.burrito` an). Verifiziert. [D]
- `maintenance directory|meta|uninstall` arbeiten vor jedem Payload-Start;
  `uninstall` fragt y/n. [D]

## Offene Punkte

- Upstream-Beitrag zu #234 (stdout nur pipen, wenn kein TTY) als Follow-up
  denkbar; für komki durch den eigenen Fix nicht mehr nötig.
- Exit-Code-Verhalten bei EPIPE unter größeren Ausgaben (etwa sehr lange
  Doctor-Listen in Pipes) ungetestet; für komkis Ausgabegrößen ohne
  Belang. [U]
- Version-Bump-Disziplin: Bei künftigen Releases vor dem Test
  `maintenance uninstall` einschalten oder Version hochzählen, sonst misst
  man alte Payloads (siehe Abschnitt oben).

Ausgeführt am 11.10.2026 im Worktree `komki-cli-burrito` (Ticket #75).
Keine Upstream-Änderungen; alle Fixes im eigenen CLI- und Naht-Code.
