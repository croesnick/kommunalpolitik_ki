# Elixir-CLI-Bibliotheken für komki

Recherche zu Ticket #74 (komki-CLI), Wayfinder Map #67. Abrufdatum
aller Quellen: 2026-10-04. [D] = durch Primärquelle belegt. [U] = ungeklärt.

## Frage

Nutzt komki eine CLI- oder TUI-Bibliothek, oder bleibt es bei der
Stdlib? Beantwortet werden: Was bietet owl konkret, wie wird es gepflegt,
was kostet es an Dependencies, und welche Option hält die Trusted Base am
schmalsten?

## Kontext

komki ist ein schlanker macOS-Operator-Launcher mit den Kommandos init,
doctor, up, down, status und run. Er erzeugt ein Sandbox-Profil, startet
und stoppt llama-server am Loopback, ruft pi unter sandbox-exec auf,
prüft SHA-256-Hashes und streamt Ausgaben. Eine TUI ist nicht das Ziel.
Die interaktive Agent-Arbeit läuft in pi selbst.

Drei Output-Bedarfe sind real. Ein Spinner oder eine Statuszeile für den
circa 60 Sekunden dauernden Health-Wait. Farbige Verdict-Zeilen. Einfache
Tabellen für status.

Der Trust-Base-Trade-off ist der Hauptpunkt. komki generiert das
Confinement-Profil. Jede Runtime-Dependency landet in dem Werkzeug, das die
Sandbox erzeugt. Eine neue Bibliothek vergrößert den Supply-Chain-
Angriffspunkt der Trusted Base und ist deshalb eine Sicherheitsfrage, nicht
nur eine Ergonomiefrage.

## Kandidatenprofile

### owl

Quellen: hex.pm/packages/owl, hex.pm/api/packages/owl/releases/0.13.1,
github.com/fuelen/owl (README und mix.exs). Alle abgerufen 2026-10-04.

Version 0.13.1, Release 2026-06-04. Apache-2.0. [D]

owl bringt genau die drei fehlenden Ausgabe-Primitiven [D README]:
Progress-Bars und Spinner, auch mehrere parallel. Tabellen und ASCII-Boxen
um mehrzeilige, bereits gefärbte Inhalte. Farbe über Text-Tags. Für
full-screen-Anwendungen ist owl nicht gebaut; das README verweist dafür
auf TermUI, Ratatouille und ExNcurses und platziert owl für "reguläre
Skripte und CLI-Tools", die top-to-bottom laufen und auf stdout ausgeben.
[D README]

Dependency-Kosten: Das Hex-Release listet genau eine Requirement,
ucwidth ~> 0.2, mit dem Flag optional: true. [D hex-release-JSON] Das
README sagt: ohne ucwidth fehlt die Unterstützung für Multibyte-Zeichen
(Emojis). Für reine ASCII-Ausgaben reicht owl allein. [D README]

Pflegezustand: 532 Stars, 15 Forks, 0 offene Issues, 0 offene PRs, 184
Commits, letzter Push 2026-06-04. [D GitHub-API] Releases in 2025 (0.12.1
Januar, 0.12.2 Februar, 0.13.0 August) und 2026 (0.13.1 Juni). [D hex.pm-API]
Downloads: 2 995 443 insgesamt, 729 746 in 90 Tagen, 4 871 pro Tag. [D hex.pm]

Verwender: ash-project/igniter (owl ~> 0.11), zachallaun/mneme (owl ~>
0.9), coryodaniel/bonny (owl ~> 0.13.0, runtime: false), mishka-group/
mishka_chelekom (owl ~> 0.13). [D GitHub-Code-Suche, 2026-10-04]

Escript-Anmerkung: owl ist eine OTP-App mit eigener Supervision; mix.exs
des Pakets deklariert mod: {Owl.Application, []}. [D mix.exs] Die
mix-Doku sagt, der escript-Task startet die eigene konfigurierte
Applikation; der Start von Dependency-Apps ist dort nicht gelistet.
[D mix.hexdocs.pm/Mix.Tasks.Escript.Build.html] Konsequenz: das
escript-Hauptmodul müsste vor der ersten owl-Nutzung
Application.ensure_all_started(:owl) aufrufen. Parallelfall aus der
Praxis: mishka_chelekom kommentiert im Task-Code, dass Owl.Spinner ohne
diesen Aufruf mit :noproc abbricht, und ruft ihn in jedem Task auf.
[D mishka-group/mishka_chelekom, lib/mix/tasks/mishka.ui.gen.mob.ex] Ein
gemeldeter escript-Bug existiert nicht, die Issues-Suche nach escript in
fuelen/owl liefert null Treffer. Ein escript-Build mit owl ist ungetestet.
[U]

