# Kommunalpolitik KI

CLI-Tools und MCP-Server für die Stadtratsarbeit: RIS durchsuchen, PDFs ingesten, Fördermittel recherchieren, Lokalzeitung scrapen. Ein AI-Harness für Ratsarbeit mit Quellenbindung — läuft lokal, die KI berät, der Mensch entscheidet.

## Projekt-Verwaltung

Tickets, Ideen und Meilensteine sind GitHub Issues in `croesnick/kommunalpolitik_ki`; das private GitHub-Projects-Board „Kommunalpolitik KI“ ist eine Sicht auf dieselben Issues, kein zweites System. Bot-Issues wie die Renovate Dependency Dashboard landen nicht auf dem Board.

- Angefangenes Ticket von Hand auf `In Progress` setzen (`Done` setzt der Board-Workflow beim Schließen):
  `gh project item-edit 1 --owner croesnick --url <issue-url> --field Status --value "In Progress"`
- Bleibt ein neues Issue vom Auto-Add-Workflow hängen, nachholen:
  `gh project item-add 1 --owner croesnick --url <issue-url>`
- Ein PR schließt sein Ticket nur über `Closes #<n>` im PR-Text; `(Ticket #<n>)` im Titel oder in Commits genügt nicht. Nur teilweise erledigt: `Refs #<n>` mit einem Satz, warum.
- Neue Erkenntnisse und geänderte Anforderungen gehören ins Ticket oder in ein Folgeticket, nie still am Ticket vorbei eingebaut.
- Vor Edits an Dateien mit unstaged Änderungen aus einer Parallel-Session (anderes Worktree, anderes Terminal): `git status` und `git diff <datei>` der Zieldatei prüfen, kollidierende Bereiche meiden.

## Agent skills

Wie das Repo arbeitet, steht in Prozess-Dokumenten unter `docs/agents/`. Gelesen wird das Dokument, das zum Fall passt:

