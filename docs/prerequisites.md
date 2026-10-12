# Externe Abhängigkeiten

> **Zweck:** Dieses Dokument listet alle externen (nicht ins Repo geclonten)
> Abhängigkeiten, die für bestimmte Skills oder Workflows Voraussetzung sind.
> Es ist die **Single Source of Truth für Voraussetzungen**: Skills referenzieren
> dieses Dokument, statt die Installationsanleitungen zu duplizieren.
>
> **Prinzip:** Jeder Skill, der eine externe Abhängigkeit hat, muss sie hier
> eintragen. Bei Änderungen an Abhängigkeiten wird zuerst dieses Dokument
> aktualisiert, analog zu den kanonischen Workflow-Dokumenten.

---

## `obsidian` CLI

**Zweck:** Vault-Read (`search`, `read`) und Vault-Write (`create`, `append`,
`eval`). Obsidian-App muss laufen.

**Install:**

```bash
brew install obsidian-cli
# oder via Obsidian Community Plugin (siehe https://help.obsidian.md/cli)
```

**Konfiguration:** Vault-Name in `config.local.yml` (nicht-getrackt, Repo-Root):

```yaml
obsidian:
  vault: "MeinVaultName"
```

**Benötigt von:**

| Skill / Workflow | Read | Write | Anmerkung |
|---|---|---|---|
| `vault_suche` | ✅ | — | Read-only, kein Vault-Write |
| `sitzungsvorbereitung` | ✅ | ✅ | Sitzungsmappe im Vault erstellen |
| `ratsprojekt_proposal` | ✅ | ✅ | Konsolidierte Notiz in Vault schreiben |
| `foerdermittel_recherche` | — | ✅ | Report an Vault-Notiz anhängen (WF 6, #36) |
| Bürgeranliegen (geplant, WF 8) | ✅ | ✅ | Anliegen im Vault erfassen |

**Fallback (wenn `obsidian` CLI nicht verfügbar):**

Skills, die Vault-Write benötigen, degradieren gracefully: sie emitieren die
Notiz als Markdown-Artifact im Verzeichnis `artifacts/vault-staging/`. Die
nutzende Person kopiert die Datei manuell in den Vault.

**Bekannte Limitierungen:**

- `obsidian create` legt keine Parent-Folder automatisch an. Vorab `fs.mkdirSync(dir, {recursive: true})` via `obsidian eval` aufrufen. Siehe Issue #43.
- `obsidian read path="..."` ist unzuverlässig bei Pfaden aus `search`-Ergebnissen. Stattdessen `read file="<name>"` (Wikilink-Auflösung) verwenden.
- `obsidian create path="..." content="..."` ist für kurze Inhalte mit `\n`-Escapes gedacht. Für lange Inhalte (z.B. Sitzungsmappen): `obsidian eval` mit `fs.readFileSync` + `app.vault.create` verwenden.

**Skill-Referenz:** `~/.agents/skills/obsidian-cli/SKILL.md` (global installiert,
nicht im Repo). Dokumentiert alle CLI-Befehle und Syntax.

---

## `nextcloud-mcp-server` (Nextcloud-Kollaborationsplattform)

**Zweck:** Eine eigene Nextcloud-Instanz als Kollaborationsplattform an
OpenCode anbinden. Liefert MCP-Tools für Files/WebDAV (lesen, schreiben,
listen, suchen), Calendar (CalDAV), Contacts, Notes, Deck, Tables, Talk,
Collectives, Cookbook, Mail. 110+ Tools insgesamt.

**Repo:** https://github.com/cbcoutinho/nextcloud-mcp-server (AGPL-3.0-only).

### Lizenz-Einordnung

Der Server läuft als **Subprocess via `uvx`**: kein Linking, keine
Modifikation, keine Verteilung. AGPL-Copyleft berührt den eigenen Code nicht.
PyMuPDF (AGPL-3.0, kommerziell Artifex) ist transitive Dependency, wird aber
nur bei aktiviertem Document-Processing-Pfad (`ENABLE_DOCUMENT_PROCESSING=true`,
Default `false`) ausgeführt.

### Installation

Keine persistente Installation nötig: `uvx` holt das Paket von PyPI und baut
einen ephemeren venv. Voraussetzung: `uv` installiert (bereits für
`tools/allgaeuer_zeitung_mcp` und `tools/pdf_ingest` erforderlich).

Cold-Start beim ersten Aufruf: 10–30s. Abhilfe: `uvx nextcloud-mcp-server --help`
einmalig laufen lassen, um den Cache zu füllen.

### Konfiguration

Umgebungsvariablen (lokal setzen, z.B. in `~/.zshrc`; **nicht ins Repo
committen!**):

```bash
export NEXTCLOUD_HOST="https://cloud.example.org"
export NEXTCLOUD_USERNAME="stadtrat"
export NEXTCLOUD_PASSWORD="<app-password>"  # App-Password, nicht Login-Passwort
```

`opencode.json` nutzt `${VAR}`-Platzhalter, die aus der lokalen Umgebung
aufgelöst werden:

```json
{
  "mcp": {
    "nextcloud": {
      "type": "local",
      "command": [
        "uvx", "nextcloud-mcp-server",
        "run", "--transport", "stdio"
      ],
      "environment": {
        "NEXTCLOUD_HOST": "${NEXTCLOUD_HOST}",
        "NEXTCLOUD_USERNAME": "${NEXTCLOUD_USERNAME}",
        "NEXTCLOUD_PASSWORD": "${NEXTCLOUD_PASSWORD}",
        "MCP_DEPLOYMENT_MODE": "single_user_basic"
      }
    }
  }
}
```

### Auth: App-Password statt Login-Passwort

Nextcloud blockt Basic-Auth mit dem regulären Login-Passwort meist ab, sobald
2FA aktiv ist. App-Password generieren unter **Settings → Security → Devices &
sessions**.

Login Flow v2 (OAuth-Alternative) ist für Multi-User/Hosted-Setups gedacht,
nicht für den Subprocess-Use-Case: der bräuchte Token-Storage-DB, Fernet-Key,
öffentliche URL und OIDC-Client. Overengineering für diese Einbindung.

### Wichtigste Tools (Auswahl)

| Tool | Scope | Operation |
|---|---|---|
| `nc_webdav_list_directory` | `files.read` | Dateien in Verzeichnis listen |
| `nc_webdav_read_file` | `files.read` | Datei lesen (Base64 für Binär, Text für UTF-8) |
| `nc_webdav_write_file` | `files.write` | Datei schreiben (z.B. Sitzungsmappe hochladen) |
| `nc_webdav_search_files` | `files.read` | WebDAV-Suche (Name, MIME, Favoriten) |
| `nc_calendar_list_events` | `calendar.read` | Kalender-Termine auflisten |
| `nc_calendar_get_upcoming_events` | `calendar.read` | Kommende Termine |
| `nc_calendar_create_event` | `calendar.write` | Termin anlegen |

### Fallstricke

- **Self-Signed-Cert:** Default ist `NEXTCLOUD_VERIFY_SSL=true`. Bei
  Self-Signed bricht die Verbindung. Besser `NEXTCLOUD_CA_BUNDLE=/pfad/ca.pem`
  setzen als `NEXTCLOUD_VERIFY_SSL=false`.
- **`ENABLE_DOCUMENT_PROCESSING=false` (Default):** Wer PDF-Inhalte via
  `nc_webdav_read_file` semantisch verarbeiten will, muss den Schalter
  explizit setzen, sonst kommt base64 zurück.
- **Nextcloud-Apps müssen aktiviert sein:** Calendar/Notes/Deck/etc.
  funktionieren nur, wenn die jeweilige App in der Nextcloud-Instanz aktiv
  ist. Vor Aktivierung des MCP-Eintrags prüfen, welche Apps aktiv sind.
- **Tag-basiertes File-Exclusion:** Sensible Vault-Dateien lassen sich über
  `EXCLUDED_TAGS`-Systemtag vor den MCP-Tools verstecken. Relevant für den
  Vault-Workflow, weil der AI-Harness sonst private Notizinhalte lesen
  könnte.
- **Version-Pinning möglich:** Das Projekt ist sehr aktiv. Für Stabilität kann
  `uvx --from 'nextcloud-mcp-server==<version>'` verwendet werden.

**Benötigt von:**

| Skill / Workflow | Read | Write | Anmerkung |
|---|---|---|---|
| WF 9 (Nextcloud) | ✅ | ✅ | Dateien, Kalender, Tabellen, ODS via `nextcloud_ods_mcp` |
| `ratsprojekt_delta` | ✅ | — | Nextcloud-Kondensat gegen ratsprojekte halten |
| `sitzungsvorbereitung` | ✅ | ✅ | Ggf. Sitzungsmappe direkt in Nextcloud hochladen |

**Quellen:** [README](https://github.com/cbcoutinho/nextcloud-mcp-server/blob/master/README.md),
[authentication.md](https://github.com/cbcoutinho/nextcloud-mcp-server/blob/master/docs/authentication.md),
[configuration.md](https://github.com/cbcoutinho/nextcloud-mcp-server/blob/master/docs/configuration.md),
[env.sample.single-user](https://github.com/cbcoutinho/nextcloud-mcp-server/blob/master/env.sample.single-user).

---

## `nextcloud_ods_mcp` (ODS-Reader, lokal im Repo)

**Zweck:** ODS-Dateien (OpenDocument Spreadsheet) strukturiert lesen: Sheets
auflisten, Ranges/Zellen lesen, suchen. Orthogonal zum Nextcloud-Server: nimmt
einen **lokalen Dateipfad**, gibt strukturierte Daten zurück. Keine Kenntnis
von Nextcloud-URLs oder Auth.

**Repo-intern:** `tools/nextcloud_ods_mcp/` (MIT, odfpy Apache-2.0).

### Setup

```bash
cd tools/nextcloud_ods_mcp
uv sync
```

### Tools

| Tool | Beschreibung |
|---|---|
| `list_sheets(path)` | Sheet-Namen einer ODS-Datei auflisten |
| `read_sheet(path, sheet_name, range?)` | Sheet als 2D-Liste, optional A1-Range (z.B. `A1:C10`) |
| `read_cell(path, sheet_name, cell)` | Einzelne Zelle (z.B. `B7`) |
| `search_sheet(path, sheet_name, query)` | Lineare Suche, case-insensitive, liefert `CellMatch[]` |

### opencode.json

```json
{
  "mcp": {
    "nextcloud_ods_mcp": {
      "type": "local",
      "command": [
        "uv", "run", "--directory", "tools/nextcloud_ods_mcp",
        "python", "-m", "nextcloud_ods_mcp"
      ]
    }
  }
}
```

### Lizenz-Einordnung

`odfpy` (Apache-2.0) ist kompatibel mit dem Repo (MIT). Keine AGPL-Abhängigkeit:
dieses Tool ist vollständig MIT-kompatibel und hat keine transitive AGPL-Last.

**Benötigt von:**

| Skill / Workflow | Anmerkung |
|---|---|
| WF 9 (Nextcloud) | ODS-Dateien aus Nextcloud lokal lesen (nach Download via Nextcloud-MCP) |
| `ratsprojekt_delta` | Projekt-Kondensat aus ODS-Sheet einlesen |

---

## Pre-commit-Hooks (gitleaks)

**Zweck:** Pre-Commit-Secret-Scan. Blockiert jeden `git commit`, der
versehentlich Credentials, API-Keys, Private Keys, Tokens oder Passwörter
enthalten würde, **bevor** sie ins Git-History gelangen. Sicherheitsnetz für
alle Entwickler:innen am Repo.

**Lizenz-Einordnung:** gitleaks (MIT) ist kompatibel mit dem Repo. pre-commit
(MIT) ebenso.

### Installation

```bash
brew install gitleaks          # Secret-Scanner
brew install pre-commit         # Hook-Runner (optional: pip install pre-commit)
pre-commit install             # aktiviert den pre-commit-Hook im lokalen .git/hooks/
```

Danach läuft der Hook automatisch bei jedem `git commit`. Ohne aktiven Hook
werden Secrets nicht abgefangen. Die lokale Installation ist also Pflicht für
jede:n Entwickler:in am Repo.

### Konfigurationsdateien (im Repo versioniert)

| Datei | Zweck |
|---|---|
| `.pre-commit-config.yaml` | Hook-Definition: gitleaks `gitleaks-system` (nutzt die lokal installierte Binary) |
| `.gitleaks.toml` | Projektspezifische Rules + Allowlist |

Die `.gitleaks.toml` blendet das gitleaks-Default-Ruleset (~850 Patterns:
AWS, GitHub, GitLab, Slack, OpenAI, Anthropic, Private Keys, JWT, DB-URLs)
via `useDefault = true` ein und ergänzt projektspezifische Patterns:

- `RIS_PASSWORD` (Ratsinfo-System)
- `AZ_PASSWORD` (Allgäuer Zeitung)
- `NEXTCLOUD_PASSWORD`
- `GRIBS_PASSWORD`

Die Allowlist erlaubt explizit `.env.example`/`.env.template`/`.env.dist` und
leere Platzhalter (z.B. `RIS_PASSWORD=` ohne Wert). Platzhalter-Dateien
werden also nicht fälschlich blockiert.

### Manuelles Prüfen

```bash
# Ganzer Repo-Stand (unabhängig von git staging):
pre-commit run --all-files

# Nur gestagte Änderungen (wie beim Commit):
pre-commit run

# gitleaks direkt über eine Datei oder Range:
gitleaks detect --source . --no-git -v
```

### Im Notfall umgehen

```bash
git commit --no-verify -m "..."
```

Nur in begründeten Ausnahmefällen verwenden (z.B. Known-False-Positive ohne
Zeit zur Config-Anpassung). Der Bypass hinterlässt keine Spur. Idealerweise
im Nachhinein die `.gitleaks.toml`-Allowlist pflegen, damit es beim nächsten
Commit nicht wieder knallt.

### Bekannte Limitierungen

- **Nur Pre-Commit, nicht Pre-Push:** Secrets, die via `git commit --no-verify`
  umgangen wurden, werden auch nicht vor dem Push abgefangen. Wer den Hook
  umgeht, trägt die Verantwortung selbst.
- **Kein Push-Schutz auf Remote-Seite:** GitHub selbst hat keinen
  Secret-Scanner aktiv (privates Repo ohne GitHub Advanced Security). Der
  Pre-Commit-Hook ist die einzige Verteidigungslinie.
- **Keine Erkennung von bereits committeden Secrets:** Der Hook scannt nur
  neue/geänderte Zeilen im Staging. Historische Secrets müssen via
  `gitleaks detect --source . -v` manuell suchen (siehe Security-Scan).
- **False Positives:** Dokumentations-Strings, die Secret-Patterns erwähnen
  (z.B. dieser Absatz hier), können gemeldet werden. Solche Fälle in die
  `.gitleaks.toml`-Allowlist aufnehmen, nicht mit `--no-verify` umgehen.

**Benötigt von:**

| Skill / Workflow | Anmerkung |
|---|---|
| Alle Commits | Hook läuft automatisch vor jedem Commit |

---

## `lychee` CLI (Markdown-Link-Check)

**Zweck:** Offline-Link-Check für Markdown-Dateien: verifiziert lokale
Dateireferenzen (relative Pfade, Bilder, Repo-Dateien) ohne Netz-Requests.
Config: [`lychee.toml`](../lychee.toml) am Repo-Root.

**Install:**

```bash
brew install lychee
```

**Benötigt von:**

| Skill / Workflow | Anmerkung |
|---|---|
| `docs-links`-Check aus der AGENTS.md-CI-Kurzfassung | Lokales Vorab-Prüfen vor dem Push (`lychee './**/*.md'`) |
| Pre-commit-Hook `lychee-markdown-links` | Läuft vor jedem Commit automatisch über die gestagten Markdown-Dateien |

CI (`.github/workflows/docs-links.yml`) nutzt die lychee-Action mit eigener
Binary; der CLI ist nur für lokale Läufe nötig.

**Fallback (wenn `lychee` CLI nicht verfügbar):**

Kein lokaler Check. Committen, pushen und den `docs-links`-Workflow laufen
lassen. Der Offline-Modus macht den Job deterministisch — Flakiness durch
externe URLs gibt es nicht.

---

## KomKI-CLI (`apps/komki_cli`)

**Zweck:** Lokal gesandboxte KI-Arbeitsfläche (`komki`): Seatbelt-Profil,
llama-server, pi-Session, tmux. Läuft nur unter macOS (Seatbelt). Details:
[`apps/komki_cli/README.md`](../apps/komki_cli/README.md).

**Install:**

```bash
brew install llama.cpp tmux      # Inferenz-Server (gepinnt 0.5.0), Session-Host
brew install fd ripgrep          # optional: pi's Such-Tools (aktiviert find/grep)
# node via asdf, Homebrew oder nvm; pi-Bundle global:
npm install -g @earendil-works/pi-coding-agent
```

**Modell:** Das gepinnte GGUF (Gemma 4 26B-A4B-it, unsloth UD-Q4_K_XL) wird
nicht heruntergeladen. `komki init` übernimmt es SHA-256-geprüft aus dem
Staging-Verzeichnis (`~/.local/share/komki/models-staging/`).

**Benötigt von:**

| Tool / Workflow | Anmerkung |
|---|---|
| `komki init/doctor/up/down/status/run/session` | `init` entdeckt node/pi/llama-server selbst und pinnt die aufgelösten Pfade in die config.json |

**Fallback:** Fehlt ein Pflicht-Werkzeug (node, pi-Bundle, llama-server),
verweigert `init` mit klarer Meldung. Fehlen fd/ripgrep, verzichtet pi auf
Dateisuche (Start-Warnung; `find`/`grep` bleiben weg).

---

## Hinzufügen einer neuen Abhängigkeit

1. Abhängigkeit in diesem Dokument eintragen (Zweck, Install, Konfiguration,
   benötigt von, Fallback).
2. Im betroffenen Skill eine `## Prerequisites`-Sektion ergänzen, die auf dieses
   Dokument verweist.
3. Bei Bedarf: `config.local.yml.example` um Einträge ergänzen.
4. Wenn die Abhängigkeit ein neues Secret-Pattern einführt (z.B. neue
   `FOO_PASSWORD`-Env-Var): Pattern in `.gitleaks.toml` ergänzen, damit der
   Pre-Commit-Hook es erkennt. Leere Platzhalter-Variante ggf. in die
   Allowlist aufnehmen.

---

## Renovate-PAT (self-hosted Dependency-Updates)

**Zweck:** `.github/workflows/renovate.yml` betreibt Renovate self-hosted
(renovatebot GitHub-Action, alle 6 Stunden). Authentifizierung gegen die
GitHub-API über einen Fine-grained Personal Access Token, der im
Actions-Secret `RENOVATE_TOKEN` liegt (Repo-Settings → Secrets and
variables → Actions).

**Erforderliche Rechte** (Fine-grained PAT, Repository Access nur auf
`croesnick/kommunalpolitik_ki`):

| Recht | Stufe | Wofür |
|---|---|---|
| Contents | Read and write | `renovate/*`-Branches pushen |
| Workflows | Read and write | Commits auf `.github/workflows/*` (Actions-Bumps); GitHub lehnt solche Pushes ohne dieses Recht ab |
| Pull requests | Read and write | Update-PRs erstellen und pflegen |
| Issues | Read and write | Dependency-Dashboard pflegen |
| Metadata | Read-only | Pflichtrecht, GitHub setzt es automatisch |
| Administration | Read-only, optional | Branch-Protection-Regeln lesen; ohne dieses Recht nur ein 403 im Log, nicht fatal |

**Fehlerbild:** Fehlt ein Schreibrecht, bricht der Workflow nicht ab. Der
Lauf ist grün, Renovate pusht Branches, aber PR-Erstellung und
Dashboard-Pflege schlagen still mit HTTP 403 fehl. Symptom: `renovate/*`-
Branches im Remote, nie ein PR. So geschehen vom 16.07. bis 07.09.2026:
„Pull requests“ und „Issues“ hatten nur Leserechte.

**Verifikation nach Setup oder Token-Änderung:**

```bash
gh workflow run Renovate --repo croesnick/kommunalpolitik_ki -f log_level=debug
# Lauf abwarten, dann im Log nach "statusCode=403" suchen
gh pr list --repo croesnick/kommunalpolitik_ki --state open
```

**Token pflegen:** GitHub → Settings → Developer settings → Personal access
tokens → Fine-grained tokens. Rechte am bestehenden Token ändern wirkt
sofort, das Secret bleibt unverändert. Bei einem neuen Token `RENOVATE_TOKEN`
im Secret aktualisieren.

**Quelle:** Empirisch verifiziert am 2026-09-07, Debug-Lauf 34079212967
(`git push` erfolgreich, `POST /pulls` und `PATCH /issues/49` mit 403
abgewiesen).

---

## Querverweise

- [`AGENTS.md`](../AGENTS.md) § „Externe Abhängigkeiten“, Tabellen-Referenz
- [`docs/workflows.md`](./workflows.md): Workflows mit Lücken, die externe
  Abhängigkeiten betreffen (WF 1, 2, 6, 8)
- [`docs/nomenklatur.md`](./nomenklatur.md): Vault-Begriff
