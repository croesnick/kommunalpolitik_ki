# Standalone-Packaging für komki: Burrito und Alternativen

Recherche zur Frage nach einem eigenständigen komki-Executable mit
Burrito. Alle Quellen am 2026-10-04 abgerufen. [D] = durch Primärquelle
belegt. [U] = ungeklärt oder nicht getestet.

## Frage

Kann komki als eigenständige Datei verteilt werden, etwa mit Burrito
(https://github.com/burrito-elixir/burrito)? Beantwortet werden: Was macht
Burrito heute, ist es build-time-only, was müsste in komki geändert
werden, und was können Alternativen?

## Kontext

komki ist eine schlanke macOS-Operator-CLI in apps/komki_cli, gebaut
als escript mit `escript: [main_module: KomkiCli.CLI, name: "komki"]`
[Ticket #74; D apps/komki_cli/mix.exs]. Kommandos: init, doctor, up, down,
status, run. Er erzeugt Seatbelt-Sandboxprofile und spawnt sandbox-exec-
Kinder, startet und stoppt llama-server am Loopback und streamt Ausgaben.
Runtime-Deps: nur optimus. [D apps/komki_cli/mix.exs] Die App ist Teil der
Trusted Base des KomKI-CLIs, denn sie erzeugt das Confinement-Profil.
Host: macOS 27.2 auf arm64 (M1 Max).

Aus der Trusted-Base-Perspektive zählt, was am Ende in der verteilten
Binary landet, nicht nur die im Mixfile deklarierte Abhängigkeit. Packaging
darf keine neuen Runtime-Quellcode-Abhängigkeiten einführen.

## Burrito-Profil

### Was Burrito ist und wie es läuft

Burrito 1.6.0, Release auf hex.pm am 2026-07-24, MIT. [D hex.pm/api/
packages/burrito] Es baut für Mix-Projekte eine self-extracting Binary und
nimmt als Eingabe ein `mix release`, nicht einen escript: die Konfiguration
lautet `steps: [:assemble, &Burrito.wrap/1]`. [D README, Abschnitt Mix
Project Setup]

Ablauf zur Laufzeit nach README [D]:

1. Der Nutzer startet die Binary wie ein natives Programm.
2. Nur beim ersten Start entpackt der Zig-Wrapper das Payload (BEAM-Code
   plus ERTS des Zielplatforms) in ein festes Verzeichnis.
3. Der Wrapper startet die Erlang-VM aus dem entpackten Verzeichnis.
4. Weitere Starts derselben Version nutzen das bereits entpackte Verzeichnis.
5. Alte Versionen werden automatisch entfernt. [D README]

Das entpackte Verzeichnis liegt unter macOS in
"$HOME/Library/Application Support/<appname>"; der Pfad ist im Code des
Wrappers fest verdrahtet (src/wrapper.zig), ein dokumentierter
Laufzeit-Env-Override existiert nicht. [D wrapper.zig und README] Zur
Laufzeit setzt der Wrapper die Umgebungsvariablen `__BURRITO`,
`RELEASE_ROOT` und `__BURRITO_BIN_PATH`; die App kann den Pfad der
laufenden Binary über `Burrito.Util.Args.get_bin_path/0` lesen.
[D erlang_launcher.zig und lib/util/args.ex] Wartungs-Subcommands sind
eingebaut: `maintenance uninstall`, `maintenance directory`,
`maintenance meta`. [D README]

Zur Argumentaufnahme ruft die App `Burrito.Util.Args.argv/0` auf: unter
Burrito aus `:init.get_plain_arguments/0`, unter plain mix aus
`System.argv/0`. [D README und lib/util/args.ex]

### Pflegezustand

Repo burrito-elixir/burrito: erstellt 2021-10-26, letzter Push 2026-07-24
(auf den Hex-Release-Tag passend), 1 443 Stars, 70 Forks, 21 offene Issues
und 11 offene PRs. [D GitHub-API] Hex-Zähler: 242 761 Downloads insgesamt,
83 410 in 90 Tagen. [D hex.pm] Vom Projekt selbst als "experimental"
bezeichnet. [D README, Disclaimer]

### macOS-arm64-Unterstützung und Build-Voraussetzungen

- Das Ziel macOS Apple Silicon ([os: :darwin, cpu: :aarch64]) wird in der
  Ziel-Matrix geführt; Burrito liefert vorcompilierte ERTS ab OTP 25.3 für
  darwin x86_64 und aarch64. [D README]
- Als Build-Maschine wird macOS (x86_64 und Apple Silicon) für alle Ziele
  inklusive Windows x64 als geeignet geführt; nur Windows selbst als
  Build-Maschine wird nicht offiziell unterstützt (WSL empfohlen).
  [D README-Matrix]
- Der Build braucht zig, xz und 7z im PATH. [D README]
README nennt zig 0.15.2; das ist teilweise veraltet. Nach Issue #229 kann
1.5.x auf der macOS-26-SDK nicht mehr linken (undefinierte Symbole
`__availability_version_check`, `_dispatch_queue_create`,
`_arc4random_buf`), und 1.6.0 wechselt zu zig 0.16. Offen ist außerdem
#227: der Zig-Cache wird bei clean-builds nicht immer korrekt gelöscht.
[D Issue #229 und #227, beide open am 2026-10-04]

### Gatekeeper und Signierung

README zur macOS-Runtime, Original: "No runtime dependencies. however a
security exemption must be set in MacOS Gatekeeper unless the binary
undergoes code-signing." [D README]

### Bekannte offene Fehler, relevant genau für komki

- Issue #229 (open, geöffnet 2026-07-25): in 1.6.0 beansprucht die
  Elixir-CLI beim Boot die Anwendungsargumente selbst. `--version`
  und `--help` beantwortet die Elixir-CLI statt der App, den ersten
  freien Parameter nimmt sie als Skriptpfad, und die VM hält am Ende.
  Ein Fix-PR (#230) ist offen, keine Maintainer-Reaktion im Issue.
  [D Issue #229]
- Issue #234 (open, geöffnet 2026-08-18): durch den EPIPE-Fix aus #225
  startet der Unix-Wrapper den BEAM mit stdout als Pipe. OTPs `prim_tty`
  findet dann keine TTY und schaltet Raw-Mode, ANSI und die Abfrage der
  Terminalgröße ab; Tasten kommen nicht an. Zitat: "The BEAM therefore
  sees a pipe on stdout even when the user runs the binary in a terminal.
  OTP's prim_tty requires both stdin and stdout to be TTYs, so the tty
  backend is disabled entirely." [D Issue #234]
- Zugehörig offen: #233 (das `-mode embedded`-Flag wurde als einziges
  argv-Element übergeben, Releases booten im interaktiven Modus statt
  embedded), #215 (Raw-Mode-Support), #201 (System.halt beendet die VM
  unsauber), #140 (tmp file ownership error), #173 (AccessDenied, wenn
  man das Release ohne sudo ausführt), #162 (Segfault auf macOS x86_64).
  [D Tracker, alle open am 2026-10-04]

### Adopter

Via GitHub-Codesuche belegt: elixir-tools/next-ls (breit genutztes CLI-Tool),
openai/symphony, pass-agent/loomkin, dolthub/dolt Testpakete, ex_tauri,
plus die Beispiele im Repo. [D Codesuche 2026-10-04]

### Dateigröße

Keine belastbare Größenangabe in README oder Hexdocs. Belegt ist nur,
dass das Payload BEAM-Code plus komplette ERTS enthält und gzip-komprimiert
wird. [D README] Die konkrete Größe eines komki-Bundles ist ungeprüft.
[U]

## Ist Burrito build-time-only?

Nein, nicht als sauber konfigurierbare build-time-only-Abhängigkeit. Die
README verlangt eine Application-Entry über `mod:` und das argv-Lesen über
`Burrito.Util.Args.argv/0`. Diese Funktion ist Laufzeitcode. Damit ist
Burrito mindestens mit dem Modul `Burrito.Util` Teil des laufenden
Programms, und die ganze :burrito-App ist im Release praxisnah enthalten.
[D README und lib/util/args.ex] Die README dokumentiert kein
`runtime: false`, und auch Burritos eigenes Beispiel
(examples/cli_example/mix.exs) deklariert keine In- oder Exklusion.
[D examples/cli_example/mix.exs] Ob man die :burrito-App aus dem Release
ausschließen kann und argv selbst über `:init.get_plain_arguments/0`
liest (insoweit analog zu lib/util/args.ex), ist nicht dokumentiert und
nicht getestet. [U]

Im Ergebnis landet Burrito-Code in der verteilten komki-Binary. Das
ist klein, aber nicht Null, und es ist eine Trusted-Base-Zugabe.

## Integrationspfad für komki

Ausgehend vom Status quo (escript, main_module) laut README [D]:

1. `escript: [main_module: KomkiCli.CLI]` abzuschaffen; die App bekommt
   in mix.exs `mod: {KomKI-CLI, []}` und implementiert das
   Application-Behaviour `start/2`. Beenden muss hier über
   `System.halt(exit_code)` geschehen. [D README]
2. Argument-Lesen auf `Burrito.Util.Args.argv/0` umstellen. [D README]
3. Dependency `{:burrito, "~> 1.0"}` hinzufügen. [D README]
4. `def releases` mit `steps: [:assemble, &Burrito.wrap/1]` und Target
   `macos: [os: :darwin, cpu: :aarch64]`. [D README]
5. zig, xz und 7z in PATH. [D README]
6. `MIX_ENV=prod mix release`; die Binary erscheint unter `burrito_out/`;
   `BURRITO_TARGET=macos` erlaubt Einzel-Target. [D README]

Offen ist der Workspace-Fall: apps/komki_cli nutzt `deps_path:
../artifacts/deps` und die gemeinsame `workspace.lock`; ob
`MIX_ENV=prod mix release` dort reibungslos läuft, ist nicht getestet.
[U] Der bestehende escript-Build von ratsinfo bleibt von einer
Umrüstung in komki unberührt. [D apps/ratsinfo/mix.exs]

## Alternativen

### plain `mix release`

Ohne extra Dependency. Nach Mix-Doku [D mix.hexdocs.pm/Mix.Tasks.Release.html]:

- Ein Release ist self-contained: "Releases do not even require Erlang or
  Elixir in your servers, as it includes the Erlang VM and its runtime by
  default"; `include_erts` hat Default `true`. [D Mix-Doku]
- Portabilität ist beschränkt: "as long as the target runs on the same
  operating system (OS) distribution and version as the machine running
  the mix release command". Für komki: Build und Betrieb auf demselben
  macOS-Rechner, also kein Problem. [D Mix-Doku]
- Output ist ein Ordner unter `_build/`; ein `:tar`-Release-Step kann ein
  `.tar.gz` produzieren. [D Mix-Doku]
- Der generierte `bin/`-Wrapper ist auf Release-Kommandos ausgelegt
  (start, stop, pid, eval). Argumente für eigene CLIs erreicht man per
  `bin/<app> eval "KomkiCli.main()" -- args` oder über ein eigenes
  `env.sh` (dort ist `$@` dokumentiert). [D Mix-Doku]

Für komki heißt das: dieselbe self-contained-Grundlage wie Burrito
(BEAM plus ERTS), aber als Ordner oder tar.gz statt Einzeldatei, ohne
Packager-Abhängigkeit und ohne neuen Code in der Trusted Base.

### Bakeware

Der Vorläufer; Burritos README nennt ihn ausdrücklich als Inspiration.
[D README] Stand: letzte Hex-Version 0.2.4, Release 2022-05-25, Apache-2.0,
2 620 Downloads in 90 Tagen, 13 pro Tag. [D hex.pm/api/packages/bakeware]
Repo (bake-bake-bake/bakeware): letzter Push 2024-09-18, 1 417 Stars, 17
offene Issues. [D GitHub-API] Befund: ohne Releases seit 2022, faktisch
eingeschlafen. [U-Einschätzung] Keine Alternative zum derzeitigen Burrito.

### Sonstige Einzeldatei-Packager

Der Codesuche-Scan zeigt in aktiv genutzten Elixir-Projekten
(next-ls, symphony, loomkin, dolt-Tests, ex_tauri) nur Burrito im
deployten Einsatz. [D Codesuche 2026-10-04] Kein weiterer Packager ist
aus dem gebundenen Scan hervorgegangen.

## Vergleichstabelle

| Kriterium | Burrito | mix release (mit :tar) | Status quo escript |
|---|---|---|---|
| Auslieferungsform | einzelne Binary | Ordner oder .tar.gz | einzelne Datei (kein ERTS darin) |
| Neuer Runtime-Code in der verteilten Einheit | Teile von :burrito enthalten [D] | keine [D] | keine [D] |
| Start ohne installiertes Erlang | ja [D README] | ja [D Mix-Doku] | nein, braucht host OTP [U] |
| TTY/ANSI-Output korrekt | nein, Issue #234 open [D] | ja, Standard-VM-Start [U] | ja [U] |
| Eigene CLI-Flags korrekt | nein, Issue #229 open [D] | anpassbar, bin/eval oder eigener bin-Wrapper [U] | ja [U] |
| macOS Gatekeeper | Exemption oder Codesigning nötig [D README] | kein Quarantäne-Fall dokumentiert [U] | [U] |
| Build-Toolchain | zig, xz, 7z [D README] | nur mix | nur mix |
| Packager-Risiko | experimental [D README] | Mix-Kern [D] | keines |

## Empfehlung mit Begründung

1. mix release mit optionaler :tar-Stufe, zum heutigen Stand die beste
   Balance: dieselbe self-contained-Basis wie Burrito (App plus ERTS),
   aber ohne extra Abhängigkeit und ohne neuen Code in der verteilten
   Trusted-Base-Einheit. Einschränkung: Ordner bzw. tar.gz statt
   Einzeldatei, und für die komki-Kommandos muss ein eigener
   bin-Einstieg gebaut werden, denn der generierte bin-Wrapper ist auf
   Release-Kommandos ausgelegt. [D Mix-Doku]

2. Status quo escript: wenn komki nur auf der eigenen Maschine des
   Operators läuft, ist die Auslieferungsfrage gegenstandslos. Der
   escript enthält kein eigenes ERTS, der Host braucht Erlang/OTP; das
   ist hier gegeben und via Ticket #74 angenommen.
   [D apps/komki_cli/mix.exs]

3. Burrito: als Reserverfall, wenn eine echte Einzeldatei-Distribution
   gebraucht wird (Fremd-Rechner ohne Erlang/OTP). Dann ist Burrito der
   einzige aktive Weg im Ökosystem [D Scan], aber zum heutigen Stand mit
   drei offenen CLI-Regressions in 1.6.0 (#229 argv, #234 stdout/TTY,
   #233 embedded mode), die genau KomKI-CLIs Muster treffen: eigene
   Argumente, gefärbte Stream-Ausgabe, Streaming aus sandbox-exec-Kindern.
   Ein Pilot-Build müsste genau diese Punkte als Prüfblock behandeln, und
   Gatekeeper-Exemption oder Codesigning würde zusätzlich benötigt.
   [D #229, #234, README]

## Offene Punkte

- Größe des komki-Payloads (BEAM plus ERTS plus optimus):
  keine belastbare Zahl in den Quellen. [U]
- Gatekeeper-Verhalten nach dem Entpacken nach
  `~/Library/Application Support/komki`: ungetestet. [U]
- mix release im Workspace mit shared deps_path und workspace.lock:
  ungetestet. [U]
- ob die :burrito-App aus dem Release ausgeschlossen werden kann und argv
  direkt über `:init.get_plain_arguments/0` gelesen wird:
  nicht dokumentiert. [U]
- ob Zig 0.16 (1.6.0) auf der macOS-27.2-SDK (host) sauber baut:
  dokumentiert ist nur 1.5.x-plus-macOS-26-SDK-Problem. [U]

Recherche ausgeführt am 2026-10-04 (Wayfinder Map croesnick/kommunalpolitik_ki#67,
Diskussion zu Ticket #74). Nur dieser Draft wurde angelegt; keine Repository-
Änderungen, keine Installationen, keine Abhängigkeitsänderungen, keine
GitHub-Writes.
