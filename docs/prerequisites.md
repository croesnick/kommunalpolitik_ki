# Externe Abhängigkeiten

> **Zweck:** Dieses Dokument listet alle externen (nicht ins Repo geclonten)
> Abhängigkeiten, die für bestimmte Skills oder Workflows Voraussetzung sind.
> Es ist die **Single Source of Truth für Voraussetzungen** — Skills referenzieren
> dieses Dokument, statt die Installationsanleitungen zu duplizieren.
>
> **Prinzip:** Jeder Skill, der eine externe Abhängigkeit hat, muss sie hier
> eintragen. Bei Änderungen an Abhängigkeiten wird zuerst dieses Dokument
> aktualisiert — analog zu den kanonischen Workflow-Dokumenten.

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

- `obsidian create` legt keine Parent-Folder automatisch an — `fs.mkdirSync(dir, {recursive: true})` via `obsidian eval` vorab aufrufen. Siehe Issue #43.
- `obsidian read path="..."` ist unzuverlässig bei Pfaden aus `search`-Ergebnissen — `read file="<name>"` (Wikilink-Auflösung) stattdessen verwenden.
- `obsidian create path="..." content="..."` ist für kurze Inhalte mit `\n`-Escapes gedacht. Für lange Inhalte (z.B. Sitzungsmappen): `obsidian eval` mit `fs.readFileSync` + `app.vault.create` verwenden.

**Skill-Referenz:** `~/.agents/skills/obsidian-cli/SKILL.md` (global installiert,
nicht im Repo). Dokumentiert alle CLI-Befehle und Syntax.

---

## Pre-commit-Hooks (gitleaks)

**Zweck:** Pre-Commit-Secret-Scan. Blockiert jeden `git commit`, der
versehentlich Credentials, API-Keys, Private Keys, Tokens oder Passwörter
enthalten würde — **bevor** sie ins Git-History gelangen. Sicherheitsnetz für
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
werden Secrets nicht abgefangen — die lokale Installation ist also Pflicht für
jede:n Entwickler:in am Repo.

### Konfigurationsdateien (im Repo versioniert)

| Datei | Zweck |
|---|---|
| `.pre-commit-config.yaml` | Hook-Definition: gitleaks `gitleaks-system` (nutzt die lokal installierte Binary) |
| `.gitleaks.toml` | Projektspezifische Rules + Allowlist |

Die `.gitleaks.toml` blendet das gitleaks-Default-Ruleset (~850 Patterns:
AWS, GitHub, GitLab, Slack, OpenAI, Anthropic, Private Keys, JWT, DB-URLs)
via `useDefault = true` ein und ergänzt projektspezifische Patterns:

- `JWT_SECRET`, `JWT_REFRESH_SECRET`, `CREDS_KEY`, `MEILI_MASTER_KEY`,
  `LIBRECHAT_ADMIN_PASSWORD` (LibreChat)
- `RIS_PASSWORD` (Ratsinfo-System)
- `AZ_PASSWORD` (Allgäuer Zeitung)
- `NEXTCLOUD_PASSWORD`
- `GRIBS_PASSWORD` (gribs.net)
- `CUSTOM_PROVIDER_API_KEY` (LibreChat Custom Provider)

Die Allowlist erlaubt explizit `.env.example`/`.env.template`/`.env.dist` und
leere Platzhalter (z.B. `RIS_PASSWORD=` ohne Wert) — Platzhalter-Dateien
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
Zeit zur Config-Anpassung). Der Bypass hinterlässt keine Spur — idealerweise
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
  `gitleaks detect --source . -v` manuell suchen — siehe Security-Scan.
- **False Positives:** Dokumentations-Strings, die Secret-Patterns erwähnen
  (z.B. dieser Absatz hier), können gemeldet werden. Solche Fälle in die
  `.gitleaks.toml`-Allowlist aufnehmen, nicht mit `--no-verify` umgehen.

**Benötigt von:**

| Skill / Workflow | Anmerkung |
|---|---|
| Alle Commits | Hook läuft automatisch vor jedem Commit |

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

## LibreChat (browserbasierte AI-Harness-Alternative)

**Zweck:** Browserbasierte, ChatGPT-artige AI-Oberfläche als Alternative zu
OpenCode. Siehe [`librechat/README.md`](../librechat/README.md) für Setup und
Entscheidungshilfe.

**Install:**

