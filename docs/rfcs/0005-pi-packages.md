# RFC 0005: Pi-Packages im KomKI-Harness

| Feld | Wert |
|---|---|
| Status | Draft, Revision 3 (validiert, Umsetzung offen) |
| Stand | 2026-10-24 (Experimente, Node 24.22.1, pi 1.4.0) |
| Gegenstand | Auswahl, Freigabe und Vendoring von pi.dev-Packages für den KomKI-Harness |
| Umsetzung | Policy validiert; Produktivintegration offen (Tickets #154–#163) |
| Verwandt | [RFC 0003](0003-vertrauliche-ki-arbeitsraeume.md), [RFC 0001](0001-vertrauliche-ki-arbeitsraeume.md) (ersetzt das nicht mehr eingecheckte RFC 0000) |
| Labbook | [2026-10-24-pi-package-experiments.md](../research/2026-10-24-pi-package-experiments.md) (in Arbeit) |

Dieses RFC beschreibt, welche pi.dev-Packages der KomKI-Harness aufnehmen darf, unter welchen Bedingungen und mit welcher Validierung. Es ist kein Feature-Katalog: Die meisten Packages sind für Coding-Agenten oder Cloud-Modelle gebaut und für einen lokalen, offline laufenden Ratsarbeitsraum ungeeignet.

Für die projektweiten Begriffe gilt die [kanonische Nomenklatur](../../GLOSSARY.md). Etablierte englische Fachbegriffe bleiben englisch: Package, Extension, Skill, Prompt-Template, Theme, Tool-Allowlist, Vendoring, Pinning, Session, Compaction, trusted code, Egress.

## Kontext

KomKI startet pi als Teil eines lokalen, gesandboxten Arbeitsraums. Der Harness pinnt heute weder pi noch dessen Version (`apps/komki_cli/README.md`; Issue #103) und schaltet alle Extensions bis auf den eingebauten MCP-Client ab:

```text
--no-extensions -e builtin:mcp
```

Dazu kommen `--no-skills`, `--no-context-files`, `--no-prompt-templates` und `--no-themes`. Die Tool-Allowlist ist bewusst klein: in der interaktiven Session `read,write,ls[,find][,grep],mcp__komki__*`, im Headless-Lauf nur `write,mcp__komki__*`.

Der pi.dev-Katalog enthält rund 5.342 Packages (Extensions, Skills, Prompt-Templates, Themes). Für KomKI ist die Auswahl klein, weil vier Randbedingungen gleichzeitig gelten:

1. **Offline:** pi läuft mit `PI_OFFLINE=1` und `--offline`; die tatsächliche Egress-Grenze ist das Seatbelt-Profil. Erlaubt sind nur Loopback zum llama-Server, der Mediator-Unix-Socket und der lokale Syslog-Socket.
2. **Lokales Modell:** Gemma 4 26B-A4B, 128K Kontext, llama.cpp. Viele Packages sind auf große Cloud-Modelle, Provider-Caching oder Coding-Agenten zugeschnitten.
3. **Tool-Allowlist und Mediator:** Fachliche Operationen laufen über den Mediator (Gate 1/Gate 2, PDR-Journal). Ein Package darf diesen Weg nicht umgehen.
4. **GO-Prinzip und Quellenpflicht:** Die KI berät, der Mensch entscheidet. Politisch relevante Aussagen brauchen eine Quelle.

### Der entscheidende Sicherheitsbefund

Pi-Extensions sind trusted code im pi-Prozess, kein Sandbox-Rand:

> „An extension runs inside the Pi process with the same operating-system permissions. It can inspect prompts, tool calls, files, credentials, and session history.“ — [pi extensions docs](https://pi.dev/docs/latest/extensions)

Die Folgen:

- Extension-Code läuft beim Start, auch wenn keines ihrer Tools benutzt wird.
- `--no-extensions` deaktiviert Discovery und Built-ins, aber explizite `-e`-Pfade laden weiterhin ([pi CLI docs](https://pi.dev/docs/latest/cli)).
- `--tools` ersetzt die Tool-Auswahl, verhindert aber nicht die Ausführung von Extension-Code.
- `PI_OFFLINE` stoppt nur pis eigene Netzwerkaktivität, nicht Extension-Code.
- Ein Package kann ein Built-in-Tool wie `read` oder `write` durch Registrierung desselben Namens überschreiben.
- `pi install` führt npm-Lifecycle-Scripts aus; es gibt keine Signatur und kein Vetting.
- Eine Extension kann das Mediator-Token aus der Umgebung und den llama-API-Key aus `pi-home` lesen.

Zuerst stellt sich deshalb die Freigabe- und Vendoring-Frage. Grenze bleibt die OS-Sandbox; keine Extension wird zu einer zweiten Sicherheitsgrenze erklärt.

### Rechercheumfang

Gesichtet wurden ~550 Packages nach Downloads, alle 46 Prompt-Packages und die Top 50 Skills; 15 Packages wurden tief geprüft. Der Katalogsuchdienst ist serverseitig defekt; die Auswahl ist download-gerankt, nicht erschöpfend. Download-Zahlen sind selbstberichtet.

Die tief geprüften Packages:

- Zuverlässigkeit/Kontext: `pi-tool-repair`, `@sting8k/pi-vcc`, `@spences10/pi-context`, `pi-cache-optimizer`
- Planung/Governance: `@mjasnikovs/pi-task`, `pi-daddy`, `@juicesharp/rpiv-ask-user-question`, `pi-verdict`, `@gotgenes/pi-permission-system`
- Dokumente/Memory/Privacy: `pi-quiver`, `pi-hermes-memory`, `pi-information-protecter`, `pi-llama-cpp`, `@ff-labs/pi-fff`
- Zusätzlich: `@juicesharp/rpiv-todo`

## Entscheidung

### D1 — Package-Policy (vendoren, pinnen, prüfen, explizit laden)

1. Packages werden nicht zur Laufzeit mit `pi install` installiert. Installation und Vendoring passieren beim Build/Init.
2. Beim Vendoring wird jedes Package als Tarball bezogen, gegen Registry-Integrität und einen eigenen SHA-256-Hash geprüft, unter `apps/komki_cli/priv/pi-packages/<name>/<version>/` entpackt und mit `npm install --omit=dev --ignore-scripts` installiert.
3. Das Manifest hält `name`, `version`, `tarball-sha256`, `license`, `source-url`, `reviewed-by` und `reviewed-at`.
4. Geladen wird ausschließlich per explizitem `-e <pfad>`; `--no-extensions` bleibt die Grundregel. `settings.json`, Discovery und Projekt-Trust bleiben aus.
5. Vor dem Start prüft `komki doctor` Manifest und Hashes und verweigert den Lauf bei Abweichung.

### D2 — Session und Headless trennen

- **Headless (`--print`):** bleibt bei `-e builtin:mcp` und `--tools write,mcp__komki__*`. Dritte Extensions, Rückfragen und Todo-Persistenz bleiben aus.
- **Interaktive Session:** darf die freigegebenen Packages laden. Die Tool-Allowlist wird um die tatsächlich benötigten Tools erweitert; Klartextnamen ersetzen die gesamte Auswahl, deshalb muss die Liste vollständig sein.

### D3 — Package-Entscheidungen

| Package | Entscheidung | Begründung in einem Satz |
|---|---|---|
| `@juicesharp/rpiv-todo` | **Aufnehmen (validiert)** | Durable Aufgabenliste ohne Netzwerk- oder Dateizugriffe; Experiment 01 belegt Create, Resume und Allowlist-Kompatibilität. |
| `@juicesharp/rpiv-ask-user-question` | **Aufnehmen (validiert, RPC + TUI)** | Strukturierte Rückfragen machen GO dokumentierbar; Experiment 02 belegt RPC-Dialog, tmux-TUI und das Entfernen im Headless-Modus. |
| `pi-tool-repair` | **Pilot, eng begrenzt** | Repariert dokumentierte Alias-Fehler (`file_path` → `path`), aber nicht beliebige malformed Argumente; Experiment 03 belegt beides. |
| `@sting8k/pi-vcc` | **Bedingt** | Algorithmische Compaction spart den Summary-Call; die semantische Extraktion ist englisch, Experiment 04 belegt das Scheitern deutscher Präferenzen. |
| `@spences10/pi-context` | **Pilot (Node 24.22.1)** | Der Retrieval-Loop funktioniert; mit Node 24.22.1 ist die deklarierte Anforderung ≥ 24.15 erfüllt, Experiment 05 besteht. |
| `@gotgenes/pi-permission-system` | **Pilot, optional** | Deterministisches Pfad-Gate funktioniert (Experiment 06); nur sinnvoll, wenn per-Call-`ask` oder Pfad-Confine-ment zusätzlich zur Seatbelt-Grenze gebraucht wird. |
| `pi-quiver` | **Pilot, nur `doc_to_md`** | Offline-Extraktion über den degradierten `unpdf`-Tier funktioniert (Experiment 07); OCR und echte RIS-PDFs sind ungetestet. |
| `pi-hermes-memory` | **Bedingt, nur read-only** | Anchor-Suche funktioniert ohne Memory-Schreibvorgänge (Experiment 08); die automatische Lernlogik bleibt deaktiviert. |
| `@mjasnikovs/pi-task` | **Ablehnen** | Unauthentifizierter LAN-Server, Web-Egress, Child-Agenten mit `bash`/`edit` außerhalb der Allowlist, AGPL-3.0. |
| `pi-daddy` | **Ablehnen** | Nur Linux/x64; KomKI läuft auf macOS/ARM und hat keinen Subagenten-Baum. |
| `pi-verdict` | **Ablehnen** | Ein Modell-Klassifikator darf Tool-Calls automatisch erlauben; das widerspricht GO. |
| `pi-information-protecter` | **Ablehnen** | Schützt die Loopback-Modellgrenze statt des Connector-Egress, legt ein plaintext-Secret-Log an und verfälscht Zahlen/Daten. |
| `pi-llama-cpp` | **Ablehnen** | Dupliziert den bereits gesandboxten llama-server-Lifecycle und kann Modellzustand hinter dem Harness ändern. |
| `@ff-labs/pi-fff` | **Ablehnen** | Ruft `setActiveTools` auf und fügt Tools außerhalb der Allowlist hinzu; scannt per Default `$HOME`. |
| `pi-cache-optimizer` | **Ablehnen** | 885 KB Remote-Provider-Cache-Maschinerie mit Prompt-Rewrite; für llama.cpp mit Prefix-Cache kein messbarer Nutzen. |

Ebenfalls abgelehnt: direkte Web-/Browser-Packages, zweite MCP-Clients, Cloud-Telemetrie, externe Judge-Modelle und modellgetriebene Kompressionspakete. **Subagenten-Packages sind zurückgestellt, nicht dauerhaft abgelehnt**; `pi-subagents` wird in D8 gesondert bewertet.

### D4 — Anforderungen an eine Aufnahme

Ein Package wird nur aufgenommen, wenn es die folgenden Anforderungen erfüllt:

| ID | Anforderung |
|---|---|
| R1 | Keine eigenen Netzwerkzugriffe; alle Modellaufrufe laufen über den konfigurierten lokalen Provider. |
| R2 | Keine Tool-Registrierung außerhalb der deklarierten Allowlist; kein `setActiveTools`, kein Shadowing von Built-ins. |
| R3 | Keine Schreibvorgänge außerhalb von `pi-home`, `arbeit` und dem Session-Verzeichnis. |
| R4 | Keine Lifecycle-Scripts beim Install; Abhängigkeiten sind gepinnt und lizenzkompatibel. |
| R5 | Kompatibel mit der installierten pi-Version (1.4.0) und der dokumentierten Flag-Oberfläche (`-ne`, `-e`, `--tools`). |
| R6 | Nutzen für die Ratsarbeit ist belegbar, nicht nur für Coding-Agenten. |
| R7 | Das Package schwächt GO, Quellenpflicht oder den Mediator nicht. |
| R8 | Ein Abbruchkriterium ist definiert; ein fehlgeschlagener Test führt nicht zu einer stillen Deaktivierung. |

### D5 — Validierung vor Aufnahme

Jedes Package durchläuft vor der Aufnahme eine Experimentreihe:

1. **Statisch:** Quelltext-Scan auf Netzwerk, Exec, Eval, `setActiveTools`, `registerProvider`, `process.env`; Dependency-, Lizenz- und Script-Prüfung.
2. **Funktional:** deterministischer Mock-Provider, isoliertes `PI_CODING_AGENT_DIR`, explizite `-e`-Pfade, Tool-Allowlist.
3. **Sicherheit:** Canary-Extension, die `fetch` und `exec` versucht; das Seatbelt-Profil muss beides verweigern. Zusätzlich: kein Schreibpfad außerhalb der erlaubten Verzeichnisse.
4. **Deutsch:** typische Sitzungsmappe-, Antrags- und Recherche-Sitzungen; Prüfung, ob Fakten, Entscheidungen und Quellen nach Compaction erhalten bleiben.
5. **Upgrade:** pi 1.4.0 und die nächste getestete Version; bei API-Bruch meldet `doctor` fail-closed.

Das Labbook unter `docs/research/2026-10-24-pi-package-experiments.md` hält Hypothese, Methode, Beobachtung, Ergebnis und Verdikt je Package fest.

### D6 — Experimentelle Ergebnisse

Am 2026-10-24 liefen acht Experimente mit pi 1.4.0, Node 24.22.1 und einem deterministischen Mock-Provider. Sechs bestanden, eines ist bedingt, eines fiel durch. Die Experimente prüfen Mechanik und Grenzen, nicht die Antwortqualität des 26B-Modells.

| ID | Package | Kernbeobachtung | Verdikt |
|---|---|---|---|
| 01 | `@juicesharp/rpiv-todo` | `Created #1`; `rpiv-todo-state`-Eintrag; `--continue` listet die Aufgabe; keine extension-attribuierten Schreibvorgänge außerhalb der Session. | **PASS** |
| 02 | `@juicesharp/rpiv-ask-user-question` | Headless wird das Tool entfernt (`declaredTools: []`); RPC-Dialog und tmux-TUI zeigen die Frage, `1` wählt `Option A`, die Antwort erreicht den Modellkontext; kein Hang. | **PASS** |
| 03 | `pi-tool-repair` | `{path:[…], content:{text:…}}` wird nicht repariert (A und B scheitern); der dokumentierte Alias `file_path` → `path` wird repariert; System-Prompt byte-gleich (2108 Bytes). | **FAIL** |
| 04 | `@sting8k/pi-vcc` | VCC mit `overrideDefaultCompaction:true`: 2 Requests, 0 Summary-Requests, `details.compactor: "pi-vcc"`. Default: 3 Requests, 1 Summary. Deutsche Präferenzen `[]`, deutsche Scope-Wechsel unerkannt; englische Kontrollen bestehen. | **CONDITIONAL** |
| 05 | `@spences10/pi-context` | Node 24.22.1 erfüllt ≥ 24.15.0. Ladbar: Receipt, `context_search`-Treffer, `context.db` im Agent-Dir, `context_export` nicht allowlistet. | **PASS** |
| 06 | `@gotgenes/pi-permission-system` | Baseline schreibt `work/ok.txt` und `escape.txt`; mit Policy wird `work/ok.txt` geschrieben, `escape.txt` in-band verweigert und bleibt absent; kein Hang. | **PASS** |
| 07 | `pi-quiver` | Nur `doc_to_md` registriert; `unpdf`-Tier extrahiert `TOP 1 Bahnhofstraße` ohne `uv` und ohne Netzwerk; Struktur degradiert, keine OCR. | **PASS** |
| 08 | `pi-hermes-memory` | `session_search` liefert `…/fixture-session.jsonl:2-3`; keine Memory-DB und keine Markdown-Memory-Dateien bei deaktivierter Lernlogik. | **PASS** |

**Konsequenzen aus den Experimenten:**

- `rpiv-todo` und `rpiv-ask-user-question` erfüllen die Aufnahmeanforderungen. `ask_user_question` ist im Headless-Lauf unsichtbar; die Freigabe gilt nur für die interaktive Session.
- `pi-tool-repair` ist **kein allgemeiner Repair-Layer**. Es hilft bei dokumentierten Alias-Fehlern, nicht bei beliebig geformten Argumenten. Vor einer Freigabe braucht es einen Korpus echter 26B-Fehlaufrufe; sonst bleibt es draußen.
- `pi-vcc` spart den Summary-Call nachweislich, ist aber für deutsche semantische Abschnitte ungeeignet. Ohne deutschen Extractor oder eine bewusste Beschränkung auf englischsprachige Sitzungen bleibt es bedingt.
- `pi-context` besteht mit Node 24.22.1. Die Node-Version ist damit eine Laufzeitvoraussetzung, keine Package-Eigenschaft; der Harness pinnt sie in `.tool-versions`.
- `pi-permission-system` erzwingt das Pfad-Gate wie dokumentiert. Es bleibt optional, weil die Seatbelt-Grenze bereits existiert.
- `pi-quiver` funktioniert offline im degradierten `unpdf`-Tier. Echte RIS-PDFs, Scans und OCR sind ungetestet; der Mediator-Connector um `tools/pdf_ingest` bleibt der belastbarere Weg.
- `pi-hermes-memory` funktioniert read-only. Die Lern- und Schreiblogik bleibt aus, weil der Vault die Source of Truth ist.

### D7 — Supply-Chain-Härtung

Vendoring, Pinning und SHA-256 sind **Integritäts- und Reproduzierbarkeitsschutz**, keine Trust-Boundary. Sie verhindern, dass ein Package zwischen zwei Läufen unbemerkt wechselt, dass ein beschädigter Tarball verwendet wird und dass Installations-Scripts laufen. Sie verhindern **nicht**, dass die gepinnte Version selbst bösartig ist.

| Risiko | Abdeckung durch D1 | Zusätzliche Maßnahme |
|---|---|---|
| Unbemerkter Package-Update | Ja: exakte Version, SHA-256 | Update nur über reviewed Manifest |
| Beschädigter oder vertauschter Tarball | Ja: Registry-Integrität plus eigener Hash | `npm audit signatures` und Provenance prüfen |
| Lifecycle-Script beim Install | Ja: `--ignore-scripts` | `npm ci` statt `npm install`, Lockfile committen |
| Transitive Dependency-Drift | Teilweise: Installation aus dem Tarball | Lockfile, SBOM, Dependency-Allowlist |
| Bösartige gepinnte Version | Nein | Quelltext-Review, Maintainer- und Provenance-Prüfung, Canary |
| Bösartige transitive Dependency | Nein | Lockfile-Review, SBOM, wenige Dependencies |
| Kompromittiertes pi-Bundle | Nein | pi-Version pinnen oder Bundle-Hash prüfen |
| Extension liest Credentials | Nein | Extensions als trusted code behandeln; Session-only, keine Fremd-Extensions headless |
| Extension schreibt außerhalb erlaubter Pfade | Teilweise: Seatbelt | Canary-Test, Pfad-Gate nur als Zusatz |

Konkrete Härtungsschritte:

1. **Provenance:** `npm audit signatures` im Vendor-Build; nur Packages mit gültiger Registry-Signatur oder nachvollziehbarer Provenance aufnehmen. Das ist ein Signal, kein Beweis.
2. **Lockfile:** Das Vendor-Verzeichnis bekommt ein eigenes `package-lock.json`; der Build nutzt `npm ci --ignore-scripts`. Der Lockfile wird reviewt, nicht nur erzeugt.
3. **SBOM:** CycloneDX oder SPDX über den Vendor-Tree erzeugen und ablegen. Sie macht transitive Abhängigkeiten sichtbar, verhindert aber keinen Angriff.
4. **Quelltext-Review:** Jedes Package wird in der gepinnten Version gelesen, nicht nur gescannt. Der Review-Stand wird mit Commit, Datum und Prüfer im Manifest festgehalten.
5. **Dependency-Allowlist:** Neue transitive Packages sind erklärungspflichtig. Pakete mit `postinstall` werden nicht aufgenommen, solange es eine Alternative gibt.
6. **pi pinnen:** pi selbst ist heute ungepinnt (Issue #103). Mindestens der Bundle-Hash sollte pro Release im Manifest stehen; besser ist ein gepinnter pi-Version-Pin mit eigenem Upgrade-Test.
7. **Canary:** Eine Test-Extension versucht `fetch` und `exec`; unter dem Seatbelt-Profil müssen beide scheitern. Der Test läuft vor der Aufnahme eines jeden Packages.
8. **Least Privilege:** Packages nur in der interaktiven Session, nie headless; keine `bash`-Allowlist; `context_export` bleibt aus; `yoloMode` und session-weite Approvals bleiben aus.

Der Canary vom 2026-10-24 bestätigt die Grenze und die Reste:

- Externer `fetch("https://example.com")`: `TypeError: fetch failed`, Ursache `getaddrinfo ENOTFOUND` (DNS/Egress blockiert).
- `execFile("/bin/echo")`: `spawn EPERM`.
- Schreiben nach `/tmp/komki-canary-escape.txt`: `EPERM`; die Datei fehlt auch auf dem Host.
- Mock-Provider auf dem erlaubten Loopback-Port: HTTP 200; der erlaubte Weg funktioniert.
- `KOMKI_MEDIATOR_TOKEN`: im Prozess-Environment sichtbar.
- `models.json`: lesbar und enthält einen `apiKey`; `auth.json`: lesbar. Der separate `llama.key` unter `base/tmp` ist nicht lesbar, weil das pi-Profil nur `pi-home` und den Scratch freigibt.

Residualrisiken bleiben damit: Eine gepinnte, aber bösartige Extension läuft mit den Rechten des pi-Prozesses und kann das Mediator-Token sowie den Provider-Key aus `models.json` lesen. Die OS-Sandbox begrenzt Datei- und Netzwerkzugriffe, nicht die In-Process-Sicht. Deshalb bleibt jede Aufnahme eine Freigabe von trusted code, keine reine Hashprüfung.

### D8 — Subagenten: zurückgestellt

`pi-subagents` ist kein reines Tool, sondern eine Orchestrierungsschicht: Es startet Kind-Sessions, verwaltet Agent-Definitionen, Modelle, Werkzeuge, Erweiterungen und im Hintergrund einen detached Runner. Das Paket ist MIT-lizenziert, 10,3 MB groß, hat fünf Dependencies und verlangt **Pi 1.2.0 oder neuer**. KomKI läuft seit dem Upgrade auf 1.4.0; die Versionssperre ist damit weg. Die übrigen Gates bleiben.

Die Mechanik ist für KomKI nicht per Default sicher:

- **Tool-Allowlist wird nicht vererbt.** Ein Kind bekommt Pis normale Built-in-Tools, wenn das Agent-Frontmatter keine `tools`-Liste setzt. KomKIs `--tools` gilt nur für den Elternprozess.
- **Foreground-Kinder** laufen als Sessions im Elternprozess und laden keine ambienten Extensions. **Background-Kinder** laufen in einem detached Runner und laden die ambienten Extensions, sofern das Agent-Frontmatter nicht `extensions: []` setzt.
- **Netzwerk:** Die Built-ins `researcher` und `evidence-auditor` verlangen `pi-web-access` im Kind. Das ist direkter Egress am Mediator vorbei und für KomKI nicht akzeptabel.
- **Kosten:** Jedes Kind ist eine eigene 26B-Session. Parallele Reviewer oder Scouts vervielfachen Token, Zeit und Speicher; der Nutzen muss gegen einen einzelnen Lauf gemessen werden.
- **Provenienz:** Kind-Output ist Modelltext. Ohne eigenes Ausgabeschema und Quellenanker verschiebt sich die Quellenprüfung nur eine Ebene nach unten. `worker` darf Dateien schreiben; das kollidiert mit GO, solange die Rolle nicht ausdrücklich freigegeben ist.

Wo Subagenten helfen könnten, sind **read-only Rollen**:

| Rolle | Aufgabe | Tools | Warum |
|---|---|---|---|
| `quellen-pruefer` | Aussagen gegen lokale Quellen prüfen, ungestützte Aussagen markieren | `read,grep,find,ls` | Entlastet den Hauptlauf, ohne Egress |
| `top-extrakt` | TOP/PDF in strukturierte Aussagen mit Seitenanker zerlegen | `read` | Quellennahe Extraktion |
| `deutsch-redakteur` | Stil und Grammatik prüfen, keine Fakten ändern | `read` | Textqualität ohne Recherche |
| `suchplaner` | Suchbegriffe für den Mediator formulieren | keine oder `read` | Kein direkter Netzwerkzugriff |

Pilot-Gate vor einer Aufnahme:

1. pi auf ≥ 1.2.0 heben und die bestehenden Contract-Tests erneut fahren. Erledigt: pi 1.4.0, `mix test` 219 Tests, 0 Fehler.
2. `pi-subagents` vendoren, pinnen und statisch prüfen; die fünf Dependencies und den 10,3-MB-Bundle reviewen.
3. Nur Foreground-Kinder, zunächst `maxSubagentDepth: 1`, `allowNestedSubagents: false`, `maxSubagentSpawnsPerRun: 2`.
4. Jedes Agent-Frontmatter explizit: `tools: read,grep,find,ls`, `extensions: []`, `model: pi-local/local-model`, `inheritProjectContext: false`, `inheritGlobalContext: false`, `inheritSkills: false`, `async: false`.
5. Canary auch für das Kind: kein `fetch`, kein `exec`, kein Schreiben außerhalb des Scratch.
6. Ausgabeschema mit `claim`, `source`, `page`, `retrieved_at`, `unsupported`; der Elternlauf prüft die Anker.
7. Messung: ein 26B-Lauf gegen zwei Kinder auf denselben Aufgaben; Latenz, Token, Speicher und Fehlerquote.

`pi-subagents` ist damit ein Kandidat für Phase 3, nicht für die erste Integration. Die Idee dedizierter Rollen ist richtig; die erste Rolle sollte read-only Quellenprüfung sein, nicht `worker`.

## Begründung der Aufnahmen

### `rpiv-todo`

**Was es hinzufügt:** Ein model-callable `todo`-Tool mit `create`, `update`, `list`, `get`, `delete`, `clear`; Zustände `pending`, `in_progress`, `completed` plus Tombstone; `blockedBy`-Abhängigkeiten; `/todos` und ein Live-Overlay. Der Zustand wird über `pi.appendEntry()` in Session-Einträgen gespeichert und bei `session_start`, `session_compact` und `session_tree` rekonstruiert.

**Welches Problem es löst:** Ein 26B-Modell verliert bei langen Aufgaben den Plan; pi hat kein eingebautes Todo-Tool; Compaction ersetzt alte Nachrichten durch eine Zusammenfassung und entfernt damit den Plan.

**Warum aufnehmen:** 118 KB, MIT, eine dependency-freie Config-Dependency, ohne Netzwerkzugriffe, ohne Dateischreibvorgänge und ohne `setActiveTools`. Das Tool muss explizit in `--tools` stehen; es kann die Allowlist nicht umgehen. Deutsche Locale ist enthalten.

**Risiko:** Aufgaben-Texte landen im Session-JSONL. Todos bleiben frei von Personendaten. Headless hat keine Persistenz.

### `rpiv-ask-user-question`

**Was es hinzufügt:** `ask_user_question` mit bis zu vier Fragen, typisierten Optionen, Freitext und Notizen; Frage und Antwort landen im Transkript.

**Welches Problem es löst:** Das Modell rät bei fehlenden Angaben oder handelt ohne explizites GO. Freitext im Chat ist kein strukturierter Nachweis.

**Warum aufnehmen:** 335 KB, eine kleine Config-Dependency, ohne Modell- oder Netzwerkaufrufe und ohne Schreibvorgänge. Es ist die fehlende UX für das GO-Prinzip.

**Risiko:** Advisory, kein Gate; nur interaktiv; Antworten und Notizen werden Transkripttext. Vor jedem `write` oder politisch relevanten Schritt muss eine dokumentierte Antwort vorliegen.

## Konsequenzen

### Positiv

- Aufgabenführung und GO werden strukturell, nicht nur per Prompt: `rpiv-todo` und `rpiv-ask-user-question` sind experimentell bestätigt.
- RPC-Dialog und tmux-TUI von `ask_user_question` sind belegt; im Headless-Lauf bleibt das Tool unsichtbar.
- Compaction ohne Summary-Call ist mit `pi-vcc` belegt; die Rohtranskript-Suche bleibt verfügbar.
- Der Seatbelt-Canary bestätigt: externe Fetches, `exec` und Schreiben außerhalb der erlaubten Pfade scheitern; der erlaubte Loopback-Port funktioniert.
- Die Package-Auswahl bleibt klein und auditierbar.

### Negativ

- Jedes Package vergrößert die Supply-Chain-Fläche und die Upgrade-Kopplung an pi.
- `rpiv-todo` und `rpiv-ask-user-question` schreiben Inhalte in das Session-JSONL; das Session-Verzeichnis bleibt ein sensibler Ort.
- `pi-tool-repair` repariert nachweislich nur dokumentierte Alias-Fehler, nicht beliebige malformed Argumente; ein allgemeiner Repair-Layer ist damit nicht belegt.
- `pi-vcc` verändert Compaction-Summaries und verliert deutsche Präferenzen und Scope-Wechsel; für deutsche Sitzungen ist es ohne eigenen Extractor nicht geeignet.
- `pi-context` verlangt Node ≥ 24.15; der Harness pinnt jetzt 24.22.1. Ohne diesen Pin bleibt das Package außen vor.
- `pi-quiver` ist im Offline-Tier degradiert (ohne Struktur und ohne OCR); der verlässlichere Weg bleibt ein Mediator-Connector um `tools/pdf_ingest`.
- `pi-hermes-memory` darf nur read-only betrieben werden; die Lernlogik würde eine zweite Quelle neben dem Vault schaffen.

### Mitigationen

- Vendoring, SHA-256-Manifest, `--ignore-scripts`, Lizenzprüfung.
- Statischer Scan und Canary-Extension in der CI.
- Session-only-Freigabe für interaktive Packages; Headless bleibt minimal.
- Todo- und Frageinhalte bleiben frei von Personendaten.
- `context_export` bleibt außerhalb der Allowlist; DB und Exporte liegen im Sandbox-Pfad.
- `grammarRepair`, `yoloMode` und session-weite Approvals bleiben aus.

## Umsetzungsstand

Die Policy ist entschieden und experimentell validiert. Die Produktivintegration ist noch nicht implementiert. Die offenen Arbeiten sind als GitHub Issues angelegt:

| Ticket | Gegenstand | Status |
|---|---|---|
| [#154](https://github.com/croesnick/kommunalpolitik_ki/issues/154) | Vendoring-Pipeline, Manifest, `doctor`-Hashprüfung | offen |
| [#155](https://github.com/croesnick/kommunalpolitik_ki/issues/155) | `rpiv-todo` und `ask_user_question` session-only integrieren | offen, blockiert durch #154 |
| [#156](https://github.com/croesnick/kommunalpolitik_ki/issues/156) | Seatbelt-Canary als Freigabe-Gate | offen, blockiert durch #154/#155 |
| [#157](https://github.com/croesnick/kommunalpolitik_ki/issues/157) | Supply-Chain-Härtung (Provenance, Lockfile, SBOM, pi-Pin) | offen, blockiert durch #154 |
| [#158](https://github.com/croesnick/kommunalpolitik_ki/issues/158) | Realmodell-Smoke-Test mit Gemma 4 26B | offen |
| [#159](https://github.com/croesnick/kommunalpolitik_ki/issues/159) | `pi-vcc`: deutscher Extractor oder Sprachbeschränkung | offen |
| [#160](https://github.com/croesnick/kommunalpolitik_ki/issues/160) | `pi-quiver`: echte RIS-PDFs, Scans, OCR | offen |
| [#161](https://github.com/croesnick/kommunalpolitik_ki/issues/161) | `pi-subagents`: read-only Pilot | offen, blockiert durch #154/#156/#157 |
| [#162](https://github.com/croesnick/kommunalpolitik_ki/issues/162) | `pi-context` und `pi-hermes-memory`: Datenhaltung/read-only | offen, blockiert durch #154 |
| [#163](https://github.com/croesnick/kommunalpolitik_ki/issues/163) | `pi-tool-repair`: echter 26B-Fehlerkorpus | offen, blockiert durch #158 |

Das Connector-Gesamtsetup (RIS, Web, Vault) ist nicht Gegenstand dieses RFC. Es wird im Rahmen von [#147](https://github.com/croesnick/kommunalpolitik_ki/issues/147) und dem [Connector-Labbook](../research/2026-10-23-labbook-komki-connectoren.md) geführt.

## Alternativen

1. **Variante ohne Packages.** KomKI bleibt bei `--no-extensions -e builtin:mcp` und baut Aufgabenführung, Rückfragen und Quellenbindung selbst als MCP-Tools. Sicherer, aber mehr Eigenbau.
2. **Nur Skills und Prompt-Templates.** Inerte Daten statt Extension-Code. Geringeres Risiko, aber ohne Tool-Zustand und ohne strukturierte Rückfragen.
3. **Pi forken oder die Packages in den eigenen Code kopieren.** Maximale Kontrolle, hoher Wartungsaufwand; kommt nur für kleine, klar abgegrenzte Extensions infrage.
4. **Pi-Updates kontrolliert heben.** 1.4.0 ist installiert; die Contract-Tests sind grün. Ein weiteres Upgrade muss Package-Kompatibilität, Canary und Experimente erneut prüfen.

## Offene Fragen

- Bleibt der `rpiv:ask-user:answer`-Eventbus als alternativer Antwortkanal außen vor, oder braucht KomKI ihn für eine spätere Pane-Steuerung?
- Wie häufig sind die von `pi-tool-repair` reparierten Alias-Fehler im echten 26B-Betrieb? Ohne einen Korpus echter Fehlaufrufe bleibt der Nutzen unklar.
- Wie aufwendig ist ein deutscher Extractor für `pi-vcc` (Präferenzen, Scope-Wechsel), und lohnt er sich gegenüber Pis eingebauter Compaction?
- Bleibt Node 24.22.1 die gepinnte Harness-Version, und wie wird der Node-Pin bei einem pi-Upgrade mitgeprüft?
- Kann `pi-quiver` echte RIS-PDFs und Scans im Offline-Tier verlässlich verarbeiten, oder bleibt nur der Mediator-Connector?
- Ist der Canary-Test (Extension versucht `fetch`/`exec`, Seatbelt verweigert) bestanden, bevor irgendein Package in die Session darf?
- Wie werden Package-Updates geprüft, wenn pi selbst ungepinnt bleibt?
- Bringt `pi-subagents` nach einem pi-Upgrade auf ≥ 1.2.0 und mit read-only Agenten einen messbaren Vorteil gegenüber einem einzelnen 26B-Lauf?

## Referenzen

- [pi packages docs](https://pi.dev/docs/latest/packages)
- [pi extensions docs](https://pi.dev/docs/latest/extensions)
- [pi CLI docs](https://pi.dev/docs/latest/cli)
- [pi security docs](https://pi.dev/docs/latest/security)
- [pi compaction docs](https://pi.dev/docs/latest/compaction)
- [rpiv-todo](https://pi.dev/packages/@juicesharp/rpiv-todo)
- [rpiv-ask-user-question](https://pi.dev/packages/@juicesharp/rpiv-ask-user-question)
- [pi-tool-repair](https://pi.dev/packages/pi-tool-repair)
- [pi-vcc](https://pi.dev/packages/@sting8k/pi-vcc)
- [pi-context](https://pi.dev/packages/@spences10/pi-context)
- [pi-permission-system](https://pi.dev/packages/@gotgenes/pi-permission-system)
- [pi-quiver](https://pi.dev/packages/pi-quiver)
- [pi-hermes-memory](https://pi.dev/packages/pi-hermes-memory)
- [`docs/research/2026-10-24-pi-package-experiments.md`](../research/2026-10-24-pi-package-experiments.md) (Labbook mit Ergebnissen)
- `apps/komki_cli/experiments/pi_packages/` (reproduzierbarer Harness)
