# Labbook: llama-server-A/B — 0.7.0-Pin gegen 0.9.0 (mit 0.8.0 als Vergleich)

- **Status:** Pre-Registration, 2026-11-06 (Ticket #372). Ergebnisse folgen nach dem Messlauf.
- **Vorgänger:** [Labbook: llama-server-A/B 0.7.0 gegen 0.8.0](2026-10-31-llama-server-0.8.0-ab.md) (#320: Arme V7/V8, Empfehlung „Pin behalten“), [Labbook: Modell-A/B](2026-10-31-modell-ab.md) (#285: Protokoll, Gates, Checklisten)
- **Harness:** `apps/komki_cli/experiments/pi_packages/smoke/` (`run-ab.mjs`, `grade-ab.mjs`), erweitert um den Arm `V9` und die draft acceptance im Bericht

## Ziel und Abgrenzung

Dieses A/B misst den llama-server-Wechsel von 0.7.0 (Build 11669, Homebrew-Pin, produktiv) auf 0.9.0 (Build 12110, Commit `cd959bae9`, der Version-Bump-Commit des v0.9.0-Releases vom 04.11.2026) unter der Produktivkonfiguration: Pin-GGUF plus MTP-Drafter, Thinking aus per `--reasoning off`, Gemma-Sampling, Kontext 131 072. Eine Variable: die Binärdatei.

0.8.0 (b11960) läuft als dritter Arm mit, rein beschreibend. Er zeigt, ob der Decode-Rückstand aus #320 (−5,9 % gegen 0.7.0) an einem neuen Tag wieder auftritt und ob 0.9.0 ihn aufholt. V8 geht in keine Entscheidung ein.

Der Bericht liefert die Grundlage für ein GO der nutzenden Person zum Upgrade. Dieses Ticket pinnt nichts um und ändert keine Instanz.

## Changelog-Sichtung: was das A/B zeigen muss

Vollständige Sichtung im Ticket #372. Für unser Setup wirksam (Quelle: Release-Notes und PRs über die GitHub-API, abgerufen 06.11.2026):

- **#31356** ändert neben dem gemma4-Graphen auch den draft-mtp-Pfad in `common/speculative.cpp`, wenn Drafter und Hauptmodell den KV-Cache teilen. Das ist bei uns so: Die Preflight-Logs zeigen `llama_kv_cache: layer N: sharing with layer M` für den Drafter. → Prefill-t/s, draft acceptance.
- **#30141** sichert den MTP-Hidden-State bei Context-Checkpoints und stellt ihn wieder her. In der Erkundung (unten) spielt der Server Checkpoints tatsächlich zurück. → draft acceptance je Aufgabe, Debug-Sonde.
- **#29510** (`flash_attn_ext_rows`) ändert die Metal-FA-Kernel. 0.9.0 meldet bei uns `Flash Attention over K/V rows enabled`. → Decode, Prefill, Same-Seed-Sonde.
- **#31075** (Metal: volle Threadgroups für Unary/Binary/GLU beim Einzel-Token-Decode). → Decode.
- **#31635** (Gemma-4-MTP-Assistent übernimmt die FA-Einstellung des Hauptmodells). Erwartung laut PR: auf einem Gerät mit f16-KV keine Änderung.

Korrektur an #320: Die dort genannten Folgekandidaten wirken bei uns nicht. b12007 ist #31073 (Hadamard-Rotation, fasst Gemma nicht an), b12008 ist #31394 (wirkt nur ohne mmap).

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

## Reproduktion

```bash
cd apps/komki_cli/experiments/pi_packages
R=$TMPDIR/komki-pi-experiments/ab-372/main
node smoke/run-ab.mjs --root $R --arms V7,V8,V9 --preflight
node smoke/run-ab.mjs --root $R --arms V7,V8,V9 --runs 3 --timeout-factor 6 --seed-base 372000
node smoke/grade-ab.mjs blind --root $R     # dann blind/grades.json ausfüllen
node smoke/grade-ab.mjs report --root $R --reference V7
```

Node 24.22.1 über asdf (`ASDF_NODEJS_VERSION=24.22.1`), wie in #285 und #320.
