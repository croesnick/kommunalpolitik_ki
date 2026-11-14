# Bau und Release von komki

> **Zweck:** Single Source of Truth dafür, wie man zu einem laufenden komki
> kommt. Heute gilt allein der **lokale Bau aus dem Checkout**. Versionen
> und Tags sind in Kraft (Ticket #538). Ein veröffentlichter Release
> (GitHub-Release, öffentlicher Homebrew-Tap) ist beschrieben, aber nicht in
> Kraft (Entscheidung 29.10.2026, Ticket #79).
> Grundlagen: der Burrito-Pilot aus Ticket #75
> ([docs/research/2026-10-11-komki-burrito-pilot.md](research/2026-10-11-komki-burrito-pilot.md)),
> die Signierungs-Entscheidung in
> [ADR 0001](adr/0001-ad-hoc-signierung-statt-developer-id.md), der Lauf vom
> frischen Clone in Ticket #241.

## Lokaler Bau aus dem Checkout

Ziel: Jede Person mit einem Clone kommt mit denselben Schritten zum selben
komki wie der Autor. Nichts wird heruntergeladen außer Werkzeugen,
Abhängigkeiten und dem gepinnten Modell.

### Voraussetzungen

Mac mit Apple Silicon, rund 32 GB Arbeitsspeicher (das Modell belegt rund
17 GB), rund 20 GB Platz. Werkzeuge und Installationsbefehle stehen in
[docs/prerequisites.md](prerequisites.md) § KomKI-CLI und auf der Doku-Site
unter [In Betrieb nehmen](site/src/content/docs/komki/in-betrieb-nehmen.mdx).
`komki setup` prüft sie zuerst und nennt für alles Fehlende den Befehl.

### Weg 1: Escript (Standard)

```bash
git clone https://github.com/croesnick/kommunalpolitik_ki.git
cd kommunalpolitik_ki
make komki          # baut apps/komki_cli/komki, Link nach ~/.local/bin/komki
komki setup --demo  # Instanz, Test-Vault, Start, doctor
komki session
```

Der Link liegt in `KOMKI_LINK_DIR` (Standard `~/.local/bin`). Das Escript
bleibt im Clone und findet dort seinen Build-Baum (die SQLite-NIF). Den
Clone deshalb nicht löschen oder verschieben, solange der Link benutzt wird.

Aktualisieren: `git pull && make komki && komki setup`. `setup` fragt, ob es
das veränderte komki übernehmen soll (Programm-Pin), und frischt Pfade und
Sandbox-Profile auf.

### Weg 2: lokaler Homebrew-Tap

Für alle, die ihre Werkzeuge über Homebrew pflegen:

```bash
make komki-tap      # baut dist/komki-<version>-macos-arm64.tar.gz,
                    # schreibt Formula/komki.rb mit file://-Adresse in den
                    # lokalen Tap croesnick/tap und installiert (neu)
komki setup
```

Der Tap existiert nur auf diesem Rechner, es gibt kein Remote. `make
komki-tap` ersetzt eine schon installierte Homebrew-Fassung von komki. Das
Paket allein, ohne Installation, baut `make komki-paket`.

Stehen beide Wege nebeneinander, gewinnt, was im `PATH` zuerst kommt
(`/opt/homebrew/bin` steht meist vor `~/.local/bin`). `which komki` zeigt es.

### Weg 3: Einzeldatei (ohne Homebrew)

`make komki-burrito` baut eine Datei mit eingebauter Laufzeit,
`dist/komki-<version>-macos-arm64-einzeldatei`. Der Bau braucht zig 0.16.0
und xz ([docs/prerequisites.md](prerequisites.md)). Für Rebuilds derselben
Version gilt die Rebuild-Disziplin unten.

### Prüfen, ohne die eigene Instanz anzufassen

Eine Wegwerf-Instanz läuft neben der Hauptinstanz:

```bash
make komki KOMKI_LINK_DIR=/tmp/komki-bin   # eigener Link statt ~/.local/bin
KOMKI_HOME=/private/tmp/komki-test /tmp/komki-bin/komki setup --demo --port 50000 \
  --gguf-from ~/.local/share/komki/models/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf \
  --drafter-from ~/.local/share/komki/models-staging/mtp-gemma-4-26B-A4B-it-Q8_0.gguf
KOMKI_HOME=/private/tmp/komki-test /tmp/komki-bin/komki run "Was steht im Vault zum Radverkehr?" 2>&1 | cat
KOMKI_HOME=/private/tmp/komki-test /tmp/komki-bin/komki down
```

Beide `--…-from`-Pfade setzen vorhandene Dateien voraus (Modell in der
Hauptinstanz, MTP-Drafter im Staging-Ort, Ticket #318). Fehlt der Drafter,
lädt `setup` ihn nach Rückfrage selbst — ohne Terminal gilt die Antwort als
Nein, der Lauf endet dann mit Exit 2.

- Der `KOMKI_HOME`-Pfad muss kurz sein: Unix-Sockets dürfen höchstens 103
  Byte lang sein. `setup` prüft das zuerst und nennt Länge und Abhilfe
  (#246); der Scratchpad eines Agenten ist dafür meist zu lang.
- `--port N` legt die Egress-Ports auf N+7 und N+8 (#203), eine
  Wegwerf-Instanz kollidiert also nicht mit der Hauptinstanz.
- `komki session` bindet das tmux-Pane ausdrücklich an seine Basis (#251).
  Jede Instanz hat ihren eigenen tmux-Server; zeigt `KOMKI_HOME` im Pane
  auf eine andere Basis, startet die Session nicht.
- Der Brave-Schlüssel liegt im Schlüsselbund unter einem festen Namen. Die
  Wegwerf-Instanz benutzt also denselben Schlüssel, und macOS fragt beim
  Start des Web-Connectors nach Touch ID.
- `komki run` stirbt, wenn stdout oder stderr an keinem Terminal hängen (#135), deshalb `2>&1 | cat`. `| cat` allein reicht nicht: Am 30.10.2026 brach pi mit Exit 134 ab, solange stderr direkt an der aufrufenden Shell ohne Terminal hing.

Ein zweites macOS-Benutzerkonto ist der ehrlichere Test, weil dort keine
asdf-, Homebrew- oder pi-Stände des eigenen Kontos mitlaufen. Er ist noch
nicht gelaufen (#241).

## Versionen und Tags (in Kraft)

Seit Ticket #538 haben fünf Einheiten eine eigene Version und ein eigenes
Changelog: `komki` (das ganze Programm), `ratsprojekte`, `sidecar`,
`seatbelt` und `sealed_envelope`. Eine repo-weite Gesamtversion gibt es
nicht. Begründung: [ADR 0005](adr/0005-versionierung-mit-changesets-und-knope.md).

- **Changesets:** Jede spürbare Änderung bringt ein Changeset unter
  `.changeset/` mit. Format, Pflicht und Sprache:
  [docs/agents/changesets.md](agents/changesets.md).
- **Version-PR:** Der Workflow `versionen` sammelt die offenen Changesets
  per knope in einem PR auf dem Branch `versionen`. Nur ein Mensch mergt
  ihn, und der Merge ist das GO für die Tags.
- **Tags:** `<einheit>/v<semver>`, etwa `komki/v0.2.0`. Das Schema gibt
  knope bei mehreren Einheiten fest vor. Ein Tag markiert eine Version und
  veröffentlicht nichts: Er startet keinen Bau und legt kein GitHub-Release
  an.
- **Version:** nie dieselbe Version zweimal. In der 0.x-Phase liest knope
  Versionen als `0.<major>.<minor>`: Brüche und große Neuerungen → `major`
  (0.1.0 → 0.2.0), kleinere Neuerungen → `minor`, Fehlerbehebungen →
  `patch` (beide 0.1.0 → 0.1.1).
- **Baseline:** Alle fünf Einheiten starten bei 0.1.0. Die Tags
  `<einheit>/v0.1.0` stehen auf dem Merge-Commit von #538.

Ein Build aus dem Checkout zwischen zwei Tags meldet die Version des
letzten Version-PR, obwohl `main` schon weiter ist. `komki version` zeigt
also den Stand der letzten Versionierung, nicht den genauen Commit.

## Release (später, nicht in Kraft)

Diese Kette gilt erst, wenn komki veröffentlicht werden soll. Bis dahin wird
nichts hochgeladen.

Grundsätze, die beim ersten Release gelten sollen:

- **Je Tool ein eigener Release** zu einem vorhandenen Tag
  `<einheit>/v<semver>` (oben). Nur Tools mit verteilbarer Datei sind
  release-fähig, heute allein komki. Der Workflow `komki-release` startet
  nur von Hand (`gh workflow run komki-release.yml -f tag=komki/v<version>`)
  und prüft, dass der Tag zur `version` in `apps/komki_cli/mix.exs` passt.
- **Bau lokal**, nicht in CI: macOS-Runner kosten rund das Zehnfache von
  Linux (0,062 gegenüber 0,006 USD/min), und am Ende steht ohnehin ein
  menschliches GO.
- **Verify-then-Publish:** Die Datei, die veröffentlicht wird, ist aus dem
  finalen Commit gebaut, frisch entpackt und gegen die Smoke-Matrix geprüft.
  Prüfsumme (`SHA256SUMS`) und Notes gehören zu genau dieser Datei.
- **Signierung:** ad-hoc, ohne Developer ID ([ADR 0001](adr/0001-ad-hoc-signierung-statt-developer-id.md)).
  Der Quarantäne-Hinweis (`xattr -d com.apple.quarantine <datei>`) ist
  Pflichtinhalt der Notes.
- **Zweit-Maschinen-Check:** Download aus dem Draft-Release, `shasum -c`,
  Quarantäne entfernen, ein Smoke-Schritt. Nur so sieht man den Weg, den
  Nutzende erleben.
- **Echte Hardware:** Was die Mock-Welt nicht nachstellen kann, steht in
  [echte-hardware.md](echte-hardware.md). Vor jedem Release läuft dort der
  Live-Test für Touch ID (`cd apps/komki_cli && mix test --include touch_id`)
  auf einem Mac und zeigt genau eine Rückfrage.
- **Ein Publish-GO** nach vorgelegtem Smoke-Protokoll, Prüfsummen, Notes und
  Zweit-Maschinen-Check. Der Tag besteht dann schon (Version-PR); das GO
  gilt dem Veröffentlichen.
- **Neuerungen auf der Doku-Site:** Mit dem ersten Release bekommt
  `docs/site/` eine Seite „Neuerungen“, die das komki-Changelog zeigt.

### Rebuild-Disziplin (Burrito)

Der Burrito-Wrapper entpackt nicht neu, sobald `_metadata.json` im
Installationsverzeichnis liegt (Payload-Staleness). Wer eine neu gebaute
Einzeldatei derselben Version testet, misst sonst den alten Stand. Vorher:

```bash
./dist/komki-<version>-macos-arm64-einzeldatei maintenance uninstall
```

oder `KOMKI_INSTALL_DIR` auf ein frisches Verzeichnis setzen. Bauen mit
`MIX_ENV=prod`, denn nur prod-Builds nutzen den entpackten Inhalt wieder.

### Smoke-Matrix (Stand Pilot #75)

| # | Schritt | grün wenn |
|---|---|---|
| 1 | `setup --demo` in einer Wegwerf-Instanz | `doctor ok`, exit 0 |
| 2 | `run "Antworte mit exakt einem Wort: ok"` | Modellantwort „ok“, exit 0 |
| 3 | `run --help` | eigene Usage, exit 0, kein pi-Lauf |
| 4 | `journal verify` | `Journal ok`, exit 0 |
| 5 | `down` | Prozesse weg, Ports frei, exit 0 |

Dazu zwei Störproben mit grüner Wiederherstellung: Profil-Drift → `doctor`
exit 3, absurd großer Kontext → `up` exit 4.

Vorbereitet sind: `make komki-formel` (Formel mit Release-Adresse) und die
Vorlage `packaging/homebrew/komki.rb.in`. Noch nicht gebaut ist eine
Automatisierung der Kette bis zur Evidenz (`mix komki.release`).

## Quellen

- Pilot-Bericht:
  [docs/research/2026-10-11-komki-burrito-pilot.md](research/2026-10-11-komki-burrito-pilot.md)
  (Ticket #75)
- Tickets: croesnick/kommunalpolitik_ki #75, #79, #180, #181, #241, #538
- ADR: [docs/adr/0001](adr/0001-ad-hoc-signierung-statt-developer-id.md),
  [docs/adr/0005](adr/0005-versionierung-mit-changesets-und-knope.md)
- Begriffe: [GLOSSARY.md](../GLOSSARY.md), Bau aus dem Checkout,
  Wegwerf-Instanz, Release, Changeset, Version-PR
- knope 0.24.0: Tag-Schema `{name}/v{version}`, Release ohne Forge nur als
  Git-Tag, 0.x-Lesart `0.<major>.<minor>` (Doku und Quellcode unter
  github.com/knope-dev/knope, abgerufen 2026-11-13).
- Draft-Mechanik („Draft legt kein Tag an“): gh-CLI-Handbuch
  (cli.github.com/manual/gh_release_create), cli/cli#11589 und
  GitHub-REST-Doku (docs.github.com/en/rest/releases/releases), abgerufen
  2026-10-13.
- Runner-Preise: GitHub-Billing-Doku
  (docs.github.com/en/billing/reference/actions-minute-multipliers),
  abgerufen 2026-10-13.
