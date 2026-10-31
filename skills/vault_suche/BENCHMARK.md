# Benchmark: vault_suche

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

## Fall: negativ-sitzungsmappe (negativ)

Negativfall: Der Prompt verlangt die Sitzungsmappe — die Sache von sitzungsvorbereitung (dessen Ablauf ruft den Vault selbst auf). vault_suche ist die eigenständige Suchaufgabe und darf bei diesem Prompt nicht greifen.

> Prompt: „Ich brauche die Sitzungsmappe für die Stadtratssitzung am 12.11.2026 — was steht dort an, welche Vorlagen muss ich lesen?“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 4/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 141171 · Median Completion-Tokens: 4157 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 0
  Fehlkriterien: skill-nicht-gelesen fehlt 1/5
  Gelesene Skills je Lauf: sitzungsvorbereitung 3/5 · vault_suche 1/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 1/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-sitzungsmappe/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Ein Sitzungsmappen-Prompt darf den
Vault-Such-Skill nicht laden.

## Fall: trigger-vaultsuche (trigger)

Trigger-Fall: Der Stadtrat bittet um eine Vault-Suche — Kern-Trigger der Description (»Was hab ich im Vault zu Thema X?«, »Hol mal alles aus dem Vault zu …«).

> Prompt: „Was hab ich im Vault zum Thema Bahnhofstraße? Such mal alles zusammen, was an Notizen dazu existiert.“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 95520 · Median Completion-Tokens: 4064 · Läufe mit Timeout/Fehler: 3/5 · ungültige Tool-Calls: 0
  Fehlkriterien: keine
  Gelesene Skills je Lauf: vault_suche 5/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 5/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-vaultsuche/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Triggerfall (Vault-Suche Bahnhofstraße):** Die Description greift in
  5/5 Läufen — jeder Lauf lädt die SKILL.md von vault_suche, kein anderer
  Skill. Drei Läufe enden im Timeout: Die obsidian-CLI existiert in der
  Sandbox nicht, das Modell probiert es trotzdem. Die Auswahl ist eindeutig.
- **Negativfall (Sitzungsmappe):** 4/5 — das Modell wählt korrekt
  sitzungsvorbereitung (3/5), aber in einem Lauf wird zusätzlich die
  SKILL.md von vault_suche gelesen. Grenzfall: Der Mappe-Workflow enthält
  selbst Vault-Schritte, eine Mitlesung im Flailen ist also keine reine
  Fehlauslösung — gezählt bleibt sie trotzdem, weil die Auswahl allein aus
  der Description entscheiden soll, bevor ein Workflow gelesen ist.
- **Fremdlast:** Alle 4 markierten Läufe sind Timeout-Läufe
  (Kill-Nachlauf-Artefakt).

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill vault_suche --baseline origin/main
```
