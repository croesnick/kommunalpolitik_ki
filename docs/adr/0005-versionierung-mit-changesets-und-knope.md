---
status: accepted
---

# Versionierung mit Changesets und knope

Wer komki oder ratsprojekte nutzt, soll sehen, welche Fassung läuft und was sich geändert hat. Bis November 2026 standen alle Apps auf `0.1.0`, ohne Tags und ohne Changelog. Entschieden in einer Grilling-Session am 13. und 14.11.2026, umgesetzt in #538.

**Fünf Einheiten** bekommen eine eigene Version und ein eigenes Changelog: `komki` als eine Version für das ganze Programm (samt Vermittler, Policy, Connectoren, Egress), `ratsprojekte`, und die drei Bibliotheken `sidecar`, `seatbelt` und `sealed_envelope` mit Blick auf hex.pm (#224 bis #226). Alle anderen Apps und die Python-Tools bleiben ohne Version.

**Jede spürbare Änderung bringt ein Changeset mit**, eine Markdown-Datei unter `.changeset/`. Ein Version-PR sammelt sie, erhöht die Versionen in den `mix.exs` und schreibt die Changelogs. Sein Merge durch einen Menschen setzt Git-Tags `<einheit>/v<semver>`. GitHub-Releases entstehen dabei nicht, veröffentlicht wird weiterhin erst nach dem Publish-GO ([release.md](../release.md)). Das Werkzeug ist **knope**, nur in CI. Regeln für Changesets: [docs/agents/changesets.md](../agents/changesets.md).

## Begründung

- **Changesets statt Commit-Konventionen.** Die Commit-Titel hier sind deutsche Prosa. Werkzeuge, die Versionen aus Conventional Commits ableiten, sehen darin nichts. Ein Changeset entsteht im selben PR wie die Änderung, und der Text ist für die Leser des Changelogs geschrieben, nicht für die Git-Historie.
- **knope statt des Werkzeugs Changesets (changesets.dev).** Changesets versioniert nur Pakete mit einer `package.json` („The only requirement is that the project has a `package.json` file“, changesets.dev/guide/beyond-npm). Wir bräuchten fünf Stub-Dateien, einen pnpm-Workspace über `apps/` und ein eigenes Skript, das die Version in die `mix.exs` überträgt. Seine Tags heißen fest `pkg@x.y.z`. knope liest dasselbe Format für Changesets, schreibt die Version per Regex direkt in die `mix.exs` und braucht kein Node.
- **Kein Knope Bot.** Die GitHub-App eines Drittanbieters verlangt Schreibrechte auf Contents, PRs, Checks und Issues und speichert Webhook-Inhalte. In einem Repo, dessen Kern eine Sicherheitsgrenze ist, bleibt der Check ein eigener kleiner CI-Schritt (`scripts/changesets.exs check`).
- **Kein Forge in knope.** Mit einem `[github]`-Eintrag legt knopes Release-Schritt immer GitHub-Releases an. Ohne Forge setzt er nur Git-Tags. Den Version-PR baut deshalb ein eigener Workflow mit `gh`.
- **Kaskade entlang der Pfad-Abhängigkeiten.** komki und ratsprojekte binden die Bibliotheken per `path:` ein, jeder Bau enthält also den Code von `main`. Ohne Kaskade bliebe eine erhöhte Bibliothek, etwa ein Sicherheitsfix in `seatbelt`, in keiner komki-Version sichtbar, solange niemand an ein komki-Changeset denkt. Deshalb bekommt jede einbindende Einheit ohne eigene Erhöhung automatisch einen Patch („Enthält seatbelt 0.1.1“). knope kennt keine Abhängigkeiten zwischen Paketen, die Kaskade ist ein eigenes Skript.
- **Tags erst nach dem Merge durch einen Menschen.** Der Version-PR ist der Moment, in dem jemand liest, was als nächste Version gilt. Sein Merge ist das GO (AGENTS.md §7). Der Dev-Loop fasst ihn nicht an.

### Verworfen

- **Changesets (changesets.dev):** siehe oben, `package.json` je Einheit und festes Tag-Schema.
- **release-please und git_ops:** beide setzen Conventional Commits voraus. git_ops ist das verbreitetste Elixir-Werkzeug dafür.
- **Changelog von Hand** (der übliche Weg in Elixir-Projekten wie Phoenix und Ecto): bei parallelen PRs Konflikte in jeder `CHANGELOG.md`, und niemand wird an einen Eintrag erinnert.
- **Ein eigener Mix-Task statt knope:** Auf hex.pm fand sich kein gepflegtes Werkzeug nach dem Vorbild von Changesets (Recherche 13.11.2026, nicht erschöpfend). Ein eigener Task wäre etwa 200 bis 300 Zeilen und ein Kandidat für die Community. Vorerst reicht knope. Wächst unser Rahmen um knope über dessen eigenen Anteil hinaus, wird es Zeit (#539).

## Folgen

- **Tag-Schema** `<einheit>/v<semver>` statt `<tool>-v<semver>`: knope gibt `{name}/v{version}` bei mehreren Paketen fest vor und erkennt daran, was schon getaggt ist. `docs/release.md`, `komki-release.yml` und das Makefile folgen dem neuen Schema.
- **`komki-release.yml`** startet nur noch von Hand mit einem vorhandenen Tag. Ein Tag allein startet keinen macOS-Bau mehr.
- **0.x-Lesart:** knope liest 0.x als `0.<major>.<minor>`. Brüche und große Neuerungen heißen in der 0.x-Phase `major` (0.1.0 → 0.2.0). `minor` und `patch` ergeben beide 0.1.1. Das ersetzt die frühere Regel aus `docs/release.md` („sichtbare Neuerungen oder Brüche → Minor“).
- **Pflicht-Checks am Version-PR:** Mit dem `GITHUB_TOKEN` gepushte Branches starten keine Workflows. Der Workflow `versionen` startet die CI deshalb per `workflow_dispatch` auf dem Branch `versionen`. Dafür braucht das Repo die Einstellung „Allow GitHub Actions to create and approve pull requests“.
- **Dev-Loop:** Die Umsetzung schreibt das Changeset oder begründet in `.dev-loop/ohne-changeset`, warum keins nötig ist. Das Skript setzt dann das Label `ohne-changeset`. Den Version-PR auf dem Branch `versionen` fasst der Loop nicht an.
- **Neuer Prüfpunkt** „Einheiten mit Version“ in [pruefpunkte.md](../agents/pruefpunkte.md).
- **Sprache der Changelogs:** komki und ratsprojekte auf Deutsch für Nutzende, mit deutschen Abschnitten. Die Bibliotheken auf Englisch für Entwickler.
- **Veröffentlichen bleibt aus.** Versionen und Tags sind kein Release. Eine Seite „Neuerungen“ auf der Doku-Site kommt mit dem ersten Release.
