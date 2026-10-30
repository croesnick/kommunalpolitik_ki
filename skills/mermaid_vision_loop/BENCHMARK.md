# Benchmark: mermaid_vision_loop

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

## Fall: negativ-sitzungsmappe (negativ)

Negativfall: Der Prompt verlangt eine Sitzungsmappe — kein Diagramm. mermaid_vision_loop darf nicht greifen, obwohl der Skill ebenfalls »erstellen«-Aufgaben abdeckt.

> Prompt: „Erstell die Sitzungsmappe für die Stadtratssitzung am 12.11.2026.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 125413 · Median Completion-Tokens: 3694 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: sitzungsvorbereitung 5/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-sitzungsmappe/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Ein Sitzungsmappen-Prompt darf den
Mermaid-Skill nicht laden.

## Fall: trigger-diagramm (trigger)

Trigger-Fall: Ein Mermaid-Diagramm soll entstehen und auf Lesbarkeit geprüft werden — Kern-Trigger der Description (»Mach ein Mermaid-Diagramm für …«, »Prüfe die Lesbarkeit«).

> Prompt: „Mach ein Mermaid-Diagramm für den Ablauf einer Stadtratssitzung und prüfe die Lesbarkeit.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 3/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 70692 · Median Completion-Tokens: 2973 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 2
  Fehlkriterien: skill-gelesen fehlt 2/5
  Gelesene Skills je Lauf: mermaid_vision_loop 3/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 3/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-diagramm/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Triggerfall (Mermaid-Diagramm + Lesbarkeitsprüfung):** Drei von fünf
  Läufen laden die SKILL.md — die Description greift mehrheitlich, aber
  nicht zuverlässig (zwei Läufe lesen gar keinen Skill und zeichnen das
  Diagramm direkt aus Kontextwissen). Bemerkenswert: Zwei der drei
  skill-geführten Läufe lesen die SKILL.md je sechsmal hintereinander — das
  Modell folgt dem Render-/Vision-Loop (mermaid@11, Playwright,
  @observer-Agent), den die read-only-Sandbox nicht hergibt, und beginnt den
  Skill-Text immer wieder von vorn. Alle Läufe enden im Timeout, zwei
  ungültige Tool-Calls entstehen beim Versuch, nicht vorhandene Werkzeuge
  zu rufen. Für die Sandbox-Messung zählt nur: Der Skill wurde ausgewählt.
  Ob der Loop produktiv funktioniert, misst diese Suite nicht.
- **Negativfall (Sitzungsmappen-Prompt):** Der Ziel-Skill wird in keinem
  Lauf geladen (5/5 bestanden); das Modell wählt korrekt
  sitzungsvorbereitung (5/5) und läuft wie bekannt in die
  config.local.yml-Suche (5/5 Timeouts).
- **Fremdlast:** Der eine markierte Lauf ist ein Timeout-Lauf
  (Kill-Nachlauf-Artefakt, keine echte fremde Last).

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill mermaid_vision_loop --baseline origin/main
```
