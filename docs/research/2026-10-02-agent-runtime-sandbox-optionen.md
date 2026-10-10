# Recherchenotiz: Agent-Runtime- und Sandbox-Optionen

| Feld | Wert |
|---|---|
| Datum | 2026-10-02 |
| Auftrag | Externe Recherche zum Pre-Charting fuer RFC 0003 (vertrauliche KI-Arbeitsraeume). |
| Geltung | Sandbox- und Ausfuehrungsruntimes. Nicht enthalten: Applikations-Broker/Proxys/MCP (weiterer Bearbeiter), Modellwahl (weiterer Bearbeiter), Repo-Code-Inspektion (Explorer). |
| Bindung | RFC 0003 bleibt normativ. Diese Notiz trifft keine GO-Entscheidung, begruendet keine RFC-Konformitaet und keinen getesteten Hostschutz. |

## 1. Auslegung und Methodik

Zwei Klarstellungen vorab.

1. Zu RFC 0003 B.8: Eine reine Engine kann ohne vollstaendige Vermittlung tatsaechliche Wirkungen weder verbindlich autorisieren noch kontrollieren; sie bleibt ein beratendes Pruefwerkzeug und ersetzt keine Sandbox. Das RFC verlangt Isolation als nachzuweisende Eigenschaft (R.8.2, "Tragfaehige Umgebung"), schreibt aber keine konkrete Sandbox-Technologie vor. Die Vermittlung ist Bestandteil des Broker-Tracks.
2. Zu RFC 0000: Historische Sandbox-Klassen aus RFC 0000 sind laut RFC 0003 R.1.2 und Anhang E Zielinventar, nicht normatives Modell. Diese Notiz bewertet nicht danach.

Evidenzstufen in dieser Notiz.

- [D] Dokumentiert. First-Party-Quelle namentlich benannt, Abrufdatum 2026-10-02.
- [S] Schluss. Abgeleitet aus [D]-Belegen, ohne eigene Ausfuehrung.
- [V] Offen. Braucht spaeter ein Experiment, bevor ein Umgebungstand im Sinne von RFC 0003 R.3 und R.4.1 daraus zulaessig werden darf.

Methodik: Nur lesende Befragung von Dokumentation, Profil- und Codepfaden sowie Repo-Metadaten (und `gh repo view`). Nichts installiert, keine Sandbox gestartet, kein Modell geladen, keine Live-Datenquelle gerufen. Lokale read-only Diagnose: `command -v sandbox-exec bwrap`, `man sandbox-exec`, `sw_vers`.

## 2. Kriterien aus RFC 0003

| ID | Kriterium | RFC 0003 Stelle |
|---|---|---|
| K1 | Isolation ist eine nachzuweisende Eigenschaft der Umsetzung, keine Folge guter Prompts | Abschnitt 1, R.1.1 |
| K2 | Agent darf keine Rechte erzeugen; vertrauenswuerdige Basis liegt ausserhalb seiner Kontrolle | R.8.1, R.1.1 |
| K3 | Beobachter umfassen lokale Prozesse, Logs, Sync, Hilfsmodelle, Proxys | R.3, R.5.2 |
| K4 | Connectoren halten Credentials; Lese- und Senderecht getrennt; verbindliche Wirkung nur ueber den kontrollierten Ausfuehrer | R.4.3, R.4.4, B.8 |
| K5 | Tooling, Skills und Konfiguration sind gesondert freizugebende Laufzeitbestandteile | R.4.4 |
| K6 | Kein stiller Fallback; Umgebungsaenderung ist eine neue Zulassung | R.3 |
| K7 | Startvertrag mit versioniertem Umgebungstand; ein Zulassungsdokument ersetzt den Nachweis der aktuellen Umgebung nicht | R.4.1, R.8.2 |

Anforderungsrahmen des Auftrags (Nutzervorgabe, kein RFC-Satz): Die Ausfuehrungsumgebung muss Netzwerk einschraenken oder ganz abschalten, ausserhalb der Agentenkontrolle, mit vermittelten Connector- und LLM-Wegen ohne Bypass. Prompts, Hooks und eine nur gesetzte HTTP_PROXY-Variable sind dafuer keine Grenze. Diese Vorgabe ist strikter als das, was typische Agent-Harnesses standardmaessig bieten; sie passt zum RFC-Kriterium K2, stammt aber aus dem Auftrag. Kernelnahe Einschraenkung ist der Ausgangspunkt; vermittelte Wege gehoeren zum Broker-Track.

## 3. Kandidatendetails

### 3.1 @anthropic-ai/sandbox-runtime (srt)

Quellen: https://github.com/anthropics/sandbox-runtime/blob/main/README.md (First-Party) und Codepfade `linux-sandbox-utils.ts`, `macos-sandbox-utils.ts`, `windows-sandbox-utils.ts`, `sandbox-manager.ts`, `http-proxy.ts`, `socks-proxy.ts`, `sandbox-config.ts`, `mitm-ca.ts`. Abgerufen 2026-10-02. Metadaten [D via `gh repo view`]: Apache-2.0, v0.0.78, erstellt 2025-10-20, letzter Push 2026-10-01.

Status [D]: "Beta Research Preview", als CLI `srt` und als Bibliothek; entwickelt fuer Claude Code.

Plattformmatrix [D]:

- macOS: `sandbox-exec` mit dynamisch generierten Seatbelt-Profilen; Abhaengigkeit ripgrep.
- Linux: bubblewrap. Der Netzwerk-Namespace des Sandboxprozesses wird vollstaendig entfernt; Zitat: "The network namespace of the sandboxed process is removed entirely, so all network traffic must go through the proxies running on the host (listening on Unix sockets that are bind-mounted into the sandbox)". Bruecke via socat.
- Windows: alpha. Dediziertes lokales Konto `srt-sandbox`; Startkette via gebuendetem `srt-win.exe` (CreateProcessWithLogonW); WFP-Filter (Windows Filtering Platform) auf Basis der SID; Dateisystem ueber NTFS-ACLs.

Netzwerkmodell [D]:

