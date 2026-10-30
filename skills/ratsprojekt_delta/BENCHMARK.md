# Benchmark: ratsprojekt_delta

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

## Fall: negativ-stand (negativ)

Negativfall: Der Prompt fragt nach dem Stand eines Projekts — die Sache von ratsprojekt_stand. ratsprojekt_delta braucht eine neue Information als Anlass; die reine Standfrage darf es nicht laden.

> Prompt: „Wo steht das Projekt Umgestaltung Bahnhofstraße gerade? Welche Vorbedingungen sind noch offen, gibt es einen Plan B?“
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-nicht-gelesen** (tool-call) | 5/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 124004 · Median Completion-Tokens: 3989 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 1
  Fehlkriterien: keine
  Gelesene Skills je Lauf: ratsprojekt_stand 5/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 0/5 Läufe (erwartet 0)

Kriterien des Falls:
- **skill-nicht-gelesen** (tool-call, `evals/cases/negativ-stand/bewerter/skill-nicht-gelesen.md`): Kernkriterium des Negativfalls: Eine reine Standfrage ohne neue
Information darf den Delta-Skill nicht laden.

## Fall: trigger-neue-info (trigger)

Trigger-Fall: Neue Information (Förderrichtlinie) gegen den Stand eines bestehenden Stadtratsprojekts halten — Kern-Trigger der Description (»Neue Förderrichtlinie ist raus«, »was bedeutet das für Projekt X?«).

> Prompt: „Hier ist eine neue Förderrichtlinie des Landes — schau mal, was das für unser Projekt Umgestaltung Bahnhofstraße ändert. Die Richtlinie liegt als foerderinfo.md im aktuellen Verzeichnis.“
> Fixtures (synthetisch): `fixtures/foerderinfo.md`
> Timeout je Lauf: 120 s
> Läufe je Arm: 5
> Arm: echte Skill-Auswahl über pis `--skill`-Mechanismus — alle 11 Skills registriert, kein Anhängen an den System-Prompt. Gemessen wird, ob der Skill per `read` geladen wird (Trigger) bzw. nicht geladen wird (Negativ).

| Kriterium (Bewerter) | aktuelle Fassung |
|---|---|
| **skill-gelesen** (tool-call) | 2/5 |

- **aktuelle Fassung** — Median-Wandzeit: 120 s · Median Prompt-Tokens: 101091 · Median Completion-Tokens: 3777 · Läufe mit Timeout/Fehler: 5/5 · ungültige Tool-Calls: 0
  Fehlkriterien: skill-gelesen fehlt 3/5
  Gelesene Skills je Lauf: ratsprojekt_stand 2/5 · ratsprojekt_delta 2/5 · vault_suche 1/5

Auffälligkeiten (automatisch gesammelt):
- Ziel-Skill gelesen: 2/5 Läufe

Kriterien des Falls:
- **skill-gelesen** (tool-call, `evals/cases/trigger-neue-info/bewerter/skill-gelesen.md`): Kernkriterium des Trigger-Falls: Das Modell muss die SKILL.md per read
laden, wenn die Description greift.

## Stichproben-Notizen

Stichproben-Notizen (Antworten der Läufe gelesen; Zahlen in den Tabellen oben):

- **Negativfall (reine Standfrage):** Der Ziel-Skill wird in keinem Lauf
  geladen (5/5 bestanden) — das Modell wählt stattdessen in 5/5 Läufen
  korrekt ratsprojekt_stand. Die Abgrenzung Standfrage (ohne neue
  Information) vs. Delta funktioniert auf der Auswahlseite sauber; die
  Läufe enden im Timeout, weil der ratsprojekte-Workflow (MCP-Aufrufe) in
  der Sandbox nicht existiert.
- **Triggerfall (neue Förderrichtlinie für ein bestehendes Projekt):** Die
  Description setzt sich nicht zuverlässig gegen die Schwester-Skills durch:
  Nur 2/5 Läufe laden ratsprojekt_delta; in 2/5 Läufen wird stattdessen
  ratsprojekt_stand gelesen (falsche Wahl innerhalb derselben Familie), in
  einem Lauf vault_suche. Offene Baustelle: Der Unterschied »neue
  Information gegen Stand halten« vs. »Stand abrufen« ist für das Modell in
  der Description von ratsprojekt_delta nicht scharf genug — dieselbe
  Schwäche zeigt die Trigger-Rate der Zwillings-Suite ratsprojekt_stand
  aus der Gegenrichtung (siehe dort).
- **Fremdlast:** Alle 3 markierten Läufe sind Timeout-Läufe
  (Kill-Nachlauf-Artefakt).

## Nicht gemessen

- keine verhalten-Fälle in der Suite — Wirkungs-Vergleich der Arme fehlt
- Läufe hatten nur die in den Fällen konfigurierten Tools — Schreib- und Netzschritte (z. B. „Quellen verifizieren“ mit Abruf) sind nicht Teil dieser Messung

## Reproduktion

```bash
komki up
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs --skill ratsprojekt_delta --baseline origin/main
```
