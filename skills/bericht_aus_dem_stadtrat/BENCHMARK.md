# Benchmark: bericht_aus_dem_stadtrat

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
| Fremdlast (serverRequestCountMismatch) | 2/10 Läufe |
| Richter für llm-Kriterien | nicht benutzt (keine llm-Kriterien in der Suite) |

## Fall: negativ-vorblick (negativ)

Negativfall: Der Prompt blickt nach vorn (»nächste« Sitzung vorbereiten), nicht zurück — bericht_aus_dem_stadtrat ist der Rückblick. Die Description darf nicht greifen.

> Prompt: „Was steht in der nächsten Stadtratssitzung an? Bereite die kommende Sitzung vor.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 142481 · Median Completion-Tokens: 4124 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 1
  Fehlkriterien: keine
  Gelesene Skills je Lauf: sitzungsvorbereitung 5/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-vorblick/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Ein Prompt über die kommende Sitzung darf
den Rückblick-Skill nicht laden.

## Fall: trigger-stammtischbericht (trigger)

Trigger-Fall: Ein kompakter Rückblick über die Ratsarbeit der letzten Wochen für einen Termin (Stammtisch) — Kern-Trigger der Description (»Bericht aus dem Stadtrat«, »Ich brauche einen Bericht für den Stammtisch«).

> Prompt: „Ich brauche einen Bericht aus dem Stadtrat für den Stammtisch am Donnerstag: Was ist seit der Sommerpause in den Ausschüssen und im Rat passiert? Fasse die letzten Wochen kompakt zusammen.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 4/5 |

- **aktuelle Fassung** — Median-Wandzeit: 100,1 s · Median Prompt-Tokens: 103506 · Median Completion-Tokens: 2574 · Läufe mit Timeout/Fehler: 2/5 · ungültige Tool-Calls: 0
  Fehlkriterien: skill-gelesen fehlt 1/5
  Gelesene Skills je Lauf: bericht_aus_dem_stadtrat 4/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 4/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-stammtischbericht/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Triggerfall (Stammtischbericht):** Die Description greift in 4 von 5
  Läufen — das Modell lädt die SKILL.md von bericht_aus_dem_stadtrat richtig
  und früh. Der fünfte Lauf liest keinen Skill und entwirft den Bericht aus
  Kontextwissen. Zwei der vier skill-geführten Läufe enden im Timeout: Nach
  dem Laden folgt das Modell dem Workflow (RIS-Sitzungen und Vault-Notizen
  sammeln), den die read-only-Sandbox nicht hergibt — dieselbe
  Config-/Werkzeug-Suche wie im Triggerfall von sitzungsvorbereitung.
- **Negativfall (Vorblick auf die nächste Sitzung):** Der Ziel-Skill wird in
  keinem Lauf geladen (5/5 bestanden); das Modell wählt stattdessen in 5/5
  Läufen korrekt sitzungsvorbereitung — die Abgrenzung Rückblick vs.
  Vorblick funktioniert. Alle Läufe enden im Timeout, weil der
  Sitzungsmappen-Workflow dann dieselbe config.local.yml-Suche durchläuft.
- **Fremdlast:** Beide markierten Läufe sind Timeout-Läufe; Markierung ist
  das Kill-Nachlauf-Artefakt (Server-Slot rechnet nach dem Abbruch weiter und
  blutet ins nächste Logfenster), keine echte fremde Last.

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill bericht_aus_dem_stadtrat --baseline origin/main
```
