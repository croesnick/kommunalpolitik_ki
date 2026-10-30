# Benchmark: foerdermittel_recherche

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

## Fall: negativ-antrag (negativ)

Negativfall: Der Prompt verlangt einen Antrag ohne jede Finanzierungs- oder Kostenfrage — Sache von antrag_generieren. foerdermittel_recherche darf nicht greifen (seine Description nennt als Trigger Kosten- und Förderfragen, die dieser Prompt nicht stellt).

> Prompt: „Schreib mir einen Stadtratsantrag, dass die Stadt an der Bahnhofstraße einen Protected Bike Lane einrichtet.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 107,9 s · Median Prompt-Tokens: 40583 · Median Completion-Tokens: 4109 · Läufe mit Timeout/Fehler: 1/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: vault_suche 3/5 · ratsprojekt_proposal 2/5 · antrag_generieren 1/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-antrag/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Ein Antrag ohne Finanzierungsfrage darf den
Fördermittel-Skill nicht laden.

## Fall: trigger-foerderfrage (trigger)

Trigger-Fall: Fördermittel für ein kommunales Projekt suchen — Kern-Trigger der Description (»Können wir Förderung beantragen?«, »Gibt es Geld für X?«).

> Prompt: „Können wir für die Umgestaltung der Bahnhofstraße Fördermittel vom Land bekommen? Was für Fördertöpfe und Fristen gibt es in Bayern, und was müsste die Stadt als Eigenanteil einplanen?“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 139376 · Median Completion-Tokens: 3814 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: foerdermittel_recherche 5/5 · vault_suche 2/5 · ratsprojekt_stand 1/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 5/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-foerderfrage/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Triggerfall (Förderfrage Bahnhofstraße):** Die Description greift in
  5/5 Läufen — jeder Lauf lädt die SKILL.md von foerdermittel_recherche
  zuerst; in zwei Läufen zusätzlich vault_suche, in einem ratsprojekt_stand —
  für eine Förderfrage naheliegende Mitwahlen. Alle Läufe enden im Timeout:
  Die Recherche-Workflow-Schritte (Websuche, RIS) existieren in der
  read-only-Sandbox nicht, das Modell sucht sie trotzdem. Die
  Skill-Auswahl selbst ist damit eindeutig bestanden.
- **Negativfall (Antrag ohne Finanzierungsfrage):** Der Ziel-Skill wird in
  keinem Lauf geladen (5/5 bestanden). Nur 1/5 Läufe endet im Timeout. Das
  Modell liest stattdessen teils vault_suche (3/5) und ratsprojekt_proposal
  (2/5) — und in genau einem Lauf antrag_generieren (1/5), dieselbe
  schwache Trigger-Rate wie in der Suite von antrag_generieren selbst;
  der Befund bestätigt sich aus einer zweiten Richtung.
- **Fremdlast:** Alle 3 markierten Läufe sind Timeout-Läufe
  (Kill-Nachlauf-Artefakt, keine echte fremde Last).

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill foerdermittel_recherche --baseline origin/main
```
