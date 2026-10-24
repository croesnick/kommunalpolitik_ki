# Labbook: Pi-Packages für KomKI

- **Status:** abgeschlossen, 2026-10-24 (Node 24.22.1, pi 1.4.0)
- **Gehört zu:** [RFC 0005: Pi-Packages im KomKI-Harness](../rfcs/0005-pi-packages.md)
- **Harness:** `apps/komki_cli/experiments/pi_packages/`

## Umgebung

| Feld | Wert |
|---|---|
| pi | 1.4.0 (`@earendil-works/pi-coding-agent`) |
| Node | 24.22.1 |
| Plattform | macOS, arm64 |
| Modell | Gemma 4 26B-A4B-it, llama.cpp, 128K Kontext — für die Experimente durch einen deterministischen Mock-Provider ersetzt |
| Package-Bezug | npm-Tarballs, entpackt und mit `npm install --omit=dev --ignore-scripts` installiert; keine Installation zur Laufzeit |
| Getestete Versionen | `rpiv-todo` 2.15.0, `rpiv-ask-user-question` 2.15.0, `pi-tool-repair` 0.3.9, `pi-vcc` 0.10.2, `pi-context` 0.1.16, `pi-permission-system` 41.0.0, `pi-quiver` 6.14.2, `pi-hermes-memory` 0.9.11 |

## Methode

Jedes Package lief in einem isolierten `PI_CODING_AGENT_DIR` mit eigenem Arbeitsverzeichnis und eigener Session-Ablage. pi wurde mit folgender Form gestartet:

```text
--print --mode json --offline --no-extensions
--no-skills --no-context-files --no-prompt-templates --no-themes --no-approve
--session-dir <run>/sessions
--provider mock --model mock-model
--tools <allowlist>
-e <expliziter Package-Pfad>
```

Der Mock-Provider antwortet OpenAI-kompatibel und erlaubt deterministische Tool-Calls, malformed Argumente und die Zählung von Modellaufrufen. Für `ask_user_question` wurde zusätzlich `--mode rpc` mit dem `extension_ui_request`/`extension_ui_response`-Protokoll getestet. Damit lassen sich Mechanik und Grenzen prüfen, ohne das 26B-Modell zu belasten. Die Experimente ersetzen keine Messung der Antwortqualität des echten Modells.

