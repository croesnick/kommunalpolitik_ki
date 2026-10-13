# Release-Konzept

> **Zweck:** Single Source of Truth für den Weg von „Code fertig“ bis
> „Release veröffentlicht“ — nachvollziehbar, mit explizitem GO-Gate. Gilt für
> alle release-fähigen Tools dieses Repos. Grundlagen: der Burrito-Pilot aus
> Ticket #75
> ([docs/research/2026-10-11-komki-burrito-pilot.md](research/2026-10-11-komki-burrito-pilot.md)),
> die Entscheidungen aus Ticket #79, die Signierungs-Entscheidung in
> [ADR 0001](adr/0001-ad-hoc-signierung-statt-developer-id.md).

## Geltungsbereich

Release-fähig ist ein Tool, wenn es eine verteilbare Binary gibt. Heute ist
das allein komki (Burrito-Standalone). Apps ohne Binary — etwa ratsinfo, das
als Escript über `make install` läuft — reifen über Issues und Merges und
bekommen keine Releases.

Jedes release-fähige Tool veröffentlicht eigenständig: eigener Tag-Strom
`<tool>-v<semver>`, eigener GitHub-Release. Eine repo-weite Gesamtversion gibt
es nicht. Mehrere reifende Apps bedeuten mehrere unabhängige Tag-Ströme, kein
gemeinsames Versions-Diktat.

## Voraussetzungen

- Bauwerkzeuge: zig exakt 0.16.0 (Seiteninstallation, Burrito prüft auf
  Gleichheit), xz im PATH — Anleitung und Begründung in
  [docs/prerequisites.md](prerequisites.md).
- Für die Smoke-Matrix: die komki-Laufzeitumgebung (llama.cpp, tmux, node mit
  pi-Bundle, gepinntes GGUF), ebenfalls [docs/prerequisites.md](prerequisites.md).

## Die Kette

Alle Befehle laufen aus `apps/komki_cli`, soweit nicht anders gesagt.

### 1. „Code fertig“ feststellen

Der Stand ist gemerged, und beide Artefakte sind grün (Dual-Artefakt-Disziplin):

- CI grün: Format, Compile ohne Warnungen, credo, Tests.
- `mix escript.build` läuft. Der Escript bleibt der Dev-Nachweis; die Tests
  der App schützen die geteilten Pfade.

### 2. Version festlegen

- Nie dieselbe Version zweimal veröffentlichen.
- Der Tag `<tool>-v<semver>` muss exakt zur `version` in
  `apps/komki_cli/mix.exs` passen (aktuell: `komki-v0.1.0` ↔ `"0.1.0"`).
  Vor dem Tag prüfen — das kann ein Skript übernehmen, ein Mensch muss es
  nicht selbst tun.
- Bump-Semantik in der 0.x-Phase, pragmatisch: sichtbare Neuerungen oder
  Brüche → Minor (`0.2.0`), Fehlerbehebungen → Patch (`0.1.1`).
- Erwünschter Nebeneffekt: Eine neue Version benennt das
  Installationsverzeichnis des Wrappers um. Payload-Staleness über
  Release-Grenzen ist damit strukturell ausgeschlossen.

### 3. Lokal bauen

Bauort ist der Rechner des Operators (macOS arm64). macOS-Runner in CI sind
bewusst verworfen: GitHub-hosted macOS-Runner kosten rund das Zehnfache pro
Minute gegenüber Linux (0,062 USD/min für macOS-Runner mit M1/Intel gegenüber
0,006 USD/min für Linux 2-core), und der Bau braucht ohnehin ein menschliches
GO am Ende; lokal zu bauen macht die Kette nicht langsamer. Neu zu entscheiden
ist das erst, wenn ein zweiter Operator oder ein zweites OS-Ziel dazukommt;
dann lohnt ein eigener Runner-Job mit gepinntem zig.

```bash
PATH="$HOME/.local/opt/zig-aarch64-macos-0.16.0:$PATH" \
  MIX_ENV=prod BURRITO_TARGET=macos_silicon mix release
# → burrito_out/komki_macos_silicon
```

`MIX_ENV=prod` ist Pflicht: Nur prod-Builds nutzen das einmal entpackte
Payload wieder; dev-Builds entpacken bei jedem Lauf neu.

### 4. Frisch entpacken (Rebuild-Disziplin)

Der Wrapper überspringt das Entpacken, sobald `_metadata.json` im
Installationsverzeichnis liegt. Wer eine neu gebaute Binary derselben Version
testet, misst sonst den alten Stand. Deshalb vor jedem solchen Test:

```bash
./burrito_out/komki_macos_silicon maintenance uninstall   # fragt y/n
```

Alternativ: `KOMKI_INSTALL_DIR` auf ein frisches Verzeichnis zeigen lassen.

### 5. Smoke-Matrix gegen die Einzeldatei

