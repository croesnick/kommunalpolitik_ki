# Benchmark: antrag_generieren

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
| Fremdlast (serverRequestCountMismatch) | 3/10 Läufe |
| Richter für llm-Kriterien | nicht benutzt (keine llm-Kriterien in der Suite) |

## Fall: negativ-sitzungsvorbereitung (negativ)

Negativfall: Der Prompt verlangt eine Sitzungsmappe — die Sache von sitzungsvorbereitung. antrag_generieren darf nicht greifen, obwohl der Kontext Ratsarbeit ist: Anträge sind in der Sitzungsmappe ausdrücklich ausgeschlossen, umgekehrt ist die Mappe kein Antrag.

> Prompt: „Ich brauche die Sitzungsmappe für die nächste Stadtratssitzung. Was steht dort an, was muss ich lesen?“
> Quelle des Falls: Issue #292: »mindestens ein Negativfall je Skill (die description … darf nicht greifen)«
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 154311 · Median Completion-Tokens: 4235 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 1
  Fehlkriterien: keine
  Gelesene Skills je Lauf: sitzungsvorbereitung 4/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-sitzungsvorbereitung/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Bei einem Sitzungsmappen-Prompt darf die
SKILL.md von antrag_generieren in keinem Lauf geladen werden.

## Fall: trigger-antrag (trigger)

Trigger-Fall: Ein Nutzender will einen Stadtratsantrag entworfen haben — Kern-Trigger der Description (»Ich brauche einen Antrag zu …«). Gemessen wird, ob das Modell die SKILL.md des Zielskills per read lädt.

> Prompt: „Ich brauche einen Antrag zu mehr Straßenbäumen: Die Stadt soll bei jedem Straßenumbau an Hauptverkehrsstraßen neue Straßenbäume pflanzen. Schreib mir den Antrag.“
> Quelle des Falls: Issue #292: »mindestens ein Trigger-Fall je Skill (die description muss greifen)«
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 1/5 |

- **aktuelle Fassung** — Median-Wandzeit: 80,6 s · Median Prompt-Tokens: 13661 · Median Completion-Tokens: 3285 · Läufe mit Timeout/Fehler: 0/5 · ungültige Tool-Calls: 0
  Fehlkriterien: skill-gelesen fehlt 4/5
  Gelesene Skills je Lauf: vault_suche 2/5 · antrag_generieren 1/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 1/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-antrag/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: pi annonciert alle Skills im System-Prompt;
das Modell muss die SKILL.md des passenden Skills selbst per read laden.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Negativfall (Sitzungsmappen-Prompt):** Der Ziel-Skill wurde in keinem Lauf
  geladen (5/5 bestanden). Das Modell wählte stattdessen in 4/5 Läufen
  korrekt sitzungsvorbereitung und verhedderte sich dann wie in deren
  Trigger-Fall an der fehlenden `config.local.yml` — alle 5 Läufe endeten im
  Timeout (bis 186 k Prompt-Tokens). Die Nicht-Auslösung von
  antrag_generieren ist damit sauber gemessen, obwohl die Läufe selbst nicht
  endeten: Der Ziel-Skill wurde auch im Flailen nie gelesen.
- **Triggerfall (Antrag-Prompt):** Die Description trägt nicht zuverlässig:
  Nur 1/5 Läufe lädt die SKILL.md von antrag_generieren. In 2/5 Läufen wird
  stattdessen vault_suche gelesen (Fehlwahl), in 2/5 gar kein Skill — der
  Antrag wird in allen Läufen trotzdem korrekt aus Kontextwissen entworfen
  (kein Timeout, Median 81 s). Offene Baustelle für die nächste Fassung der
  Description: Der erste Trigger-Satz ist gut, aber das Modell greift bei
  „Ich brauche einen Antrag zu …“ nicht auf den Skill zu — prüfen, ob die
  lange Triggerliste im Description-Feld bei Gemma 26B verwässert statt
  hilft.
- **Fremdlast:** Alle 3 markierten Läufe sind Timeout-Läufe des Negativfalls;
  die abgebrochene Server-Seitenarbeit des jeweils vorherigen Laufs blutet
  ins nächste Logfenster (Kill-Artefakt). Keine echte fremde Last; die
  Kriterienzahlen kommen aus dem Proxy-Log und sind unberührt.

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill antrag_generieren --baseline origin/main
```