Die Anforderungen R1–R8 stehen in [RFC 0005, Abschnitt D4](../rfcs/0005-pi-packages.md#d4--anforderungen-an-eine-aufnahme).

## Ergebnisübersicht

| ID | Package | Verdikt | Kurzbefund |
|---|---|---|---|
| 01 | `@juicesharp/rpiv-todo` | **PASS** | Create, Persistenz über `--continue`, Allowlist-Kompatibilität und keine Fremdschreibvorgänge belegt. |
| 02 | `@juicesharp/rpiv-ask-user-question` | **PASS** | Headless wird das Tool entfernt; RPC-Dialog und tmux-TUI liefern die Antwort an das Modell; kein Hang. |
| 03 | `pi-tool-repair` | **FAIL** | Repariert den dokumentierten Alias `file_path` → `path`, aber nicht `{path:[…], content:{…}}`; System-Prompt bleibt unverändert. |
| 04 | `@sting8k/pi-vcc` | **CONDITIONAL** | Algorithmische Compaction spart den Summary-Request; deutsche Präferenzen und Scope-Wechsel werden nicht erkannt. |
| 05 | `@spences10/pi-context` | **PASS** | Node 24.22.1 erfüllt ≥ 24.15.0; Receipt, `context_search`, `context.db` und Allowlist-Verhalten funktionieren. |
| 06 | `@gotgenes/pi-permission-system` | **PASS** | Schreiben innerhalb `work` erlaubt, außerhalb verweigert; kein Headless-Hang. |
| 07 | `pi-quiver` | **PASS** | Nur `doc_to_md` geladen; `unpdf`-Tier extrahiert Text offline; Struktur degradiert, keine OCR. |
| 08 | `pi-hermes-memory` | **PASS** | Anchor-Suche liefert `path:startLine-endLine`; bei deaktivierter Lernlogik keine Memory-Schreibvorgänge. |
| 09 | Seatbelt-Canary | **PASS** | Externer `fetch`, `exec` und `/tmp`-Write scheitern; Loopback und Scratch funktionieren. Credentials bleiben in-process sichtbar. |

## Anforderungsabgleich

`PASS` heißt: im Experiment beobachtet. `PARTIAL` heißt: teilweise belegt oder nur unter Einschränkung. `FAIL` heißt: im Experiment nicht erfüllt. `N/T` heißt: nicht getestet.

| Package | R1 Netz | R2 Allowlist | R3 Writes | R4 Install | R5 pi 1.1 | R6 Nutzen | R7 GO | R8 Abbruch |
|---|---|---|---|---|---|---|---|---|
| `rpiv-todo` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `rpiv-ask-user-question` | PASS | PARTIAL | PASS | PASS | PASS | PASS | PASS | PASS |
| `pi-tool-repair` | PASS | PASS | PASS | PASS | PARTIAL | PARTIAL | PASS | PASS |
| `pi-vcc` | PASS | PASS | PASS | PASS | PASS | PARTIAL | PARTIAL | PASS |
| `pi-context` | PASS | PASS | PASS | PASS | PASS | PARTIAL | PASS | PASS |
| `pi-permission-system` | PASS | PARTIAL | PASS | PARTIAL (20 MB Dep) | PASS | PARTIAL | PASS | PASS |
| `pi-quiver` | PASS (nur `doc_to_md`) | PASS | PASS | PARTIAL (Deps/PyMuPDF) | PASS | PARTIAL | PASS | PASS |
| `pi-hermes-memory` | PASS (read-only) | PASS | PASS (read-only) | PARTIAL (native) | PASS | PARTIAL | PASS | PASS |

`R2 PARTIAL` bei `rpiv-ask-user-question` und `pi-permission-system`: Beide rufen `setActiveTools` auf. Bei `ask_user_question` dient das der UI-Verfügbarkeit (Tool entfernen, wenn keine UI); bei `permission-system` der Tool-Sichtbarkeit. Keiner der Aufrufe fügte im Experiment ein fremdes Tool hinzu, aber der Aufruf muss bei jedem Update geprüft werden.

## Einzelresultate

### 01 — `rpiv-todo`

**Hypothese:** Das Tool legt Zustand an, persistiert ihn als `rpiv-todo-state`-Eintrag, `--continue` replayt ihn, und ohne Extension ist `--tools todo` wirkungslos.

**Beobachtung:**

- Create: `Created #1: TOP 1 prüfen (pending)`.
- Session: ein Custom-Eintrag `rpiv-todo-state` mit `{"entryCount":1,"task":{"id":1,"subject":"TOP 1 prüfen","status":"pending"}}`.
- Resume: `[pending] #1 TOP 1 prüfen`.
- Baseline ohne Extension: `declaredTools: []`, `Tool todo not found`, `isError: true`.
- Schreibvorgänge: keine extension-attribuierten Dateien außerhalb des Session-Verzeichnisses. pi selbst schreibt `auth.json` und `models-store.json`; die Baseline isoliert das.
- Netzwerk: nur die zwei Mock-Requests.

**Verdikt:** PASS. Die Aufnahme in die interaktive Session ist belegt. Headless bleibt außen vor, weil dort keine Session-Persistenz existiert.

### 02 — `rpiv-ask-user-question`

**Hypothese:** Headless gibt es entweder `no_ui` oder das Tool fehlt; im RPC-Modus und in der tmux-TUI wird ein Dialog gerendert, und die Antwort erreicht das Modell.

**Beobachtung:**

- Headless: `declaredTools: []`; der Mock-Aufruf traf `Tool ask_user_question not found`, nicht das `no_ui`-Envelope. Kein Hang (268 ms).
- RPC: `declaredTools: ["ask_user_question"]`; `extension_ui_request` mit `method: "select"` und Optionen `["1. Option A — Erste Option", "2. Option B — Zweite Option", "3. Type something."]`.
- RPC-Antwort: `value: "1. Option A — Erste Option"`.
- TUI in tmux: Dialog zeigt `Welche Option soll geprüft werden?`, `❯ 1. Option A`, `2. Option B`, `3. Type something.`; Taste `1` wählt Option A, danach `Danke, Option A.`
- Tool-Result in beiden Fällen: `User has answered your questions: "Welche Option soll geprüft werden?"="Option A". You can now continue with the user's answers in mind.`
- `answerInModelContext: true`, Exit 0, `agentSettled: true`, kein Timeout; tmux sauber beendet.

**Verdikt:** PASS für RPC und TUI. Der `rpiv:ask-user:answer`-Eventbus wurde nicht getestet; das bleibt eine offene Lücke.

### 03 — `pi-tool-repair`

**Hypothese:** Ein malformed `write`-Call mit `{path:[…], content:{text:…}}` wird repariert; der System-Prompt bleibt byte-gleich.

**Beobachtung:**

- Baseline: Validierungsfehler `path: must be string`, `content: must be string`; keine Datei.
- Mit Extension: derselbe Validierungsfehler; keine Datei. Die Argumente bleiben unverändert.
- Diagnose D: Der dokumentierte Alias `file_path` → `path` wird repariert; die Datei entsteht mit `Hallo`.
- System-Prompt: in A und B identisch, 2108 Bytes.
- Netzwerk: keine Requests außer dem Mock.

**Verdikt:** FAIL für die breite Hypothese, PASS nur für den dokumentierten Alias. `pi-tool-repair` ist kein allgemeiner Repair-Layer. Vor einer Freigabe braucht es einen Korpus echter 26B-Fehlaufrufe.

### 04 — `pi-vcc`

**Hypothese:** VCC ersetzt die LLM-Summary durch eine algorithmische Compaction; die deutschen Extractor-Pfade sind englisch.

**Beobachtung:**

- Default-Compaction: 3 Provider-Requests, davon 1 Summary-Request; eine `compaction`-Entry.
- VCC mit `overrideDefaultCompaction: true`: 2 Provider-Requests, 0 Summary-Requests; `details.compactor: "pi-vcc"`, `sections: ["Session Goal","Files And Changes","user","assistant"]`.
- `B-defer` mit `false`: 3 Requests, 1 Summary-Request — erwartetes Defer-Verhalten, kein VCC-Defekt.
- Deutsch: `Ich bevorzuge immer kurze Sätze.` → `germanPreferences: []`; englische Kontrolle `I always prefer short sentences.` wird erkannt.
- Deutsch: `Stattdessen ...` erzeugt keinen `[Scope change]`; die englische Kontrolle tut es.
- Netzwerk: nur Mock-Requests.

**Verdikt:** CONDITIONAL. Der No-Extra-LLM-Call-Teil ist bestanden, die deutsche semantische Extraktion fällt durch. Für deutsche Sitzungen braucht VCC einen eigenen Extractor oder eine bewusste Beschränkung. `vcc_recall` über das Rohtranskript ist davon getrennt und weiterhin interessant.

### 05 — `pi-context`

**Hypothese:** Das Package verlangt Node ≥ 24.15; mit Node 24.22.1 ist die Anforderung erfüllt. Der Retrieval-Loop wird geprüft.

**Beobachtung:**

- `engines.node: ">=24.15.0"`; installiert ist 24.22.1 → erfüllt.
- Ladbar: `declaredTools: ["read","context_search","context_get","context_list","context_stats"]`.
- 39-KiB-Read wird durch eine Receipt ersetzt: `Size: 39.0 KiB, 1027 lines, 10 chunks`.
- `context_search` findet den Begriff; `context.db` liegt im Agent-Dir; `context_export` ist nicht allowlistet.
- Kein Netzwerk.

**Verdikt:** PASS. Node 24.22.1 erfüllt die Anforderung; Receipt, Suche, DB und Allowlist-Verhalten funktionieren. Echte RIS-Dokumente bleiben ungetestet.

### 06 — `pi-permission-system`

**Hypothese:** Eine globale Policy verweigert Schreiben außerhalb `work`, ohne den Headless-Lauf aufzuhängen.

**Beobachtung:**

- Baseline: `work/ok.txt` und `escape.txt` werden geschrieben.
- Mit Policy: `work/ok.txt` wird geschrieben; `escape.txt` bleibt absent.
- Verweigerung in-band: `[pi-permission-system] Denied by policy: 'path_write' for tool 'write' … (rule '*')`.
- Kein Timeout (424 ms), Exit 0.
- `setActiveTools` ist im Paket vorhanden; im Test wurde kein fremdes Tool hinzugefügt.

**Verdikt:** PASS für das Pfad-Gate. Das Paket bleibt optional, weil die Seatbelt-Grenze bereits existiert und die Dependency `tree-sitter-bash` groß ist.

### 07 — `pi-quiver`

**Hypothese:** Nur `extensions/doc_to_md.ts` registriert kein `fetch`/Slack; ein minimales PDF wird ohne `uv` über den JS-Tier extrahiert.

**Beobachtung:**

- `declaredTools: ["doc_to_md"]` — nur die eine Extension.
- Ausgabe: `Engine: unpdf`, `Tier: unpdf`, `Page-Count: 1`, `Degraded: unpdf text extraction - structure not preserved`.
- Markdown enthält `TOP 1 Bahnhofstraße` und `--- end of page.page_number=1 ---`.
- `PATH=/usr/bin:/bin`, kein `uv`; kein Netzwerk.

**Verdikt:** PASS für den degradierten Offline-Tier. Echte RIS-PDFs, Scans und OCR sind ungetestet. Der belastbarere Weg bleibt ein Mediator-Connector um `tools/pdf_ingest`.

### 08 — `pi-hermes-memory`

**Hypothese:** Die Extension lädt trotz `--ignore-scripts`; die Anchor-Suche liefert `path:startLine-endLine`; bei deaktivierter Lernlogik entstehen keine Memory-Dateien.

**Beobachtung:**

- `declaredTools: ["session_search"]`; keine Extension-Fehler.
- Treffer: `…/fixture-session.jsonl:2-3 — matched all: Bahnhofstraße`.
- Weder Memory-DB noch Markdown-Memory-Dateien; nur `hermes-memory-config.json`, Session-Fixture und pi-Core-Dateien.
- Konfiguration: Review, Correction, Flush und Standing Instructions deaktiviert; `variant: "anchors"`.

**Verdikt:** PASS im read-only Modus. Die Lernlogik bleibt aus, weil der Vault die Source of Truth ist.

### 09 — Seatbelt-Canary

**Hypothese:** Unter dem echten komki-Profil scheitern externer `fetch`, `exec` und Schreiben außerhalb der erlaubten Pfade; der erlaubte Loopback-Port funktioniert. Credentials, die pi im Prozess hält, bleiben für eine Extension sichtbar.

**Beobachtung:**

- Profil: temporär über `KomkiCli.Profile.generate/2` mit dem Mock-Port erzeugt; das Basisprofil blieb unverändert.
- Externer `fetch("https://example.com")`: `TypeError: fetch failed`, Ursache `getaddrinfo ENOTFOUND` (DNS/Egress blockiert).
- `execFile("/bin/echo")`: `spawn EPERM`.
- Schreiben nach `/tmp/komki-canary-escape.txt`: `EPERM`; die Datei fehlt auch auf dem Host.
- Mock-Provider auf dem erlaubten Loopback-Port: HTTP 200; pi führte einen Chat-Request aus.
- Ergebnisdatei im Scratch: geschrieben und lesbar.
- `KOMKI_MEDIATOR_TOKEN`: im Prozess-Environment sichtbar.
- `models.json`: lesbar und enthält einen `apiKey`; `auth.json`: lesbar. Der separate `llama.key` unter `base/tmp` ist nicht lesbar, weil das pi-Profil nur `pi-home` und den Scratch freigibt.

**Verdikt:** PASS für die gating requirements. Die OS-Grenze hält für Netzwerk, Exec und fremde Pfade. Die In-Process-Sicht bleibt das Residualrisiko: Eine Extension kann das Mediator-Token und den Provider-Key aus `models.json` lesen.

## Statische Analyse

Der Scan zählt rohe Texttreffer und unterscheidet nicht zwischen echtem Netzwerkcode und Regex-`.exec`. Die wichtigsten Befunde:

| Package | Netzwerk | Exec/Child-Process | Allowlist-Risiko | Installationshinweis |
|---|---|---|---|---|
| `rpiv-todo` | keins | keins | keins | eine kleine Config-Dependency |
| `rpiv-ask-user-question` | keins | `spawn` für externen Editor | `setActiveTools` für UI-Reconcile | eine kleine Config-Dependency |
| `pi-tool-repair` | keins | keine echten Prozesse; `exec` sind Regexe | keins | keine Dependencies |
| `pi-vcc` | keins | keine echten Prozesse | keins | keine Dependencies |
| `pi-context` | keins | keine echten Prozesse | keins | vier Dependencies; Node ≥ 24.15 |
| `pi-permission-system` | keins | `spawnSync` für Node-Modul-Erkennung | `setActiveTools` | drei Dependencies, u. a. `tree-sitter-bash` |
| `pi-quiver` | `fetch` in anderen Extensions und im Bundle | `spawn` für Dokument-Tools | keins | fünf Dependencies; PyMuPDF optional/AGPL |
| `pi-hermes-memory` | keins | `pi.exec`/Child-Prozesse für Hintergrund-Review | `registerProvider` im Umfeld | `better-sqlite3` nativ |

Bei `pi-quiver` ist entscheidend, dass ausschließlich `extensions/doc_to_md.ts` geladen wird. Das Package selbst enthält `fetch`, Slack und weitere Extensions; die dürfen im KomKI-Harness nie aktiv werden. Bei `pi-hermes-memory` sind die Hintergrundpfade deaktiviert; `registerProvider` und die Child-Prozesse bleiben außerhalb des read-only Modus.

## Erkenntnisse

1. **Zwei Packages sind reif:** `rpiv-todo` und `rpiv-ask-user-question` erfüllen die Aufnahmeanforderungen für die interaktive Session. Beide sind klein, MIT-lizenziert, ohne eigenen Egress und ohne fremde Tool-Registrierung.
2. **Der Headless-Pfad bleibt minimal:** `ask_user_question` wird dort entfernt, `rpiv-todo` hat keine Persistenz. Die Package-Freigabe gehört deshalb an die Session, nicht an `--print`.
3. **Repair ist nicht gleich Repair:** `pi-tool-repair` hilft bei dokumentierten Alias-Fehlern, aber nicht bei beliebigen malformed Argumenten. Ohne echten Fehlerkorpus ist der Nutzen für das 26B-Modell nicht belegt.
4. **Compaction ohne LLM funktioniert, Deutsch nicht:** `pi-vcc` spart den Summary-Call, verliert aber deutsche Präferenzen und Scope-Wechsel. Das ist ein konkretes Ausschlusskriterium für deutsche Sitzungen, kein theoretisches Risiko.
5. **Node-Version ist eine Laufzeitvoraussetzung:** `pi-context` verlangt Node ≥ 24.15; mit dem Pin auf 24.22.1 besteht der Test. Die Version gehört damit in die Harness-Voraussetzungen, nicht in die Package-Bewertung.
6. **Dokument-Ingestion bleibt besser im Mediator:** `pi-quiver` extrahiert offline Text, aber degradiert und ohne OCR. Für echte RIS-PDFs ist `tools/pdf_ingest` hinter dem Mediator der belastbarere Weg.
7. **Read-only Memory ist nützlich:** `pi-hermes-memory` liefert verifizierbare Anchor-Treffer, ohne den Vault zu duplizieren — vorausgesetzt, die Lernlogik bleibt aus.
8. **Die Allowlist ist kein Sandbox-Ersatz:** `setActiveTools` und `registerProvider` sind in mehreren Packages vorhanden. Die Experimente prüfen das beobachtete Verhalten, nicht die Abwesenheit solcher Aufrufe im Quelltext.
9. **Die OS-Grenze hält, die In-Process-Sicht nicht:** Der Canary scheitert bei externem `fetch`, `exec` und `/tmp`-Write, erreicht aber den erlaubten Loopback-Port. `KOMKI_MEDIATOR_TOKEN`, `models.json` mit `apiKey` und `auth.json` bleiben für Extension-Code lesbar. Das ist ein Freigabe-Risiko, kein Sandbox-Bug.

## Nicht getestet

- Antwortqualität des echten Gemma-4-26B-Modells; alle Experimente nutzten den Mock-Provider.
- Echter Fehlerkorpus des 26B-Modells für `pi-tool-repair`; der Test nutzte konstruierte malformed Argumente.
- `pi-subagents`: nicht getestet. Die Pi-1.2.0-Sperre ist mit pi 1.4.0 weg, aber das Pilot-Gate aus RFC 0005, Abschnitt D8, ist noch nicht erfüllt.
- `rpiv:ask-user:answer`-Eventbus als alternativer Antwortkanal.
- Echte RIS-PDFs, Scans und OCR für `pi-quiver`.
- Künftige pi-Versionen; 1.4.0 ist getestet, ein weiteres Upgrade nicht.
- Langzeitverhalten und Speicherverbrauch über viele Sessions.

## Reproduktion

Das Vendor-Verzeichnis wird einmalig nach `apps/komki_cli/experiments/pi_packages/README.md` vorbereitet:

```bash
export KOMKI_PI_EXPERIMENTS_DIR="${TMPDIR:-/tmp}/komki-pi-experiments"
# Pakete packen und nach "$KOMKI_PI_EXPERIMENTS_DIR/vendor" installieren
node apps/komki_cli/experiments/pi_packages/run-all.mjs
```

Der Lauf schreibt `results.json`, pro Experiment ein JSON und ein generiertes `LABBOOK.md` in das Laufverzeichnis. Die Rohartefakte des hier dokumentierten Laufs liegen unter:

```text
Hauptlauf:  /var/folders/zb/b95sfwxs10g1wrqvcqy1xjf40000gp/T/opencode/komki-pi-experiments/runs/2026-10-24T10-27-28-776Z/
TUI-Lauf:   /var/folders/zb/b95sfwxs10g1wrqvcqy1xjf40000gp/T/opencode/komki-pi-experiments/runs/2026-10-24T10-27-45-913Z/results/02b-ask-user-tui.json
Canary:     apps/komki_cli/experiments/pi_packages/canary/report-2026-10-24T10-27-45-913Z.json
```

Die Rohartefakte des Hauptlaufs sind nicht Teil des Repos; das Labbook hält die belastbaren Beobachtungen fest. Das Canary-Report-JSON liegt im Repo, weil es klein und prüfbar ist.
