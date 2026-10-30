# Benchmark: ratsprojekt_proposal

Gemessen am 30. Oktober 2026 gegen das Zielmodell der komki-Instanz. Alle Zahlen sind Rohzählungen über die gelaufenen Läufe; nichts davon „belegt“ einen Nutzen für sich allein — gezählt wird, was zählbar ist. Fälle, Fixtures und Bewerter stehen versioniert in [`evals/`](evals/) (Suite-Stand: `3be3869f`); jede Änderung an einem Kriterium setzt die Vergleichsreihe zurück und gehört in denselben Commit.

## Rahmen

| Feld | Wert |
|---|---|
| Modell | Gemma 4 26B-A4B-it (llama.cpp, Zielmodell der komki-Instanz) |
| GGUF | `gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf` · sha256 `ef728c8e0c337fd1…` |
| Sampling (Server-Defaults, pro Request nicht überschrieben) | temp 1 · top-p 0.95 · top-k 64 · min-p 0.05 · repeat-penalty 1 · seed zufällig |
| llama-server | llama.cpp 0.7.0 · port 49524 · auth erforderlich |
| pi · Node | pi 1.4.0 · v24.22.1 |
| Kontext · maxTokens | 131072 · 16384 |
| Läufe pro Arm | 5 |
| Arme je Runde abwechselnd | ja (Lauf 1 aller Arme, dann Lauf 2, …) |
| Fremdlast (serverRequestCountMismatch) | 1/10 Läufe |
| Richter für llm-Kriterien | nicht benutzt (keine llm-Kriterien in der Suite) |

## Fall: negativ-delta (negativ)

Negativfall: Der Prompt bringt eine neue Information zu einem bestehenden Projekt — die Sache von ratsprojekt_delta. Ein Proposal für ein neues Projekt ist hier nicht gefragt; ratsprojekt_proposal darf nicht greifen.

> Prompt: „Hier ist eine neue Förderrichtlinie des Landes: Zuschüsse für Straßenbegleitgrün, Mittelabruf bis Ende 2027. Was bedeutet das für unser bestehendes Projekt Umgestaltung Bahnhofstraße?“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 135658 · Median Completion-Tokens: 3700 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: ratsprojekt_delta 3/5 · ratsprojekt_stand 3/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-delta/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Eine neue Information zu einem
bestehenden Projekt darf den Proposal-Skill nicht laden.

## Fall: trigger-proposal (trigger)

Trigger-Fall: Eine Idee als neues Projekt in ratsprojekte anlegen — Kern-Trigger der Description (»Ich will das als Projekt anlegen«, »Mach daraus ein ratsprojekt«).

> Prompt: „Ich will die Idee mit den Baumspenden für die Bahnhofstraße als neues Projekt in ratsprojekte anlegen. Bring das als Proposal ein.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 107829 · Median Completion-Tokens: 3086 · Läufe mit Timeout/Fehler: 3/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: ratsprojekt_proposal 5/5 · vault_suche 5/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 5/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-proposal/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Triggerfall (Idee als Projekt anlegen):** Die Description greift in
  5/5 Läufen — jeder Lauf lädt die SKILL.md von ratsprojekt_proposal. In
  allen Läufen wird zusätzlich vault_suche gelesen: Der Proposal-Workflow
  sammelt zuerst Material im Vault, die Mitwahl ist also
  workflow-begründet, keine Fehlwahl. Drei Läufe enden im Timeout, weil
  Gates-Prüfungen und MCP-Aufrufe in der Sandbox nicht laufen.
- **Negativfall (neue Information zu bestehendem Projekt):** Der Ziel-Skill
  wird in keinem Lauf geladen (5/5 bestanden). Das Modell streut zwischen
  ratsprojekt_delta (3/5) und ratsprojekt_stand (3/5) — dieselbe
  Unschärfe zwischen den Schwester-Descriptionen, die auch der Triggerfall
  von ratsprojekt_delta zeigt; ratsprojekt_proposal selbst bleibt korrekt
  ungewählt.
- **Fremdlast:** Der eine markierte Lauf ist ein Timeout-Lauf
  (Kill-Nachlauf-Artefakt).

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill ratsprojekt_proposal --baseline origin/main
```
