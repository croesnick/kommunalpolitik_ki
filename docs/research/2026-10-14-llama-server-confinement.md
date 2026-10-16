# Nachweis-Konsolidierung: llama-server unter der Seatbelt-Grenze (Experimente exp4–exp18)

| Feld | Wert |
|---|---|
| Datum | Experimente 2026-10-14 (exp4–exp16, exp18 Runden 1–3); Konsolidierung 2026-10-15 |
| Gegenstand | llama-server 0.6.0 (build 11429) unter der eigenen deny-default-Grenze `profile/llama-server.sb` auf macOS 27.2 (Build 26B5101f): Startup-Schicht, Execbarkeit, Modell-Load (mmap), Health, Inferenz und TERM-Exit — CPU-only-Pfad (Ticket [#100](https://github.com/croesnick/kommunalpolitik_ki/issues/100)) und GPU/Metal-Freigabe (Ticket [#111](https://github.com/croesnick/kommunalpolitik_ki/issues/111)). |
| Entscheidung | Die Grants wurden menschlich in [#100](https://github.com/croesnick/kommunalpolitik_ki/issues/100) und [#111](https://github.com/croesnick/kommunalpolitik_ki/issues/111) entschieden (Wayfinder-Map [#89](https://github.com/croesnick/kommunalpolitik_ki/issues/89)). Dieser Bericht konsolidiert die beobachtete Beweislage; er trifft keine neue Entscheidung und stellt keine Isolationsbehauptung auf. |
| Beweislabels | [B] beobachteter Einzelfall: lokal unter dem Profil gemessen. [E] Kernel-Beleg: `deny`-Zeile aus dem Unified Log (vormals „Kernel-Evidenz“, siehe [Probebericht 2026-10-04](2026-10-04-probe-harness-sandbox.md)). [D] dokumentiert: externe Quelle mit Abrufdatum. [S] Schluss: aus Belegen abgeleitet. [U] offen/ungetestet. |
| Provenienz | Die Rohprotokolle der Serie sind nicht persistent konserviert [U]. Diese Konsolidierung bündelt drei schriftliche Träger, alle versioniert: die Commit-Messages [8910258](https://github.com/croesnick/kommunalpolitik_ki/commit/8910258) (Ticket #100) und [29b5dea](https://github.com/croesnick/kommunalpolitik_ki/commit/29b5dea) (Ticket #111), die Rationale-Kommentare der Regelblöcke in `apps/komki_cli/lib/komki_cli/profile.ex`, `llama.ex` und `steps.ex` (Mach-O-Scanner ab diesem PR: `KomkiCli.MachODeps`) sowie die Tickets #100 (0 Kommentare) und #111 (1 Kommentar), abgerufen 2026-10-15. |

## 1. Auftrag und Ausgangslage

Ticket #100 fragt: „Wie kommt llama-server unter eine nachweisbare Grenze — statt der dokumentierten Annahme ‚unsandboxed by convention‘?“ Der Ausgangsbefund dazu stand im [Policy-Modell-Vergleich 2026-10-13](2026-10-13-agent-policy-models-openappa-pace.md), Z. 152: „llama-server runs unsandboxed by convention, which the RFC's own R.3 and D.9 requirements flag as an unproven assumption.“ Der dritte Punkt des Tickets bindet das Ziel an R.3: „Die R.3-Aussage ‚lokale Inferenz‘ wird damit zur geprüften Aussage statt zur unbelegten Ausnahme.“

Die in #100 gesetzte CPU-only-Grenze hob das Folgeticket #111 (geschlossen) auf und gab die GPU/Metal-Kette gezielt frei — Grants nur für die per Unified Log belegte Kette, keine breiten Wildcards.

## 2. Umgebung

macOS 27.2 (Build 26B5101f); llama-server 0.6.0, build 11429; `sandbox-exec`/SBPL mit `(version 1)` und `(deny default)`-Basis. Deterministisch aus der config.json generiert `KomkiCli.Profile.generate_llama/1` das Profil; vor jedem Start schreibt komki es frisch, und der Doctor vergleicht die gespeicherte Datei gegen die Regeneration (Identitäts-Check). Quelle: Moduldokumentation `apps/komki_cli/lib/komki_cli/profile.ex`, Commit 8910258.

## 3. Serie exp4–exp16 (CPU-only-Pfad, Ticket #100)

| Befund | Klasse | Regelblock (Quelle) |
|---|---|---|
| Ohne die Startup-Schicht (`common_boot_rules`, validierte Ticket-#70-Schicht) stirbt jeder exec auf macOS 27.2 mit SIGABRT rc=134 | [B] | `KomkiCli.Profile.llama_start_layer/0` |
| dyld öffnet die deklarierten Pfadformen aus dem Mach-O; Regeln nur in kanonischer Form matchen nicht (Pfadform-Cave, beide Richtungen) | [B exp6] | `KomkiCli.Profile.llama_dylib_rules/1`, `KomkiCli.MachODeps.dylib_dirs/1` |
| Transitive Deps außerhalb des Installationspräfix: libomp via libggml-base | [B] | otool-Walk (`KomkiCli.MachODeps`) |
| Ohne Leserecht auf das libexec-Geschwisterverzeichnis bleibt die ggml-Backend-Registry leer | [E exp6/exp7/exp14] | `KomkiCli.MachODeps.libexec_forms/1` |
| SBPL-bind-Grammatik: host muss `*` oder `localhost` sein; `localhost:PORT` ist die engste Form und matcht den 127.0.0.1-Bind | [B exp7/exp8] | `KomkiCli.Profile.llama_network_rules/1` |
| Ohne die FEAT-Sysctls (DotProd, FP16, I8MM, SME, SME2 …) scoret kein apple_m*-Bundle | [E exp14/exp15] | `@llama_sysctls` (profile.ex) |
| Ohne memsize/pagesize_compat/logicalcpu degradiert der Memory-Fitter/Threadpool; der Fitter bricht mit Warnung ab und lässt die Parameter wie angefordert | [E exp14] | sysctl-Block (profile.ex) |
| getcwd unter der Grenze braucht nur file-read-data `/` (Startup-Schicht); ein ungeschütztes Aufrufer-cwd blockt den Metadaten-Walk | [B exp14] | `KomkiCli.Llama.spawn_llama/1` (`cd: "/"`), `KomkiCli.Steps.llama_boot_gate/1` |
| Pfad-Sonden (`/`, `/System/Volumes/Data`, `/tmp`, `/home`, `/private/etc`, `/private/var`, `/.VolumeIcon.icns`) sind benigne Metadaten-Zugriffe | [E exp15] | `KomkiCli.Profile.llama_probe_rules/0` |
| Mach-Lookups Runde 2: opendirectoryd (libinfo/membership), notification_center, logd, dirhelper; posix-shm `apple.shm.notification_center` | [E exp14] | `KomkiCli.Profile.llama_mach_shm_rules/0` |
| `--device none` (damals benannte CPU-Grenze): ohne sie scheitert die Metal-Context-Init an der verweigerten iokit-Kette | [E exp15] | damals `Llama.spawn_llama`; durch #111 ersetzt |
| Kontrolle ungesandboxet: Der Host nutzt die Metal-Device MTL0; unter der Grenze CPU-only ~5 t/s Eval | [B exp15/exp16] | Commit 8910258 |

Entwicklungs-Befunde innerhalb der Serie (jeweils im Code kommentiert, Quelle profile.ex/MachODeps): ein vorbelegtes `visited` übersprang den Root des Dylib-Walks (leere Dep-Liste); otool rückt Dep-Zeilen mit Tab ein; der RPATH-Scan darf bei `cmdsize` nicht vorzeitig zurückspringen; `@rpath`-Werte sind selbst loader-relativ (`@loader_path/../lib`). `otool` fehlt → `[]` (CI-Linux; Profil bleibt generierbar).

## 4. GPU/Metal-Freigabe in exp18 (Ticket #111)

Drei Runden mit Unified-Log-Denials je Runde [E], Quelle: Regelblock-Kommentar `KomkiCli.Profile.llama_metal_rules/0` und Commit 29b5dea:

- **Runde 1** scheiterte an der Command Queue (iokit: AGXDeviceUserClient, IOSurfaceRootUserClient verweigert).
- **Runde 2** scheiterte am ausgelagerten Shader-Compiler — `mach-lookup com.apple.MTLCompilerService (xpc)` verweigert; Fund: Lektüre der Systemverzeichnisse (Cryptex-dyld).
- **Runde 3** lief grün unter der Grant-Kette: iokit-Userclients AGX/IOSurface; mach-lookup windowserver/tccd/coreservicesd/diskarbitrationd/MTLCompilerService; `file-issue-extension` (Metal-Caches); Systemverzeichnisse `/usr/lib`, `/System/Library`, `/System/Volumes/Preboot`; OS-Varianten-Sysctls (`hw.ephemeral_storage`, `kern.osvariant_status`, `kern.osproductversion`).

Messung auf der echten Instanz (ctx 131072): 53,9 t/s Eval und 382 t/s Prompt-Eval unter der Grenze, gegen ~57 t/s ungesandboxet (exp13) und ~5 t/s CPU-only (exp15/16) [B]. Damit wurde die Erwartung aus #111 (~57 t/s) erreicht. `--device none` entfiel; der auto-Offload auf MTL0 läuft unter der Grenze.

Bewusst ungenutzt blieb die AGX-Bundle-Entdeckung (17 GPU-Klassen-Bundles): Jede Einzelregel wäre von der System-Haus-Regel subsumiert; Schein-Portabilität ohne Zuwinn [E][S]. Teststand beim #111-Review: Suite 77/77 grün (inkl. echtem Doctor-Smoke), dialyzer ohne Befunde, credo --strict sauber (Quelle: [PR #112](https://github.com/croesnick/kommunalpolitik_ki/pull/112), Evidence-Abschnitt, abgerufen 2026-10-15).

## 5. Doctor, up, run und Boot-Gate unter der Grenze (Antwort auf die Ticket-Frage)

- **Doctor/Boot-Gate:** zwei neue Checks in allen Gates — Identität des llama-Profils (Regeneration byte-stabil / Drift / Missing) und llama-Boot-Probe (`--version` unter dem eigenen Profil, cwd `/`, wie beim Spawn). `up`/`run`/`session` verweigern, bevor Inferenz unter ungeprüfter Grenze läuft. Quelle: Commit 8910258, `KomkiCli.Steps.llama_boot_gate/1`.
- **Health-Check:** unverändert — pidfile, wait_health, `/health` via plain TCP auf Loopback; kill nur nach ps-Identitätscheck (PID-Kette verifiziert). Quelle: Commit 8910258, `KomkiCli.Llama`.
- **Ports:** bind auf `localhost:PORT` gepinnt. `(allow network-inbound (local ip))` ist bewusst breit; die Enge trägt die bind-Regel, denn der Server kann keine weiteren Adressen/Ports belegen [S].
- **Modell-Download:** existiert in diesem Pfad nicht — llama-server läuft `--offline` mit dem lokal SHA-verifizierten Artefakt aus `komki init`; das Profil vergibt keinen einzigen network-outbound-Grant, damit ist `--offline` profilseitig erzwungen [S]. Quellen: Moduldokumentation `llama.ex`, Regelblock `llama_network_rules/1`.

## 6. Bewusst benannte Grenzen

- **GPU-Treiber-Angriffsfläche:** iokit-Userclients plus ausgelagerter Shader-Compiler-Service — die in #111 bewusst eingegangene Grenze (Commit 29b5dea, Regelblock `llama_metal_rules/0`).
- **Netz-Auswärts:** bleibt verweigert, auch mit GPU-Grants — einschließlich des syslog-Unix-Sockets (os_log-Fallback; einziger beobachteter Outbound-Versuch, Kernel-Denial exp18) [E]. Seatbelt zählt Unix-Socket-Verbindungen als `network-outbound`, nicht als File-Operation; File-Regeln auf dem Socket-Pfad blocken die Verbindung nicht [D]. Die Enge des pi-Profils (`remote tcp localhost:PORT` allein) erfasst Unix-Socket-Kanäle nicht; verweigert werden sie von der deny-default-Basis. Denselben Klassifikations-Befund zeigte bereits der Probebericht 2026-10-04: `deny(1) network-outbound /private/var/run/mDNSResponder`.
- **Inbound-Breite:** siehe Abschnitt 5; die Pinning-Aussage trägt die bind-Regel, nicht die inbound-Regel [S].
- **Umgebungsgebundene Byte-Identität:** gleiche cfg und gleiche Umgebung (HOME, otool-Verfügbarkeit, Dateisystemstand) erzeugen byte-identischen Profiltext; geänderte Umgebung erzeugt erwarteten Drift im Doctor — kein Profildefekt [S].

## 7. Nachweisgrenzen [U]

- Nicht persistent konserviert sind die Rohprotokolle der Experimente; die Beleglage besteht aus Commit-Messages, Regel-Kommentaren und diesem Bericht.
- Am Boot-Gate ist die Startschicht (Execbarkeit) belegt, nicht der Inferenzpfad. Den vollen Pfad — Modell-Load, Health, Inferenz, TERM-Exit — belegt die Experimentserie; im laufenden Betrieb belegt ihn der erfolgreiche `up` (Health 200 unter der Grenze) [S].
- Keine Isolations- oder Nichtinterferenzbehauptung über die belegten Grants hinaus.

## 8. Externe Bestätigung [D]

Die Seatbelt-Internals-Doku des nono-CLI ([alwaysfurther.mintlify.app/cli/internals/seatbelt](https://alwaysfurther.mintlify.app/cli/internals/seatbelt), Abruf 2026-10-15) dokumentiert fünf Befunde, die dieser Bericht aus [B]/[E] selbst ableitet — unabhängige Zweitquelle je Anker:

| Unser Befund | Externe Aussage (nono-Doku) | Anker (Abschnitt) |
|---|---|---|
| Startup-Schicht-Pflicht, sonst SIGABRT rc=134 (Abschnitt 3) | „Abort (exit 134) → Missing system path" | „Common Issues" |
| dyld-Kette im Profil (Abschnitt 3) | `(allow file-map-executable)` „required for dyld" | „Profile Structure" |
| Unix-Socket-Verbindungen sind Netz-Operationen (Abschnitt 6) | „a file-read-data or file-write-data deny rule for the socket path will not block the connection" | „Unix Socket Connections" |
| Pfadform-Cave, beide Richtungen (Abschnitt 3) | „rules written for `/Users/luke` might not match the kernel's resolved path" | „APFS Firmlinks" |
| Grenzen-Permanenz (deny default lässt sich nicht aufheben) | „There is no `sandbox_remove()` or `sandbox_expand()` API" | „Irreversibility" |

Zur Pfadform-Falle lösen nono und komki dieselbe Falle unterschiedlich: nono hält eine kuratierte Firmlink-Liste, komki hält je aufgelöster Dylib-Abhängigkeit die deklarierte und die kanonische Pfadform (`KomkiCli.MachODeps`). Die nono-Doku ist Produktdokumentation eines anderen CLI, keine Kernel-Quelle; als [D]-Anker bestätigt sie Befunde, die hier aus Belegen erster Hand hervorgehen.

## 9. Versionierung

R.3 (RFC 0003, Z. 502): „Umgebungsbeschreibungen, ihre zugänglichen Empfänger und ihre Nachweise sind versioniert.“ Die versionierten Träger sind dieser Bericht, die Regel-Kommentare im Profilgenerator und die Commits [8910258](https://github.com/croesnick/kommunalpolitik_ki/commit/8910258) und [29b5dea](https://github.com/croesnick/kommunalpolitik_ki/commit/29b5dea). Ein Wechsel des OS-Builds oder des llama-server-Builds erneuert die Prüfung (R.3, [RFC 0003](../rfcs/0003-vertrauliche-ki-arbeitsraeume.md)).