```bash
cd librechat
cp .env.example .env                       # Credentials eintragen
cp librechat.yaml.example librechat.yaml   # ggf. Custom Provider aktivieren
./scripts/setup.sh                         # baut, startet, seedet Agents
```

**Voraussetzungen:**

- Docker + Docker Compose v2-Plugin (`docker compose version` muss funktionieren;
  bei Colima: `brew install docker-compose` + `ln -sfn $(brew --prefix)/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose`)
- Mind. 1 Model-Provider: Ollama lokal (`ollama serve`) ODER OpenAI/Anthropic-API-Key ODER Custom-OpenAI-kompatibler-Provider
- Optional parallel: `ratsprojekte` Phoenix-App (`mix phx.server` auf :4000) für Projekt-Integration
- Optional: Obsidian-Vault als Verzeichnis (für `obsidian`-MCP-Server)

**Setup-Skripte:**

| Skript | Zweck |
|---|---|
| `librechat/scripts/setup.sh` | One-Shot-Bootstrap: Pre-Flight → `docker compose up -d --build` → Health-Poll → auto-seed der Agents |
| `librechat/scripts/seed-agents.py` | Idempotentes Seeding der 7 LibreChat-Agents aus `librechat/agents/*.md` via REST-API |
| `librechat/scripts/verify.sh` | Health-Check: Container, MCP-Server, Vault-Mount, ratsprojekte, Agents |

**Konfigurations-Dateien (privat, in `.gitignore`):**

| Datei | Zweck | Vorlage (committable) |
|---|---|---|
| `librechat/.env` | Alle Credentials (Secrets, Provider, AZ, Nextcloud, RIS, gribs) | `librechat/.env.example` |
| `librechat/librechat.yaml` | MCP-Server + Custom Provider (mit baseURLs) | `librechat/librechat.yaml.example` |
| `librechat/docker-compose.override.yml` | Externe MCP-Server als Volume-Mounts (z.B. gribs_mcp) | `librechat/docker-compose.override.yml.example` |

**MCP-Server im LibreChat (7 aktiv, 1 optional):**

| Server | Typ | Transport | Anmerkung |
|---|---|---|---|
| `pdf_ingest` | Repo (`tools/pdf_ingest`) | stdio | via `uv run` im Container |
| `allgaeuer_zeitung_mcp` | Repo (`tools/allgaeuer_zeitung_mcp`) | stdio | via `uv run` im Container |
| `nextcloud_ods` | Repo (`tools/nextcloud_ods_mcp`) | stdio | via `uv run` im Container |
| `obsidian` | Repo (`tools/obsidian_mcp`) | stdio | nativer Vault-Zugriff, ohne `obsidian-cli`-Abhängigkeit |
| `ratsinfo` | Repo (`tools/ratsinfo_mcp` + `apps/ratsinfo`) | stdio | Multi-Stage-Build baut Elixir-escript im Dockerfile |
| `ratsprojekte` | Phoenix-App (Host :4000) | streamable-http | via `host.docker.internal` |
| `nextcloud` | extern (`uvx nextcloud-mcp-server`) | stdio | via `uvx` im Container |
| `gribs_mcp` (optional) | extern (nicht im Repo) | stdio | via `docker-compose.override.yml` als Volume-Mount |

**Bekannte Limitierungen:**

- **Kein Auto-Skill-Triggering** wie in OpenCode — das Modell hat aber always-on Zugriff auf alle MCP-Tools und kann diese ad-hoc nutzen. Skills liegen als LibreChat-Agents in `librechat/agents/` (7 System-Prompts).
- **Kein Tidewave** — Tidewave-MCP (Debugging für Phoenix-Apps) ist OpenCode vorbehalten (dev-only).
- **Multi-Stage-Build** dauert beim ersten Mal länger (Elixir-Dependencies), danach gecacht.

**Querverweise:**

- [`librechat/README.md`](../librechat/README.md) — Setup-Details, Agent-Einrichtung, opencode-vs-LibreChat-Entscheidungshilfe
- [`AGENTS.md`](../AGENTS.md) § „Zwei AI-Harnesses" — Architektur-Prinzip 5

## Querverweise

- [`AGENTS.md`](../AGENTS.md) § „Externe Abhängigkeiten" — Tabellen-Referenz
- [`docs/workflows.md`](./workflows.md) — Workflows mit Lücken, die externe
  Abhängigkeiten betreffen (WF 1, 2, 6, 8)
- [`docs/nomenklatur.md`](./nomenklatur.md) — Vault-Begriff
