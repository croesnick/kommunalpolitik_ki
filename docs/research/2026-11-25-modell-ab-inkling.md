# Labbook: Modell-A/B — Inkling 2 Mini gegen den Gemma-4-Pin, mit deutscher Textqualität

- **Status:** abgeschlossen, 2026-11-25 (Ticket [#642](https://github.com/croesnick/kommunalpolitik_ki/issues/642)). Pre-Registration committet um 09:00 Uhr (`1e327847`), erster Lauf um 09:02 Uhr
- **Empfehlung:** Pin behalten. Inkling 2 Mini ist auf dem M1 Max vier- bis zehnmal langsamer und schreibt weniger fehlerfreies Deutsch. Inhaltlich trifft es den Beratungsstand besser als Gemma. Herleitung im Abschnitt [Empfehlung](#empfehlung)
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

## Ablauf

| Schritt | Zeit (25.11.2026, MEZ) | Laufverzeichnis unter `$TMPDIR/komki-pi-experiments/ab-642/` |
|---|---|---|
| Vorab-Check (Denkstufe, Tool-Call, eine deutsche Probefrage je Arm), Entwicklungslauf und Probe der Auswertung mit Platzhalter-Bewertungen | 08:40–09:00 | `vorab/`, `dev-task7/`, `dev-grade/` |
| Pre-Registration committet | 09:00 | Commit `1e327847`, Arbeitsbaum sauber |
| Preflight-Check, Warm-up und 3 Runden × 3 Arme | 09:01–10:56 | `main/` (`schedule.json`, `provenance.json`, `REPORT.md`) |
| Blindbewertung, Entblindung | danach | `main/blind/`, `main/blind-key.json` |

Die Rohdaten (Request-Mitschnitte, Sessions, Server-Logs, Blindkopien) liegen nur in diesen Verzeichnissen und sind nicht Teil des Repos.

## Umgebung und Provenance

| Feld | Wert |
|---|---|
| Hardware | MacBookPro18,4, Apple M1 Max, 64 GB, keine Thermik- oder Leistungswarnung in irgendeinem Lauf (`pmset -g therm`) |
| macOS | 27.2 (26B5101f) |
| llama-server | `1.0.0-dev (build 12720, commit 33aeb17f8)`, SHA-256 `685941b8df982e4e205fd20492f9aaa9418f2d1224ba3d311a686abd0edb0439`, für alle drei Arme |
| Node, pi | 24.22.3, pi 1.5.2 (aus der Homebrew-Formel komki 0.1.0) |
| Seeds | Warm-up 642 000, Runden 1–3: 642 001–642 003 |
| Störgrößen | Die komki-Instanz lief nicht. Der Warm-up von G und der Beginn des Warm-ups von IL liefen auf Akku, danach am Netz. Im Warm-up von IL stieg die Systemlast auf 179 (5-Minuten-Mittel; vorher 3,1) und der Swap von 2,8 auf 8,1 GB, durch Prozesse außerhalb des Harness. Zu Beginn von Runde 1 lag das 15-Minuten-Mittel noch bei 55. Danach blieb der Swap bei rund 8 GB. Die Messläufe sind nicht erkennbar betroffen: Runde 1 war für IL und IH die schnellste (373 s und 932 s). |

Vorab-Check bestanden: Der IL-Server rendert „Thinking effort level: 0.2“ in die Vorlage, IH „0.9“. Auf eine Frage mit Tool liefern beide Arme `finish_reason: tool_calls` mit gültigem `tool_calls`-Objekt, das Thinking getrennt in `reasoning_content`. Alle drei Arme laden im Preflight (G 3,3 s, IL 5,8 s, IH 3,0 s).

## Ergebnisübersicht

Kein Inkling-Arm besteht die Gates. Entscheidend ist die Kostengrenze K: IL braucht viermal so lange wie der Pin, IH zehnmal so lange. Inhalt und Sprache zeigen gegenläufige Stärken:

- **G, Pin:** schnell und sprachlich fehlerfrei. In allen neun bewerteten Texten fand die Bewertung keinen Rechtschreib- oder Grammatikfehler. Den Kasusfehler der Vorlage korrigiert der Pin in allen drei Zusammenfassungen. Inhaltlich lässt er wie in #285 den Eigenanteil weg. In der Bürgerinformation erfindet er in jedem Lauf ein Ziel („die Lebensqualität und Sicherheit im Straßenraum zu verbessern“), wertet („lediglich 80.000 Euro“) und stellt den Umbau als festen Plan der Stadt dar, ohne Ausschuss und Rat.
- **IL, Inkling low:** inhaltlich der stärkste Arm in der Bürgerinformation. In allen drei Läufen bleibt der Beratungsstand korrekt, zweimal mit dem Hinweis, dass der Rat entscheidet. Sprachlich unsauberer als der Pin: übernommener Kasusfehler, eigene Fehler („der Verwaltung zu beauftragen“), schiefe Wendungen („Im Umbau sind vorgesehen“).
- **IH, Inkling high:** denkt im Median 12 650 Token je Lauf und braucht dadurch fast zehnmal so lange wie der Pin. Die Zusammenfassungen sind die vollständigsten (11 von 11 in zwei Läufen). In der Bürgerinformation verschärft IH zweimal „melden“ zu „aufnehmen“ bzw. „übernehmen“, die Verschärfung, die #285 bei Gemma fand.

### Gates

| Gate | G (Pin) | IL | IH |
|---|---|---|---|
| H1: 0 Faktenänderungen in Aufgabe 3, jeder Lauf | 0 / 0 / 0 | 1 / 0 / 0 → nicht bestanden | 0 / 1 / 0 → nicht bestanden |
| H2: Reparaturrate ≤ Pin | 0 von 63 | 0 von 65 → bestanden | 1 von 73 → nicht bestanden |
| Q: Median ≥ Pin in ≥ 2 von 3 (Aufgaben 1–3) | Referenz | Aufgaben 1 und 3 → bestanden | nur Aufgabe 1 → nicht bestanden |
| D: Deutsch-Summe ≥ Pin, Englisch-Anteil ≤ Pin | 15, 1 von 24 | 14, 1 von 24 → nicht bestanden | 14, 1 von 24 → nicht bestanden |
| K: Gesamtdauer ≤ 2 × Pin | 101 s | 400 s → nicht bestanden | 990 s → nicht bestanden |
| L: Läufe mit repetition loop ≤ Pin | 0 von 3 | 0 von 3 → bestanden | 0 von 3 → bestanden |
| R1: `fail` oder Timeout ≤ Pin | 0 | 1 → nicht bestanden | 1 → nicht bestanden |

### Qualität (blind, Punkte: Median und Spanne)

| Aufgabe | G (Pin) | IL | IH |
|---|---|---|---|
| 1 — TOP-Zusammenfassung (von 11) | 10 (10–10) | 10 (10–11) | 11 (10–11) |
| 2 — Quellen (von 20) | 20 (20–20) | 18 (0–20) | 18 (0–20) |
| 3 — Redigieren (von 16) | 15 (15–15) | 15 (14–15) | 14 (14–14) |
| 7 — Bürgerinformation (von 8) | 5 (5–5) | 7 (6–7) | 6 (5–6) |
| Deutsch Aufgabe 1 (von 5) | 5 (5–5) | 5 (4–5) | 4 (4–4) |
| Deutsch Aufgabe 3 (von 5) | 5 (5–5) | 5 (4–5) | 5 (4–5) |
| Deutsch Aufgabe 7 (von 5) | 5 (5–5) | 4 (3–4) | 5 (5–5) |
| Fehler je 100 Wörter, alle neun Texte | 0,0 (0,0–0,0) | 0,0 (0,0–0,8) | 0,0 (0,0–1,5) |

Einzelwerte, Notizen je Text und alle Messgrößen stehen im generierten `main/REPORT.md`.

### Leistung (Median und Spanne über 3 Messläufe, Aufgaben 1–4, 6 und 7)

| Messgröße | G (Pin) | IL | IH |
|---|---|---|---|
| Ladezeit | 8,6 s (8,6–8,8) | 6,1 s (5,6–6,3) | 3,0 s (3,0–3,0) |
| Gesamtdauer | 101 s (97–104) | 400 s (373–402) | 990 s (932–1 047) |
| Decode | 57,2 t/s (55,7–59,4) | 22,0 t/s (21,9–22,1) | 21,4 t/s (21,4–21,6) |
| Prefill | 420 t/s (408–425) | 140 t/s (140–141) | 138 t/s (134–141) |
| erste sichtbare Antwort, Median je Request | 0,8 s | 3,9 s | 5,8 s |
| Completion-Token | 2 507 | 5 202 | 16 959 |
| davon Thinking-Token | 0 | 1 529 | 12 650 |
| `phys_footprint` max | 13,5 GiB | 13,7 GiB | 14,9 GiB |
| Tool-Calls / schema-invalide / Reparaturen | 63 / 0 / 0 | 65 / 0 / 0 | 73 / 0 / 1 |

| Aufgabe | Gesamtdauer G | Gesamtdauer IL | Gesamtdauer IH | Prüfergebnisse G · IL · IH |
|---|---|---|---|---|
| 1 TOP | 4,2 s | 24,2 s | 37,9 s | partial³ · pass³ · pass³ |
| 2 Quellen | 10,5 s | 59,2 s | 333 s | pass³ · pass, fail, pass · pass, pass, fail |
| 3 Redigieren | 8,1 s | 34,0 s | 68,3 s | pass³ · pass³ · pass³ |
| 4 Todo | 23,7 s | 74,9 s | 86,8 s | pass³ · pass³ · pass³ |
| 6 Compaction | 44,4 s | 169 s | 211 s | pass³ · pass³ · pass³ |
| 7 Bürgerinfo | 9,4 s | 26,4 s | 197 s | pass³ · pass, pass, partial · pass, pass, partial |

Die `partial` in Aufgabe 7 sind Texte über 150 Wörter (153 und 163).

## Befunde

### 1. Inkling decodiert auf dem M1 Max mit 22 t/s

Der Pin decodiert mit MTP-Drafter 57 t/s, Inkling ohne Drafter 22 t/s. Das liegt an der Architektur: Die mittleren Schichten laufen dreimal, je Token rechnet Inkling mit rund 5,4B effektiv aktiven Parametern statt Gemmas 3,8B, und jede Schleife liest dieselben Gewichte erneut. Auch Prefill ist dreimal langsamer (140 gegen 420 t/s). Dazu kommt das Denken, das sich nicht abschalten lässt: Selbst auf der Stufe low sind 29 % der Completion-Token Thinking, auf der Stufe high 75 %. Die erste sichtbare Antwort kommt nach 3,9 bzw. 5,8 s statt nach 0,8 s. Der DSpark-Drafter würde laut Unsloth 1,1- bis 1,2-fach beschleunigen und die Lücke nicht schließen.

### 2. Der Pin schreibt das sauberere Deutsch

In den neun Texten des Pins fand die Bewertung keinen Fehler. Den Kasusfehler der Vorlage („den Entwurf zuzustimmen“) schreibt der Pin in allen drei Zusammenfassungen richtig. Inkling übernimmt ihn in drei von sechs Zusammenfassungen (IH zweimal, IL einmal) und macht eigene Fehler: „der Verwaltung zu beauftragen“, „Haushaltplanung“. Schiefe Wendungen kommen nur bei Inkling vor: „Im Umbau sind vorgesehen“, „den Haushaltsplan 2027 entsprechend zu melden“, „Der Abschnitt ist im öffentlichen Ausschuss beraten worden“, „ihr in Vorbereitung der Haushaltsplanung zuzusagen“, „adressiert werden“. Die Fehlerdichte bleibt niedrig (höchstens 1,5 je 100 Wörter), englische Sätze oder Sprachmischung kamen in keinem bewerteten Text vor. Den englischen Begriff „Protected Bike Lane“ übersetzen alle drei Arme in der Bürgerinformation („geschützter Radweg“).

Englisch antwortet jeder Arm genau einmal, jeweils in Aufgabe 6 nach der Compaction. In #285 taten das Pin und QAT-Variante zusammen in 8 von 14 Läufen; hier ist es beim Pin einer von drei. Die Ursache wurde nicht untersucht.

### 3. Inkling trifft Inhalt und Beratungsstand besser

Inkling nennt den Eigenanteil in allen sechs Zusammenfassungen, der Pin in keiner seiner drei, wie schon in #158 und #285. In der Bürgerinformation gibt IL den Beratungsstand und die Empfehlung in allen drei Läufen richtig wieder. IH stellt einmal etwas als sicher dar (der Ergänzungsantrag „wird vorbereitet“) und verändert in allen drei Läufen den Inhalt der Empfehlung: zweimal „melden“ → „aufnehmen“ bzw. „übernehmen“, einmal einen anderen Akteur. B1 zählt beides nach der präzisierten Regel (Abweichung 1). Der Pin stellt den Umbau in allen drei Läufen als festen Plan der Stadt dar, ohne Ausschuss und Rat. Der Pin erfindet dort in allen drei Läufen ein Ziel, in einem auch eine Begründung („Um den Verkehrsfluss und die Anwohner nicht zu stören“). In zwei Läufen macht er aus dem Ersatz der Parkbuchten „14 neue Parkplätze“, in allen dreien wertet er mit „lediglich“. Die Vorgabe „sachlich und ohne Wertung“ hält er nicht ein. Inkling erfindet in keinem Lauf etwas, verwendet aber Verwaltungsbegriffe wie „Zuwendungsbescheid“, die Laien nicht verstehen (B3 in fünf von sechs Läufen verfehlt).

### 4. Rohe Anführungszeichen machen Inklings JSON ungültig

In Aufgabe 2 übernimmt Inkling das ASCII-Anführungszeichen aus `„Barrierefreiheit Bahnhofstraße"` roh in `quellen.json`, je Arm in einem von drei Läufen. Das JSON wird ungültig und bekommt 0 von 20 Punkten. Das ist dieselbe Fehlerklasse wie bei Qwen3.8-27B in #285 (Befund 5). Der Pin maskiert das Zeichen in allen Läufen.

### 5. Beide Inkling-Arme ändern je einen Fakt beim Redigieren

IL macht in einem Lauf aus der Bitte um Zustimmung „im Vorgriff auf“ die Haushaltsplanung zusätzlich eine Bitte, der Maßnahme „in Vorbereitung der Haushaltsplanung zuzusagen“ (F10). IH macht in einem Lauf aus „einer der zentralen Achsen unserer Stadt“ „die zentrale Achse“ (F0). Beide Fälle sind Ermessensentscheidungen am Rand der Checkliste. Die Empfehlung hängt nicht an ihnen, weil K beide Arme ohnehin ausschließt. Die Modalität „kann gedeckt werden“ geht wie in #285 in allen neun Fassungen verloren (S4).

### 6. Der Warm-up von IL dauerte 20 Minuten

Aufgabe 6 brauchte im ungemessenen Warm-up von IL 1 218 s, in den Messläufen 160–184 s. Zwei Requests liefen 447 und 573 s für 130 bzw. 573 Completion-Token. Danach trat das nicht wieder auf. Wahrscheinliche Ursache ist die Systemlast in diesem Zeitraum (siehe Störgrößen: Last bis 179, Swap von 2,8 auf 8,1 GB). Ein Aufwärmeffekt des neuen Architekturpfads auf Metal ist nicht ausgeschlossen; untersucht wurde das nicht.

## Abweichungen vom Protokoll

1. **Bewertungsregel B1 präzisiert, vor dem Entblinden.** Auch ein veränderter Inhalt der Empfehlung zählt gegen B1: eine andere Handlung („melden“ → „aufnehmen“) oder ein anderer Akteur (der Rat statt der Verwaltung bereitet den Ergänzungsantrag vor). Auf alle neun Bürgerinformationen gleich angewandt.
2. **Bewertungsregel B3 präzisiert, vor dem Entblinden.** Gegen B3 zählen nur Begriffe, die Laien aus dem Text nicht erschließen können: Förderrichtlinie, Zuwendungsbescheid, Auflagen ohne Erläuterung. „Kostenschätzung“, „Eigenanteil“ und „Haushaltsplanung“ zählen nicht, wenn der Satz ihre Bedeutung klar macht („80.000 Euro Eigenanteil der Stadt, der Rest aus Landesförderung“).
3. **Zählregel für M1 festgelegt, vor dem Entblinden.** #285 hat sie nicht dokumentiert. Ein Stichpunkt zählt als ein Satz, mehrere Sätze in einem Stichpunkt zählen einzeln, die Überschrift zählt nicht.
Die Präzisierungen 1 bis 3 widersprechen der eigenen Pre-Registration, nach der bei unklaren Regeln „die Wertung bleibt wie registriert“. Auf die Gates wirken sie nicht: Aufgabe 7 steht in keinem Gate, und mit M1 erfüllt läge IL in Aufgabe 1 bei 11 statt 10, also weiter über dem Pin. Wörtlich nach der registrierten Fassung gewertet, hält IH in B1 zwei von drei Läufen (nur der als sicher dargestellte Ergänzungsantrag zählt). Die Mediane der Aufgabe 7 lägen dann bei G 5, IL 6 und IH 6, wenn man B3 auch für erschließbare Begriffe streng zählt. Die Rangfolge bleibt.

4. **Regel 4 nicht angewandt.** Gate D liegt knapp (14 gegen 15), und H1 hängt je an einem Lauf. Die Empfehlung hängt aber an keinem der beiden: K schließt beide Arme mit Faktor 4 bzw. 10 aus. Eine Nachmessung auf n = 5 hätte daran nichts geändert.
5. **Fehlende Messwerte im generierten Bericht.** `REPORT.md` meldet für IL und IH fehlende Drafter-Zeilen und deshalb „unvollständige Log-Requests“. Die Arme laufen ohne Drafter; Prompt- und Eval-Zeiten sind für jeden Request vorhanden (nachgeprüft).

## Grenzen

- n = 3 bei Temperatur 1,0. Einzelne Fehlerklassen (Befunde 4 und 5) liegen bei einem Fall je Arm.
- Die Blindbewertung, auch die des Deutschen, lag bei der Session, die den Harness gebaut hat, einem Sprachmodell. Die Verblindung ist nicht perfekt: Die drei Texte des Pins je Aufgabe sind einander so ähnlich, dass sie als Gruppe erkennbar waren, und der Entwicklungslauf hatte den Pin in Aufgabe 7 gezeigt. Dazu kommt, was die Pre-Registration nicht nennt: Der Vorab-Check stellte jedem Arm eine deutsche Probefrage (was ein Eigenanteil ist), die Session kannte also vor der Bewertung je eine kurze deutsche Antwort von G, IL und IH. Während der Läufe waren nur Rundenwechsel und Prüfergebnisse sichtbar, keine Texte. Eine Zweitbewertung durch einen Menschen auf den Kopien unter `main/blind/` würde das absichern.
- Gemessen ist nur ein M1 Max. Auf neuerer Hardware mit mehr Speicherbandbreite verschiebt sich das Verhältnis der Geschwindigkeiten möglicherweise. Der Hersteller zeigt Inkling auf einem „MacBook Pro (M5 Pro, 48GB)“ ([Blog](https://thinkingmachines.ai/news/inkling-2-mini/), abgerufen am 25.11.2026).
- Der Pin lief auf b12720, nicht auf dem Binary der Instanz. Seine Gesamtdauer für die fünf Aufgaben aus #285 (rund 92 s ohne Aufgabe 7) liegt nahe am Wert aus F4 (86 s auf 0.7.0).
- pis Default-System-Prompt, nicht der komki-Produktiv-Prompt; die Skills (`sitzungsvorbereitung`, `bericht_aus_dem_stadtrat`) waren nicht geladen.

## Empfehlung

**Nach der registrierten Regel:** Kein Inkling-Arm besteht alle Gates. IL scheitert an H1, D, K und R1, IH zusätzlich an H2 und Q. Die Regel lautet: **Pin behalten.**

**Inhaltlich** komme ich zum selben Ergebnis. Begründung:

1. Für interaktive Ratsarbeit auf dem M1 Max ist Inkling zu langsam. Selbst auf der Stufe low dauert dieselbe Arbeit viermal so lange, und die erste sichtbare Antwort kommt nach fast 4 statt nach 0,8 Sekunden.
2. Beim Deutsch, um das es in diesem Ticket ausdrücklich ging, liegt der Pin vorn: Er schreibt fehlerfrei und korrigiert sogar den Fehler der Vorlage. Inkling schreibt flüssig, aber mit vereinzelten Grammatikfehlern und schiefen Wendungen. Die Warnung der Modellkarte („Output quality can be lower outside English“) bestätigt sich in milder Form.
3. Inklings Stärke liegt beim Inhalt: Es lässt den Eigenanteil nicht weg und erfindet in der Bürgerinformation nichts. Das spricht nicht für einen Wechsel, aber gegen die Annahme, der Pin sei inhaltlich unbedenklich.

**Daraus folgt ein Vorschlag unabhängig vom Modell:** Der Pin erfindet in freien Bürgertexten Ziele und Wertungen und stellt Vorhaben als beschlossen dar, in jedem der drei Läufe. Für Skills, die für die Öffentlichkeit schreiben (etwa `bericht_aus_dem_stadtrat`), wäre ein Prüfpunkt „Beratungsstand nennen, nichts begründen oder bewerten, was die Vorlage nicht begründet oder bewertet“ der nächste Schritt. Das wäre ein eigenes Ticket.

Neu bewerten lohnt sich, wenn Inkling auf der Zielhardware deutlich schneller läuft (neuere Apple-Chips, ein gemergter und schnellerer Drafter) oder wenn ein Inkling-Modell mit ausgewiesener Deutsch-Unterstützung erscheint. Die Entscheidung über den Pin trifft die nutzende Person. Dieses Ticket pinnt nichts um.

## Reproduktion

```bash
cd apps/komki_cli/experiments/pi_packages
export KOMKI_PI_EXPERIMENTS_DIR=$TMPDIR/komki-pi-experiments
export KOMKI_PI_CLI=/opt/homebrew/Cellar/komki/0.1.0/libexec/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js

# llama.cpp b12720 neben dem Homebrew-Pin (Digest gegen GitHub prüfen)
mkdir -p $KOMKI_PI_EXPERIMENTS_DIR/downloads/b12720 && cd $_
curl -fLO https://github.com/ggml-org/llama.cpp/releases/download/b12720/llama-b12720-bin-macos-arm64.tar.gz
shasum -a 256 llama-b12720-bin-macos-arm64.tar.gz   # 42d569fe…8668ca3a3
tar xzf llama-b12720-bin-macos-arm64.tar.gz && cd -

# Inkling stagen (Revision, SHA-256: smoke/ab-arms.mjs)
node smoke/stage-gguf.mjs --repo unsloth/Inkling-2-Mini-GGUF \
  --revision 8078d149286eec7193795413b9e0643da6d11fa1 \
  --file Inkling-2-Mini-UD-Q4_K_XL.gguf \
  --sha256 e64276656f072e9b2197a61723667cbdb71da66a716ffd966e572c21088f3cd3

R=$KOMKI_PI_EXPERIMENTS_DIR/ab-642/main
node smoke/run-ab.mjs --root $R --arms G,IL,IH --preflight
node smoke/run-ab.mjs --root $R --arms G,IL,IH --runs 3 --only 1,2,3,4,6,7 \
  --timeout-factor 6 --seed-base 642000
node smoke/grade-ab.mjs blind --root $R     # dann blind/grades.json ausfüllen
node smoke/grade-ab.mjs report --root $R --reference G
```
