# Probebericht: Harness und Sandbox für den Lernbetrieb

| Feld | Wert |
|---|---|
| Datum | 2026-10-04 |
| Gegenstand | Lokale Seatbelt-Abgrenzungsprobe für eine gepinnte Harness-/Sandbox-Kombination im Lernbetrieb: Phase 1 (Profil-Reparatur und Gates), Phase 2 (Harness-Gates OpenCode vs. pi), Phase 3 (echte Inferenz über llama-server). |
| Entscheidung | Die Auswahl wurde menschlich im Wayfinder-Ticket [Nr. 70](https://github.com/croesnick/kommunalpolitik_ki/issues/70) getroffen; dieser Bericht liefert die beobachtete Beweislage, keine Entscheidung und keine Isolationsbehauptung über die beobachteten Gates hinaus. |
| Beweislabels | [B] beobachteter Einzelfall: lokal unter Profil gemessen (rc/errno). [E] Kernel-Evidenz: `deny`-Zeile aus dem Unified Log. [D] dokumentiert: externe Quelle mit Abrufdatum. [S] Schluss: aus Belegen abgeleitet. [U] offen/ungetestet. |
| Provenanz | Die Rohbelege liegen im ephemeren Probebaum `$TMPDIR/open/probe-70` (Temp-Verzeichnis, nicht langlebig); alle entscheidenden Zahlen sind hier inline konsolidiert. Attempt-Wurzeln: `07-path-pin` und `08-harness-phase2` (run_id `2533a3f65e3444da`). |

## 1. Auftrag und GO-Basis

Maßgeblich ist das dokumentierte GO aus der Probe-Sitzung (Datei `probe-70-authorizations.md`), Kerne:

- Native Seatbelt-Proben mit synthetischen Fixtures; OpenCode und pi vergleichen, danach entscheidet der Mensch.
- Lokale Inferenz über llama.cpp oder eine bereits vorhandene MLX-Laufzeit; Ollama ist einschließlich Rückfall ausgeschlossen.
- Höchstens ein kleines öffentliches Modellartefakt (pinned GGUF), Herkunft und Integrität dokumentiert; keine Runtime-Pakete installieren.
- Keine Vault-, RIS-, Obsidian- oder Credential-Zugriffe; keine Änderungen an Benutzerkonfiguration, Host-DNS oder fremden Diensten.
- Externe Testbudgets: insgesamt höchstens zwei TCP-Verbindungsversuche zu `1.1.1.1:443` ohne Anwendungsdaten und höchstens zwei Systemresolver-Aufrufe für zufällige `probe-<nonce>.example.com`-Namen; je eine Kontrolle ohne Profil und ein Versuch mit Profil. Budget zählt API-Aufrufe, keine DNS-Pakete.
- Keine Isolations- oder Konformitätsbehauptung; lokale Integration, Modellqualität und Abschirmung werden getrennt beurteilt.

## 2. Phase 1: Instabilitätsbefund, Bisect, korrigierter Kandidat

### 2.1 Instabilitätsbefund (Overnight-Flip)

Identische deny-default-Profile (SHA unverändert) booteten 2026-10-03 ca. 21:01 UTC `/usr/bin/true`, `/bin/sh`, `python3.9` sauber [B]; ab 2026-10-04 06:26 UTC starben alle Kinder mit instanter SIGABRT (ca. 10 ms, kein `.ips`-Report) [B]; Daemon-Startzeiten und Boot-Kontext in `artifacts/diagnostics.json`. `(allow default)`-Profile liefen unveränderlich weiter [B]. Kein Reboot seit 2026-09-25 [B]. Wurzelursache ungeklärt [U]; siehe Abschnitt 7.

### 2.2 Klassen-Bisect (Attempt 06)

Ladder A (`allow default` + je eine einzeln verweigerte Klasse) reproduzierte die exakte Abort-Signatur `-6` (SIGABRT) nur für **`file-read-data`** (auch als Paar mit `file-read-metadata`) [B]:

- `deny file-read-metadata` allein → rc 0 (no-abort).
- `process-info*` → rc −5 (SIGTRAP, andere Signatur).
- `sysctl*`, `iokit*`, `signal`, `job-creation`, `file-write*`, `mach-lookup` → rc 0.

Ladder B (deny-default-Kandidat + genau `allow file-read-data`): `/usr/bin/true` → exit 0; `/bin/sh -c "exit 0"` → exit 1 mit sauberem EPERM statt SIGABRT [B]. Damit war die Abort-Klasse identifiziert und als gezielte Zulassung behandelbar [S]; die Bootstrap-Fähigkeit braucht weiter oben benannte Zusatzzulassungen [S].

Zwischenergebnis: vier der 18 Klassenformen waren Parserfehler (`file-ioctl*`, `dtrace*` u. a.) — korrigiert gegen `/System/Library/Sandbox/Profiles/*.sb`: `ipc-posix-shm*`, `ipc-posix-sem*` gültig; `file-ioctl` ohne Stern; `dtrace-restrict` ungeklärt [B].

### 2.3 Load-bearing Pfade (Unified Log, Attempt 06/07)

Verbatim beobachtete lastgebende Operationen beim Boot unter deny-default [E]:

```
file-read-metadata /bin/sh, /bin, /System/Cryptexes/OS, /var,
                   /private/var/select/sh
file-read-data     /
process-info-pidinfo self
sysctl-read *
file-write-data    /dev/dtracehelper, /dev/tty
mach-lookup        com.apple.system.notification_center,
                   com.apple.system.opendirectoryd.libinfo
```

Ein-Pfad-Pinning (je nur einer dieser Pfade) reichte nicht zum sauberen Boot: sechs Ein-Pfad-Fälle, alle SIGABRT (rc −6) [B]; der Kandidat entstand als deny-default-Atom plus minimaler, einzeln belegter Erweiterungen [S].

### 2.4 Korrigierter Kandidat `llm-lern-07-v3`

SHA256 `7cb11230a5c90495c194d5a15cae99db22156d052f13949fa335a37d9ff2c668` [B] (V3). Vorgeschichte: V2 (SHA `fd97386c…`) bootete true/sh/Python, verletzte aber die Kontrolle (H1-control-read refuted: `control/manifest` lag innerhalb eines `file-read*`-Subpfads) [B]; in V3 wurde die Manifest-Lesbarkeit entfernt — alle Gates grün.

Narrow-Additions in V3, jede mit Violation-Beleg [E→Zulassung]:

| Zulassung | Beleg |
|---|---|
| `/private/var/select/sh` (+ metadata `/private/var/select`) | npm-Laufzeit löst `sh` auf |
| `/bin` (subpath) | behebt `getcwd`-Fehler |
| `/bin/bash` (`process-exec`, `file-read*`, metadata) | sh-Varianten-Startkette |
| `/dev/random`, `/dev/urandom` (`file-read*`) | Python `_Py_HashRandomization_Init` |
| `/dev/null` (write), `/` (data, Reminder) | process-start |

Boot-Ladder V3 [B]: `/usr/bin/true` rc 0; `/bin/sh -c 'exit 0'` rc 0; Python-Helper-Bootstrap rc 0 mit sauberem Fixture-Roundtrip.

### 2.5 Gate-Urteile unter V3 (Phase 1)

| Gate | Ergebnis |
|---|---|
| H1-guard-read / guard-write / control-read / control-write / child-guard-read | jeweils supported — rc 20, sauberes EPERM; Kontrolle-Canary außerhalb des Lesestands |
| H2-baseline allowed/denied | supported — unsandboxed Empfänger erreicht beides |
| H2-bind (unerlaubter Port) | supported — rc 20 |
| H2-sandbox-tcp allowed | supported — rc 0, Nonce übermittelt |
| H2-sandbox-tcp denied | supported — rc 20, kein Nonce-Ankunft beim verweigerten Empfänger |
| H3-tcp-ext-profile (extern `1.1.1.1:443` mit Profil) | supported — rc 20, errno 1 (EPERM) |
| H3-tcp-ext-control (ohne Profil) | supported/limitiert — rc 0, nur Kontrollreferenz |
| H3-dns-ext-profile / -control | inconclusive — rc 20 errno 8 (EAI_NONAME); kein Beleg für eine DNS-Sperre |

Externe Budgets: vollständig und planmäßig verbraucht — TCP **2/2** (Kontrolle + Profil), Systemresolver **2/2** (Kontrolle + Profil). Keine Wiederholung [B].

## 3. Phase 2/3: Gates-Matrix OpenCode vs. pi, echte Inferenz

Basis: V3-Kandidat, SHA vor Gebrauch verifiziert [B]. Ports reserviert im vertrauenswürdigen Elternprozess (mock 127.0.0.1:49523, llama-server 127.0.0.1:49524; TOCTOU-Risiko dokumentiert). Jede Zusatzzulassung vor dem ersten Harness-Lauf in `control/manifest/allowances.md` preregistriert, keine Wildcards [B].

### 3.1 Preregistrierte Zusatzzulassungen (Überblick, kernel-evidenzbasiert)

**Nur für OpenCode 1.18.34** [E]: Ausführung/Lektüre des bun-Shims und der Installations-Subtree `opencode-ai` (`~/.bun/...`, inkl. `opencode.exe`-Bundle); Lese-/Schreibsubpfad isolierter HOME (`clients/home-opencode`) und Scratch; neun benannte bun-boot sysctls (`kern.bootargs`, `kern.osvariant_status`, `hw.*`, `security.mac.lockdown_mode_state`, …); metadata-Kette Cryptexes/ICU/Zeitzonen; mach-lookup `com.apple.logd`, `notification_center` + Notification-ShM.

**Nur für pi 1.0.0** [E]: benannte Shim-Hops (`~/.asdf/shims/pi`, `/shims/node`) — jeweilig für `process-exec` **und** `process-exec*` (Shebang-Ausführung ist eine eigenständige Kernel-Operation: `deny(1) process-exec* …/shims/pi`); `asdf` 0.20.2 Go-Binärkette (bin + Cellar-Realpath) mit Go-CPU-Sysctls und enum-Lektüre in `~/.asdf/{installs,shims,plugins}`-Subtrees; node-Laufzeit (`env`-Hop, uname-Sysctls, `/etc`-metadata, `/private/var/run/syslog` Unix-Socket-Ausgang); Lese-/Schreibsubpfad `clients/home-pi` und Scratch; `vfs.disk-space` (Grammatik aus `system.sb:202`).

Diagnostische Breitprofile: **nicht nötig**. `(deny default (with log))` ist auf diesem Build ungültiges SBPL (`sandbox-exec: unbound variable: log`, Parsefehler [B]); der Kernel schreibt `deny`-Ereignisse ohnehin bei Error-Priorität [E].

### 3.2 Gates-Matrix (Phase 2a)

| Gate | OpenCode 1.18.34 | pi 1.0.0 |
|---|---|---|
| G1 Boot (`--version`) | supported — `1.18.34`, rc 0 | supported — `1.0.0`, rc 0 |
| G2 Mock-Chat-Turn | supported — Text verbatim | supported — identischer Text |
| G3 Tool-Write→Scratch | supported — Inhalt verbatim | supported — `isError:false` |
| G4 Negativprobe | supported — webfetch → Transport-Error; [E] `deny(1) network-outbound /private/var/run/mDNSResponder` | supported — guarded write → sauberes EPERM (`realpath`) |
| G5 Confinement | supported — Canarien unverändert; Kinder erben Profil | supported — identisch |

Ladder-Notizen [B]: GGUF-Download rc 0, 69 s, 491.400.032 Bytes, SHA256-Match (einzig autorisierter Ursprung); Parity-Ladder (`08-parity.sb`) mit vier sauberen EPERM-Verweigerungen unterstützt. OpenCode-Boot verlangte zwei evidenzgetriebene Erweiterungsrunden (erst stiller SIGTRAP rc −5); der pi-Boot über Shim scheiterte am `process-exec*`-op und an der asdf-Init-Auflösung, die direkte Kette lief sauber. Mock-Argument-Dialekt: OpenCode erwartet `filePath`/`url`, pi `path`/`content` — Mock belegt aus den Schemas, die der Harness selbst schickt. Rein kosmetisch getolerierte Denials blieben in grünen Läufen verzeichnet (metadata `/etc`, `~/.bun/bin`-Komponenten, `SDKs`/`developer_dir`-Meldung, disk-space-Probes) — kein Gate blockiert.

### 3.3 Phase 3: echte Inferenz (llama-server 0.5.0, build 11146)

Server außerhalb des Profils, pid 54485, argv exakt mandatiert (`-m <gguf> --host 127.0.0.1 --port 49524 --alias local-model --jinja --offline --no-webui --no-slots -c 2048`), `GET /health` → 200 [B]. Fernlade-Flags (`-mu/--hf-repo/-dr`) existieren, wurden nicht benutzt [B].

| Lauf | OpenCode | pi |
|---|---|---|
| R1 Sanity (echte Inferenz) | failed — Server lehnt Anfrage ab: 6030–7063 Tokens > Kontext `-c 2048`; OpenCode gerät in Compaction-Loop, Treiber-Timeout 300 s | supported — Antwort `Ok.`, rc 0, sauberes stderr |
| R2 echter Tool-Call-Write | failed — gleiche Fehlerklasse | supported — echter Qwen-`tool_call` `write` mit Pfad/Inhalt, ausgeführt (`isError:false`), Dateiinhalt verifiziert |

**Ehrliche Einordnung des OpenCode-Befunds:** der R1/R2-Fehlschlag ist ein **Testvorgabe-Artefakt**, kein Sandbox-Befund — die Mock-Leiter war vollständig grün; der voreingestellte Agentenprompt (~6–7K Tokens) übersteigt nur das eng gesetzte Probe-Fenster `-c 2048`. Ein breiteres Fenster (≥8K) oder ein schmalerer Prompt wäre nötig; OpenCode bleibt bewertbarer Kandidat für spätere Iterationen [S].

**Qualitative Latenz (keine Benchmarks)** [B]: pi echte Inferenzrunden ~0,4–1,0 s (382 ms R1; 1029 ms für den vollen Agentenloop inkl. Tool-Write und Folge-Turn; Token-Statistik input 92/output 85, cacheRead 717). Mock-getriebene Runden 1,5–1,8 s pro Runde je Harness.

## 4. DNS-Befund

Phase 1 hatte DNS als unbelegt zurückgestellt (zwei EAI_NONAME-Rückgaben sind laut Probevertrag kein Sperrnachweis). Phase 2 antwortet teilweise **auf die Loopback-Regel-Design-Frage** [E]: mit `(deny network*)` und nur der gepinnten Portausnahme erzeugt ein `fetch`-Versuch (node/bun) die Kernel-Zeile `deny(1) network-outbound /private/var/run/mDNSResponder` — der Unix-Socket des Systemresolvers ist von der Netzregel selbst miteingezäunt; Namenauflösung kann daher nicht auswärts laufen. **UDP/53 direkt bleibt ungetestet** [U]; die DNS-Sperre bleibt ein Abnahmekriterium und wird nicht vorab als erledigt dokumentiert.

## 5. Benannte Einschränkungen

1. **pi läuft über die aufgelöste echte Kette (`node` → `pi cli.js`), nicht über den asdf-Shim:** `asdf exec pi` scheitert unter der engen Grenze still mit rc 126 (mit gepinntem `ASDF_DATA_DIR`: „No executable pi found"), ohne auswertbare Violation-Zeile zur Auflösungszeit — die Auflösungsschicht verlangt Rechte, die sie nicht namentlich einfordert; daraus lässt sich keine evidenzbasierte Minimalzulassung ableiten [B]. Rohbelege: `pi-asdf-debug-log.txt`, `asdf-resolve-debug-2.txt`.
2. **Alle Zusatzzulassungen sind einzeln benannt und kernel-evidenzbasiert**, preregistriert und ohne Wildcards (Abschnitt 3.1); keine diagnostischen Breitprofile wurden für den Kandidaten benutzt.
3. Cluster an kosmetischen Denials: siehe 3.2. Kein Gate beruhte auf ihnen.
4. `OpenCode --version` braucht zwingend die isolierte Konfiguration (`OPENCODE_CONFIG`); ohne sie bricht der Start hart ab [B].

## 6. Instabilität und Kontext (upstream-Check)

Keine passende dokumentierte Regression zum Overnight-Flip gefunden [D, Abruf 2026-10-04]: Treffer in `openai/codex` (TIOCSTI-Parseklasse, #45330/#48780), `anthropics/sandbox-runtime` (#430: fehlendes `hw.optional.neon` → Qt-Abort auf Apple Silicon, gleiche Mechanismuskategorie ohne den Flip-Fingerprint), `google-gemini/gemini-cli` (#28598: deny-default-Migration ließ `/usr/bin/git`-xcrun-Shim mit SIGABRT sterben, PR #28424). Apple-Release-Notes rendern leer bzw. Foren sind botgesperrt [U].

Einheitliches gepflegtes Muster aller drei Basen [D]: **`(deny default)` plus Start-Allowlist** (Codex seatbelt_base_policy gepinnt an `279b932`; srt main `9e93406`; gemini-cli PR #28424 vom 2026-07-17). Die nötige Start-Allowlist enthält prozesskritische Rechte (exec/fork/signal same-sandbox, sysctl-list, mach-lookups, ipc-posix-sem/shm, PTY/`/dev/*`-ioctls) — unser Probe-Befund [B] deckt sich mit dem Muster. **Konsequenz als Abnahmekriterium:** Boot-Re-Verifikation bei jedem Sitzungsstart; ein Boot-Erfolg allein bewertet nichts nachhaltig [S].

## 7. MLX-Verweis

MLX bleibt ein zweites Artefakt-Problem und ist zurückgestellt: die Ein-Artefakt-Regel der Freigabe erlaubt nur das eine gepinnte GGUF, und `mlx_lm` kann GGUF-Formate nicht laden (Gewichts-Austausch bräuchte ein MLX-konvertiertes zweites Artefakt plus eigene GO-Entscheidung). In dieser Probe nicht ausgeführt [S nach Freigabetext].

## 8. Cleanup und Nachlauf

Beide Serverprozesse terminiert und verifiziert [B]: mock pid 49825 (SIGTERM, kein Listener auf 49523/49524), llama pid 54485 (term + kill-Check). Kanarien-Digests identisch zur Preregistrierung an jedem Messpunkt; Cleanup-Artefakte `cleanup.json`, `cleanup-followup*.json`, `canaries-*.json`, letzter Stand `post-R-pi.json`.

## 9. Offene Punkte

1. UDP/53 direkt, IPv6, Unix-Sockets über die resolver-Zeile hinaus, AppleEvents, Symlink-Kanonisierung, Protokoll-Scopes des localhost-Selektors — ungetestet [U].
2. Wurzelursache des Overnight-Flips; Datierung eines möglichen Seed-Build-Wechsels (27.1 vs. 27.2) als Gegenprobe [U].
3. Produktionsartefakt (größeres Qwen-GGUF) und dessen Download-GO — erster Bauschritt nach der Harness-Entscheidung.
4. Modellqualität jenseits der Sanity-Checks; keine Freigabe geschützter Verarbeitung; keine Isolationsbehauptung über die beobachteten Gates hinaus.
5. Repo-Integration (Skills, MCP-Registrierung) ist OpenCode-ausgerichtet und muss für pi aufgebaut werden.
6. MLX: siehe Abschnitt 7.

## 10. Quellen

Lokale Rohbelege (ephemerer Probebaum, hier nur als Provenanz): `$TMPDIR/open/probe-70/attempts/{04-dyld-preboot,06-class-bisect,07-path-pin}/labbook/phase1-seatbelt.md`; `$TMPDIR/open/probe-70/attempts/08-harness-phase2/{labbook/artifacts/labbook-phase2-3.md, control/manifest/allowances.md}`; `$TMPDIR/open/probe-70-known-issues.md`; `$TMPDIR/open/probe-70-authorizations.md`.

Pinned-Modell-Daten [B]: 491.400.032 Bytes, SHA256-Match, Download rc 0 / 69 s, einzig autorisierter Ursprung; Aliase `local-model`, Endpunkt 127.0.0.1:49524 (Loopback, OpenAI-kompatibel). Versionen: OpenCode 1.18.34, pi 1.0.0, llama-server 0.5.0 (build 11146), asdf 0.20.2, node 24.11.1, python3.9 (CLT) SHA `6e7ae6…`, sandbox-exec SHA `a2c3482…`.

Upstream-Quellen (Abruf 2026-10-04) [D]: `github.com/openai/codex/blob/279b93242cfef379e65da97e87e44b83c5934fd7/codex-rs/sandboxing/src/seatbelt_base_policy.sbpl`; `github.com/anthropics/sandbox-runtime/blob/9e93406ab2e0b6e9794624896f729560dc9445db/src/sandbox/macos-sandbox-utils.ts`; `github.com/google-gemini/gemini-cli/pull/28424` und `issues/28598`; `github.com/anthropics/sandbox-runtime/issues/430`; `github.com/openai/codex/issues/38028`, `issues/45330`, `issues/48780`; `developer.apple.com/documentation/macos-release-notes/macos-27-release-notes` (leer gerendert); `developer.apple.com/tutorials/data/documentation/endpointsecurity.json`.