### optimus

Quellen: hex.pm/packages/optimus, hex.pm/api/packages/optimus/releases/
0.6.1, github.com/savonarola/optimus (README und mix.exs), apps/ratsinfo/
mix.exs. Alle abgerufen 2026-10-04.

Version 0.6.1, Release 2026-02-03; 0.6.0 folgte erst eine Woche vorher am
2026-01-25. Die Paketversion ist also frisch. MIT. [D]

optimus ist ein Argument-Parser im Stil von clap.rs, keine TUI-Bibliothek.
[D README auf github.com/savonarola/optimus] Er bietet Commands und
Subcommands, Flag- und Positional-Parsing, typisierte Werte mit eigenen
Parsers, Validierung unbekannter Argumente über allow_unknown_args: false,
und generierte Hilfetexte mit USAGE-Block sowie automatisch behandelter
--help und --version. [D README] Er rendert keine Widgets und färbt nichts;
die eigentliche Ausgabe baut man selbst, zum Beispiel mit IO.ANSI. [U
Inferenz, nicht getestet]

Dependency-Kosten: exakt null. Die Release-JSON listet requirements {},
mix.exs des Pakets konfiguriert keine Application mit mod, nur
extra_applications: [:logger]. Es gibt also keine Prozesse, die beim
escript-Start angestoßen werden müssten. [D hex-release-JSON und mix.exs]
Elixir-Anforderung: ~> 1.12. [D release-JSON]

Pflegezustand: letzter Push 2026-07-27, 0 offene Issues, 3 offene PRs,
161 Commits, 22 Stars, 5 Forks. [D GitHub-API] Downloads: 578 919
insgesamt, 105 534 in 90 Tagen, 823 pro Tag. [D hex.pm-API] Kleine
Community und geringes Wachstum.

Repo-Präzedenz: apps/ratsinfo/mix.exs hat {:optimus, "~> 0.6"} und baut
als escript mit main_module Ratsinfo.CLI. [D apps/ratsinfo/mix.exs]

### ratatouille

Quellen: hex.pm/packages/ratatouille, hex.pm/api/packages/ratatouille/
releases/0.5.1, github.com/ndreynolds/ratatouille. Abgerufen 2026-10-04.

Letzte Version 0.5.1, Release 2020-03-25. [D release-JSON] Repo: letzter
Push 2023-03-20, 22 offene Issues, 850 Stars, Downloads nur noch 670 in
90 Tagen und 3 pro Tag. [D GitHub-API und hex.pm] Lizenz MIT, Runtime-Deps
zwei feste: asciichart ~> 1.0 und ex_termbox ~> 1.0, letztgenanntes bindet
eine Native-Library ein. [D release-JSON]

Befund: ein full-screen-TUI-Framework, das komki nicht braucht, und
seit über drei Jahren ohne Commit. Die Schlussfolgerung "stale" folgt aus
den Zahlen oberhalb. [U] Ausgeschieden.

### progress_bar

Quellen: hex.pm/packages/progress_bar, hex.pm/api/packages/progress_bar/
releases/3.1.0, github.com/JustAman62/progress_bar (mix.exs, branch
master). Abgerufen 2026-10-04.

Version 3.1.0, Release 2026-06-27. MIT. [D]

Bietet genau zwei Dinge: Progress-Bars und Spinner für CLI-Ausgaben. Die
hex.pm-Beschreibung lautet "Command-line progress bars and spinners".
[D hex.pm] Genau das deckt die Spinner-Anforderung ab. Tabellen und Boxen
kann owl, dieses Paket nicht. [D owl README]

Dependency-Kosten: exakt null. Requirements {} im Release, Application
ohne mod im mix.exs des Pakets. [D release-JSON und mix.exs]
Elixir-Anforderung: ~> 1.9. [D release-JSON]

Pflegezustand: letzter Push 2026-06-27, 4 offene Issues, 338 Stars.
[D GitHub-API] Downloads: 1 240 040 insgesamt, 64 696 in 90 Tagen, 639 pro
Tag. [D hex.pm] Etwa ein zehntel der owl-Nachfrage.

### bunt (Randnotiz)

Quellen: hex.pm/api/packages/bunt. Abgerufen 2026-10-04.

Version 1.0.0, Release 2023-12-05. MIT. Reine ANSI-Färbenerweiterung für
256 Farben. [D hex.pm] Sie bringt gegenüber IO.ANSI wenig Neues und wäre
eine zusätzliche Runtime-Dependency. Ausgeschieden.