- **Tickets und Specs** (GitHub Issues via `gh`): [issue-tracker.md](docs/agents/issue-tracker.md)
- **Ticket umsetzen** (Abnahmekriterien im Ticket statt im Dispatch-Prompt; Verifikation und Prüfbericht durch eine Session, die nicht gebaut hat): [lane-protocol.md](docs/agents/lane-protocol.md); Prüfpunkte je Bereich: [pruefpunkte.md](docs/agents/pruefpunkte.md)
- **Interaktive Session** (`.claude/settings.json` sperrt Hub, Vault und Schlüssel für Read-Tool und Bash-Sandbox; Stop-Hook endet erst bei grünen Gates; `gh pr create` braucht einen Prüfbericht): [interaktive-sessions.md](docs/agents/interaktive-sessions.md)
- **Changesets** (ein PR, der komki, ratsprojekte, sidecar, seatbelt oder sealed_envelope für Nutzende ändert, bringt ein Changeset unter `.changeset/` mit): [changesets.md](docs/agents/changesets.md)
- **Triage** (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`): [triage-labels.md](docs/agents/triage-labels.md)
- **AI-Stufen** (`ai:s-tier`, `ai:a-tier`, `ai:b-tier`: Grenze und Urteil, Feature mit Vertrag, Handwerk; berührt eine A- oder B-Aufgabe einen geschützten Pfad, hält die Session an und eskaliert): [ai-tiers.md](docs/agents/ai-tiers.md)
- **Dev-Loop** (unbeaufsichtigte Ticketarbeit über `scripts/dev_loop.exs`): [dev-loop.md](docs/agents/dev-loop.md)
- **Domain** (GLOSSARY.md am Repo-Root, ADRs unter `docs/adr/`): [domain.md](docs/agents/domain.md)

## Architektur-Prinzipien

### 1. Elixir-first

Tools werden in Elixir gebaut. Fehlt eine Bibliothek, wird sie selbst gebaut und als eigenständiges Paket an die Elixir-Community zurückgegeben (so entstanden `apps/sidecar`, `apps/seatbelt`). Eine fertige Bibliothek in einer anderen Sprache (etwa `PyMuPDF`, `trafilatura`, `Playwright`) rechtfertigt keine Abweichung. Nativer Code ist keine Abweichung (NIF über Rustler oder vorkompiliertes Hex-Paket), hat aber eine Elixir-Schnittstelle. Abweichungen nur als Vorschlag im Ticket, gebaut wird erst nach dem GO (§7). Für Connectoren regelt das [ADR 0002](docs/adr/0002-connectoren-nur-in-elixir.md). Die Python-Tools unter `tools/` bleiben als Werkzeuge außerhalb von komki bestehen.

### 2. Unix-Prinzip

Ein Tool pro Aufgabe; Pipes und Verzeichnisübergabe sind die Schnittstellen, kein Tool kennt die Interna eines anderen (`ratsinfo` lädt PDFs herunter, `pdf_ingest` verarbeitet sie und weiß nichts vom RIS).

### 3. MVP vor Infrastruktur

Erst der einfache Fall (`sync/search/show/open`), dann RAG/OCR/UI. Lehrstück `riski` (München): professioneller Stack, für den persönlichen Use Case zu schwer. Referenzarchitektur, nicht Codebasis. Der MVP muss beweisen, dass ein Stadtrat vor einer Sitzung schnell etwas findet.

### 4. Problem-first, nicht tool-first

Neue Tools entstehen aus konkreten Bedarfen der Ratsarbeit, nicht aus Technik-Faszination.

### 5. AI-Enabled

Jedes Tool bringt eine AI-Schnittstelle mit, von Anfang an mitgedacht: CLI, MCP-Server oder Agent Skill in `skills/`. Ein Tool ohne AI-Schnittstelle gehört nicht in dieses Repo.

## Politische & ethische Guardrails

### 6. Quellenpflicht (nicht optional)

Jede politisch relevante Aussage aus einem Tool trägt eine Quelle: URL, Abrufdatum, ggf. Paragraf. Quellen werden vor der Verwendung geprüft: Links auflösen und nachsehen, dass die Seite zeigt, wofür sie zitiert wird (HTTP-200 allein genügt nicht), Fundstelle nachschlagen, Zitate gegen den Wortlaut halten; URL, Kennung und Abrufdatum stammen aus dem tatsächlichen Abruf. Was sich nicht prüfen lässt, wird als „nicht verifiziert“ gekennzeichnet.

### 7. GO-Prinzip: KI berät, Mensch entscheidet

Keine Triage-Änderung, kein Vault-Eintrag, kein Task-Update ohne explizites GO. GO im Chat zählt; entscheidend ist der Mensch, nicht der Kanal. Ausnahme: die Pflege des GitHub-Boards in Dev-Sessions (Tickets anlegen, kommentieren, Status setzen). Für Entscheidungen im ratsprojekte-Hub reicht ein GO im Chat nicht: Die KI schlägt über den Connector-Schreibweg vor, der Mensch entscheidet im Hub ([ADR 0004](docs/adr/0004-ratsprojekte-als-lokaler-hub.md)). Tools sind read-only by design, wo immer möglich; demokratische Verantwortung bleibt beim Menschen.

### 8. Datenschutz-Grenze

Nur Zugriff auf das, was als Stadtrat bzw. öffentlich regulär abrufbar ist. Nicht-öffentliche Unterlagen bleiben lokal und kontrolliert. Keine Schreibzugriffe ins RIS. Keine öffentliche Bereitstellung ohne Prüfung.

### 9. Politisches Framing

Technische Tools nach außen als „strukturierte öffentliche Ratsinformationen“, „digitale Arbeitsfähigkeit“ oder „Transparenz“ framen, nicht als „AI-Zugriff“ oder „ich will RAG bauen“.

### 10. Vault für Material, Hub für den Stand

Der Vault ist das Gedächtnis: roh, unstrukturiert, alles. Der Hub ist der Stand: welche Projekte es gibt, in welcher Phase, was entschieden ist. Beide sind je Quelle für eine eigene Art von Wahrheit ([ADR 0004](docs/adr/0004-ratsprojekte-als-lokaler-hub.md)). Menschen schreiben direkt in den Hub; eine Idee darf dort ohne Vault-Notiz entstehen. Die KI schlägt nur vor: aus einem komki-Raum über den Connector, nach GO (§7); Material aus dem Vault erreicht den Hub nur auf diesem Weg oder von Hand. Kein Rückfluss: Der Hub schreibt nie in den Vault und nie ins RIS.

### 11. Projektlebenszyklus (kanonisch)

Single Source of Truth für Statuswerte, Übergänge und Gates ist [docs/ratsprojekte-lifecycle.md](docs/ratsprojekte-lifecycle.md) (Mermaid-Chart). Grenzen zu komki: [docs/schnittstellen/stand.md](docs/schnittstellen/stand.md) (Lesen), [docs/schnittstellen/connector-socket.md](docs/schnittstellen/connector-socket.md) (Schreiben). Pflicht: Lifecycle-Änderungen zuerst ins Dokument, bevor Code oder Skills angefasst werden.

### Slug-Konvention

Der Slug ist der stabile Vertrag zwischen ratsprojekte und Vault: `/projekte/{slug}` im Hub, `#ratsprojekt/{slug}` als Vault-Tag. Kebab-case, lowercase, ASCII (`^[a-z0-9]+(?:-[a-z0-9]+)*$`, Umlaute als ae/oe/ue/ss). Projektbezogene Schnittstellen nehmen `slug`, nie die DB-ID; intern bleiben IDs Primärschlüssel, die Auflösung passiert an der Grenze.

## Kanonische Dokumentation

Bei Änderungen zuerst das jeweilige Dokument pflegen, dann Code oder Skills:

| Dokument | Single Source of Truth für |
|---|---|
| [docs/ratsprojekte-lifecycle.md](docs/ratsprojekte-lifecycle.md) | Projektlebenszyklus: Statuswerte, Übergänge, Gates |
| [docs/workflows.md](docs/workflows.md) | Use Cases & Lückenanalyse der Ratsarbeit |
| [GLOSSARY.md](GLOSSARY.md) | kanonische Nomenklatur des Repos |
| [docs/prerequisites.md](docs/prerequisites.md) | externe Abhängigkeiten (nicht im Repo) |
| [docs/release.md](docs/release.md) | Bau aus dem Checkout, Release-Kette |

### Doku-Site aktuell halten

[docs/site/](docs/site/) (Astro Starlight, GitHub Pages) ist der Benutzer-Guide zu komki. Pflicht: Ein PR, der ändert, was Nutzende von komki sehen oder tun (Befehle, Optionen, Ausgaben, Einrichtung, Sicherheitsgrenze), passt die betroffenen Seiten im selben PR an. Terminal-Ausgaben dort stammen aus echten Läufen, nie nachgebaut. Gestaltungsregeln: [docs/site/README.md](docs/site/README.md).

## Γ-Datenorte (RFC 0003)

- **Datenvertrag:** [apps/komki_policy/CONTRACT.md](apps/komki_policy/CONTRACT.md). Die Γ-Konsumformate (`komki-registry/2`, Snapshot, Intent, Decision, Proof) gehören zur Engine, weil `KomkiPolicy.Registry.compile/1` die Formate durchsetzt; Änderungen nur durch den Integrator.
- **Quelle eines Γ:** der Label-Store. Vorlage des Arbeitsraums ist `KomkiMediator.Templates.label_store_seed/0`; `komki up` importiert sie und schreibt `<base>/mediator/registry.json` als Export; `registry.json` nie von Hand pflegen. Importformat `komki-label-store/2`: Moduledoc in [apps/komki_cli/lib/komki_cli/label_store.ex](apps/komki_cli/lib/komki_cli/label_store.ex), Beispiel in [apps/komki_cli/priv/fixtures/registry-seed.json](apps/komki_cli/priv/fixtures/registry-seed.json).
- **Normative Basis:** [docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md](docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md), ≈ 2 400 Zeilen; Abschnitte per Anker-Grep (`R.N.M`, `B.N`) und gerangelte Reads statt Volltext.
- Import und Export validieren immer über `KomkiPolicy.Registry.compile/1`; die Engine ist die Schemainstanz: kein Tool schreibt eigene Schema-Checks für engine-seitige Datenformate.

## Sprachregelung

Etablierte englische Fachbegriffe bleiben englisch — nicht eingedeutscht, nicht durch deutsche Komposita ersetzt (remedy plan, field provenance, taint tracking). Deutsch, wo kein etablierter englischer Begriff existiert oder ein deutscher etabliert ist (Nichtinterferenz, Sitzungsmappe). Neue Begriffe werden bei ihrer ersten Verwendung definiert. Kommentare und Docstrings zu Code mit englischen Bezeichnern sind englisch; Prompts, Fixtures und Meldungen an Nutzende bleiben deutsch.

## Lizenz-Bewusstsein

Abhängigkeiten auf Lizenzkompatibilität prüfen (`PyMuPDF` ist AGPL-3.0; Alternativen `pdfplumber` MIT, `pdf.js` Apache-2.0) und pro Tool in der Tool-Doku festhalten.

## Tooling-Vorgaben

Beschreibungen der Apps stehen als `description:` im jeweiligen `mix.exs`, die der Python-Tools im `pyproject.toml`; neue Apps und Tools tragen sie dort ein.

### Elixir

Achtung: `mix credo` und `mix dialyzer` sind App-Tasks — am Repo-Root existieren sie nicht. Root-Aufrufe gehen über den Workspace-Dispatch:

```bash
mix deps.get && mix workspace.run -t deps.get
mix format --check-formatted                              # Root, deckt alle Apps ab
mix workspace.run -t compile -- --warnings-as-errors
mix workspace.run -t credo -- --strict                    # App-lokal: cd apps/<app> && mix credo --strict
mix workspace.run -t test --affected --base origin/main   # im PR; lokal ohne --base
cd apps/<app> && mix dialyzer                             # Root-Dispatch crasht (dialyxir im Workspace-Pattern)
```

### Python

Pro Tool unter `tools/`: `uv sync`, `uv run ruff check`, `uv run ruff format --check`, `uv run mypy src/`, `uv run pytest`. Lose Python-Skripte in `skills/*/scripts` (Config: `ruff.toml` am Root): `uvx ruff@0.15.21 check skills/*/scripts` und `uvx ruff@0.15.21 format --check skills/*/scripts`.

### Lean

Die Lean-Spezifikation unter `apps/komki_policy/lean/` beweist `derive` (normaler Zweig) und `verify` für `admit`, `emit`, `store` und `transfer` und gleicht beide per Differenztest ab. Sie ist ein Prüforakel, kein Tool im Sinne von § 1 (GO in #625). Ändert ein PR ein Modul, das `apps/komki_policy/lean/SYNC.sha256` pinnt, zieht er das Lean-Modell nach: [README](apps/komki_policy/lean/README.md).

### Versionen

`.tool-versions` am Root pinnt Python, Erlang und Elixir; asdf und uv lesen die Datei direkt, die CI parst sie (`setup-python`, `setup-beam` mit `version-file`). Erlang/Elixir folgen Homebrews aktuellem `erlang`, weil die komki-Formel davon abhängt (`packaging/homebrew/`).

### Debugging (Phoenix-Apps mit Tidewave)

Lokal laufende Phoenix-Apps mit Tidewave (wie ratsprojekte) werden über den Tidewave-MCP-Endpoint gedebuggt (`http://localhost:4000/tidewave/mcp`, Plug in `endpoint.ex`, nur `:dev`): Evaluator ausführen, Logs und Module inspizieren.

### CI

Maßgeblich sind die Workflows unter [.github/workflows/](.github/workflows/); dort stehen die exakten Befehle samt Begründungen. Kurzfassung: die Elixir- und Python-Blöcke oben, dazu Markdown-Links offline prüfen mit `lychee './**/*.md'` (Config: `lychee.toml`) und `elixir scripts/changesets.exs check origin/main` für Changesets.

Nach einem Push zuerst mit `gh run list --branch <branch> --limit 1` abgleichen, dass der Lauf zur eigenen Head-Short-SHA gehört — `gh pr checks --watch` zeigt unmittelbar nach einem Push sonst die Ergebnisse des vorherigen Heads als „pass“.
