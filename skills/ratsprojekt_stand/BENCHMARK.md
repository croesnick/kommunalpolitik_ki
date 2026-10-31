# Benchmark: ratsprojekt_stand

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
| Fremdlast (serverRequestCountMismatch) | 4/10 Läufe |
| Richter für llm-Kriterien | nicht benutzt (keine llm-Kriterien in der Suite) |

## Fall: negativ-proposal (negativ)

Negativfall: Der Prompt will ein NEUES Projekt anlegen — die Sache von ratsprojekt_proposal. ratsprojekt_stand ist die Abfrage zum bestehenden Stand und darf hier nicht greifen.

> Prompt: „Ich will die Idee mit dem autofreien Sonntag am Marktplatz als neues Projekt in ratsprojekte anlegen — bring das bitte als Proposal ein.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 4/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 104429 · Median Completion-Tokens: 3789 · Läufe mit Timeout/Fehler: 3/5 · ungültige Tool-Calls: 1
  Fehlkriterien: skill-nicht-gelesen fehlt 1/5
  Gelesene Skills je Lauf: ratsprojekt_proposal 5/5 · vault_suche 3/5 · ratsprojekt_stand 1/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 1/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-proposal/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Ein neues-Projekt-Anlegen darf den
Stand-Skill nicht laden.

## Fall: trigger-standfrage (trigger)

Trigger-Fall: Standortbestimmung für ein konkretes Projekt — Kern-Trigger der Description (»Wo steht Projekt X?«, »Was steht dem Vorhaben entgegen?«).

> Prompt: „Wo steht das Projekt Umgestaltung Bahnhofstraße? Welche rechtlichen Vorbedingungen sind offen, welche Optionen und Realisierungsstränge gibt es?“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 102345 · Median Completion-Tokens: 3976 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: ratsprojekt_stand 5/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 5/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-standfrage/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Triggerfall (Standfrage zu einem konkreten Projekt):** Die Description
  greift in 5/5 Läufen — jeder Lauf lädt die SKILL.md von
  ratsprojekt_stand, in keinem Lauf ein anderer Skill. Alle Läufe enden im
  Timeout, weil die MCP-Aufrufe an ratsprojekte in der Sandbox nicht
  existieren; die Auswahl ist eindeutig.
- **Negativfall (neues Projekt anlegen):** 4/5 — das Modell wählt korrekt
  ratsprojekt_proposal (5/5), aber in einem Lauf wird zusätzlich die
  SKILL.md von ratsprojekt_stand gelesen: der einzige Negativ-Miss aller
  Suiten in dieser Messung. Da der Lauf auch proposal liest, ist die
  Mitlesung Streuung im Workflow-Schritt (Stand des angelegten Projekts
  prüfen), keine echte Fehlauslösung durch die Description — gezählt bleibt
  sie trotzdem.
- **Fremdlast:** Alle 4 markierten Läufe sind Timeout-Läufe
  (Kill-Nachlauf-Artefakt).

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill ratsprojekt_stand --baseline origin/main
```