## Vergleichstabelle

| Paket       | Version (Release)      | Runtime-Deps                  | Elixir  | Lizenz      | Letzter Repo-Push | Offene Issues | Downloads 90 Tage |
|-------------|------------------------|-------------------------------|---------|-------------|-------------------|---------------|-------------------|
| owl         | 0.13.1 (2026-06-04)    | 1 (ucwidth, optional)         | ~> 1.16 | Apache-2.0  | 2026-06-04        | 0             | 729 746           |
| optimus     | 0.6.1 (2026-02-03)     | 0                             | ~> 1.12 | MIT         | 2026-07-27        | 0             | 105 534           |
| progress_bar| 3.1.0 (2026-06-27)     | 0                             | ~> 1.9  | MIT         | 2026-06-27        | 4             | 64 696            |
| ratatouille | 0.5.1 (2020-03-25)     | 2 (asciichart, ex_termbox)    | ~> 1.5  | MIT         | 2023-03-20        | 22            | 670               |
| bunt        | 1.0.0 (2023-12-05)     | 0                             | n/a     | MIT         | 2023-12-06        | 1             | 4 222 436         |

Quellen: hex.pm-API und GitHub-API, alle abgerufen 2026-10-04. [D]

## Empfehlung (Ranking, keine Entscheidung)

1. optimus für das Parsing, IO.ANSI für Farben, ein handgeschriebener
   minimaler Spinner. Keine neuen Runtime-Dependencies. optimus ist mit
   ratsinfo bereits im Workspace vorhanden, hat null Runtime-Deps und
   null Prozesse, die es zu starten gäbe. Der Spinner für den 60-s-Wait
   ist mit IO.ANSI und Process in unter 100 Zeilen eigenbaubar. Farbige
   Verdict-Zeilen deckt IO.ANSI; einfache Tabellen lassen sich bei den
   paar status-Zeilen selbst rendern. Das ist die kleinste Vergrößerung
   der Trusted Base.

2. optimus plus owl. owl ist im ökosystem der einzige aktive Kandidat,
   der Spinner, Tabellen und Boxen auf einmal bietet. Er ist gepflegt
   (0 offene Issues, Release 0.13.1 im Juni 2026) und hat produktive
   Anwender wie igniter. Die Kosten sind: owl ist eine OTP-App mit
   eigener Supervision und landet damit in der Trusted Base. Der
   escript-Hauptmodul braucht Application.ensure_all_started(:owl).
   ucwidth bleibt optional und weglassbar, solange keine Emojis in den
   Tabellen landen. Die Risikostufe ist mittel, im Absolutwert aber
   klein: der Dependency-Footprint von owl selbst ist eine einzige,
   optional weglassbare Dependency ohne Transitivität.

3. stdlib-only. OptionParser und IO.ANSI, auch ohne optimus. Das hält
   die Trusted Base unverändert. Die Kosten sind: ratsinfo hat einen
   optimus-Präzedenz, komki würde mit einem zweiten Parser-Stil
   parsen; die Hilfe-Texte und die Argument-Validierung müssen
   für jedes Kommando manuell gepflegt werden. Der wiederkehrende
   Mehrcode ist klein, aber kontinuierlich.

Ausgeschieden: ratatouille (stale seit 2023, falsche Kategorie, bindet
ex_termbox mit Native-Code) und bunt (Farb-Hilfsfunktionen, die IO.ANSI
schon deckt).

## Offene Punkte

- owl unter escript ist ungetestet. Es existiert kein gemeldeter Bug und
  keine Doku. Bewertung und echte Kosten bleiben bis zum Test offen.
  Vor einer owl-Entscheidung wäre einmal mix escript.build mit owl
  durchzuführen, inklusive Application.ensure_all_started(:owl) im
  Hauptmodul. [U]
- ob der 60-s-Wait wirklich ein dynamisches Widget braucht oder ob eine
  statische Statuszeile reicht. Wenn die Statuszeile ausreicht, entfällt
  das owl-Argument fast vollständig. [U]
- ucwidth, falls Status-Tabellen Emoji oder CJK-Zeichen zeigen sollen,
  müsste es zusätzlich aktiviert werden; wie groß sein eigener Code-
  Footprint ist, wurde nicht geprüft. [U]
- optimus ist klein (22 Stars), hat aber Releases 2026 und 0 offene
  Issues. Ob die kleine Community beim Auftreten eines Bugs hilft, ist
  unbeantwortet. [U]