Die komplette Matrix läuft gegen die frisch entpackte Binary, ohne Elixir im
PATH — in einer eigenen Instanz (temporäres KOMKI_HOME, eigener Port), damit
eine laufende Nutzer-Instanz unberührt bleibt. Für komki (Stand: Pilot #75):

| # | Schritt | grün wenn |
|---|---|---|
| 1 | `init` | GGUF-Kopie SHA-geprüft, exit 0 |
| 2 | `doctor` | 9/9 Checks grün, exit 0 |
| 3 | `up` | llama-Boot, health 200, exit 0 |
| 4 | `run "Antworte mit exakt einem Wort: ok"` | Modellantwort „ok", exit 0 |
| 5 | `run --help` | eigene Usage, exit 0, kein pi-Lauf |
| 6 | Write-Werkzeug-Lauf | Datei mit erwartetem Inhalt, exit 0 |
| 7 | `down` | pidfile weg, Port frei, Prozess weg, exit 0 |

Dazu zwei Störproben, jede mit grüner Wiederherstellung: Profil-Drift →
`doctor` exit 3; absurd großer Kontext → `up` exit 4.

### 6. Checksummen bilden

```bash
cd burrito_out
shasum -a 256 komki_macos_silicon > SHA256SUMS
```

Die SHA256SUMS wird zusammen mit der Binary als Release-Asset hochgeladen —
konventionelles Format, auf der Gegenseite prüfbar per `shasum -c`.

### 7. Release-Notes schreiben

Bewährter Inhalt (aus #75):

- **Bau-Stand:** Commit-SHA, aus dem die Binary gebaut wurde.
- **Grenzen:** was diese Version nicht kann oder nicht tut.
- **Gatekeeper-Hinweis** — Pflichtinhalt, nie optional (ADR 0001):

  > Diese Datei ist ad-hoc signiert und nicht notarisiert. Beim ersten Start
  > nach dem Download blockiert Gatekeeper. Abhilfe einmalig:
  > `xattr -d com.apple.quarantine <datei>`

- **Quellen-Links:** Pilot-Bericht, zugehörige Tickets.

### 8. Draft-Release anlegen

```bash
gh release create komki-v0.1.0 --draft \
  --target <finaler-commit-sha> \
  --title "komki 0.1.0" --notes-file notes.md \
  burrito_out/komki_macos_silicon burrito_out/SHA256SUMS
```

Zwei Eigenschaften von Drafts, auf denen dieses Protokoll baut:

- Ein Draft legt kein Tag an. Das Release ist bis zur Veröffentlichung
  „untagged“; das Tag-Ref entsteht erst beim Veröffentlichen und zeigt dann
  auf den Ziel-Commit aus `--target`. Das GO deckt also Tag und
  Veröffentlichung in einem Zug ab; vor dem GO verändert nichts das Repo.
- Drafts sehen nur Konten mit Schreibrechten. Das Repo ist privat: Die
  zweite Maschine braucht ein authentifiziertes `gh` mit Zugriff.

### 9. Zweit-Maschinen-Check

Auf einem anderen macOS-arm64-Rechner, bei jedem Release:

```bash
gh release download komki-v0.1.0
shasum -a 256 -c SHA256SUMS   # prüft den Download-Weg mit
xattr -d com.apple.quarantine komki_macos_silicon
./komki_macos_silicon doctor   # ein Smoke-Schritt genügt
```

Das ist die einzige Probe des echten Download-Pfads — des Erlebnisses, das
Nutzer haben. Lokal lässt sich das Quarantäne-Verhalten nicht sehen, deshalb
gehört dieser Schritt in jeden Release, nicht nur in den ersten.

### 10. Publish-GO

Vorgelegt werden: Smoke-Protokoll, SHA256SUMS, Notes-Entwurf, Ergebnis des
Zweit-Maschinen-Checks. Dann genau ein GO, keine verketteten Teil-GOs. Nach
dem GO:

```bash
gh release edit komki-v0.1.0 --draft=false
git fetch --tags origin
```

Das Veröffentlichen legt das Tag an (auf den finalen Commit) und macht das
Release sichtbar — ein Vorgang, ein GO.

## Automatisierung

Die Kette bis zur Evidenz ist mechanisch und wird als Elixir-Mix-Task
automatisiert: `mix komki.release` übernimmt

1. Versions-Check (Tag ↔ `mix.exs`),
2. Bau,
3. Uninstall (Rebuild-Disziplin),
4. Smoke-Matrix,
5. SHA256SUMS,

und gibt das Protokoll aus, das beim GO vorgelegt wird. Manuell bleiben die
Schritte, die einen Menschen oder eine zweite Maschine brauchen: Draft
anlegen, Zweit-Maschinen-Check, Veröffentlichen — alles hinter dem
Publish-GO.

## Signierung

Ad-hoc linker-signiert, dauerhaft — Begründung und Konsequenzen in
[ADR 0001](adr/0001-ad-hoc-signierung-statt-developer-id.md). Für dieses
Dokument heißt das: Der Quarantäne-Hinweis ist fester Pflichtbestandteil
jeder Release-Notes.

## Erste Anwendung

`komki-v0.1.0` ist noch nicht veröffentlicht. Der erste Release nach diesem
Konzept validiert die Kette end-to-end — die Schritte 8 bis 10 hat der Pilot
nicht durchlaufen.

## Quellen

- Pilot-Bericht:
  [docs/research/2026-10-11-komki-burrito-pilot.md](research/2026-10-11-komki-burrito-pilot.md)
  (Ticket #75)
- Tickets: croesnick/kommunalpolitik_ki #75, #79
- ADR: [docs/adr/0001](adr/0001-ad-hoc-signierung-statt-developer-id.md)
- Begriffe: [GLOSSARY.md](../GLOSSARY.md) — Verify-then-Publish, Smoke-Matrix,
  Payload-Staleness, Publish-GO, Dual-Artefakt-Disziplin
- Draft-Mechanik („Draft legt kein Tag an“, „Drafts nur für Schreibrechte
  sichtbar“): gh-CLI-Handbuch (cli.github.com/manual/gh_release_create),
  cli/cli#11589 (github.com/cli/cli/issues/11589) und GitHub-REST-Doku
  (docs.github.com/en/rest/releases/releases), abgerufen 2026-10-13.
- Runner-Preise (macOS 0,062 USD/min gegenüber Linux 0,006 USD/min):
  GitHub-Billing-Doku
  (docs.github.com/en/billing/reference/actions-minute-multipliers), abgerufen
  2026-10-13.
