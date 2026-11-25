# Labbook: Modell-A/B — Inkling 2 Mini gegen den Gemma-4-Pin, mit deutscher Textqualität

- **Status:** Pre-Registration, 2026-11-25 (Ticket [#642](https://github.com/croesnick/kommunalpolitik_ki/issues/642))
- **Vorgänger:** [Labbook: Modell-A/B](2026-10-31-modell-ab.md) (#285, Harness, Checklisten der Aufgaben 1–3)
- **Harness:** `apps/komki_cli/experiments/pi_packages/smoke/` (`run-ab.mjs`, `grade-ab.mjs`; neue Arme in `ab-arms.mjs`, neue Aufgabe 7 in `run-smoke.mjs`)

## Ziel und Abgrenzung

Inkling 2 Mini von Thinking Machines Lab ist am 20.11.2026 als Open-Weights-Modell unter Apache 2.0 erschienen. Es ist ein MoE-Modell mit 26,4B Parametern, davon 3,4B aktiv. Laut Hersteller liegt es in Agentic- und Tool-Benchmarks weit vor Gemma 4 31B, etwa bei MCP Atlas mit 82,7 gegen 54,2 % ([Modellkarte](https://huggingface.co/thinkingmachines/Inkling-2-Mini), abgerufen am 25.11.2026). Deutsch nennt die Modellkarte nicht. Unter „Languages“ steht „English, general multilingual support“, unter den Grenzen: „Output quality can be lower outside English.“

Dieses Labbook misst, ob Inkling 2 Mini den Gemma-Pin im komki-Alltag ersetzen kann. Es gelten dieselben Aufgaben wie in #285, dazu kommt eine eigene Bewertung der deutschen Textqualität. Der Bericht empfiehlt, entscheiden tut der Mensch. Dieses Ticket pinnt nichts um und ändert keine Instanz.

Begriffe: Ein **looped transformer** durchläuft einen Teil seiner Schichten mehrfach mit denselben Gewichten. Bei Inkling 2 Mini laufen die mittleren 12 von 24 Schichten dreimal, deshalb rechnet das Modell je Token mit etwa 5,4B effektiv aktiven Parametern statt 3,4B. Der **reasoning effort** ist die Denkstufe, die die Chat-Vorlage dem Modell als Systemzeile mitgibt („Thinking effort level: 0.2“). Ganz abschalten lässt sich das Denken laut Modellkarte nicht. Arm, Warm-up, TTFT und repetition loop sind wie in [#285](2026-10-31-modell-ab.md#ziel-und-abgrenzung) definiert.

## Pre-Registration

Dieser Abschnitt wird vor dem ersten Messlauf committet. Checklisten, Gates und Entscheidungsregel stehen gleichlautend als Code in `smoke/grade-ab.mjs` (`MANUAL`, `DEUTSCH`, Gates im `report`). Nach den Messläufen ändert sich daran nichts. Erweist sich eine Regel als unklar, steht das als Befund im Ergebnisteil, die Wertung bleibt wie registriert.

### Arme

| Arm | Artefakt | Sampling | Server-Schalter |
|---|---|---|---|
| G — Pin | `unsloth/gemma-4-26B-A4B-it-GGUF@c099eb48`, `gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf`, SHA-256 `ef728c8e…0636e30c`, MTP-Drafter `6326fb9f…26d93ed1b` | `--temp 1.0 --top-p 0.95 --top-k 64` | `--reasoning off --spec-type draft-mtp --spec-draft-n-max 4` (Produktivstart nach #318) |
| IL — Inkling, low | `unsloth/Inkling-2-Mini-GGUF@8078d149`, `Inkling-2-Mini-UD-Q4_K_XL.gguf`, SHA-256 `e6427665…f3cd3` | `--temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0` | `--reasoning-effort low` (0,2) |
| IH — Inkling, high | wie IL | wie IL | `--reasoning-effort high` (0,9, Default der Chat-Vorlage) |

Volle Revisionen und Prüfsummen stehen in `smoke/ab-arms.mjs`. Inkling kommt in derselben Quantisierung wie der Pin (Unsloth Dynamic UD-Q4_K_XL, 17,6 GB). Das Sampling für Inkling empfiehlt Unsloth: „Recommended sampling is temperature 1.0 with no truncation (top-p 1.0, top-k off, min-p 0)“ ([Mainline_Support/README.md](https://huggingface.co/unsloth/Inkling-2-Mini-GGUF/blob/8078d149286eec7193795413b9e0643da6d11fa1/Mainline_Support/README.md), abgerufen am 25.11.2026).

Zwei Denkstufen, weil sich das Denken bei Inkling nicht abschalten lässt („Setting reasoning effort to its minimum does not fully disable reasoning“, Modellkarte): IL steht für einen schnellen Alltagsbetrieb, IH ist der Default der Vorlage. Der Pin läuft ohne Thinking wie im Produktivstart. Für Inkling gibt es einen DSpark-Drafter (speculative decoding wie MTP). Er wird nicht gemessen, Unsloth nennt einen Gewinn von 1,1- bis 1,2-fach.

### Messprotokoll

- **Ein Build für alle Arme:** llama.cpp-Release b12720 (`1.0.0-dev`, Commit `33aeb17f8`), aus `llama-b12720-bin-macos-arm64.tar.gz`, SHA-256 `42d569fea95f7944c1138cb57a9aa76497cb32ae527107069da220f8668ca3a3`, geprüft gegen den GitHub-Digest. Inkling braucht mainline ab b12611, der Homebrew-Pin 1.0.0 (Build 12359) ist zu alt: Ältere Builds verlieren laut Unsloth NVFP4-Skalen in den Schleifen und liefern eine Perplexität von etwa 130 statt 7,65. Der Pin läuft deshalb hier auf b12720, nicht auf dem Binary der Instanz.
- **Gleich für alle Arme:** Maschine, Node, pi, Fixtures, Prompts, Logging-Proxy, Serverkontext `-c 131072`, pis `models.json` (`maxTokens` 16 384, `reasoning: false`, pi schickt also keinen eigenen reasoning effort), Staging-Server ohne Seatbelt-Profil auf eigenem Port (G 49624, IL 49625, IH 49626).
- **Ablauf:** Runde 0 ist das Warm-up (ungemessen), Runden 1–3 sind Messläufe, je Runde G, IL, IH. Jeder Lauf startet seinen Server frisch. Seed je Runde: 642 000 + Runde, alle Arme einer Runde teilen ihn.
- **Aufgaben:** 1, 2, 3, 4 und 6 aus #285 unverändert, dazu die neue Aufgabe 7. Ein Task-Fehler ist ein Messwert. Timeouts für alle Arme mit Faktor 6 gestreckt.
- **Vorab-Check:** `run-ab.mjs --preflight` lädt alle drei Arme. Dazu prüfe ich am IL-Server über `/apply-template`, dass die Denkstufe in der Vorlage ankommt, und mit einem Request mit Tool, dass llama-server den Tool-Call von Inkling als `tool_calls` liefert. Scheitert eins davon, wird nicht gemessen, sondern im Ticket berichtet.

Messgrößen wie in [#285](2026-10-31-modell-ab.md#messgrößen-je-lauf): Ladezeit, TTFT, Decode und Prefill, Token samt Thinking-Token, Tool-Calls, Reparaturbedarf, Speicher, finishReasons, Compaction. Neu ist die **Antwortsprache**: Für jede nicht leere Schlussantwort aller Aufgaben zählt `answerLanguage` deutsche und englische Funktionswörter; überwiegen die englischen, gilt die Antwort als Englisch. Berichtet werden Median und Spanne über die drei Messläufe.

### Aufgabe 7: Bürgerinformation

Prompt: „Lies die Datei top-3-anhoerung.md im aktuellen Verzeichnis. Schreibe daraus eine kurze Bürgerinformation für die Website der Stadt in die Datei buergerinfo.md: höchstens 150 Wörter, verständlich für Menschen ohne Verwaltungswissen, sachlich und ohne Wertung. Antworte am Ende nur mit einem Satz.“

Die Aufgaben 1–3 verdichten oder redigieren vorhandenen Text. Aufgabe 7 verlangt freies Schreiben in einem anderen Register. Das Fixture aus Aufgabe 1 enthält zwei Fallen für die Sprache: den englischen Begriff „Protected Bike Lane“ und den Kasusfehler „den Entwurf zuzustimmen“. Dazu kommt eine inhaltliche Falle: Der Ausschuss empfiehlt nur, beschlossen ist noch nichts.

### Blinde Qualitätsbewertung

`grade-ab.mjs blind` kopiert die Outputs der Aufgaben 1, 2, 3 und 7 aller neun Messläufe unter Zufalls-IDs, je Aufgabe gemischt. Automatische Punkte werden vor der manuellen Bewertung gerechnet. Die manuelle Bewertung arbeitet nur auf den verblindeten Kopien, der Schlüssel wird erst von `report` gelesen. Jeder Punkt zählt 1.

**Inhalt.** Die Aufgaben 1–3 werden mit den Checklisten aus [#285](2026-10-31-modell-ab.md#blinde-qualitätsbewertung) bewertet, unverändert (11, 20 und 16 Punkte). Aufgabe 7 hat 8 Punkte:

| ID | Art | Kriterium |
|---|---|---|
| W1 | auto | höchstens 150 Wörter |
| K1–K4 | auto | Bahnhofstraße, 240 000 Euro, Eigenanteil 80 000 Euro, Sitzungsdatum 12.11.2026 |
| B1 | manuell | Beratungsstand korrekt: Der Ausschuss empfiehlt dem Rat; nichts ist als beschlossen, genehmigt oder sicher dargestellt |
| B2 | manuell | nichts hinzuerfunden (keine neue Tatsachenbehauptung, Zahl, Frist, Wirkung oder Wertung) |
| B3 | manuell | verständlich ohne Verwaltungswissen: Fachbegriffe wie Kostenschätzung, Eigenanteil, Förderrichtlinie, Auflagen oder Haushaltsplanung vermieden oder erklärt |

**Deutsch.** Eine eigene Skala neben dem Inhalt, bewertet auf den Texten der Aufgaben 1, 3 und 7, je 5 Punkte:

| ID | Kriterium |
|---|---|
| D1 | Rechtschreibung und Zeichensetzung: höchstens ein Fehler (Kommas, Groß- und Kleinschreibung, Getrennt- und Zusammenschreibung, ß/ss) |
| D2 | Grammatik: kein Fehler (Kasus, Kongruenz, Wortstellung, Rektion); „den Entwurf zuzustimmen“ unverändert übernommen zählt als Fehler |
| D3 | Idiomatik: kein Übersetzungsdeutsch, keine schiefe Kollokation, kein erfundenes Wort. Englische Begriffe der Vorlage dürfen in den Aufgaben 1 und 3 stehen bleiben, in Aufgabe 7 müssen sie übersetzt oder erklärt sein |
| D4 | Register passt zur Textsorte und bleibt einheitlich: Aufgabe 1 sachlich-knapp für die Sitzungsmappe, Aufgabe 3 Beschlussvorlage, Aufgabe 7 bürgernah ohne Amtsdeutsch; keine wechselnde Anrede |
| D5 | Sprachtreue: durchgehend Deutsch, kein englischer Satz oder Halbsatz, keine Denk-, Tool- oder Formatierungsartefakte |

Zusätzlich wird je Text die Zahl der Rechtschreib-, Zeichensetzungs- und Grammatikfehler notiert und als Fehler je 100 Wörter berichtet. Ein fehlender Text bekommt in allen Punkten 0.

### Gates

Referenz ist G.

| Gate | Art | Regel |
|---|---|---|
| H1 | hart | 0 Faktenänderungen (F0–F10) in Aufgabe 3, in jedem Messlauf |
| H2 | hart | Reparaturrate ≤ G, gepoolt über alle Messläufe und Aufgaben (Zählweise wie in #285 nach der Korrektur) |
| Q | Inhalt | Median ≥ G in mindestens 2 der 3 Aufgaben 1–3 (wie #285; Aufgabe 7 wird berichtet) |
| D | Deutsch | Summe der Deutsch-Mediane über die Aufgaben 1, 3 und 7 ≥ G **und** Anteil englischer Schlussantworten ≤ G |
| K | Kosten | Median der Gesamtdauer über alle sechs Aufgaben höchstens doppelt so lang wie bei G |
| L | Schleifen | Läufe mit repetition loop ≤ G (Zeile ≥ 8-mal in einer Antwort, wie F1 in #285) |
| R1 | Ausfälle | Aufgaben mit `fail` oder Timeout ≤ G |

Die Kostengrenze K ist neu. Qwen3.8-27B fiel in #285 inhaltlich nicht durch, war aber 9,5-mal langsamer und damit nicht alltagstauglich. K legt diese Grenze vorher fest: Heute braucht der Produktivstart rund 90 s für die fünf Aufgaben aus #285, das Doppelte bleibt interaktiv nutzbar.

### Entscheidungsregel

1. Ein Inkling-Arm wird zum Re-Pin empfohlen, wenn er alle Gates besteht: H1, H2, Q, D, K, L und R1.
2. Bestehen IL und IH, entscheidet die Summe der Median-Punkte aus Inhalt (Aufgaben 1, 2, 3, 7) und Deutsch, bei Gleichstand die Gesamtdauer.
3. Besteht keiner, lautet die Empfehlung: Pin behalten. Der Bericht nennt, an welchen Gates Inkling scheitert.
4. Liegt eine Entscheidung knapp, also innerhalb eines Punktes oder an einem einzelnen Lauf, wird nur die knappe Kennzahl auf n = 5 erhöht, und das wird so berichtet.
5. Ein Re-Pin hieße mehr als eine neue Modelldatei: llama.cpp-Pin ab b12611, Sampling und Denkstufe im Produktivstart, Modell-Pin samt SHA-256. Das wäre ein eigenes Ticket nach dem GO.

### Vorab bekannte Grenzen

- n = 3 bei Temperatur 1,0: Mediane und Spannen beschreiben, sie beweisen nichts.
- Die Blindbewertung, auch die des Deutschen, macht die Session, die den Harness gebaut hat, also ein Sprachmodell. Sie ist kein Urteil einer deutschen Muttersprachlerin. Vor der Pre-Registration hat die Session je einen ungemessenen Entwicklungs-Output von G für die Aufgaben 1 und 7 gesehen (Probelauf `dev-task7`, Seed 642 900).
- Der Pin läuft auf b12720 statt auf dem Binary der Instanz (1.0.0). Ob sich der Pin zwischen beiden Builds unterscheidet, misst dieses Labbook nicht.
- pis Default-System-Prompt wie in #285, nicht der komki-Produktiv-Prompt; Mediator, MCP-Tools und Seatbelt-Profile sind außen vor.
