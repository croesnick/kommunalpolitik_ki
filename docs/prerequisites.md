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

## Hinzufügen einer neuen Abhängigkeit

1. Abhängigkeit in diesem Dokument eintragen (Zweck, Install, Konfiguration,
   benötigt von, Fallback).
2. Im betroffenen Skill eine `## Prerequisites`-Sektion ergänzen, die auf dieses
   Dokument verweist.
3. Bei Bedarf: `config.local.yml.example` um Einträge ergänzen.

## Querverweise

- [`AGENTS.md`](../AGENTS.md) § „Externe Abhängigkeiten" — Tabellen-Referenz
- [`docs/workflows.md`](./workflows.md) — Workflows mit Lücken, die externe
  Abhängigkeiten betreffen (WF 1, 2, 6, 8)
- [`docs/nomenklatur.md`](./nomenklatur.md) — Vault-Begriff
