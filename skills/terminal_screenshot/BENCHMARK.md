# Benchmark: terminal_screenshot

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

## Fall: negativ-mermaid (negativ)

Negativfall: Der Prompt will ein Mermaid-Diagramm — die Sache von mermaid_vision_loop (SVG, nicht Terminal-Capture). terminal_screenshot darf nicht greifen, obwohl beide Skills Visualisierungen liefern.

> Prompt: „Mach ein Mermaid-Diagramm für den Ablauf einer Stadtratssitzung und prüfe die Lesbarkeit.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 79943 · Median Completion-Tokens: 2646 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: mermaid_vision_loop 5/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-mermaid/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Ein Mermaid-Diagramm-Auftrag darf den
Terminal-Screenshot-Skill nicht laden.

## Fall: trigger-nutzungsbild (trigger)

Trigger-Fall: Ein README braucht ein Nutzungsbild eines CLI-Tools — Kern-Trigger der Description (»Mach einen Terminal-Screenshot für die README«, »Zeig, wie eine Session aussieht«).

> Prompt: „Die README von komki braucht ein Nutzungsbild: Mach einen Terminal-Screenshot, wie eine komki-Session aussieht, und bette ihn in die README ein.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 3/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 124915 · Median Completion-Tokens: 3880 · Läufe mit Timeout/Fehler: 4/5 · ungültige Tool-Calls: 1
  Fehlkriterien: skill-gelesen fehlt 2/5
  Gelesene Skills je Lauf: terminal_screenshot 3/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 3/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-nutzungsbild/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Triggerfall (Nutzungsbild für die README):** Drei von fünf Läufen laden
  die SKILL.md von terminal_screenshot — die Description greift
  mehrheitlich, aber nicht zuverlässig. Alle Läufe enden im Timeout (ein
  ungültiger Tool-Call): Der tmux-Capture- und SVG-Workflow existiert in
  der read-only-Sandbox nicht, das Modell probiert es trotzdem.
- **Negativfall (Mermaid-Diagramm):** Der Ziel-Skill wird in keinem Lauf
  geladen (5/5 bestanden); das Modell wählt korrekt mermaid_vision_loop
  (5/5). Die Abgrenzung Screenshot vs. Diagramm funktioniert in beide
  Richtungen — auch der Mermaid-Suite gelang diese Abgrenzung (dort wurde
  terminal_screenshot nie gelesen).
- **Fremdlast:** Alle 4 markierten Läufe sind Timeout-Läufe
  (Kill-Nachlauf-Artefakt).

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill terminal_screenshot --baseline origin/main
```
