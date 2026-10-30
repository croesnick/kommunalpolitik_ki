# Benchmark: sprachinventur

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
| Fremdlast (serverRequestCountMismatch) | 0/10 Läufe |
| Richter für llm-Kriterien | nicht benutzt (keine llm-Kriterien in der Suite) |

## Fall: negativ-antrag (negativ)

Negativfall: Der Prompt verlangt einen Antrag — reine Antragsarbeit ohne Begriffsfrage. sprachinventur darf nicht greifen.

> Prompt: „Schreib mir einen Stadtratsantrag dazu: Die Stadt soll den Lieferverkehr in der Bahnhofstraße auf die Zeit von 6 bis 9 Uhr beschränken.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 64,7 s · Median Prompt-Tokens: 13043 · Median Completion-Tokens: 2418 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: vault_suche 1/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-antrag/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Ein Antrag ohne Begriffsfrage darf den
Sprachinventur-Skill nicht laden.

## Fall: trigger-begriffsfrage (trigger)

Trigger-Fall: Über einen Fachbegriff entscheiden und die Verwendung im Repo vereinheitlichen — Kern-Trigger der Description (»Ist X etabliert?«, »Sprachinventur«).

> Prompt: „Ist »Sitzungsmappe« ein etablierter deutscher Begriff oder prägen wir den selbst? Und heißt es überall im Repo einheitlich so? Mach eine Sprachinventur.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 78146 · Median Completion-Tokens: 3993 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: sprachinventur 5/5 · sitzungsvorbereitung 4/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 5/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-begriffsfrage/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Triggerfall (Begriffsfrage »Sitzungsmappe«):** Die Description greift in
  5/5 Läufen — jeder Lauf lädt die SKILL.md von sprachinventur. In 4/5
  Läufen wird zusätzlich sitzungsvorbereitung gelesen: Die Frage dreht sich
  um »Sitzungsmappe«, das Nachschlagen der Verwendung dort ist
  sachgerecht, keine Fehlwahl. Alle Läufe enden im Timeout, weil die
  Inventur Repo-Websuche und Lexikonabfragen verlangt, die die Sandbox
  nicht hergibt.
- **Negativfall (Antrag):** Der Ziel-Skill wird in keinem Lauf geladen
  (5/5 bestanden), und die Läufe enden alle regulär (Median 65 s, kein
  Timeout, keine Fremdlast) — der Antrag braucht keinen Workflow, das
  Modell schreibt ihn direkt. Der Kontrast zu den workflow-lastigen
  Suiten zeigt: Timeouts entstehen dort, wo der geladene Skill Schritte
  verlangt, die es in der Sandbox nicht gibt — nicht beim blossen
  Beantworten.
- **Fremdlast:** 0/10 Läufe.

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill sprachinventur --baseline origin/main
```
