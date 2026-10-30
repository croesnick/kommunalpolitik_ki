# Skill-Evals: Benchmark gegen das Zielmodell

Updated: 2026-10-30. Skills werden nachvollziehbar „best in class“ ausgeliefert,
gemessen am Modell, das sie im Produktivbetrieb ausführt: **Gemma 4 26B im
llama-server der komki-Instanz, angesprochen über pi** — nicht Claude. Diese
Konvention ist verbindlich für jeden Skill unter `skills/`; sie definiert, wo
die Suite liegt, wie Fälle und Bewerter aussehen, was der Runner misst und
welche Pflichtfelder die `BENCHMARK.md` hat. Runner:
[`apps/komki_cli/experiments/pi_packages/skill-evals/`](../../apps/komki_cli/experiments/pi_packages/skill-evals/)
(dort auch die Begründung, warum der Messweg an den Vorlauf aus #158
angeschlossen ist statt neu gebaut zu werden).

Methodisch folgt die Konvention dem Stand der Technik (Oktober 2026), der bei
OpenAI, NVIDIA, Anthropic und SkillsBench übereinstimmend ist: gepaarter
Vergleich mit Baseline, Δ statt Absolutwert, mehrere Läufe, Trigger- und
Negativfälle, Kosten mitmessen, Modell pinnen. Quellen: [OpenAI eval-skills
Blog](https://developers.openai.com/blog/eval-skills) · [NVIDIA SkillEvaluator
— BENCHMARK.md neben SKILL.md](https://docs.nvidia.com/skills/evaluating-agent-skills) ·
[Anthropic plugin evals](https://code.claude.com/docs/en/plugin-evals) ·
[SkillsBench](https://hyper.ai/en/papers/2602.12670). `claude plugin eval` und
der skill-creator messen Claude, nicht Gemma; eine Übernahme fremder Runner
wird durch das Ablageformat `evals/` neben der `SKILL.md`
(agentskills.io-Konvention) nicht verbaut.

## Messfragen

| Fall-Typ | Frage | Arme |
|---|---|---|
| `verhalten` | Bringt der Skill die Antwort näher an das gewünschte Verhalten? | ohne Skill · vorige Fassung · aktuelle Fassung |
| `trigger` | Greift die Description, wenn sie greifen soll? | aktuelle Fassung (echter Mechanismus) |
| `negativ` | Greift die Description, obwohl sie nicht greifen darf? | aktuelle Fassung (echter Mechanismus) |

**verhalten** simuliert den vollständig geladenen Skill: Jede Fassung wird als
eingefrorene Kopie per `pi --append-system-prompt` in den System-Prompt
gehängt (wie im Vorlauf #158). Ob der Skill *auslöst*, misst das nicht —
deshalb laufen **trigger/negativ** über pis echten Skill-Mechanismus: pi
annonciert alle Skills im System-Prompt (`<available_skills>` mit Name,
Description, Pfad), und das Modell muss die passende `SKILL.md` selbst per
`read` laden. Gemessen wird dieser Tool-Aufruf (bzw. sein Ausbleiben).

## Ort und Layout

```
skills/<name>/
├── SKILL.md                  # der Skill selbst
├── evals/                    # die Suite (agentskills.io-Konvention)
│   └── cases/<fall-id>/
│       ├── case.md           # Frontmatter: Konfiguration · Body: der Prompt
│       ├── fixtures/         # synthetische Eingabedateien für den Lauf
│       └── bewerter/         # je Datei ein Kriterium
│           └── <kriterium-id>.md
└── BENCHMARK.md              # vom Runner geschrieben, committet (Pflichtfelder unten)
```

Die Runner-Artefakte (Rohdaten `ergebnis.json`, Antworten je Lauf) landen im
Laufverzeichnis unter `$TMPDIR/komki-pi-experiments/runs/…` und werden **nicht**
committet; die `BENCHMARK.md` ist der committete Bericht.

## Fallformat (`case.md`)

```yaml
---
id: sitzungsmappe-top3      # muss der Verzeichnisname sein
typ: verhalten             # verhalten | trigger | negativ
beschreibung: >
  Ein bis zwei Sätze: Was misst der Fall und warum.
arme: [ohne-skill, vorige, aktuelle]   # nur verhalten; trigger/negativ laufen automatisch einteilig
tools: read                # pi-Tool-Allowlist des Laufs
timeout_s: 300
laeufe: 5                  # Minimum laut Konvention: 5
quelle: "#158, Nachmessung 2"   # optional: Herleitung des Falls
---
Bereite TOP 3 als Abschnitt für meine Sitzungsmappe auf. Die Vorlage liegt als top-3-anhoerung.md im aktuellen Verzeichnis.
```

Der Body ist der Prompt, vollständig und so, wie ihn eine nutzende Person
schreiben würde — nicht skill-spezifisch vorformuliert. Mindestens **ein
Trigger-Fall und ein Negativfall je Skill** sind Pflicht; der Negativfall
sollte inhaltlich in die Domäne eines *anderen* Skills fallen (Stichwort-Falle
eingebaut), damit die Description wirklich unterscheidet und nicht nur
Themen-Keywords matched.

## Bewertertypen

Bewerterdefinitionen sind Teil der Suite — der Runner kennt die Typen, aber
keine Kriterien (Lehre aus #158: das Wort „Eigenanteil“ ohne Zahl genügte und
machte ein lasches Kriterium unabsichtlich grün). Deterministische Bewerter
kommen zuerst; ein LLM als Richter nur für kurze Ausgaben mit konkreten
PASS/FAIL-Bedingungen.

| Typ | Frontmatter | Bestanden, wenn |
|---|---|---|
| `enthaelt` | `optionen` (Regex-Liste, Groß-/Kleinschreibung egal), optional `min_treffer` | mindestens `min_treffer` (Default 1) Optionen matchen die Antwort |
| `enthaelt-nicht` | `optionen` | keine Option matcht |
| `zahlen` | optional `kennzeichne_abgeleitet: true`, `abgeleitet_vermerke` | keine erfundene Zahl laut `classifyNumbers` (Quelle = Fixtures des Falls); abgeleitete Zahlen (Summe/Differenz aus Quellenzahlen) sind toleriert und werden protokolliert; mit `kennzeichne_abgeleitet` müssen sie in der Antwort als abgeleitet vermerkt sein |
| `tool-call` | `tool`, `parameter` (Regex gegen die Argumente), `anzahl_min`, `anzahl_max` | die Zahl der passenden Aufrufe liegt in [`anzahl_min`, `anzahl_max`] |
| `datei` | `datei` | die Datei im Lauf-Arbeitsverzeichnis wurde erzeugt |
| `llm` | (Body = Bedingungen) | der Richter urteilt PASS; dasselbe gepinnte Modell über denselben llama-server, Antwort nur PASS/FAIL in Zeile 1 |

Der Body einer Bewerter-Datei ist die Begründung des Kriteriums und erscheint
im Bericht; bei `llm` ist der Body die konkrete PASS/FAIL-Bedingung, die der
Richter wörtlich bekommt.

Regeln für Kriterien:

- **Wortstellungstoleranz über Alternativen** („Förder… Frist“ und „Frist …
  Förder“), nie über weichere Kriterien. Ein strengeres Kriterium verschiebt
  Ergebnisse (#158: K4 ohne „Umgestaltung“ machte aus 5/5 ein 4/5).
- **Zahlen-Kriterien verlangen die Zahl**, wenn eine Zahl gemeint ist — Wörter
  allein genügen nicht.
- **Kriterien sind versioniert** in der Suite. Eine Änderung an einem Kriterium
  setzt die Vergleichsreihe zurück und gehört in denselben Commit wie die neue
  Messung; die `BENCHMARK.md` nennt den Suite-Stand (Git-SHA).
- **Jeder neue Fehlertyp wird zum Fall**: Das Lesen der Stichproben findet
  Fehler, die kein abgefragtes Kriterium kennt (in #158 war es die erfundene
  RIS-URL). Pflicht je Messrunde: Stichproben lesen und neue Fehler als Fälle
  in die Suite aufnehmen.

## Runner und Messdisziplin

```bash
komki up   # llama-server der komki-Instanz; der Runner startet ihn nie selbst
node apps/komki_cli/experiments/pi_packages/skill-evals/run.mjs \
  --skill sitzungsvorbereitung --baseline 9c50fa1
```

- **Arme einfrieren:** Jede Skill-Fassung wird vor der Messung als Kopie ins
  Laufverzeichnis geschrieben (ohne/vorige/aktuelle), im Bericht mit Zeilenzahl,
  sha256 des Inhalts und Git-Stand. Ein Arm, der auf die Arbeitsdatei zeigt,
  misst Mischstände, wenn parallel editiert wird (#158).
- **`--baseline <git-ref>`** wählt die vorige Fassung (Default `origin/main`).
  Für die erste committete Messung stand der aktuelle Skill schon auf main;
  deshalb lief sie gegen den tatsächlichen Vorgänger (9c50fa1, 834 Zeilen).
  Künftige Skill-PRs messen gegen den Stand, den sie ersetzen.
- **Arme abwechselnd:** Lauf 1 aller (Fall, Arm)-Paare, dann Lauf 2 … Der
  llama-server ist die geteilte Live-Instanz; Prefix-Cache, Wärme und Last
  driften, also verteilt statt geblockt.
- **Fremdlast sichtbar machen:** Jeder Lauf gleicht das Server-Logfenster
  gegen die eigene Proxy-Request-Zählung ab (`serverRequestCountMismatch`).
  Verzeichnete Läufe werden gezählt und im Bericht genannt, nicht verworfen.
- **Richter erst nach den Messläufen:** llm-Bewerter laufen in einem eigenen
  Abschnitt, damit kein Richter-Request ein Logfenster verfälscht.
- **Kosten:** 30–80 s je Lauf (Skill im Kontext ≈ 8–9 k Prompt-Tokens; die
  834-Zeilen-Fassung ≈ 25 k). Drei Arme × 5 Läufe ≈ 15 Minuten je
  verhalten-Fall. Messungen im Hintergrund fahren; vorher `komki status`
  prüfen.
- **Einbau-Kontrollen:** Nach dem ersten Lauf je (Fall, Arm) prüft der Runner,
  dass der Skill-Anhang wirklich im System-Prompt steht (bzw. bei
  trigger/negativ, dass `<available_skills>` den Skill enthält) — ein still
  fehlgeschlagenes `--append-system-prompt` würde sonst fünf Läufe lang
  sauber wirkende Zahlen produzieren.

## Pflichtfelder der `BENCHMARK.md`

Der Runner schreibt sie; sie wird committet. Pflicht je Bericht:

- **Rahmen/Modell-Pin:** Modell, GGUF-Dateiname und sha256, Sampling
  (Server-Defaults, pro Request nicht überschrieben), llama-server-Version,
  pi- und Node-Version, Kontextgröße, maxTokens, Datum.
- **Arme:** Bezeichnung, Skill-Fassung (Zeilen, sha256, Git-Stand/Herkunft).
- **Je Fall:** Beschreibung, Prompt, Fixtures, Kriterien mit Bewertertyp,
  **roh gezählte Erfolge je Kriterium und Arm** (z. B. 4/5), Fehlkriterien je
  Arm, Median-Wandzeit, Median Prompt-Tokens (und Completion-Tokens), Läufe
  mit Timeout/Fehler, ungültige Tool-Calls, Fremdlast-Zählung; bei
  trigger/negativ zusätzlich, welche Skills je Lauf gelesen wurden.
- **Auffälligkeiten:** automatisch gesammelte Signale (erfundene Zahlen,
  URLs, Abrufdaten) auch dort, wo kein Kriterium sie abfragt.
- **Stichproben-Notizen** (aus `--notizen`): was das Lesen der Antworten
  ergab, inkl. kurzer Zitate.
- **Nicht gemessen:** bekannte Lücken der Messung (z. B. Schreib- und
  Netzschritte).
- **Reproduktion:** dieRunner-Kommandozeile mit allen Entscheidungen.
- **Zählungen, keine „belegt“-Formeln:** Der Bericht zählt Vorkommen und nennt
  Mediane — er schreibt nicht „der Skill belegt X“. Ob ein Zählerstand ein
  GO rechtfertigt, entscheidet die lesende Person.

## Fixtures: nur synthetisch

Keine echten oder vertraulichen Ratsdaten in Fixtures — nur synthetische
(Erfundene Gremien, Beträge, Vorgänge; im Repo etabliert: das
Bahnhofstraße-Universum). Die Fixture einer Suite gehört zum Fall, nicht zur
Smoke-Test-Bibliothek (`smoke/fixtures.mjs`): Der Fall muss ohne imports
lesbar und gegen ein anderes Modell replizierbar sein.

## Folgeregel: Messung vor dem Merge

Ein Skill-PR ohne aktualisierte `BENCHMARK.md` gilt nicht als fertig: Eine
Skill-Änderung belegt ihren Nutzen (oder zeigt ihren Fehlschlag), statt ihn zu
behaupten — mit gegen ohne Skill und neue gegen vorige Fassung. Für reine
Kosmetik (Tippfehler, Linkpflege) genügt ein Vermerk im PR, dass die
`BENCHMARK.md` unverändert bleibt, weil sich Verhalten und Trigger nicht
ändern können.
