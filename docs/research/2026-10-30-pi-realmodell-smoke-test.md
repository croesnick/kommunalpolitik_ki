# Labbook: Realmodell-Smoke-Test — pi 1.4.0 + Gemma 4 26B

- **Status:** abgeschlossen, 2026-10-30 (Ticket #158)
- **Gehört zu:** [RFC 0005: Pi-Packages im KomKI-Harness](../rfcs/0005-pi-packages.md)
- **Vorgänger:** [Labbook: Pi-Packages für KomKI](2026-10-24-pi-package-experiments.md) (Mock-Provider)
- **Harness:** `apps/komki_cli/experiments/pi_packages/smoke/`

## Ziel und Abgrenzung

Die Mock-Experimente vom 24.10. haben Mechanik und Grenzen der Packages belegt — nicht das Verhalten des echten Modells. Dieser Smoke-Test läuft gegen den llama-server der komki-Live-Instanz und misst: Laufen die fünf Aufgaben (oder welcher Fehler tritt auf), Latenz, Tool-Call-Fehler, Reparaturbedarf, Token, Speicher. Er ersetzt keine systematische Qualitätsbewertung des Modells; wo der Smoke eine Qualitätslücke zeigte (Aufgabe 1), folgt ein eigener Benchmark gegen explizit definiertes gewünschtes Verhalten.

## Umgebung

| Feld | Wert |
|---|---|
| pi | 1.4.0 (`@earendil-works/pi-coding-agent`) |
| Node | 24.22.1 |
| Plattform | macOS 27.2, arm64 |
| llama-server | 0.7.0 (build 11669, Homebrew), gestartet von `komki up` unter `profile/llama-server.sb` |
| Modell | Gemma 4 26B-A4B-it, `gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf`, 131 072 Kontext, `--alias local-model` |
| Sampling | Server-Defaults der Instanz: temp 1.0, top-p 0.95, top-k 64 |
| API-Key | Ja (`/props` ohne Key: 401); pi erhält ihn über seine `models.json`, Requests laufen 200 |
| pi-Konfiguration | `contextWindow` je Aufgabe (131 072; Aufgabe 6: 16 384), `maxTokens` 16 384 (pis Produktiv-Default, `provider-composer.js`), pis Default-System-Prompt wie in den Mock-Experimenten |
| Packages | `@juicesharp/rpiv-todo` 2.15.0, `@juicesharp/rpiv-ask-user-question` 2.15.0 (pnpm, `--ignore-scripts`; GO vom 30.10. im Ticket) |
| Messweg | Logging-Forward-Proxy (`lib/provider.mjs`) zwischen pi und llama-server: Wandzeit, `usage` (inkl. `cached_tokens`), `finishReason`, Tool-Calls je Request; dazu llama-Log-Segmente (Tokens, t/s) und `ps`-RSS |

Dokumentierter Endlauf (alle Aufgaben, TUI und Benchmark im selben Laufverzeichnis):
`$TMPDIR/komki-pi-experiments/runs/2026-10-30T05-32-05-567Z/`. Die Rohartefakte sind nicht Teil des Repos. Der Endlauf lief mit dem nach Review bereinigten Harness (UTF-8-sicherer Proxy, Log-Abschluss auf allen Fehler- und Abrisspfaden, robustere Tool-Argument-Klassifikation, Datum-toleranter Faktenabgleich); die Vorläufe des Tages dienten der Harness-Entwicklung und sind als solche gekennzeichnet. 53 Request-Log-Datensätze des Endlaufs enthalten null U+FFFD-Zeichen; der Logfenster-Abgleich (`serverRequestCountMismatch`) zeigt in jeder Aufgabe, dass kein fremder Client des geteilten Live-Servers in die Messung gefallen ist.

## Methode

Jede Aufgabe läuft in einer eigenen isolierten `PI_CODING_AGENT_DIR`-Instanz mit deutschem Prompt und eigener Proxy-Instanz. Aufgabe 5 läuft interaktiv unter tmux (120×40, `send-keys`). Aufgabe 6 erzwingt die Standard-Compaction über ein verkleinertes Fenster — die Parameter-Übertragung vom Mock-Experiment 04 ist selbst ein Befund (siehe Mechanikbefunde). Ein Lauf je Aufgabe; bei temp 1.0 ist das Modell nicht deterministisch — Aufgabe 1 lief an sechs Tagenpunkten mit konsistentem Qualitätsbefund und bekam deshalb einen eigenen Benchmark mit je drei Läufen je Prompt-Variante. Varianz wird benannt, nicht weggemittelt.

Jeden Tool-Call validiert der Harness gegen die JSON-Schemata aus den aufgezeichneten Requests. Das ergibt den Fehlerkorpus für die `pi-tool-repair`-Bewertung.

## Ergebnisübersicht

6/6 Läufe enden fehlerfrei (Exit 0, kein Timeout). Fünf Verdikte PASS; Aufgabe 1 FAIL im Smoke — mit laufender Mechanik, aber unvollständiger Zusammenfassung. Der Benchmark danach belegt: kein Modelldefizit, sondern Prompt-Sensitivität — unter spec-explizitem Prompt ist das Ergebnis 3/3 vollständig.

| Aufgabe | Verdikt | Kurzbefund |
|---|---|---|
| 1 — RIS-TOP zusammenfassen | **FAIL** (natürlicher Prompt) | `read`-Call sauber; Zusammenfassung lässt Eigenanteil 80 000 € und Vorhabensnamen weg — in jedem natürlichen Prompt-Lauf des Tages. |
| 1b — TOP-Benchmark (A/B, je 3 Läufe) | **PASS** | Variante A: 0/3 vollständig (K6 Finanzierungsstruktur fehlt 3/3). Variante B (explizit): 3/3 vollständig, K8 sauber. |
| 2 — Quellen extrahieren | **PASS** | `quellen.json` mit 6 Einträgen; `Quelle`/`Abrufdatum`/`Seite` korrekt, `null`-Behandlung funktioniert. |
| 3 — Text redigieren | **PASS** | 276 → 101 Wörter, kein Fakt verloren (Zahl-/Paragrafen-/Datumsabgleich, prosaische Datumsumschreibung zählt als erhalten). |
| 4 — Todo-Workflow | **PASS** | 4 Aufgaben in einem Batch-`create`, 13 Tool-Calls mit korrekten Zustandsübergängen, Zustand persistiert, `--continue` listet alles als `completed`. |
| 5 — `ask_user_question` im TUI | **PASS** | Dialog nach 26 s mit deutscher Frage und vier Optionen; Taste 1 wählt, die Antwort erreicht das Modell über die Tool-Result-Nachricht, sauberer Exit per Ctrl+D. |
| 6 — Compaction-Experiment | **PASS** | Compaction löst aus (2 Summary-Requests, zusammen 85,9 s); Summary auf Englisch, deutsche Präferenz überlebt semantisch; nach `--continue` antwortet das Modell auf Deutsch und erinnert beide Regeln — inklusive Quellenangabe. |

## Messwerte (Endlauf)

| Aufgabe | Wandzeit | Requests | Tokens (Prompt/Completion) | Tool-Calls (davon invalid) | t/s (llama-Log) |
|---|---|---|---|---|---|
| 1 | 5,4 s | 2 | 2 207 / 135 | 1 (0) | 50–55 |
| 2 | 16,9 s | 3 | 4 616 / 457 | 2 (0) | 40–46 |
| 3 | 77,1 s | 4 | 11 089 / 2 629 | 3 (0) | 35–38 |
| 4 | 53,6 s | 15 | 48 535 / 1 314 | 13 (0) | 34–39 |
| 5 (TUI) | 51,7 s (Dialog 25,6 s, Antwort 24,6 s) | 3 | 7 113 / 1 570 | 2 (0) | – |
| 6 | 170,0 s | 5 | 14 846 / 3 935 | 1 (0) | 33–37 |
| Benchmark 1b | 6 Läufe à 5–30 s | 12 | – | 6 (0) | – |
| Σ (ohne Benchmark) | ~375 s | 32 | 88 406 / 10 040 | 22 (0) | 33–56 |

- **Latenz:** 33–56 Tokens/s Eval über alle 24 gemessten Requests (llama-Log-Segmente; Aufgabe 5 ohne Log-Segment). Der Prefix-Cache wirkt sichtbar (`cached_tokens`: im Endlauf 355 von 847 Prompt-Tokens schon beim Erstrequest von Aufgabe 1, 842 von 1 360 im Folge-Request — der Slot-Präfix der Live-Instanz ist warm).
- **Speicher:** `ps`-RSS des llama-server stieg über den Endlauf von 2,5 auf 8,0 GiB und lag danach bei 5,2 GiB (macOS purged ungenutzte Seiten). Richtwert mit Vorbehalt: Der Großteil der Gewichte liegt im Metal-/GPU-Speicher und wird in RSS nicht vollständig erfasst.
- **Fehlerkorpus:** 22 Tool-Calls im Endlauf, alle valide, kein Retry, null Request-Log-Parse-Fehler. Über alle Läufe des Tages (Endlauf, Vorläufe, Benchmark — 89 Calls): genau ein invalid-Call (Längentruncation, Vorlauf) und **null Alias-Fehler**.
- **Session-Usage:** pi verbucht eigene Input-Zahlen; die Proxy-Usage ist die llama-Sicht und maßgeblich.

## Fehlerbild und Reparaturbedarf

- **Kein einziger Alias-Fehler** (`file_path` statt `path` o. ä.) in irgendeinem Lauf. `read`, `write`, `todo` und `ask_user_question` wurden durchgehend mit korrekten Argumenten gerufen, `todo` auch mit Optionalfeldern (`activeForm`, Batch-`tasks`).
- **Vorlauf, 1 Truncation-Fehler (einziger invalid-Call des Tages):** Der `write` von `quellen.json` in Aufgabe 2 schnitt am Output-Limit ab, das der Harness damals auf 4 096 gesetzt hatte. pi hat die truncierten Argumente erkannt und die Ausführung verweigert (In-Band-Fehler: „the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call“). Das Modell hat den Call daraufhin selbstständig vollständig wiederholt — der zweite Versuch schrieb die Datei korrekt. Der Endlauf mit pis Produktiv-Default 16 384 zeigte den Fehler nicht. Zwei Lehren: (a) pi fängt trunierte Tool-Argumente fail-safe ab, das Modell repariert sich selbst — `pi-tool-repair` war an keiner Stelle nötig; (b) ein zu knappes `maxTokens` in `models.json` erzeugt genau diese Fehlerklasse — die Produktiv-Instanz trägt das richtige Default.

## Mechanikbefunde (pi 1.4.0, Quelltext gelesen am 30.10.2026)

1. **Output-Klemme mit festem Sicherheitsabstand.** pi sendet `max_completion_tokens = min(maxTokens, max(1, contextWindow − est(Kontext) − 4096))` (`clampMaxTokensToContext`, `CONTEXT_SAFETY_TOKENS = 4096`, Schätzer `chars/4`). Bei `contextWindow: 1000` — den Parametern des Mock-Experiments 04 — kollabiert jedes Budget auf 1 Token: Antworten und Compaction-Summary brechen mit `finishReason: length` ab, der Mock bemerkt das nie, weil er `max_completion_tokens` ignoriert. Für echte Läufe muss das Fenster grob `benötigter Output + est(Kontext) + 4096` hergeben; das Compaction-Experiment lief daher mit 16 384. Für die Produktiv-Instanz (131 072) ist das unkritisch.
2. **`keepRecentTokens` erzwingt keine Eintragsgrenze.** Ein 32-KB-Read-Result (≈ 8 700 Tokens) überlebte die Compaction vollständig im Keep-Schwanz, obwohl `keepRecentTokens: 512` konfiguriert war — pi behält ganze Einträge, ein Tool-Result wird nicht mittendin abgeschnitten. In einem Vorlauf fraß der erhaltene Eintrag das gesamte Output-Budget (Request geklemmt auf 1 Token, leere Antwort); erst eine zweite Compaction-Runde schuf wieder Raum. Produktion: relevant erst ab Tool-Results jenseits von ~120 000 Tokens — für Ratsarbeit-Dateien kaum erreichbar, aber beim Ingest sehr großer Dokumente im Hinterkopf zu behalten.
3. **Auto-Compaction nimmt keine eigenen Anweisungen an.** Manuelles `/compact` reicht `customInstructions` durch (`agent-session.js:2287`), die automatische Compaction übergibt fest `undefined` (`agent-session.js:2578`).
4. **Sprachdrift durch die Compaction.** pis Summarization-Prompt ist englisch und sprachneutral; Gemma fasst die deutsche Sitzung auf Englisch zusammen. Der Inhalt überlebt semantisch, die Antwortsprache driftet, bis ein deutscher Nutzer-Prompt zurückankert (Aufgabe 6: Resume-Antwort wieder auf Deutsch). Deutschsprachige Summaries ließen sich nur über Compact-Instructions erzwingen — die die Auto-Compaction (pi 1.4.0) nicht annimmt (Befund 3). Das ist der konkrete Hebel für [#159](https://github.com/croesnick/kommunalpolitik_ki/issues/159).

## Einzelresultate

### 1 — RIS-TOP zusammenfassen (synthetisch) und Benchmark

`read` mit `{"path":"top-3-anhoerung.md"}` beim ersten Versuch, korrekt — in jedem Lauf. Die Zusammenfassungen unter dem natürlichen Prompt („Nenne Gremium, Sitzungsdatum, Kostenschätzung und Beschlussvorschlag“) nennen Gremium, Datum, 240 000 € und Beschlussvorschlag, lassen aber den **Eigenanteil von 80 000 €** weg — in jedem der sechs Läufe, einmal zusätzlich den Vorhabensnamen. Smoke-Verdikt FAIL: Mechanik einwandfrei, Qualitätslücke konsistent.

Deshalb ein Benchmark gegen explizit definiertes gewünschtes Verhalten, abgeleitet aus der Sitzungsmappe-Vorlage des Skills `sitzungsvorbereitung` (Gremium, Datum, Gegenstand, „was die Vorlage will“, Beschlussvorschlag; Finanzierungs-TOPs sind im Workflow erster Klasse) und der Quellenpflicht (AGENTS.md §6). Muss-Kriterien: K1 Gremium, K2 Datum, K3 Vorhaben, K4 Anliegen, K5 Gesamtkosten, **K6 Finanzierungsstruktur** (der Rat beschließt über den Eigenanteil; der Beschlussvorschlag meldet ihn zur Haushaltsplanung), K7 Beschlussvorschlag, K8 keine erfundenen Zahlen (arithmetisch abgeleitete werden protokolliert, aber toleriert).

- **Variante A (natürlicher Prompt), 3 Läufe:** 0/3 vollständig — K6 fehlt 3/3, alles andere besteht.
- **Variante B (Prompt fordert Vorhaben und Aufteilung explizit), 3 Läufe:** 3/3 vollständig; als Förderanteil erscheint jeweils 160 000 (= 240 000 − 80 000), korrekt als abgeleitet statt erfunden klassifiziert.

Ergebnis: **kein Modelldefizit, sondern Prompt-Sensitivität.** Das Modell kann jede Muss-Anforderung, wenn der Prompt sie verlangt. Konsequenz für die Ratsarbeit: Die Vollständigkeit von TOP-Zusammenfassungen muss auf der Instruktions-Ebene eingefordert werden — der `sitzungsvorbereitung`-Skill bekommt die Kriterienliste (folgt in diesem PR), die Produktivintegration (#155) muss sie in Session-Vorlagen bzw. Systemprompt tragen.

### 2 — Quellen extrahieren

Sechs Quellen als JSON-Array in `quellen.json`: URL-Angaben, Gutachten mit Auftragsnummer, Amtsblatt; `Abrufdatum` nur wo im Text, `Seite` nur wo angegeben, sonst `null` — die bedingten Felder sauber behandelt.

### 3 — Deutscher Text redigieren

276 → 101 Wörter. Faktenabgleich (Zahlen, Paragrafen, Hausnummern, Daten als eigene Einheiten — „3. Februar 2027" gilt als erhaltene Form von „03.02.2027"): kein Verlust. Beobachtung am Rand: Das Modell wechselte die Perspektive von Ich-Form zu Drittperson — sprachlich legitim, faktlich neutral, für GO-relevante Texte aber eine Review-relevante Änderung.

### 4 — Todo-Workflow über mehrere Schritte

Das Modell legte alle vier Aufgaben (drei Notizen + Abschlussaufgabe) in **einem** `create`-Call als Batch an — ein Aufrufmuster, das die Allowlist-Mechanik von Experiment 01 nicht abbildete, aber schema-konform ist — und arbeitete sie sequenziell ab: `read` → `update` auf `in_progress` → `update` auf `completed`, je Notiz, plus Abschlussaufgabe. 15 Requests, 13 `todo`-Calls, null Fehler. Zustand als `rpiv-todo-state` persistiert; nach `--continue` listet das Modell alle vier Aufgaben mit Status `completed`. Der Workflow-Gedanke aus RFC 0005 („Ein 26B-Modell verliert bei langen Aufgaben den Plan“) trägt mit dem echten Modell.

### 5 — `ask_user_question` im interaktiven TUI

Das Modell entscheidet selbst, das Tool zu rufen (der Prompt nennt nur die unklare Prüftiefe). Dialog nach 26 s mit deutscher Frage („Wie tief soll ich die Drucksache für die Ausschusssitzung prüfen?“) und vier Optionen mit eigenen Beschreibungen („Oberflächlich (Quick Check)", „Umfassend" u. a.). Taste 1 wählt die erste Option, die Antwort landet im Session-Tool-Result und erreicht das Modell über die Tool-Result-Nachricht (im Folge-Request verifiziert, nicht über das Tool-Call-Echo), das Modell arbeitet die gewählte Prüfung ab, Ctrl+D beendet sauber. Vor dem Dialog zeigt das TUI gelegentlich kurze englische Selbstmonologzeilen — die Antwortqualität beeinträchtigt das nicht, für die Nutzererfahrung aber erwähnenswert.

### 6 — Compaction-Experiment (deutsche Präferenz)

Fenster 16 384, `reserveTokens: 8192`, `keepRecentTokens: 512`, 32-KB-Filler (Dimensionierung: siehe Mechanikbefund 1). Ablauf: `read`-Call → Compaction zwischen den Turns → finale Antwort über den erhaltenen Tool-Result → zweite Compaction. Zwei Summary-Requests, zusammen 85,9 s — das ist die echte Kostenlinie der Standard-Compaction mit dem 26B-Modell. Die Summary steht auf Englisch, enthält die Präferenz aber semantisch vollständig; nach `--continue` antwortet das Modell auf Deutsch („Du hast angewiesen, kurze Sätze zu verwenden und für jede faktische Aussage eine Quelle anzugeben (`summary`).“) — beide Regeln korrekt, kein zweiter Summary-Request nötig.

## Empfehlungen

### `pi-tool-repair`: nicht aufnehmen

Experiment 03 (Mock) hatte gezeigt: repariert wird nur der dokumentierte Alias `file_path` → `path`, kein beliebig geformter Call. Der echte Korpus liefert die Gegenprobe: 89 Tool-Calls über alle Läufe des Tages, **null** Alias-Fehler, null Schema-Verletzungen. Der einzige invalid-Call war Längentruncation — eine Klasse, die `pi-tool-repair` nicht adressiert, die aber pi selbst fail-safe abfängt und die das Modell ohne fremde Hilfe repariert. Kein belegbarer Nutzen, also keine Aufnahme. [#163](https://github.com/croesnick/kommunalpolitik_ki/issues/163) kann mit diesem Korpus weiterarbeiten: Gesucht sind Alias-Fehler aus echten Sitzungen; der Smoke-Test hat sie in dieser Aufgabenklasse nicht erzeugt.

### `pi-vcc`: nicht für deutsche Sitzungen

Experiment 04 (Mock) hatte gezeigt: die algorithmische Compaction spart den Summary-Call, verliert aber deutsche Präferenzen und Scope-Wechsel — modellunabhängig, denn die Extraktion läuft ohne LLM. Der echte Lauf liefert die fehlende Gegenseite: Die Standard-Compaction erhält die deutsche Präferenz semantisch und macht sie nach dem Resume abrufbar — zum Preis von zusammen 85,9 s Summary-Zeit in Aufgabe 6 (zwei Compactions). Dass die Summary dabei auf Englisch ausfällt (Mechanikbefund 4), ist eine Sprachfrage mit bekanntem Hebel (Compact-Instructions / #159), kein Inhaltsverlust. Die Einsparung von `pi-vcc` wiegt den Verlust deutscher Sitzungsinhalte nicht auf; die Alternative ist billiger zu haben.

## Nicht getestet

- Der KomKI-Produktiv-Kontext: Mediator/MCP-Tools, KomKI-System-Prompt, Workspace `arbeit` — der Smoke-Test läuft bewusst im Experiment-Harness mit pis Default-Prompt.
- Statistische Absicherung: ein Lauf je Aufgabe; Aufgabe 1 als Mehrfachlauf (Benchmark: 3+3) ist die Ausnahme.
- `pi-subagents` (D8-Pilot bleibt), `pi-context`, `pi-quiver`, `pi-hermes-memory` mit dem echten Modell.
- Compaction unter dem Produktivfenster (131 072) — ausgelöst wird sie dort erst bei sehr langen Sitzungen.
- Andere Sampling-Parameter (temp 0 für deterministischere Ausgaben etwa) und längere Sitzungen über Stunden.

## Reproduktion

```bash
komki up   # llama-server mit gepinntem GGUF und frischem API-Key
node apps/komki_cli/experiments/pi_packages/smoke/run-smoke.mjs              # 1,2,3,4,6
node apps/komki_cli/experiments/pi_packages/smoke/run-tui.mjs --root <root> # 5
node apps/komki_cli/experiments/pi_packages/smoke/run-top-bench.mjs --root <root>  # 1b
```

Vorbereitung (Vendor) und alle Optionen: [`smoke/README.md`](../../apps/komki_cli/experiments/pi_packages/smoke/README.md). Die Fixture-Texte sind synthetisch (Bahnhofstraße-Thema, frei erfunden); es wurden keine echten vertraulichen Daten verwendet.