- Deny-by-default an den Proxys. Leere `allowedDomains` bedeutet: kein erlaubtes Ziel ueber diese Proxys. Die dokumentierte Systemresolver-Ausnahme auf macOS/Windows erlaubt daraus keine Aussage ueber vollstaendig abgeschaltetes Netzwerk (siehe DNS-Grenze unten).
- HTTP(S) laeuft ueber einen host-seitigen HTTP-Proxy, sonstiges TCP ueber einen host-seitigen SOCKS5-Proxy. Beide erzwingen allowedDomains und deniedDomains.
- Resolved-address-check: erlaubte Hostnamen werden vor dem Dial aufgeloest und einer Verweigerliste gegenuebergehalten: Loopback 127.0.0.0/8 und ::1, unspecified, link-local, multicast, broadcast, Cloud-Metadatenendpunkte, Adressen eigener Interfaces, IP-Literale aus deniedDomains, zusaetzlich `deniedResolvedAddresses`.
- IPv6: Literale muessen RFC 3986 gemaess geklammert sein; IPv4-mapped und verwandte Formen werden behandelt; lokale NAT64-Praefixe sind laut Doku nicht aus der Adresse allein erkennbar.
- macOS: `allowLocalBinding`, Standard false. `allowUnixSockets` als Pfadliste.
- Linux: Unix-Socket-Blockade via seccomp BPF, vorgebaute Filter fuer x86-64 und arm64; seccomp kann laut Doku nicht nach Pfad filtern.

IPC und OS-Schicht [D]:

- Unix-Sockets sind auf beiden Plattformen standardmaessig blockiert.
- Der seccomp-Filter blockiert `socket(AF_UNIX, ...)` und io_uring-Syscalls, weil `IORING_OP_SOCKET` ab Linux 5.19 sonst die socket()-Regel umgeht.
- Dokumentierte Luecke: geerbte File-Descriptoren und via SCM_RIGHTS uebergebene Sockets bleiben nutzbar.
- `apply-seccomp` legt einen verschachtelten user+PID+mount Namespace an und remountet /proc; der innere PID 1 setzt PR_SET_DUMPABLE=0. Scheitert die Verschachtelung, bricht srt ab statt unisoliert weiterzulaufen.
- Ancestors geschuetzter Pfade werden als Mountpoints "gepinnt"; `mv` oder `rmdir` davon scheitert mit EBUSY, `rm -rf` durch ein nested Repo laesst geschuetzte Dateien zurueck.

Konfiguration und Hoheit [D]:

- `~/.srt-settings.json` oder per `--settings`. Eine existierende, aber unlesbare oder ungueltige Datei ist ein Fehler: srt beendet sich statt auf Defaults zurueckzufallen. Defaults greifen nur bei fehlender Datei.
- `--control-fd` erlaubt Laufzeitaktualisierung nur der Netzwerklisten; der Deskriptor wird dem Sandboxprozess nicht gegeben, der Slot zeigt bei macOS und Linux auf /dev/null. Ersetzungen werden nur vorgenommen, wenn die Deskriptorquelle lebt.
- Warnung: Optionen wie `allowAppleEvents` duerfen laut README nur aus trusted user-level configuration stammen, nie aus projektlokalen Dateien eines checked-out Repos.

Dokumentierte Schwachen und Escape-Flaechen [D]:

- `allowAppleEvents=1` hebt die Code-Execution-Isolation: "so this option removes code-execution isolation, not just weakens it".
- `enableWeakerNetworkIsolation` erlaubt `com.apple.trustd.agent` und oeffnet einen dokumentierten Exfiltrationsvektor ueber trustd.
- Breite Domains wie github.com erlauben Exfiltration; Domain-Fronting wird als moegliche Umgehung benannt.
- `allowUnixSockets: ["/var/run/docker.sock"]` kann Privilegien-Eskalation bedeuten.
- DNS: Windows-Teil des README: "DNS resolution via the system resolver is not fenced ... This mirrors the macOS behaviour." Auf macOS und Windows erreicht der Name-lookup das System ausserhalb der Sandbox; Tools, die selbst UDP/53 sprechen, sind gefenced. [D]
- Linux und Proxy-Variablen [D]. Unter "Known Limitations" steht: "may be ignored by programs that don't respect these variables, leading to them being unable to connect to the internet". Zusammen mit dem entfernten Netzwerk-Namespace ist das kein Bypass und kein Widerspruch, sondern fail-closed fuer diesen Internetweg: wer die Proxy-Variablen nicht beachtet, baut ueber diese Proxys keine Internetverbindung auf. Das ist keine pauschale Aussage ueber alle IPC- oder Linux-Netzwerkwege. Offen bleibt der Betriebsaspekt, welche Werkzeuge welche Variablen brauchen.
- Violation-Store-Traeger sind laut README aus dem Inneren der Sandbox schreibbar ("the carriers are writable from inside the sandbox"). Relevant fuer Rueckschluesse im Audit [D].

### 3.2 pi (earendil-works/pi, frueher badlogic/pi-mono)

Quellen: https://github.com/earendil-works/pi/blob/main/README.md und https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/containerization.md. Abgerufen 2026-10-02. Metadaten [D via `gh repo view`]: MIT; npm-Paket `@earendil-works/pi-coding-agent`; Node 22.19+.

Basis-Zitat [D]: "Pi does not include a built-in permission system for restricting filesystem, process, network, or credential access. By default, it runs with the permissions of the user and process that launched it."

Isolationsschichten [D via containerization.md]:

- Plain Docker: kompletter pi-Prozess im Container; Anmeldedaten via Environment-Variable; `~/.pi/agent` nicht mounten, weil dort Anmeldedaten, Einstellungen, Erweiterungen und Sessions liegen. Stattdessen ein named volume `pi-agent-home`.
- Docker Sandboxes (`sbx`): kompletter pi-Prozess im verwalteten Sandbox-Container; Provider-Credential bleibt auf dem Host, der sbx-Proxy ersetzt einen Platzhalter nur fuer den konfigurierten Host. Doku warnt: nicht mit `/login` innerhalb der Sandbox arbeiten.
- OpenShell (NVIDIA, https://github.com/NVIDIA/OpenShell, Apache-2.0, v0.1.2): policy-controlled sandbox mit filesystem, process, network, credential und inference policies; Gateway-Pflicht; lokal oder remote.
- Gondolin (https://github.com/earendil-works/gondolin, Apache-2.0, sandbox-helpers-0.12.0): lokale Linux-MicroVM; Extension routet built-in tools und `!`-Befehle in die VM; pi-Prozess und file-based credentials bleiben auf dem Host. Warn-Zitat: "Commands inside the VM inherit the host process environment. Provider keys supplied through environment variables can therefore be visible inside the VM. Do not use this pattern as a credential boundary".

Abgrenzungs-Zitat [D]: "Tool-only isolation does not constrain the host Pi process or extension tools that do not use the isolated backend."

Bewertung [S]: pi ist ein guter Harness-Kandidat, bringt aber selbst keine Laufzeitverriegelung. Es dokumentiert Anbindungswege, die an RFC R.4.3 Credential-Forderungen anknuepfbar sind.

### 3.3 OpenCode (sst/opencode)

Quelle: https://opencode.ai/docs/permissions/, abgerufen 2026-10-02.

Befund [D]: application-level Berechtigungen mit allow/ask/deny pro Tool; Muster fuer bash, edit, webfetch, websearch; `external_directory` mit Default "ask"; `doom_loop`. Der Enforcement-Ort ist die App-Logik. Eine OS-Ebene-Isolation (seatbelt, bubblewrap, container, Netzwerk-Kontrolle) wird in dieser Doku nicht beschrieben.

Suchsignal: `gh_grep` fuer `(?i)sandbox` und fuer `(?i)seatbelt|bubblewrap|sandbox-exec|bwrap` in sst/opencode ergab keine Treffer. Vorsicht [S]: kein endgueltiger Beweis fuer Abwesenheit; die Dokumentation ist die tragende Quelle. Faire Ticketformulierung: verifizieren vor Zulassung. [V]

Bewertung [S]: Fuer RFC K2 bis K6 benoetigt OpenCode eine externe Sandbox und einen Broker wie jeder andere Harness.

### 3.4 michaelneale/agent-seatbelt-sandbox

Quellen: https://github.com/michaelneale/agent-seatbelt-sandbox, README und `sandbox.sb`. Abgerufen 2026-10-02. Metadaten: erstellt 2026-02-11, letzter Push 2026-02-11, keine LICENSE, kein Release. [D]

Status [D]: minimale macOS-Seatbelt-Demo, ohne Lizenz, ohne Release, ohne aktive Pflege. [S] Fuer uns nur Mechanismus-Referenz, kein uebernehmer Code- oder Text-Kasten: das Profil wird nicht kopiert, weil keine Lizenz vorliegt. Eigene Profile leiten wir unabhaengig ab, aus First-Party-Mechanismus-Doku (srt-Profilgenerierung im Quellbaum, macOS-Doku) oder aus einer lizenzierten Implementierung (srt, Apache-2.0).

Profilbefund [D, `sandbox.sb`]: Default-Allow mit Lese-/Schreibverbot fuer `SECRETS_DIR`; Netzwerkverbot mit Ausnahmen fuer mDNSResponder, ausgehende Unix-Sockets und Loopback in beide Richtungen. Keine kopierte Profilvorlage aus dem unlizenzierten Demo-Repo; dies ist eine Beschreibung der dokumentierten Grenzen, kein nutzbares Profil.

Architektur [D via README]:

- "The sandbox uses Apple's Seatbelt (`sandbox-exec`). Once applied, it inherits to every child process and cannot be removed from inside." [D claim; experimentell nicht verifiziert [V]]
- Kernel: non-localhost `connect()` bekommt EPERM. Host-seitiger `proxy.py` als CONNECT-Proxy auf Port 18080; protokolliert Domainen nach stderr und `connections.log`; erlaubt live un/block via `blocked.txt`, ablehnung mit 403.
- "`http_proxy`/`https_proxy` env vars; Node.js needs `NODE_OPTIONS=--use-env-proxy` (Node 20.18+). Tools that ignore proxy vars simply fail safe." [D]
- Kein TLS-Inspection; Proxy sieht Kontakt-Domainen, nicht Inhalte. [D]
- Konfighoheit ueber `sandbox.sb` und `blocked.txt` ist ungeklaert: lesende und schreibende Zugriffe aus der Sandbox sind nicht abgegrenzt. [V]

Grenzen dieses Profiltyps [S]:

- `(allow default)` als Boden ist ein Deny-Liste-Design, kein Deny-by-default. Der Sandboxprozess hat damit vollen Lese-Zugriff auf den Host, vollen Mach-Lookup-Umfang, breite ausgehende Unix-Sockets (durch die dokumentierte Allow-Linie) und Loopback in beide Richtungen (dev servers, LSPs, alle lokalen Dienste). Die eine Deny-Regel auf `SECRETS_DIR` schuetzt nur diesen Pfad. Keines der Kriterien K2 bis K5 ist allein damit erfuellt.
- Ein lokaler Modell-Dienst auf dem Host ist selbst eine Egress-Flaeche [S, [V]]: solch ein Dienst kann eigene ausgehende Verbindungen aufbauen (Dienst-Management, Modell-Downloads, Registry- oder Admin-Endpunkte). Ohne Vermittlung ist der Loopback-Weg damit ein Ausgangskanal des Gesamtsystems, nicht nur des Agenten. Der lokale Dienst braucht eigene Grenzen oder wird ein Knoten mit eigener Vermittlung.

### 3.5 Google AX (google/ax) und Agent Substrate

Quellen: https://github.com/google/ax/blob/main/README.md und https://github.com/google/ax/blob/main/docs/sandbox.md (Runner-Abschnitt); https://github.com/agent-substrate/substrate/blob/main/README.md. Abgerufen 2026-10-02. Metadaten [D via `gh repo view`]: AX Apache-2.0, v0.3.1, Push 2026-09-27. Substrate Apache-2.0, kein Release-Tag, Push 2026-10-02.

Befunde [D]:

- AX ist eine Agenten-Orchestrierung fuer Kubernetes: Task, Workspace, Model als `ax.io/v1alpha1`-Ressourcen, kubectl-foermig; dazu `ax suspend/resume/ssh`.
- README warnt: "AX and several of its features are in heavy development" und vor "major breaking changes prior to a stable release".
- Isolation delegiert AX an Agent Substrate: Kubernetes Pods, "secure-by-default agent execution runtime". Zwei dokumentierte Runtime-Binder in cmd-Pfaden: `cmd/ateom-gvisor` (gVisor `runsc`, mit checkpoint/restore-Support) und `cmd/ateom-microvm` (cloud-hypervisor VMs). Node-level DaemonSet mit dem Namen `atelet`.
- Egress-Policy pro Actor, Index-Zitat: "Egress Traffic: Which protocols an Actor may reach the outside world with and which are blocked"; im Umfeld wird eine MITM-Interception guide referenziert. Inhalt der Egress-Doku wurde nicht gelesen. [V]
- `ax-task-runner` laeuft als PID 1 im Task-Container, metadata/guest management auf Port 80. `spec.debug: true` aktiviert gRPC guest services; Doku-Zitat: "off by default because they allow arbitrary process execution and file access"; `ax ssh` braucht diese Services. [D]

Assessment [S]: Fuer eine kleine Lerniteration unpraktisch: Kubernetes-basiert mit Betrieb in einem Cluster. Die Recherche nimmt nicht an, dass der Nutzer keinen Cluster hat; sie stellt nur fest, dass fuer die Erstiteration kein Cluster ausgewiesen ist. AX und Substrate bleiben Referenz fuer gVisor, microVM und Egress-Policy in einem Cluster-Kontext.

### 3.6 Codex CLI (openai/codex)

Quellen: Learn-Doku `learn.chatgpt.com/codex/sandboxing` (entstanden nach Redirect von developers.openai.com/codex/security); `github.com/openai/codex/blob/main/docs/sandbox.md` ist ein Stub, der auf die Learn-Doku zeigt. Abgerufen 2026-10-02. Metadaten: Apache-2.0, release `rust-v0.160.0`, Push 2026-10-02. [D]

Kernaussagen [D]:

- Plattform-native enforcement: macOS mit built-in Seatbelt; Linux und WSL2 mit bubblewrap (`bwrap` aus PATH oder gebuendelter Helper; Anforderung user-namespaces; Ubuntu 24.04 und 25.04 AppArmor-Anmerkungen); nativer Windows sandbox via PowerShell.
- Die Sandbox gilt fuer launched commands, nicht nur fuer builtin-Dateiaktionen. Git, Paketmanager und Testrunner erben die Grenzen.
- Modi: `read-only`, `workspace-write`, `danger-full-access`; approvals `on-request` oder `never`; Defaults via `config.toml` keys `sandbox_mode`, `approval_policy`, `approvals_reviewer`.
- Die gelesene Seite dokumentiert nicht, ob Netzwerk per Default deaktiviert ist und wie es vermittelt wird. [U]
- Die fruehere Landlock-seccomp-Implementierung wird in der aktuellen Doku nicht mehr beschrieben; die jetzige Doku nennt bubblewrap. [S] [V im Detail]

### 3.7 Gemini CLI (google-gemini/gemini-cli)

Quellen: https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/sandboxManagerFactory.ts plus `sandbox/linux/LinuxSandboxManager.ts`, `sandbox/macos/MacOsSandboxManager.ts`, `sandbox/windows/WindowsSandboxManager.ts`. Metadaten: Apache-2.0, v0.62.0, Push 2026-10-02. [D]

Assessment [S]: weitere harness-integrierte Sandbox mit per-OS Manager-Fabrik; nahe verwandt mit srt und Codex. Tiefe nicht gelesen [V]. Nur als Begleiteintrag aufgezaehlt, keine Einzelrecherche dazu [S].

### 3.8 Linux-Native Schichten

Quellen: Linux-Kernel-Doku `userspace-api/landlock.html`, Stand August 2026 [D], abgerufen 2026-10-02; gVisor-Doku `https://gvisor.dev/docs/` [D], abgerufen 2026-10-02; Metadaten via `gh repo view` fuer bubblewrap, nsjail, Lima, Podman.

Landlock [D]:

- Unprivilegierte Self-Restriktion als stackbarer LSM. Regeln beschraenken den Thread und alle seine Nachkommen.
- Zitat: "Once a thread is landlocked, there is no way to remove its security policy; only adding more restrictions is allowed."
- Regeltypen: filesystem, TCP bind/connect ab ABI v4, UDP bind/send ab ABI v10, IPC-Scoping fuer abstract unix sockets und Signals ab ABI v6.
- Grenzen: Portgranularitaet, keine Host- oder IP-Whitelist, keine DNS-Regeln; weiterhin nicht einschraenkbar sind chdir, stat, flock, chmod, chown, setxattr, utime, fcntl, access. [D via documented list]

gVisor/runsc [D]:

- Userspace-Kernel ("Sentry") plus Filesystem-Proxy ("Gofer") via 9P; OCI runtime; Docker, Kubernetes und OCI-Nutzung. Linux-only. Bekannte Tradedoffs: hoehere Syscall-Latenz, unvollstaendige Kompatibilitaet.

bubblewrap, nsjail, Lima, Podman [D Metadaten; Tiefen offen [V]]:

- bubblewrap: die `COPYING`-Datei nennt (abgerufen 2026-10-02, https://github.com/containers/bubblewrap/blob/main/COPYING) die GNU Lesser General Public License, Version 2.1, Februar 1999, mit "either version 2.1 ..., or (at your option) any later version", also LGPL-2.1-or-later. Das GraphQL-API-Feld "Other" ist ein Sammel-Label, kein Rechtsbescheid. Eine vollstaendige Lizenzpruefung und jede tatsaechliche Code-Nutzung bleiben offen [V].
- nsjail: Apache-2.0, release 3.6, Push 2026-10-02. Nur namentlich, um den Katalog zu begrenzen.
- Lima: Apache-2.0, v2.2.0, Push 2026-10-02. Podman: Apache-2.0, v6.1.3, Push 2026-10-02.
- Linux containers unter macOS laufen in einer Linux-VM; `--network none` gibt Kernel-Grenze ohne mediation-Schicht auf host-Ebene.

### 3.9 Host- und Versionskontext

- Host: macOS 27.2, Build 26B5091g, Apple M1 Max, 64 GiB RAM. [D Explorer plus `sw_vers` lokal, 2026-10-02]
- `/usr/bin/sandbox-exec` existiert. Lokale man page: "The sandbox-exec command is DEPRECATED. Developers who wish to sandbox an app should instead adopt the App Sandbox ...". [D local man page, 2026-10-02] Deprecation-Risiko beachten [S].
- Auf PATH vorhanden: `opencode`, `pi`, `ollama`, `llama-server`, `llama-cli`. Kein docker/podman/container-CLI auf PATH [D explorer]. Das ist eine Beobachtung, kein Beweis fuer Abwesenheit, und sie sagt nichts darueber, ob ein Kubernetes-Cluster verfuegbar ist.
- Lokale Inferenz: `ollama` und `llama-server` sind auf dem PATH installiert. Aus Sicht der Recherche ist das nur eine Installation von Binaries: kein Daemon laeuft, kein Modell ist geladen, kein Endpunkt wurde geprueft [V].

## 4. Vergleichstabelle

| Projekt | Plattform | Kernmechanismus | Netz | DNS | UDP | IPv6 | Loopback | IPC / Unix-Sockets | Konfig-Hoheit | Wartung, Lizenz |
|---|---|---|---|---|---|---|---|---|---|---|
| srt (Anthropic) | macOS, Linux, Windows alpha | seatbelt profile generiert; bwrap mit netns-Wegfall; Windows alpha WFP plus SID | deny-by-default Domains via host-Proxys [D] | macOS/Windows: via Systemresolver, nicht gefenced [D, README "mirrors macOS behaviour"]; Linux: DNS am Host-Proxy [D] | macOS durch seatbelt-deny; Linux netns weg; Windows WFP [D] | geklammerte Literale plus IPv4-mapped behandelt [D] | Default false; Literale und allowLocalBinding [D] | default blockiert; macOS Pfad-allowlist; Linux seccomp x86/arm64 [D] | user-level settings; fehlerhafte Datei bricht ab statt Fallback [D] | [D] Apache-2.0; beta preview; v0.0.78; aktiv |
| agent-seatbelt-sandbox | macOS | seatbelt profile via sandbox-exec | `deny network*` plus Loecher fuer localhost, mDNSResponder, unix sockets [D] | via mDNSResponder erlaubt [D] | durch seatbelt-deny [D] | ungeprueft [V] | localhost:* inbound und outbound [D] | outbound unix sockets breit erlaubt [D] | Profil und blocked.txt auf dem Host; Abgrenzung nicht dokumentiert [V] | [D] Demo, keine LICENSE, push 2026-02-11 |
| pi (nur Harness) | macOS/Linux/Windows | none [D] | none [D] | none | none | none | none | none | nur app config [D] | MIT; aktiv; npm releases [D] |
| pi + Docker Sandboxes | Container | sbx proxy ersetzt Credentials fuer konfigurierten Host [D] | Docker networking [D]; tiefe [V] | [D Docker] | [D Docker] | [D Docker] | [D Docker] | [D Docker] | sbx secret placeholder [D] | sbx kits; aktiv [D] |
| pi + OpenShell | lokal oder remote | policy-controlled sandbox [D] | policies filesystem/process/net/credential [D; Tiefe [V]] | [V] | [V] | [V] | [V] | [V] | credential policy [D] | Apache-2.0; v0.1.2; sehr aktiv [D] |
| pi + Gondolin | Linux microVM | Extension routet built-in tools und Befehle via `!` in QEMU microVM [D] | VM-Grenze; innerer netzstack [V] | [V] | [V] | [V] | [V] | [V] | host env erbt in die VM; nicht als credential boundary gedacht [D] | Apache-2.0; sandbox-helpers-0.12.0; aktiv |
| OpenCode (nur Harness) | plattformabhaengig, keine Grenze in der gelesenen Doku | tool-level permissions only [D via docs] | nicht netzverriegelnd [D] | n/a | n/a | n/a | n/a | n/a | app config [D] | aktiv [D] |
| google/ax + Agent Substrate | Kubernetes only | gVisor runsc oder cloud-hypervisor microVM; atelet [D] | Egress-Policy pro Actor [D]; Details [V] | [V] | [V] | [V] | [V] | debug true erlaub arbitrary exec [D] | K8s manifests und secrets [D] | AX v0.3.1; Substrate ohne release; beide in development [D] |
| Codex CLI | macOS, Linux, WSL2, Windows | seatbelt; bwrap; windows native sandbox [D] | modus-abhaengig; Netz default in gelesener Doku nicht beschrieben [U] | [V] | [V] | [V] | [V] | [V] | `config.toml` [D]; trusted vs project separation nicht dokumentiert [U] | Apache-2.0; rust-v0.160.0; sehr aktiv [D] |
| Gemini CLI sandbox | macOS/Linux/Windows/Docker | per-OS SandboxManager-Fabrik [D via Codepfade] | [V] | [V] | [V] | [V] | [V] | [V] | app config [V] | Apache-2.0; v0.62.0; aktiv [D] |
| Landlock | Linux | self-restriction; irreversibel; FS + TCP ab ABI 4 + UDP ab ABI 10 + IPC-Scope ab ABI 6 [D] | Port-Granularitaet [D] | TCP 53 erlaubbar per Kernel-Beispiel [D] | UDP 53 erlaubbar per Kernel-Beispiel [D] | [V] | [V] | abstract-socket und signal Scope ab ABI 6 [D] | im Programmcode [D] | Kernel-Feature [D] |
| gVisor/runsc | Linux | Userspace-Kernel ("Sentry" plus "Gofer" via 9P), OCI runtime [D] | via runsc [D]; Details [V] | [V] | [V] | [V] | [V] | [V] | OCI native [D] | Apache-2.0; release-20260928.0 [D] |
| bubblewrap | Linux | namespaces-Containment; von srt Linux und Codex Linux genutzt [D] | `--unshare-net`-Stil; keine Domain-allowlist [D] | [V] | [V] | [V] | [V] | [V] | CLI-Parameter [D] | COPYING nennt LGPL-2.1-or-later; v0.13.0 [D]; Lizenzpruefung offen [V] |
| nsjail | Linux | namespace-Jail [D limitiert geprueft] | [V] | [V] | [V] | [V] | [V] | [V] | config-Dateien [V] | Apache-2.0; 3.6 [D] |
| macOS containers / VMs (Docker Desktop, Lima, Podman) | macOS host, Linux VM | Linux-VM unter dem Host [D generisch] | `--network none` moeglich; mediation gehoert nicht zum Container [S] | [D generisch] | [D generisch] | [D generisch] | [D generisch] | [D generisch] | mounts und env-Variablen [D Docker] | Lima Apache-2.0 v2.2.0; Podman Apache-2.0 v6.1.3 [D] |

## 5. Abgrenzung: Tools, Wrappers, Harness-Konfinement und Vermittlung

1. App-level permissions (OpenCode permission system; bei pi fehlen sie) sind Schalter in der App. Agenten koennen bash-Schachteln und Unteragenten nutzen; eine Grenze ist die App-Logik, keine Laufzeitkapsel. [D via OpenCode docs und pi claim]
2. Ein srt-Wrapper um einen einzelnen Shell-/Tool-Aufruf kapselt nur diesen Kindprozess und dessen Nachkommen; der aufrufende Harness bleibt ausserhalb. [D via srt README use case "Sandboxing MCP Servers"] Wird dagegen der gesamte Harness via `srt opencode` oder `srt pi` gestartet, ist der vorgeschlagene Umfang der gesamte gestartete Prozessbaum, nicht automatisch nur ein Tool. Die tatsaechliche Abdeckung aller Hilfs-, Plugin-, Datei- und Netzwerkprozesse muss verifiziert werden. [V]
3. Harness-wide confinement ist nicht dasselbe wie tool-only isolation.

   Harness-wide: der gesamte Agent-Prozess steht hinter der Grenze. Quellen [D]: der Claim in agent-seatbelt-sandbox ("inherits to every child process and cannot be removed from inside"); pi Plain Docker und pi Docker Sandboxes (kompletter pi-Prozess im Container); pi OpenShell (kompletter pi-Prozess im Policy-Sandbox).

   Tool-only: nur ausgewaehlte Werkzeuge laufen in der isolierten Einheit; der Harness-Prozess bleibt auf dem Host. Gondolin ist genau dieses Muster (pi-Prozess auf dem Host; built-in tools und `!`-Befehle in einer Linux-MicroVM). Doku-Zitat: "Tool-only isolation does not constrain the host Pi process or extension tools that do not use the isolated backend." [D] Fuer RFC 0003 R.8.1, wenn der Angreifer das gesamte Agentenverhalten bestimmen darf, ist tool-only isolation allein unzureichend [S].
4. Vermittlung (Broker-Track) ist nicht Teil dieser Notiz. Sie muss RFC 0003 R.4.3 erfuellen und sitzt neben der Sandbox, nicht in ihr. [D via RFC 0003] [S] Designanbindung an den Broker-Auftrag des anderen Bearbeiters.

Rueckschluss [S]: Fuer RFC 0003 R.8.1 ("Der Angreifer darf das gesamte Agentenverhalten bestimmen, nicht aber die vertrauenswuerdige Basis kontrollieren") heisst das: harness-wide confinement plus mediation layer. Beides zusammen ist die tragfaehige Basis fuer die Erstiteration.

## 6. Drei plausible Erstiterationspfade

Vorbetrachtung: Die Lerniteration arbeitet mit synthetischem oder ausdruecklich freigegebenem, oeffentlichem Material und Arbeitsauftraegen; keine reale Autorisierung fuer geschuetzte Daten. Zielform laut Auftrag [D Auftrag]: ein kleines, brauchbares Lernstueck, ein dokument-basiertes Ergebnis mit Quellenbindung, innerhalb einer kleinen Coding-Session. Kein Benchmark, keine Streuversuche. Lokale Inferenz ist bevorzugt, ein ausdruecklich gewaehlter Remote-Weg optional; laufende Dienste, geladene Modelle oder erreichbare Endpunkte sind zu diesem Zeitpunkt nicht verifiziert [V]. In der Recherche wurde fuer keinen Pfad etwas installiert oder ausgefuehrt. Pfad A setzt keine Installation voraus; B und C brauchen spaetere GOs fuer Installationen. Alle Pfade sind ungetestet; die Ein-/Zwei-/Drei-Session-Angaben sind grobe Schaetzungen, keine Zusagen. [S]

### Pfad A: macOS-native Sandbox um den Harness, ohne Installation

Umfang: experimenteller Entwurf, KEIN gueltiges Betriebsrezept. `sandbox-exec -f <profil.sb> -D ...` um den Harness (opencode oder pi). Ein eigenes Profil, unabhaengig abgeleitet (siehe Abschnitt 3.4 zur Nicht-Kopierbarkeit der Demo-Lizenz [S]); mit reduzierten Loechern:

- `deny network*` behalten.
- statt `(allow network-outbound (remote ip "localhost:*"))` nur eine fest definierte loopback-Zeile fuer das Ziel des lokalen LLM-Servers (oder den Proxy, wenn der Broker-Track aktiv wird). [V]
- outbound unix-sockets einschraenken oder streichen. [V]
- DNS-Regel beseitigen oder als benannte Grenze im Startvertrag dokumentieren (RFC R.4.1 "Umgebung"). [V]
- `SECRETS_DIR` so setzen, dass das Profil ausserhalb der Sandbox-Write-Scope liegt (RFC R.4.4). [V]

Diese kleinen Netzwerk-/`SECRETS_DIR`-Aenderungen ergeben keine umfassende Dateisystem-, Prozess-, IPC- oder Credential-Isolation. Erforderlich und noch offen sind allowlist-basierte Quell- und Ausgabe-Scope-Grenzen, geschuetzte Konfiguration sowie Operationsgrenzen fuer IPC, geerbte File-Descriptoren und lokale Dienste; ein einzelner geschuetzter Pfad oder Loopback-Port ersetzt diese Nachweise nicht. [S, V]

Ablaufskizze der Iteration:

1. Minimalprofil schreiben und mit `sandbox-exec -f profil.sb /bin/zsh -c 'curl http://127.0.0.1:<port>/health'` gegen lokale Inferenz pruefen.
2. Harness in der Sandbox starten und mit `http://127.0.0.1:<port>` arbeiten; ggf. `no_proxy=localhost,127.0.0.1,::1` in der Session bereitstellen.
3. Negative Proben: eine externe HTTP-Anfrage versuchen, Ausbruchsversuche ueber Tools starten und das Ergebnis als belegte Wirkung oder `no_effect` pruefen. [V]

Aufwand [grobe Schaetzung, unverbindlich]: bis zu eine kleine Coding-Session.

Unbekannte [V]:
- Seatbelt-Verhalten auf macOS 27.2 in einem Node-basierten Harness, inklusive subprocess-Handling.
- Wie Node-basierte Harnesses selbst HTTP_PROXY veraendern; DNS via mDNSResponder bleibt bei einer entsprechenden Profil-Ausnahme moeglich (siehe Abschnitt 3.4), ihre Entfernung in einem eigenen Profil ist ungeprueft. [V]
- Der Prozessbaum erbt das Seatbelt-Profil und kann es laut README nicht von innen entfernen; der Claim ist unbelegt bis zum Experiment. [V]
- OpenCode- und pi-Einbindung unter Seatbelt sind in beiden Dokumentationen nicht beschrieben. [V]

### Pfad B: srt als Bibliothek auf macOS (installiert noetig)

Umfang [S]: `npm install -g @anthropic-ai/sandbox-runtime` plus eine user-level Config. Ein als lauffaehig behauptetes Beispiel gibt es in dieser Notiz nicht; kein solcher Weg wurde geprueft. Konfigkonzept [D via srt README]:

- Leere `allowedDomains` bedeutet: kein erlaubtes Ziel ueber die Proxys, nicht vollstaendig abgeschaltetes Netzwerk; die dokumentierte macOS/Windows-Systemresolver-Ausnahme bleibt zu beruecksichtigen.
- IP-Literal-Eintraege in `allowedDomains` sind vom resolved-address-check ausgenommen; das README dokumentiert genau das: "allow-listing `127.0.0.1:3000` is an explicit choice ... there is no separate carve-out list."
- Ob dieser Weg einen lokalen Inferenz-Dienst Ende-zu-Ende serviert, ist ungeprueft [V].

Zur Serverseite [D via srt README]: srt startet auf dem Host einen HTTP-Proxy und einen SOCKS5-Proxy und gibt dem wrapped Befehl die passenden Proxy-Variablen.

Zwei Loopback-Anbindungen sind dokumentiert, aber ohne Ende-zu-Ende-Nachweis [V]:

1. IP-Literal in `allowedDomains`; der Traffic geht dann weiterhin durch den host-seitigen Proxy.
2. macOS `allowLocalBinding`. Laut README bedeutet der Schalter direkt: "on macOS, `allowLocalBinding` lets the sandboxed process connect to loopback ports without going through the proxy at all". Der Doku-Name nennt "Binding"; der dokumentierte Mechanismus ist eine outbound-Verbindung zum Loopback-Port ohne Proxy. Beide Lesarten stehen im README; die tatsaechliche Verdrahtung braucht ein Experiment.

Den Harness via `srt opencode` oder `srt pi` starten, analog zum README-Beispiel. [D]

Aufwand [grobe Schaetzung, unverbindlich]: bis zu zwei kleine Coding-Sessions (Config plus Harness-Integration).

Unbekannte und Risiken [V]:
- Beta-Preview-Status; API und Konfigformat aendern sich weiter. [D Warnlabel]
- macOS: `allowLocalBinding` ist default false [D]. Die beiden Loopback-Anbindungen oben sind hier noch nicht nachgebaut. [V]
- DNS via Systemresolver bleibt moeglich [D known limitation].
- Linux-Pfad, konditional [D via README Linux]. Distributionen mit aktiver `kernel.apparmor_restrict_unprivileged_userns`-Einschraenkung (laut README Ubuntu 24.04+) koennen bubblewrap behindern; das README nennt eine Sysctl-Aenderung oder ein AppArmor-Profil als Loesungen. Solche Aenderungen beruehren die Sicherheitssysteme des Hosts. Sie gehoeren nicht in diese Recherche; sie sind eine eigenstaendige, autorisierte Host-Entscheidung.
- Jeder Sicherheitstest des Laufzeitstands gehoert in eine spaetere, freigegebene Session [S].

### Pfad C: Sandbox in Linux-VM oder Container (mehr Aufwand)

Umfang: Aufsetzen einer Linux-VM (Lima oder Podman machine); darunter pi oder opencode in einem Container-Pattern (Docker Sandboxes mit sbx oder OpenShell) oder srt-Linux im VM-Host-Setup. [D via pi docs und srt README] Gondolin ist nur ein ergaenzendes tool-only Backend: Es isoliert nicht den Host-Harness oder Extension-Tools ausserhalb des Backends und ist daher keine eigenstaendige Alternative fuer Whole-Agent-Konfinement (Abschnitt 3.2 und 5). [S]

Aufwand [grobe Schaetzung, unverbindlich]: drei oder mehr kleine Coding-Sessions (VM-Bootstrap, Image-Pattern, Harness- plus Connector-Verkehrs-Wiring).

Unbekannte und Risiken [V]:
- QEMU-Layer; GO noetig fuer Installation. [S]
- pi Container-Muster betrachtet `~/.pi/agent` ohne Mount als Credential-Boundary [D].
- Ubuntu 24.04 AppArmor userns-Einschraenkung betrifft srt Linux [D README Linux].
- Das sbx-Muster ersetzt Anmeldedaten am Proxy [D]; die Verbindung zum eigentlichen RFC R.4.3 Connector-Design bleibt Designarbeit [S].

Pfad C ist fuer den RFC 0003 Build-Zyklus sinnvoll ab der zweiten Iteration; fuer die erste Lernsession ist Pfad A oder B vorzuziehen [S].

## 7. Praezise Entscheidungsticket-Fragen

Alle Tickets spiegeln Befunde aus dieser Notiz; keine GO.

Ticket A1 (Pfad A, Loopback): Welche Loopback-Anbindung verbindet die lokale Inferenz und spaeter den Broker mit dem Sandboxprozess? Dokumentiert sind zwei srt-Wege (IP-Literal in `allowedDomains` ueber den Proxy; macOS `allowLocalBinding` direkt zum Loopback-Port), beide ohne Ende-zu-Ende-Nachweis in dieser Recherche. [V]

Ticket A2 (Pfad A, Konfig-Hoheit): Wo liegt das Profil, damit es ausserhalb der Sandbox-Write-Scope bleibt? srt beschreibt hierfuer "trusted user-level configuration" [D README]; agent-seatbelt-sandbox nicht [V]. Adressiert RFC R.4.4.

Ticket A3 (DNS-Kanal): RFC R.4.3 trennt Lese- und Senderecht. Der DNS-Name-Raum bleibt im Systemresolver (macOS/Windows [D], agent-seatbelt-sandbox [D]): unvermittelter Kanal. Akzeptieren wir diese Grenze fuer die Erstiteration oder fassen wir eine Vermittlung von DNS im Broker-Track ins Auge? [V]

Ticket B1 (Pfad B): srt ist `Beta Research Preview` [D], aber aktiv (v0.0.78 [D]). Frage: srt als Basis, oder Pfad A als Minimalvariante zuerst [S]?

Ticket C1 (Pfad C): Welcher Container- oder VM-Ansatz faengt nach der Lerniteration am besten an? pi-Doku betont "Tool-only isolation does not constrain the host Pi process or extension tools" [D]; host-seitige credentials bleiben am sbx-Proxy [D]. [S]

Ticket Q9 (Transversal): Wie bekommen Sandbox-Profil und Broker-Eintrag einen versionierten Umgebungstand (R.4.1 "Umgebung")? Das ist Designarbeit [S].

## 8. Staerkste offene Punkte nach dieser Recherche

1. Netzstacks der Container- und VM-Pfade (pi-Gondolin, OpenShell, sbx) sind nicht bis zur Syscall-Ebene belegt [V] oder nur auf Architekturlektuere gestuetzt [S].
2. Codex-Doku beschreibt per-OS enforcement und Sandbox-Modi, aber nicht das Netz-Default und die trust-Grenze zwischen project- und user-Konfiguration. [U]
3. pi plus Gondolin: der interne Netzstack der MicroVM ist in den gelesenen Dokumenten nicht im Detail beschrieben; die Netz-Grenze des microVM Pfades ist unbelegt. [V]
4. agent-seatbelt-sandbox: kein Beleg fuer Konfig-Abgrenzung und nichts fuer "cannot be removed from inside" ausser dem README-Claim.
5. AX/Substrate: Egress-Policy-Doku nicht gelesen; Kubernetes-only und kein stabiler Release [D].
6. OpenCode: tool-level permissions; die Enforcement-Ebene ist Applikationslogik [D via docs]; bypass-Analysen offen [V].
7. Lokale Broker-Anbindung der Inferenz: kein gepruefter Weg vom Sandboxprozess zu einem lokalen Modell-Dienst. Zwei dokumentierte, aber Ende-zu-Ende-unbelegte Varianten (srt IP-Literal via Proxy; macOS `allowLocalBinding` direkt) bleiben offen [V]. Ob sich der lokale Modell-Dienst selbst mit egress schafft (Modell-Downloads, Admin-Endpunkte), ist ebenfalls unbelegt [V].

## 9. Primare Quellen (alle Abrufe am 2026-10-02)

1. RFC 0003, lokal: `docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md`. Unveraendert.
2. srt: README, abgerufen 2026-10-02: https://github.com/anthropics/sandbox-runtime/blob/main/README.md. Von hier stammen die Zitate: Linux netns-Absatz unter "Dual Isolation Model"; "Known Limitations" (Linux proxy bypass wording); Windows "Network isolation"-Absatz; resolved-address-Check mit Loopback-Ausnahme; `allowLocalBinding`-Satz; `allowAppleEvents`-Satz.
3. srt Releases und Repo-Metadaten [D via `gh repo view`, 2026-10-02]: v0.0.78, Apache-2.0.
4. Anthropic Claude Agent SDK Python types (`SandboxNetworkConfig`): https://github.com/anthropics/claude-agent-sdk-python/blob/main/src/claude_agent_sdk/types.py.
5. Anthropic cookbook self-hosted sandboxes (Vercel, Modal, Daytona webhook pattern; Einblick nur snippet, Tiefe nicht gelesen [V]): https://github.com/anthropics/claude-cookbooks/tree/main/managed_agents/self_hosted_sandboxes.
6. michaelneale/agent-seatbelt-sandbox: README und Profil, abgerufen 2026-10-02: https://github.com/michaelneale/agent-seatbelt-sandbox/blob/main/sandbox.sb und https://github.com/michaelneale/agent-seatbelt-sandbox/#how-it-works.
7. pi (earendil-works): README und containerization.md, abgerufen 2026-10-02: https://github.com/earendil-works/pi/blob/main/README.md und https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/containerization.md.
8. NVIDIA/OpenShell: repo metadata [D via `gh repo view`].
9. Gondolin: repo metadata [D via `gh repo view`].
10. Google AX und Agent Substrate: https://github.com/google/ax/blob/main/README.md und https://github.com/google/ax/blob/main/docs/sandbox.md (Runner-Abschnitt); https://github.com/agent-substrate/substrate/blob/main/README.md. Egress-Doku nicht gelesen [V].
11. Codex CLI docs: https://learn.chatgpt.com/codex/sandboxing (nach redirect chain von developers.openai.com/codex/security) und Stub https://github.com/openai/codex/blob/main/docs/sandbox.md. [D]
12. Gemini CLI Codepfade: https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/services/sandboxManagerFactory.ts, plus die dort verlinkten linux/mac/windows manager files. [D]
13. Landlock Kernel-Doku (Stand 2026-08): https://docs.kernel.org/userspace-api/landlock.html.
14. gVisor Doku: https://gvisor.dev/docs/.
15. bubblewrap: COPYING (LGPL, Version 2.1): https://github.com/containers/bubblewrap/blob/main/COPYING; nsjail https://github.com/google/nsjail; Lima https://github.com/lima-vm/lima; Podman https://github.com/containers/podman (Metadaten via `gh repo view`).
16. OpenCode permissions docs: https://opencode.ai/docs/permissions/.
17. Explorer-Fakten: Host-Hardware, PATH-Befehle, macOS 27.2 status via `sw_vers`; lokale man page `sandbox-exec`.

Alle [U]- und [V]-Felder sind Experimentzuweisungen: jedes braucht eine spaetere, freigegebene Session [S].

Diese Notiz gibt keine produktive Betriebsfreigabe. Sie beschreibt moegliche Umgebungen und ihre dokumentierten Grenzen. Der Orchestrierer ist Validierungsbesitzer; vor der Tracker-Publikation braucht es ein GO.
