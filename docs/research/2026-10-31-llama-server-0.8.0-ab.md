# Labbook: llama-server-A/B — 0.7.0-Pin gegen 0.8.0

- **Status:** abgeschlossen, 2026-10-31 (Ticket #320). Nutzer-GO 31.10.2026: Lane starten, ohne auf den Merge von PR #319 zu warten — der Merge war um 16:07 Uhr durch; die Lane lief auf `origin/main` (`d191752`), also auf dem Stand nach #319 (`--reasoning off`).
- **Empfehlung:** 0.7.0-Pin behalten. 0.8.0 besteht alle registrierten Gates, bringt aber keinen messbaren Gewinn und dekodiert rund 6 % langsamer. Herleitung im Abschnitt [Empfehlung](#empfehlung).
- **Vorgänger:** [Labbook: Modell-A/B](2026-10-31-modell-ab.md) (#285: Protokoll, Gates, Checklisten, F4-Referenz), [Labbook: Realmodell-Smoke-Test](2026-10-30-pi-realmodell-smoke-test.md) (#158: Harness-Basis)
- **Harness:** `apps/komki_cli/experiments/pi_packages/smoke/` (`run-ab.mjs`, `grade-ab.mjs`), erweitert um eine Binär-Auswahl je Arm (`--bin`, Arme `V7`/`V8`)

## Ziel und Abgrenzung

Dieses A/B misst den llama-server-Wechsel von 0.7.0 (Build 11669, Homebrew-Pin, produktiv) auf 0.8.0 (Build 11960, Commit `8642541b2` — der Version-Bump-Commit des v0.8.0-Releases) unter der Produktivkonfiguration nach #319: Pin-GGUF plus MTP-Drafter, Thinking aus per `--reasoning off`, Gemma-Sampling, Kontext 131 072. Eine Variable: die Binärdatei.

Der Bericht liefert die Grundlage für ein GO der nutzenden Person zum Upgrade (brew, Re-Pin, Profil-Regeneration, Doku — alles Schritte nach diesem A/B). Dieses Ticket pinnt nichts um und ändert keine Instanz; die 0.8.0-Binärdatei liegt side-by-side im Experiment-Verzeichnis, nicht in Homebrew.

## Pre-Registration

Dieser Abschnitt ist vor dem ersten Messlauf committet. Checklisten und Gates stehen gleichlautend als Code in `smoke/grade-ab.mjs` (`MANUAL`, `QUELLEN_SOLL`) und `smoke/criteria.mjs` (K1–K8), unverändert aus #285. Neu ist nur, dass die Referenz der Gates parametrierbar ist (`--reference`, Default `A` wie in #285; dieses A/B übergibt `--reference V7`) — die Gate-Logik selbst ist unverändert. Nach den Messläufen ändert sich daran nichts.

### Arme

| Arm | Binärdatei | `--version` | SHA-256 |
|---|---|---|---|
| V7 — Pin | `/opt/homebrew/bin/llama-server` → `…/Cellar/llama.cpp/0.7.0/bin/llama-server`, identisch mit dem Binär-Pin der Live-Instanz | 0.7.0 (build 11669, commit `620d2225c`) | `fd5cb5a7974c1633c9f7e487908cc270094f8506d823523b16c4b3ed723eabde` |
| V8 — 0.8.0 | `$KOMKI_PI_EXPERIMENTS_DIR/downloads/b11960/llama-b11960/llama-server`, entpackt aus dem Release-Asset `llama-b11960-bin-macos-arm64.tar.gz` (GitHub-Digest `sha256:58e5a5e1d7c2bf66cedd9c29e0323f3e570660a70a1e2156d32eed08f4cc1e3c`, vor dem Entpacken abgeglichen) | 0.8.0-dev (build 11960, commit `8642541b2`) | `3d81b7997317e5ffd13ed3ba32436658e0f4067172cea3674b4215b39d4635be` |

Beide Arme laufen mit demselben GGUF-Paar — Pin `gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf`, `ef728c8e…0636e30c`, und Drafter `mtp-gemma-4-26B-A4B-it-Q8_0.gguf`, `6326fb9f…26d93ed1b`, jeweils vor jedem Lauf per SHA geprüft —, demselben Sampling (`--temp 1.0 --top-p 0.95 --top-k 64`), demselben Kontext `-c 131072` und denselben Extra-Flags: `--reasoning off --spec-type draft-mtp --spec-draft-n-max 4 --model-draft <drafter>`. Ports: V7 49619, V8 49620.

Zwei Hinweise zur Provenance:

- Das Nightly-Artefakt b11960 meldet sich als `0.8.0-dev`, obwohl sein Commit der Version-Bump des v0.8.0-Releases ist. Welchen String Homebrew beim GO einschenkt, ist dort zu prüfen; der Commit ist der Abgleichpunkt.
- Die Abkürzung `fd5cb5a7…21ded9d81` in Labbook #285 gibt einen Schwanz an, den der heutige Voll-Hash nicht hat. Die Live-Instanz pinnt exakt den oben stehenden Voll-Hash, und die Datei liefert ihn heute erneut — autoritativ ist `provenance.json` des jeweiligen Laufs.

### Messprotokoll

- **Eine Variable:** die Binärdatei. Gleich für alle Arme: Maschine, GGUFs (SHA-256 geprüft), Sampling, Server-Flagliste — inklusive `--no-webui`, das beide Builds laut `--help` annehmen (`--ui, --webui, --no-ui, --no-webui`, je identisch in 11669 und 11960; die Deprecation-Warnung steht in beiden Logs gleich an) —, Node, pi, Fixtures, Prompts, Logging-Proxy, Timeout-Faktor 6, Seed-Basis 320 000.
- **Preflight:** beide Builds laden das Pin-GGUF und den Drafter (`run-ab.mjs --preflight`). Scheitert V8, wird nicht gemessen, sondern der Befund dokumentiert.
- **Ablauf:** Runde 0 Warm-up (ungemessen), Runden 1–3 Messläufe, je Runde V7, V8 verzahnt. Jeder Lauf startet seinen Server frisch und beendet ihn danach — Ladezeit ist Messwert. Seed je Runde: 320 000 + Runde, beide Arme teilen ihn. Kein Lauf wiederholt einen Seed aus #285 (285 000er-Bereich).
- **Aufgaben:** 1, 2, 3, 4 und 6 aus #158/#285, Prompts und Fixtures unverändert. Aufgabe 5 (TUI) entfällt. Ein Task-Fehler ist ein Messwert.
- **Referenz:** V7 ist die Referenz, V8 der Kandidat.

### Messgrößen je Lauf

Wie in #285: Ladezeit, TTFT und erste sichtbare Antwort (Proxy), Decode-/Prefill-t/s (llama-Log), Prompt-/Completion-Token samt Thinking-Anteil (Proxy, `/tokenize`), Tool-Calls mit Schema-Validierung, Reparaturbedarf (distinkte `isError`-Results nach `toolCallId`), `phys_footprint` und RSS, finishReasons, Compaction-Verhalten (Aufgabe 6; der Triggerpunkt kann sich mit dem Tokenizer verschieben und wird nicht wegnormalisiert) — dazu die **draft acceptance** des MTP-Drafters aus dem llama-Log (Referenz: 0,62 aus der Sonde vom 31.10., 0,70 aus F3). Berichtet werden Median und Spanne über die drei Messläufe, keine Einzelwerte und keine Signifikanzaussagen.

### Sonde: gleicher Seed

Beide Arme einer Runde laufen auf demselben Seed. Nach F4-Beobachtung 2 garantiert das keine bytengleichen Antworten — GPU-Rechenreihenfolgen brechen die Gleichheit auch bei unveränderter Ausgabeverteilung. Der Textvergleich je Runde ist deshalb eine **Sonde, kein Gate**: bytengleiche Läufe wären ein starker Hinweis auf unveränderte Numerik; Abweichungen werden dokumentiert und fließen nur über die Blindbewertung in die Wertung ein.

### Blinde Qualitätsbewertung

Wie #285: `grade-ab.mjs blind` kopiert die Outputs der Aufgaben 1, 2 und 3 aller Messläufe unter Zufalls-IDs, mischt je Aufgabe, rechnet die automatischen Punkte vorab und hält den Schlüssel getrennt. Manuelle Bewertung nur an den verblindeten Kopien, Bewertung vor dem Lesen des Schlüssels abgeschlossen. Checklisten unverändert (Aufgabe 1: K1–K8 automatisch plus M1–M3 manuell; Aufgabe 2: Q0/Q9 plus je Soll-Quelle drei Punkte, vollautomatisch; Aufgabe 3: S1 automatisch, F0–F10 und S2–S5 manuell).

### Gates

| Gate | Art | Regel |
|---|---|---|
| H1 | hart | 0 Faktenänderungen (F0–F10) in Aufgabe 3, in jedem der drei Messläufe |
| H2 | hart | Reparaturrate ≤ V7; Reparaturrate = distinkte Fehlerfälle / alle Tool-Calls, gepoolt über alle Messläufe und Aufgaben |
| Q | Qualität | Median-Punktzahl ≥ V7 in mindestens 2 der 3 Textaufgaben (blind) |
| Regel 1 | hart | V8 scheitert (Verdikt `fail` oder Timeout) in den Aufgaben 1–4 und 6 nicht häufiger als V7 |
| — | Kosten | t/s, TTFT, Ladezeit, Gesamtdauer und Speicher werden berichtet, kein K.-o. |

### Entscheidungsregel

1. V8 wird nur dann zum Upgrade empfohlen, wenn es H1, H2, Q und Regel 1 besteht.
2. Tempo und Speicher werden als Kosten/Nutzen berichtet; sie entscheiden nicht allein.
3. Scheitert V8 an einem Gate, bleibt es beim Pin; der Befund steht in diesem Labbook und im Ticket.
4. Das Upgrade selbst (brew, Re-Pin, Profil-Regeneration, Doku-Pflege) läuft nur nach ausdrücklichem GO der nutzenden Person.

## Ablauf

| Schritt | Zeit (31.10.2026, MEZ) | Verzeichnis unter `$TMPDIR/komki-pi-experiments/ab-320/` |
|---|---|---|
| 0.8.0-Bundle geladen, Tarball-SHA-256 gegen die GitHub-Digest geprüft, entpackt | 19:08 | `downloads/b11960/` |
| Pre-Registration committet | 19:14 | Commit `c7e8b1c`, Arbeitsbaum sauber — der Hauptlauf lief auf genau diesem Stand |
| Preflight-Check V7, V8 | 19:15 | `main/preflight/V7|V8/` (V7 4,3 s, V8 8,9 s) |
| Hauptlauf: Warm-up + 3 Runden × 2 Arme, verzahnt | 19:16–19:29 | `main/` (`schedule.json`, `provenance.json`, `REPORT.md`) |
| Blindbewertung, Entblindung | 19:31–19:34 | `main/blind/`, `main/blind-key.json` |

Abweichungen vom Protokoll: keine. Die Rohdaten (Request-Mitschnitte, Sessions, Server-Logs, Blindkopien) liegen nur in diesen Verzeichnissen und sind nicht Teil des Repos.

## Umgebung und Provenance

| Feld | Wert |
|---|---|
| Hardware | MacBookPro18,4, Apple M1 Max, 64 GB, Netzbetrieb, in keinem Lauf eine Thermik- oder Leistungswarnung (`pmset -g therm`) |
| macOS | 27.2 (26B5101f) |
| Node, pi | 24.22.1 (asdf), pi 1.4.0 |
| Git-Stand | `c7e8b1c` (Pre-Registration), sauber |
| V7-Binärdatei | `/opt/homebrew/Cellar/llama.cpp/0.7.0/bin/llama-server` — 0.7.0 (build 11669, `620d2225c`), identisch mit dem Pin der Live-Instanz |
| V8-Binärdatei | `downloads/b11960/llama-b11960/llama-server` — 0.8.0-dev (build 11960, `8642541b2`), SHA-256 `3d81b799…4635be`, aus dem geprüften Release-Asset entpackt |
| GGUF, Drafter | Pin `gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf` (`ef728c8e…`), Drafter `mtp-gemma-4-26B-A4B-it-Q8_0.gguf` (`6326fb9f…`) — vor jedem Lauf geprüft |
| Störgrößen | Live-Instanz (Port 49524) und eine #318-Wegwerf-Instanz (Port 49621) liefen idle mit; Swap ~29 GB belegt, weitgehend stabil. Das Interleaving verteilt Resteffekte gleich auf beide Arme. |

## Ergebnisübersicht

V8 besteht alle registrierten Gates gegen V7 — aber ohne jeden messbaren Gewinn.

### Gates

| Gate | V7 (Referenz) | V8 (0.8.0) |
|---|---|---|
| H1 0 Faktenänderungen (A3, jeder Lauf) | 0 / 0 / 0 | 0 / 0 / 0 → bestanden |
| H2 Reparaturrate ≤ Referenz | 0 von 49 (0 %) | 0 von 48 (0 %) → bestanden |
| Q Median ≥ Referenz in ≥ 2 von 3 Textaufgaben | Referenz | Aufgaben 1–3, überall Gleichstand → bestanden |
| Regel 1 kein zusätzlicher `fail`/Timeout | 0 | 0 → bestanden |

### Qualität (blind, Median und Spanne)

| Aufgabe | V7 | V8 |
|---|---|---|
| 1 — TOP-Zusammenfassung (von 11) | 10 (10–10) | 10 (10–10) |
| 2 — Quellen (von 20) | 20 (20–20) | 20 (20–20) |
| 3 — Redigieren (von 16) | 15 (15–15) | 15 (15–15) |

Alle 18 bewerteten Outputs liegen auf denselben Punktzahlen. Einziges Verfehlten ist überall S4 („kann gedeckt werden" wird zu „wird gedeckt/finanziert") — derselbe Befund wie in #285 (dort Befund 7), ohne Unterschied zwischen den Builds.

### Leistung (Median und Spanne über 3 Messläufe, Aufgaben 1–4 und 6)

| Messgröße | V7 (0.7.0) | V8 (0.8.0) |
|---|---|---|
| Ladezeit | 3,5 s (3,5–3,5) | 2,5 s (2,5–2,5) |
| Gesamtdauer | 89 s (88–97) | 91 s (91–96) |
| Decode | 59,6 t/s (59,2–59,8) | 56,1 t/s (56,0–56,4) |
| Prefill | 405 t/s (399–408) | 400 t/s (397–402) |
| TTFT = erste sichtbare Antwort (ohne Thinking) | 825 ms (737–876) | 877 ms (860–882) |
| Thinking-Token | 0 | 0 |
| draft acceptance (gepoolt) | 0,710 (4 428 von 6 240) | 0,708 (4 347 von 6 140) |
| `phys_footprint` max | 14,5 GiB (12,9–16,4) | 13,5 GiB (13,0–17,3) |
| Tool-Calls / invalide / Reparaturen | 49 / 0 / 0 | 48 / 0 / 0 |
| repetition loops / längengeklemmte Requests | 0 / 0 | 0 / 0 |

Prüfergebnisse je Aufgabe: in beiden Armen und allen Läufen identisch — Aufgabe 1 `partial` in allen sechs Läufen (Eigenanteil fehlt, bekannter Befund aus #158/#285), Aufgaben 2, 3, 4 und 6 überall `pass`.

### Sonde: gleicher Seed

| Artefakt | Runden mit Bytengleichheit V7 = V8 |
|---|---|
| `quellen.json` (Aufgabe 2) | 3 von 3 |
| TOP-Antwort (Aufgabe 1) | 1 von 3 (Runde 2; Runden 1 und 3 mit Formulierungsunterschieden) |
| `neue-fassung.md` (Aufgabe 3) | 0 von 3 (Formulierungsunterschiede, alle Fakten identisch) |

Wie in F4-Beobachtung 2 garantiert gleicher Seed keine Bytengleichheit — GPU-Rechenreihenfolgen brechen sie auch bei unveränderter Verteilung. Dass vier von neun Artefakt-Paaren trotzdem bytengleich sind und die übrigen nur in Kleinigkeiten abweichen, ist ein Hinweis, dass die 0.8.0-Numerik für dieses Setup nahe an 0.7.0 liegt. Mehr kann eine n=3-Sonde nicht zeigen.

## Befunde

1. **0.8.0 ist voll kompatibel zur Produktivkonfiguration.** Der Build akzeptiert die exakte Flagliste (inklusive `--no-webui`, `--reasoning off`, `--spec-type draft-mtp --spec-draft-n-max 4 --model-draft`); Preflight und alle acht Läufe liefen ohne Einschränkung. Die `--no-webui`-Zeile steht in beiden Logs identisch (Info, kein Fehler); der Wechsel auf `--no-ui` bleibt ein eigener, zu vermessender Schritt (PR #319, „bewusst offen").
2. **Verhalten ununterscheidbar.** Thinking bleibt aus (0 Token überall), die draft acceptance liegt mit 0,708 quasi auf 0,710 (Referenzband 0,62–0,70 aus #318/#285), Qualität und Prüfergebnisse sind identisch.
3. **Kein Tempo-Gewinn — ein kleiner Decode-Nachteil.** V8 dekodiert stabilerweise in allen Runden langsamer (56,0–56,4 gegen 59,2–59,8 t/s; Median −5,9 %), die Gesamtdauer gleicht das fast aus (91 gegen 89 s), der Prefill ist gleich. Einziger messbarer Vorteil: die Ladezeit (2,5 gegen 3,5 s — Vokabular-Laden, llama/30679). Für den Agentenalltag mit langen Sitzungen wiegt der Decode mehr als der Start.
4. **Speicher ohne belastbaren Unterschied.** V8s footprint-max tendiert niedriger (13,5 gegen 14,5 GiB), die Spannen überlappen bei n = 3.

## Empfehlung

Formal besteht V8 alle registrierten Gates — die Regel ließe ein Upgrade zu. Inhaltlich gibt es aber keinen Grund: gleiche Qualität, gleiches Verhalten, gleiche Annahmequote, und im Decode rund 6 % langsamer. **Empfehlung: den 0.7.0-Pin behalten, 0.8.0 nicht übernehmen.** Die Changelog-Kandidaten (Metal-/MoE-Fixes, `no_alloc`-Arbeit) schlagen sich in dieser Konfiguration nicht in messbaren Vorteilen nieder. Die kurz nach dem Release gelandeten Builds b12007 (RoPE-Konstanten auf die GPU — könnte den 128K-Prefill bringen) und b12008 (Gemma-tied-Embedding-Puffer) sind nicht Teil von 0.8.0 und bleiben Kandidaten für die nächste Messung, ebenso ein mögliches 0.8.x mit Decode-Korrekturen. Das Setup dafür steht: Arme V7/V8, `--bin` je Arm und `--reference V7` sind im Harness.

Die Entscheidung trifft die nutzende Person. Dieses Ticket pinnt nichts um; die Live-Instanz läuft unverändert auf 0.7.0.

## Grenzen

- n = 3 bei temp 1,0: Der Decode-Unterschied ist über alle Runden stabil und ohne Spannenüberlappung, aber klein; die Qualitätsgleichstände lösen keine Differenzen auf.
- Die Blindbewertung lag bei derselben Session, die die Arme ergänzt hat; sie arbeitete nur an den verblindeten Kopien vor dem Lesen des Schlüssels. Da alle Bewertungen auf Inhalt fielen und einheitlich ausfielen, ist die Verblindung hier unkritisch — perfekt war sie ohnehin nie (#285, Grenzen).
- Gemessen wurde das Nightly-Artefakt b11960 des Release-Commits; ein Homebrew-Build desselben Commits kann andere Compiler-Flags tragen (der AppleClang-Buildstring unterscheidet sich schon). Die Empfehlung gilt für diesen Build; ein Build, den Homebrew später einschenkt, wäre beim GO noch einmal zu vermessen.

## Reproduktion

```bash
cd apps/komki_cli/experiments/pi_packages
R=$TMPDIR/komki-pi-experiments/ab-320/main
node smoke/run-ab.mjs --root $R --arms V7,V8 --preflight
node smoke/run-ab.mjs --root $R --arms V7,V8 --runs 3 --timeout-factor 6 --seed-base 320000
node smoke/grade-ab.mjs blind --root $R     # dann blind/grades.json ausfüllen
node smoke/grade-ab.mjs report --root $R --reference V7
```

Node 24.22.1 über asdf. Die committete `.tool-versions` nennt nodejs 24.22.2, das lokal nicht installiert ist; die Läufe laufen auf der installierten 24.22.1 — demselben Node wie in allen #285-Messungen.
