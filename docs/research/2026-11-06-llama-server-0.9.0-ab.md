# Labbook: llama-server-A/B — 0.7.0-Pin gegen 0.9.0 (mit 0.8.0 als Vergleich)

- **Status:** gemessen, 2026-11-06 (Ticket #372). Die Pre-Registration ist unverändert; die Ergebnisse stehen ab [Ergebnisübersicht](#ergebnisübersicht).
- **Empfehlung:** 0.7.0-Pin vorerst behalten. V9 besteht alle registrierten Gates, bringt aber außer der Ladezeit keinen belastbaren Gewinn. Herleitung und Abwägung im Abschnitt [Empfehlung](#empfehlung). Die Entscheidung trifft die nutzende Person.
- **Vorgänger:** [Labbook: llama-server-A/B 0.7.0 gegen 0.8.0](2026-10-31-llama-server-0.8.0-ab.md) (#320: Arme V7/V8, Empfehlung „Pin behalten“), [Labbook: Modell-A/B](2026-10-31-modell-ab.md) (#285: Protokoll, Gates, Checklisten)
- **Harness:** `apps/komki_cli/experiments/pi_packages/smoke/` (`run-ab.mjs`, `grade-ab.mjs`), erweitert um den Arm `V9` und die draft acceptance im Bericht

## Ziel und Abgrenzung

Dieses A/B misst den llama-server-Wechsel von 0.7.0 (Build 11669, Homebrew-Pin, produktiv) auf 0.9.0 (Build 12110, Commit `cd959bae9`, der Version-Bump-Commit des v0.9.0-Releases vom 04.11.2026) unter der Produktivkonfiguration: Pin-GGUF plus MTP-Drafter, Thinking aus per `--reasoning off`, Gemma-Sampling, Kontext 131 072. Eine Variable: die Binärdatei.

0.8.0 (b11960) läuft als dritter Arm mit, rein beschreibend. Er zeigt, ob der Decode-Rückstand aus #320 (−5,9 % gegen 0.7.0) an einem neuen Tag wieder auftritt und ob 0.9.0 ihn aufholt. V8 geht in keine Entscheidung ein.

Der Bericht liefert die Grundlage für ein GO der nutzenden Person zum Upgrade. Dieses Ticket pinnt nichts um und ändert keine Instanz.

## Changelog-Sichtung: was das A/B zeigen muss

Vollständige Sichtung im Ticket #372. Für unser Setup wirksam (Quelle: [Release v0.9.0](https://github.com/ggml-org/llama.cpp/releases/tag/v0.9.0) und die verlinkten PRs über die GitHub-API, abgerufen 06.11.2026; Titel und Merge-Status der PRs nachgeprüft am selben Tag):

- **[llama.cpp#31356](https://github.com/ggml-org/llama.cpp/pull/31356)** ändert neben dem gemma4-Graphen auch den draft-mtp-Pfad in `common/speculative.cpp`, wenn Drafter und Hauptmodell den KV-Cache teilen. Das ist bei uns so: Die Preflight-Logs zeigen `llama_kv_cache: layer N: sharing with layer M` für den Drafter. → Prefill-t/s, draft acceptance.
- **[llama.cpp#30141](https://github.com/ggml-org/llama.cpp/pull/30141)** sichert den MTP-Hidden-State bei Context-Checkpoints und stellt ihn wieder her. In der Erkundung (unten) spielt der Server Checkpoints tatsächlich zurück. → draft acceptance je Aufgabe, Debug-Sonde.
- **[llama.cpp#29510](https://github.com/ggml-org/llama.cpp/pull/29510)** (`flash_attn_ext_rows`) ändert die Metal-FA-Kernel. 0.9.0 meldet bei uns `Flash Attention over K/V rows enabled`. → Decode, Prefill, Same-Seed-Sonde.
- **[llama.cpp#31075](https://github.com/ggml-org/llama.cpp/pull/31075)** (Metal: volle Threadgroups für Unary/Binary/GLU beim Einzel-Token-Decode). → Decode.
- **[llama.cpp#31635](https://github.com/ggml-org/llama.cpp/pull/31635)** (Gemma-4-MTP-Assistent übernimmt die FA-Einstellung des Hauptmodells). Erwartung laut PR: auf einem Gerät mit f16-KV keine Änderung.

Korrektur an #320: Die dort genannten Folgekandidaten wirken bei uns nicht. b12007 ist [llama.cpp#31073](https://github.com/ggml-org/llama.cpp/pull/31073) (Hadamard-Rotation, fasst Gemma nicht an), b12008 ist [llama.cpp#31394](https://github.com/ggml-org/llama.cpp/pull/31394) (wirkt nur ohne mmap).

## Erkundung vor der Pre-Registration (nicht gemessen)

Unter `ab-372/explore/`, ausschließlich zur Prüfung von Umgebung, Log-Format und Sonden-Design:

- **Umgebung:** `$TMPDIR` wurde seit #320 geleert. Die Tarballs `llama-b11960-bin-macos-arm64.tar.gz` und `llama-b12110-bin-macos-arm64.tar.gz` sind neu geladen und vor dem Entpacken gegen die GitHub-Digests geprüft. Die b11960-Binärdatei ist byte-identisch mit der aus #320. Die zwei Vendor-Pakete aus #158 sind per `pnpm add --ignore-scripts` in denselben Versionen (2.15.0) neu installiert, statt wie im README per `npm pack`.
- **Flag-Preflight:** Alle 17 Flags der Produktiv-Flagliste stehen in `--help` von 0.7.0, 0.8.0 und 0.9.0. `--help` ist zwischen 0.8.0 und 0.9.0 byte-identisch. Der Lade-Preflight (`run-ab.mjs --preflight`) ist für V7, V8 und V9 grün.
- **Log-Format:** gleich in 0.7.0 und 0.9.0. Bei Standard-Verbosität stehen je Task `prompt eval time`, `eval time` und `draft acceptance = r (a accepted / g generated)` im Log, aber weder Checkpoint-Restores noch der FA-Modus.
- **Debug-Erkundung** (`-lv 4`, Aufgabe 6, Seed 372 950, V7 und V9): Context-Checkpoints sind aktiv (`max = 32, min spacing = 8192`). Je Build spielt der Server einen Checkpoint zurück. Genau dieser Request und der folgende weichen in der acceptance ab (V7 48 von 92, V9 58 von 120), die drei übrigen Requests sind zwischen den Builds identisch. Der Server läuft mit `n_slots = 4, kv_unified = 'true'`.

Daraus folgt das Design unten: Das A/B bleibt bei der exakten Produktiv-Flagliste, und die Checkpoint- und FA-Fragen klärt eine getrennte Debug-Sonde.

## Pre-Registration

Dieser Abschnitt ist vor dem ersten Messlauf committet. Checklisten und Gates sind unverändert aus #320 und #285 (`smoke/grade-ab.mjs`: `MANUAL`, `QUELLEN_SOLL`; `smoke/criteria.mjs`: K1–K8). Neu im Harness sind nur Messgrößen: die draft acceptance (gepoolt und je Aufgabe) und eine Liste fehlender Messwerte je Lauf. Die Gate-Logik bleibt unverändert.

### Arme

| Arm | Rolle | Binärdatei | `--version` | SHA-256 |
|---|---|---|---|---|
| V7 | Referenz (Pin) | `/opt/homebrew/bin/llama-server` → `…/Cellar/llama.cpp/0.7.0/bin/llama-server` | 0.7.0 (build 11669, commit `620d2225c`) | `fd5cb5a7974c1633c9f7e487908cc270094f8506d823523b16c4b3ed723eabde` |
| V8 | beschreibend | `$KOMKI_PI_EXPERIMENTS_DIR/downloads/b11960/llama-b11960/llama-server` (Tarball-Digest `sha256:58e5a5e1…f4cc1e3c`) | 0.8.0-dev (build 11960, commit `8642541b2`) | `3d81b7997317e5ffd13ed3ba32436658e0f4067172cea3674b4215b39d4635be` |
| V9 | Kandidat | `$KOMKI_PI_EXPERIMENTS_DIR/downloads/b12110/llama-b12110/llama-server` (Tarball-Digest `sha256:4f5b8de12e0b9516658ca6a5764c6ffb3d7c659c3dd538556b1413c7b4050662`) | 0.9.0-dev (build 12110, commit `cd959bae9`) | `e7e3c60a5e612460d095bfd219047040d6bb9d0b56466aae30a480980b676959` |

Alle Arme laufen mit demselben GGUF-Paar (Pin `gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf`, `ef728c8e…0636e30c`; Drafter `mtp-gemma-4-26B-A4B-it-Q8_0.gguf`, `6326fb9f…26d93ed1b`, jeweils vor jedem Lauf per SHA geprüft), demselben Sampling (`--temp 1.0 --top-p 0.95 --top-k 64`), demselben Kontext `-c 131072` und denselben Extra-Flags `--reasoning off --spec-type draft-mtp --spec-draft-n-max 4 --model-draft <drafter>`. Ports: V7 49619, V8 49620, V9 49622.

Wie in #320 meldet sich das Nightly-Artefakt als `-dev`, obwohl sein Commit der Version-Bump des Releases ist. Abgleichpunkt ist der Commit.

### Messprotokoll

- **Eine Variable:** die Binärdatei. Alles andere wie in #320: Maschine, GGUFs, Sampling, Server-Flagliste (inklusive `--no-webui`), Node 24.22.1, pi 1.4.0, Fixtures, Prompts, Logging-Proxy, Timeout-Faktor 6.
- **Ablauf:** Runde 0 Warm-up (ungemessen), Runden 1–3 Messläufe, je Runde V7, V8, V9 verzahnt. Jeder Lauf startet seinen Server frisch; die Ladezeit ist Messwert.
- **Seeds:** 372 000 + Runde, alle Arme einer Runde teilen ihn. Kein Seed aus #285 (285 000er), #320 (320 000er) oder der Erkundung (372 900er, 372 950).
- **Aufgaben:** 1, 2, 3, 4 und 6 aus #158/#285, unverändert. Aufgabe 5 (TUI) entfällt.
- **Referenz:** V7. Kandidat: V9. V8 wird berichtet, aber nicht gegated.

### Messgrößen je Lauf

Wie #320: Ladezeit, TTFT und erste sichtbare Antwort, Decode-/Prefill-t/s, Prompt-/Completion-Token samt Thinking-Anteil, Tool-Calls mit Schema-Validierung, Reparaturbedarf, `phys_footprint` und RSS, finishReasons, Compaction-Verhalten. Neu im Harness: **draft acceptance** gepoolt und je Aufgabe, aus den `draft acceptance`-Zeilen des llama-Logs (Referenz #320: V7 0,710, V8 0,708). Ein Lauf, in dem eine Messgröße fehlt, erscheint im Bericht unter „Fehlende Messwerte“; das wäre ein Hinweis auf ein geändertes Log-Format. Berichtet werden Median und Spanne über drei Messläufe, ohne Signifikanzaussagen.

### Sonde: gleicher Seed

Wie #320, eine Sonde und kein Gate. Verglichen werden je Runde die Artefakte der Aufgaben 1, 2 und 3 zwischen V7 und V9 (und V8). Erwartung: Bytengleichheit ist seltener als in #320, weil #29510 und #31356 die Rechenwege auf dem Mac-Pfad ändern.

### Sonde: Debug-Log (beschreibend)

Nach dem Hauptlauf, getrennt davon: V7 und V9 mit zusätzlich `-lv 4`, eine Runde, Aufgaben 1, 2, 3, 4 und 6, Seed 372 800. Erhoben aus dem Log:

- FA-Modus (`Flash Attention enabled` bzw. `Flash Attention over K/V rows enabled`),
- Anzahl erzeugter und zurückgespielter Context-Checkpoints,
- draft acceptance der Requests mit zurückgespieltem Checkpoint gegen die übrigen Requests.

Die Sonde geht in kein Gate ein. Debug-Logging kostet Zeit, deshalb fließen ihre Tempowerte nicht in den Bericht.

### Blinde Qualitätsbewertung

Wie #285/#320: `grade-ab.mjs blind` verblindet die Outputs der Aufgaben 1, 2 und 3 aller Messläufe aller drei Arme. Die manuelle Bewertung ist abgeschlossen, bevor der Schlüssel gelesen wird.

### Gates

Unverändert aus #320, V9 gegen `--reference V7`:

| Gate | Art | Regel |
|---|---|---|
| H1 | hart | 0 Faktenänderungen (F0–F10) in Aufgabe 3, in jedem der drei Messläufe |
| H2 | hart | Reparaturrate ≤ V7 (distinkte Fehlerfälle / alle Tool-Calls, gepoolt) |
| Q | Qualität | Median-Punktzahl ≥ V7 in mindestens 2 der 3 Textaufgaben (blind) |
| Regel 1 | hart | V9 scheitert (Verdikt `fail` oder Timeout) in den Aufgaben 1–4 und 6 nicht häufiger als V7 |
| — | Kosten | t/s, TTFT, Ladezeit, Gesamtdauer, Speicher, draft acceptance werden berichtet, kein K.-o. |

### Entscheidungsregel

1. V9 wird nur dann zum Upgrade empfohlen, wenn es H1, H2, Q und Regel 1 besteht.
2. Tempo, Speicher und draft acceptance werden als Kosten/Nutzen berichtet und entscheiden nicht allein. Wie in #320 gilt: Ohne messbaren Gewinn bleibt es beim Pin, auch wenn alle Gates bestanden sind.
3. Scheitert V9 an einem Gate, bleibt es beim Pin; der Befund steht in diesem Labbook und im Ticket.
4. Das Upgrade selbst (brew, Re-Pin, Profil-Regeneration, Doku) läuft nur nach ausdrücklichem GO der nutzenden Person. Homebrew bietet am 06.11.2026 als stable 0.8.0 an. Liefert Homebrew später einen anderen Build als b12110, wird dieser vor dem Re-Pin nachgemessen.

## Ablauf

| Schritt | Zeit (06.11.2026, MEZ) | Verzeichnis unter `$TMPDIR/komki-pi-experiments/ab-372/` |
|---|---|---|
| Erkundung, Flag- und Lade-Preflight | 14:45–15:00 | `explore/` |
| Pre-Registration committet | 15:04 | Commit `4ab9e09` |
| erster Hauptlauf, abgebrochen (siehe [Abweichungen](#abweichungen-vom-protokoll)) | 15:06–19:34 | `main/` |
| Abweichung und Debug-Sonde committet | 19:39 | Commit `47919bb`, Arbeitsbaum sauber; `main-2` lief auf genau diesem Stand |
| Preflight V7, V8, V9 | 19:40 | `main-2/preflight/` (3,3 s, 2,5 s, 2,8 s) |
| Hauptlauf: Warm-up + 3 Runden × 3 Arme, verzahnt | 19:41–21:00 | `main-2/` (`schedule.json`, `provenance.json`, `REPORT.md`) |
| Blindbewertung, Entblindung | 21:03–21:04 | `main-2/blind/`, `main-2/blind-key.json` |
| Debug-Sonde V7D, V9D (`-lv 4`, Seed 372 800) | 21:03–21:06 | `probe-lv4/` (`PROBE.md`, `probe.json`) |

In allen Läufen von `main-2` und der Sonde: Netzbetrieb, Loadavg beim Start zwischen 1,2 und 3,1, kein anderer llama-server, 19–25 GB Speicher frei, keine Thermik- oder Leistungswarnung. Die Live-Instanz lief nicht. Nach dem Hauptlauf wurde nur Auswertungscode geändert, also Bericht und Sonde (siehe [Harness nach dem Lauf](#harness-nach-dem-lauf)), kein Code der Messläufe.

## Ergebnisübersicht

V9 besteht alle registrierten Gates gegen V7. Außer der Ladezeit zeigt es aber keinen Gewinn, der über die Streuung von drei Läufen hinausgeht. Ein Lauf des Referenzarms V7 geriet in eine Tool-Call-Schleife. Das verzerrt die Spannen von V7 und ist ein eigener Befund (Befund 4).

### Gates (V9 gegen V7)

| Gate | V7 (Referenz) | V9 (0.9.0) |
|---|---|---|
| H1 0 Faktenänderungen (A3, jeder Lauf) | 0 / 0 / 0 | 0 / 0 / 0 → bestanden |
| H2 Reparaturrate ≤ Referenz | 0 von 707 (0 %) | 0 von 55 (0 %) → bestanden |
| Q Median ≥ Referenz in ≥ 2 von 3 Textaufgaben | Referenz | Aufgaben 2 und 3 gleich, Aufgabe 1 einen Punkt darunter → bestanden |
| Regel 1 kein zusätzlicher `fail`/Timeout | 1 (`10-r3-V7`, Aufgabe 4, Timeout) | 0 → bestanden |

V8 (beschreibend) bestünde dieselben Gates: Q in allen drei Aufgaben, Regel 1 mit 0 Fehlschlägen.

### Qualität (blind, Median und Spanne)

| Aufgabe | V7 | V8 | V9 |
|---|---|---|---|
| 1 — TOP-Zusammenfassung (von 11) | 10 (10–10) | 10 (9–10) | 9 (9–10) |
| 2 — Quellen (von 20) | 20 (20–20) | 20 (20–20) | 20 (20–20) |
| 3 — Redigieren (von 16) | 15 (15–15) | 15 (15–15) | 15 (15–15) |

In Aufgabe 1 fehlt überall K6 (Eigenanteil, bekannt aus #158/#285/#320). Drei Outputs verlieren dazu einen manuellen Punkt:
- Zweimal M3, weil der Satz „wird … über die Umgestaltung … angehört“ grammatisch nicht stimmt (V8 Runde 3, V9 Runde 3).
- Einmal M2, weil der Satz „empfohlen, dem Rat zuzustimmen“ die Rollen verdreht (V9 Runde 2).

In Aufgabe 3 verfehlt jeder Output S4 („kann gedeckt werden“ wird zur sicheren Finanzierung), wie in #285 und #320. Der Abstand in Aufgabe 1 beträgt einen Punkt bei n = 3, und V8 zeigt denselben Satzfehler wie V9. Einen Build-Effekt trägt das nicht.

### Leistung (Median und Spanne über 3 Messläufe, Aufgaben 1–4 und 6)

| Messgröße | V7 (0.7.0) | V8 (0.8.0) | V9 (0.9.0) |
|---|---|---|---|
| Ladezeit | 3,3 s (3,3–3,5) | 2,5 s (2,5–2,5) | 2,5 s (2,5–2,8) |
| Gesamtdauer | 97 s (93–3 695) | 94 s (85–102) | 90 s (86–98) |
| Decode | 61,2 t/s (58,2–62,6) | 59,8 t/s (51,9–60,2) | 58,8 t/s (57,7–59,8) |
| Prefill | 382 t/s (147–431) | 419 t/s (387–449) | 440 t/s (400–448) |
| TTFT = erste sichtbare Antwort | 741 ms (531–3 989) | 748 ms (705–887) | 723 ms (695–794) |
| Thinking-Token | 0 | 0 (ein Lauf 1) | 0 |
| draft acceptance je Lauf | 0,706 (0,701–0,831) | 0,712 (0,709–0,712) | 0,714 (0,705–0,721) |
| draft acceptance gepoolt | 0,801 (15 523 von 19 380) | 0,711 (4 757 von 6 692) | 0,713 (4 709 von 6 600) |
| `phys_footprint` max | 14,3 GiB (14,2–14,4) | 13,6 GiB (13,1–14,3) | 14,3 GiB (12,5–18,5) |
| RSS max | 30,7 GiB (30,5–30,7) | 29,9 GiB (29,5–30,6) | 29,8 GiB (28,8–30,6) |
| Tool-Calls / invalide / Reparaturen | 707 / 0 / 0 | 60 / 0 / 0 | 55 / 0 / 0 |
| repetition loops (Text) / längengeklemmte Requests | 0 / 0 | 0 / 0 | 0 / 0 |

Ohne den Schleifenlauf `10-r3-V7` liegen die zwei übrigen V7-Läufe bei folgenden Werten:
- Decode 58,2 und 61,2 t/s,
- Prefill 382 und 431 t/s,
- Gesamtdauer 97 und 93 s,
- draft acceptance 0,706 und 0,701.

Alle diese Werte überlappen mit V9. Die gepoolte acceptance von V7 (0,801) stammt fast ganz aus den 648 Schleifen-Requests mit kurzen, leicht vorhersagbaren Antworten. Aussagekräftig ist hier der Wert je Lauf.

Die draft acceptance je Aufgabe (gepoolt) liegt bei V7 (ohne Aufgabe 4), V8 und V9 in jeder Aufgabe höchstens 0,021 auseinander:
- Aufgabe 1: 0,661 / 0,667 / 0,669
- Aufgabe 2: 0,900 / 0,899 / 0,905
- Aufgabe 3: 0,673 / 0,688 / 0,667
- Aufgabe 6: 0,561 / 0,564 / 0,562

Der Check „Fehlende Messwerte“ meldet nur `10-r3-V7: task-4-todo Requests Log ≠ Proxy`. Das ist der vom Timeout abgebrochene letzte Request der Schleife. In V9 fehlt keine Messgröße, und das Log-Format ist gleich geblieben.

### Sonde: gleicher Seed

| Artefakt (Runden 1–3) | V7 = V9 | V7 = V8 | V8 = V9 |
|---|---|---|---|
| TOP-Antwort (Aufgabe 1) | 1 von 3 | 1 von 3 | 1 von 3 |
| `quellen.json` (Aufgabe 2) | 2 von 3 | 2 von 3 | 2 von 3 |
| `neue-fassung.md` (Aufgabe 3) | 1 von 3 | 2 von 3 | 1 von 3 |

Vier von neun Paaren V7/V9 sind bytegleich, in #320 waren es bei V7/V8 ebenfalls vier von neun. Die erwartete Abnahme der Bytegleichheit durch [llama.cpp#29510](https://github.com/ggml-org/llama.cpp/pull/29510) und [llama.cpp#31356](https://github.com/ggml-org/llama.cpp/pull/31356) zeigt sich nicht. Auf demselben Seed geriet nur V7 in die Schleife (Runde 3), V8 und V9 nicht.

### Debug-Sonde (`-lv 4`, eine Runde, Seed 372 800, beschreibend)

| | V7D (0.7.0) | V9D (0.9.0) |
|---|---|---|
| FA Hauptmodell | `Flash Attention enabled` | `Flash Attention enabled`, `Flash Attention over K/V rows enabled` |
| FA Draft-Kontext | `Flash Attention enabled` | `Flash Attention over K/V rows enabled` |
| Context-Checkpoints angelegt / zurückgespielt | 58 / 6 | 68 / 6 |
| draft acceptance, Requests mit Restore | 0,774 (647 von 836, 6 Requests) | 0,777 (628 von 808, 6 Requests) |
| draft acceptance, übrige Requests | 0,638 (664 von 1 040, 18 Requests) | 0,671 (891 von 1 328, 23 Requests) |
| Prüfergebnisse | 1 `partial`, sonst `pass` | 1 `partial`, sonst `pass` |

Der Server spielt Checkpoints in jeder Sitzung mit Folge-Requests zurück, sechsmal in fünf Aufgaben, in beiden Builds gleich oft und bei den ersten vier Restores an denselben Request-Positionen (2, 4, 6, 7). Die Restore-Requests haben in beiden Builds fast dieselbe acceptance. Der Unterschied aus der Erkundung (V7 0,522, V9 0,483, n = 1) wiederholt sich nicht. Einen Effekt von [llama.cpp#30141](https://github.com/ggml-org/llama.cpp/pull/30141) auf die acceptance zeigt diese Sonde also nicht. Unter 0.9.0 läuft auch der Draft-Kontext mit dem K/V-Rows-Pfad aus #29510 ([llama.cpp#31635](https://github.com/ggml-org/llama.cpp/pull/31635): Der Assistent übernimmt die FA-Einstellung des Hauptmodells).

## Befunde

1. **0.9.0 ist voll kompatibel zur Produktivkonfiguration.** Alle 17 Flags stehen in `--help`, der Preflight ist grün, alle fünf Läufe von V9 und V9D liefen ohne Einschränkung, das Log-Format ist gleich und es fehlt keine Messgröße.
2. **Verhalten und Qualität ununterscheidbar.** Thinking bleibt aus, die draft acceptance je Lauf und je Aufgabe liegt auf dem Niveau von V7 und V8, und die Quote der Bytegleichheit gleicht der aus #320. Der Abstand in Aufgabe 1 (Median 9 gegen 10) ist ein Punkt bei n = 3. Derselbe Satzfehler kommt auch in V8 vor.
3. **Tempo: Ladezeit besser, sonst nichts Belastbares.** Die Ladezeit sinkt stabil von 3,3 auf 2,5 s, wie schon bei 0.8.0. Decode, Prefill, TTFT und Gesamtdauer überlappen mit V7, sobald man den Schleifenlauf herausnimmt. Decode tendiert bei V9 leicht niedriger (Median 58,8 gegen 61,2 t/s; ohne den Schleifenlauf 59,7 t/s bei V7). Prefill tendiert leicht höher (440 gegen 382 bzw. 407 t/s). Beide Tendenzen liegen innerhalb der Spannen.
4. **Neu: Tool-Call-Schleife im Referenzarm.** In `10-r3-V7`, Aufgabe 4, ruft das Modell 648-mal `todo {"action":"update","id":2,"status":"completed"}` auf, bis der Task-Timeout nach 3 600 s greift (657 Requests, 12,1 Mio. Prompt-Token). Der Loop-Detektor des Harness prüft nur wiederholte Textzeilen und erkennt solche Schleifen nicht. Ein Einzelfall (n = 1) auf 0.7.0: V8 und V9 auf demselben Seed laufen sauber. Einem Build lässt sich das nicht zuordnen. Für die Produktion ist es trotzdem relevant, denn ein Agent ohne Abbruchgrenze dreht hier eine Stunde lang. Folgeticket: #383 (Schleifen im Harness erkennen, im Alltag begrenzen).
5. **Der Decode-Rückstand von 0.8.0 aus #320 lässt sich nicht sauber reproduzieren.** V8 liegt bei 59,8 t/s im Median (V7: 61,2). Ein Lauf fällt auf 51,9 t/s, die beiden anderen liegen bei 59,8 und 60,2. In #320 lagen die Spannen bei 56,0–56,4 gegen 59,2–59,8 und überlappten nicht.
6. **Korrektur zu Homebrew.** Ticket und Pre-Registration nennen für den 06.11.2026 „Homebrew stable 0.8.0“. Das stimmt nicht: [homebrew-core](https://github.com/Homebrew/homebrew-core/blob/main/Formula/l/llama.cpp.rb) hat `llama.cpp 0.9.0` am 05.11.2026 um 05:32 UTC übernommen (Commit `af72bbf00`, Bottles 05:59 UTC, `tag: "v0.9.0"`, `revision: "cd959bae99ff4bed22bef2604f45241c09bbb8c8"`), abgerufen über die GitHub-API am 06.11.2026. Das ist derselbe Commit wie b12110. Das Bottle ist aber ein eigener Build mit anderen Compiler-Flags und SHA. Nach der Entscheidungsregel 4 wird es vor einem Re-Pin nachgemessen. Außerdem gilt: Ein beliebiges `brew upgrade` hebt die Maschine jetzt auf 0.9.0. Der 0.7.0-Pin hält nur, solange niemand upgradet.

## Empfehlung

Nach Entscheidungsregel 1 dürfte V9 übernommen werden, denn H1, H2, Q und Regel 1 sind bestanden. Regel 2 verlangt aber einen messbaren Gewinn, und den gibt es außer der Ladezeit nicht: −0,8 s je Serverstart, schon in #320 als zu gering bewertet. **Empfehlung nach der registrierten Regel: 0.7.0-Pin vorerst behalten.**

Für die Entscheidung der nutzenden Person zählt dazu dreierlei:
- 0.9.0 ist nachweislich nicht schlechter. Die Qualität ist gleich, keine Messgröße fehlt, und die Spannen überlappen.
- Homebrew liefert jetzt 0.9.0 aus. Der Pin auf 0.7.0 wird damit zur Wartungsfrage: ältere Formel, kein Bottle-Update.
- Die einzige Zuverlässigkeitsstörung dieser Messung trat auf 0.7.0 auf.

Wer deshalb upgraden will, misst nach dem GO zuerst das Homebrew-Bottle `0.9.0` mit einem Arm wie V9 nach (Grenze aus #320). Erst danach folgen Re-Pin, `komki setup`, `komki doctor`, ein echter Lauf mit `komki up` und `run-smoke.mjs` sowie die Doku-Stellen aus #320. Dieses Ticket pinnt nichts um. Die Live-Instanz bleibt auf 0.7.0.

## Grenzen

- n = 3 bei temp 1,0. Der Schleifenlauf nimmt V7 effektiv einen Messlauf für die Tempo-Werte. Die Mediane sind robust, die Spannen von V7 nicht.
- Die Blindbewertung lag wie in #285 und #320 bei derselben Session, die den Harness erweitert hat. Sie arbeitete nur an den verblindeten Kopien und war abgeschlossen, bevor der Schlüssel gelesen wurde. Die zwei M3-Abzüge und der M2-Abzug sind Urteile. Strenger oder milder gewertet, verschiebt sich Aufgabe 1 um einen Punkt, Q bliebe bestanden.
- Gemessen wurde das Nightly-Artefakt b12110 des Release-Commits, nicht das Homebrew-Bottle (Befund 6).
- Die Debug-Sonde ist eine Runde mit Debug-Logging. Ihre acceptance-Werte sind beschreibend, ihre Tempowerte fließen nirgends ein.

## Harness nach dem Lauf

Nach dem Hauptlauf und vor der Auswertung kamen Änderungen aus dem Review hinzu. Sie betreffen nur Auswertung und Darstellung, keinen Code, der in den Messläufen lief, und keine Gate-Logik:
- Der Check „Fehlende Messwerte“ prüft zusätzlich `firstAnswerMedianMs`, `rssMaxMiB`, die draft acceptance je Aufgabe, unvollständige Log-Requests und `serverRequestCountMismatch`.
- Die draft acceptance steht zusätzlich je Lauf mit Spanne im Bericht.
- Die Debug-Sonde listet jeden Request in Log-Reihenfolge, also auch den Request nach einem Restore.
- Pooling und Regex der draft acceptance liegen nur noch an einer Stelle (`poolDraft` in `measure.mjs`).

Die Werte der Messläufe sind vor und nach der Änderung gleich. Geprüft wurde das am gespeicherten `serverRequests` gegen eine Neuauswertung des Logs von `06-r1-V9`.

## Abweichungen vom Protokoll

**Hauptlauf `main` abgebrochen und als `main-2` neu gestartet.** Der erste Hauptlauf (`ab-372/main`, 06.11.2026 15:06–19:34 Uhr MEZ) kam in vier Stunden nur bis Lauf 4 von 12. Danach endete die Session, die ihn gestartet hatte. Eine Störung der Umgebung hat die Daten verfälscht, und zwar in allen drei Armen:

- Der llama-server blieb minutenlang stehen, ohne dass das am Build lag. Ein Beispiel aus `01-r0-V7`: `prompt eval time = 593935.23 ms / 269 tokens`, also rund zehn Minuten für einen Prefill, der sonst etwa eine Sekunde braucht. Decode und Prefill zwischen den Hängern liefen normal schnell (etwa 70 t/s, 500–650 t/s).
- `schedule.json` zeigt den Zustand des Systems: Alle vier Läufe starteten im Akkubetrieb, die Loadavg stieg auf 22 bis 47 (in #320 lag die Gesamtdauer eines Laufs bei rund 90 s), und vor Lauf 1 waren nur 12,7 GB Speicher frei. Das Bild passt zu Speicherdruck, unter dem die per mmap geladenen Gewichte ausgelagert und neu eingelesen werden. Zu dieser Zeit liefen weitere Sessions auf derselben Maschine.
- Folge: Aufgabe 2 in `04-r1-V7` scheiterte am Timeout (1 827 s). Lauf 4 endete mit Exit-Code 1.

Diese Läufe gehen in keine Auswertung ein; von ihnen wurde nichts verblindet und nichts bewertet. Der Neustart nutzt dasselbe Protokoll mit denselben Seeds (372 000 + Runde), denselben Armen und demselben Harness-Stand für alle Messgrößen. Neu ist nur `probe-lv4.mjs` für die getrennte Debug-Sonde, die schon vorab registriert war. Vor dem Start werden Netzbetrieb, Loadavg und freier Speicher geprüft. Läuft ein anderer llama-server, wird nicht gestartet. Die Rohdaten von `main` bleiben zur Nachvollziehbarkeit liegen.

## Reproduktion

```bash
cd apps/komki_cli/experiments/pi_packages
R=$TMPDIR/komki-pi-experiments/ab-372/main-2
node smoke/run-ab.mjs --root $R --arms V7,V8,V9 --preflight
node smoke/run-ab.mjs --root $R --arms V7,V8,V9 --runs 3 --timeout-factor 6 --seed-base 372000
node smoke/grade-ab.mjs blind --root $R     # dann blind/grades.json ausfüllen
node smoke/grade-ab.mjs report --root $R --reference V7

# Debug-Sonde (beschreibend): V7 und V9 mit -lv 4, eine Runde, Seed 372 800
P=$TMPDIR/komki-pi-experiments/ab-372/probe-lv4
node smoke/run-ab.mjs --root $P --arms V7D,V9D --runs 0 --timeout-factor 6 --seed-base 372800
node smoke/probe-lv4.mjs --root $P
```

Node 24.22.1 über asdf (`ASDF_NODEJS_VERSION=24.22.1`), wie in #285 und #320.
