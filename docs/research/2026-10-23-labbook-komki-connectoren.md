# Labbook: komki-Connectoren (RIS, Web, Vault)

Laufendes Versuchsprotokoll zum Bau und zur Prüfung des Gesamtsetups. Ticket #147. Beginn 2026-10-23.

| Feld | Wert |
|---|---|
| Branch | `komki-connectors` |
| Vertrag | [`apps/komki_connector/CONTRACT.md`](../../apps/komki_connector/CONTRACT.md) |
| Begründung | [Entscheidungshandbuch Tool-Zugang](2026-10-20-tool-zugang-entscheidungshandbuch.md) |
| Host | macOS (Darwin 27.2.0), arm64, Erlang/OTP 28, Elixir 1.19.5, pi 1.1.0 |
| Annahme | Host nicht kompromittiert. Gegner ist der prompt-injizierte Agent in pis Sandbox und lokale Clients ohne Token |

Format je Eintrag: **Frage** · **Aufbau** (Befehl, Daten) · **Ergebnis** (beobachtet, wörtlich wo möglich) ·
**Erkenntnis** · **Folge** (Änderung, Ticket). Ein Ergebnis ist nur „bestanden“, wenn es beobachtet wurde. Was
nicht lief, steht als nicht gelaufen da.

## Übersicht

| ID | Thema | Ergebnis | Folge |
|---|---|---|---|
| L-001 | Seatbelt: Hostfilter für ausgehenden Verkehr | widerlegt die Handbuch-Annahme | Egress-Proxy (#145) |
| L-002 | Seatbelt: Verschachtelung | nicht möglich | `komki up` startet alles (#146) |
| L-003 | pi-MCP-Client und Unix-Socket | nicht unterstützt | stdio-Relay (#143) |
| L-004 | Erlang Unix-Sockets und Peer-PID | funktioniert | Protokoll auf Unix-Sockets; PID-Prüfung optional |
| L-005 | `lo0` mitschneidbar ohne root | ja, auf diesem Host | Unix-Socket statt TCP (#143) |
| L-006 | Engine-Abbildung eines Connector-Aufrufs | emit + admit | CONTRACT §6 |

## Phase 0: Vorab-Experimente (vor dem Bau)

### L-001 Kann Seatbelt ausgehenden Verkehr auf Hosts begrenzen?

- **Frage:** Das Handbuch nahm an, ein Connector-Profil könne „nur `api.search.brave.com`“ erlauben.
- **Aufbau:**
  ```
  sandbox-exec -p '(version 1)(allow default)(deny network-outbound)(allow network-outbound (remote ip "example.com:443"))' /usr/bin/true
  sandbox-exec -p '… (remote ip "93.184.215.14:443") …' /usr/bin/true
  sandbox-exec -p '… (remote tcp "*:443") …' /usr/bin/true
  ```
- **Ergebnis:** Hostname: `sandbox-exec: host must be * or localhost in network address`, Exit 65. IP-Literal:
  dieselbe Meldung, Exit 65. Wildcard `*:443`: Exit 0.
- **Erkenntnis:** Seatbelt kennt als Ziel nur `*` oder `localhost`. Eine Host-Allowlist ist im Profil nicht
  ausdrückbar.
- **Folge:** Egress-Proxy `komki-egress` mit Allowlist je Connector-Port (#145). Connector-Profile erlauben
  nur `localhost:<proxy-port>`. Handbuch (V3, B5, Abschnitt 9) korrigiert.

### L-002 Kann ein gesandboxter Prozess ein Kind mit eigenem Profil starten?

- **Frage:** Kann der Vermittler (selbst gesandboxt, #137) Connectoren mit eigenem Profil starten?
- **Aufbau:**
  `sandbox-exec -p '(version 1)(allow default)' sandbox-exec -p '(version 1)(allow default)(deny network-outbound)' /usr/bin/curl -sS -m 3 https://example.com -o /dev/null`
- **Ergebnis:** `sandbox-exec: sandbox_apply: Operation not permitted`, Exit 71.
- **Erkenntnis:** Seatbelt lässt sich nicht verschachteln.
- **Folge:** `komki up` (nicht gesandboxt) startet Egress, Connectoren und Vermittler jeweils selbst. Der
  Vermittler spricht die Connectoren über Unix-Sockets an. Der Kommentar in #137 ist korrigiert.

### L-003 Kann pis MCP-Client einen Unix-Socket ansprechen?

- **Frage:** Lässt sich der Kanal pi → Vermittler direkt auf einen Unix-Socket legen?
- **Aufbau:** Suche im installierten Paket `@earendil-works/pi-coding-agent` (pi 1.1.0, `dist/`) nach `socketPath`,
  `unix:` und `StreamableHTTP`. Abgleich mit der pi-MCP-Doku (Transporte: stdio und Streamable HTTP mit `url`).
- **Ergebnis:** Treffer für `socketPath` nur im gebündelten `ws`-WebSocket-Code, nicht im MCP-Transport. Die
  MCP-Konfiguration kennt `url` (HTTP) und `command`/`args` (stdio).
- **Erkenntnis:** Kein Unix-Socket-Transport in pis MCP-Client.
- **Folge:** stdio-Relay `komki-relay.js` in pis Sandbox, das HTTP über den Unix-Socket des Vermittlers spricht
  (#143, CONTRACT §8).

### L-004 Funktionieren Unix-Sockets und Peer-PID in Erlang auf macOS?

- **Frage:** Trägt `:gen_tcp` mit `{:local, path}` das Frame-Protokoll, und liefert macOS die PID der
  Gegenstelle?
- **Aufbau:** `elixir uds.exs`: `:gen_tcp.listen(0, ifaddr: {:local, path}, packet: 4)`, Client verbindet und
  sendet `"hallo"`, Server liest `:inet.getopts(s, [{:raw, 0, 2, 4}])` (SOL_LOCAL = 0, LOCAL_PEERPID = 2).
- **Ergebnis:** `recv: "hallo"`; `LOCAL_PEERPID: {:ok, [{:raw, 0, 2, <<167, 66, 0, 0>>}]}`; eigene OS-PID `17063`
  (= 0x42A7, Little Endian `167, 66`).
- **Erkenntnis:** Unix-Sockets mit Längenpräfix funktionieren ohne Abhängigkeiten. Peer-PID ist verfügbar.
- **Folge:** Frame-Protokoll über Unix-Sockets (`komki_connector`, 11 Tests grün). Peer-PID-Prüfung bleibt
  ungenutzt, weil die Host-Annahme sie nicht verlangt.

### L-005 Ist Loopback-Verkehr ohne root mitschneidbar?

- **Frage:** Kann ein beliebiger Prozess des Nutzers den MCP-Verkehr auf `127.0.0.1:49525` mitlesen?
- **Aufbau:** `ls -l /dev/bpf*`, `dscl . -read /Groups/access_bpf GroupMembership`, `ls /Library/LaunchDaemons | grep -i bpf`.
- **Ergebnis:** `crw-rw---- root access_bpf /dev/bpf0`; Gruppenmitglieder `crntng crn`;
  `org.wireshark.ChmodBPF.plist` vorhanden.
- **Erkenntnis:** Auf diesem Host kann jeder Prozess des Nutzers `lo0` ohne root mitschneiden. Zusätzlich
  war der Vermittler ohne Authentisierung erreichbar.
- **Folge:** Unix-Socket plus Bearer-Token (#143). Mitschnitt fällt unter die Host-Annahme und ist kein
  Abnahmekriterium. Ob `access_bpf` bleibt, entscheidet die nutzende Person.

### L-006 Wie bildet die Engine einen Connector-Aufruf ab?

- **Frage:** Reicht der Regelzweig `admit` für Anfragen an externe Dienste?
- **Aufbau:** Lektüre `apps/komki_policy/CONTRACT.md` §2, §4.3, §4.5. Abgleich mit `KomkiMediator.Gate` und
  `Room.snapshot_for/4`.
- **Ergebnis:** Die Engine entscheidet `admit` und `emit`. `emit` prüft Empfänger (ρ ⊆ R(B_W)) gegen die
  Umgebung im Snapshot und verlangt den Fakt `output_content_digest`. Der bisherige Vermittler setzt
  B_W = Objektlabels (MVP-Vereinfachung für `admit_document`).
- **Erkenntnis:** Eine Anfrage ist ein `emit`, dessen Umgebung die Empfänger der Anfrage modelliert
  (`web-suche@1` mit `brave-search`). Die Antwort ist ein `admit` mit Labels aus der Import-Regel. Die
  Lethal-Trifecta-Sperre fällt damit aus der vorhandenen Empfängerprüfung heraus: Liegt eine vertrauliche
  Bindung in B_W, ist `brave-search` kein zulässiger Empfänger.
- **Folge:** CONTRACT §6 und §7; `room.json` bekommt `workspace_bindings` (#144).

## Phase 1: Lanes (Bau)

Jede Lane lief als eigener Agent in einem eigenen Worktree auf Basis von 9cb8af6. Die Tests jeder Lane hat
der Integrator nach dem Merge auf `komki-connectors` erneut ausgeführt.

| ID | Lane | Ticket | Tests (Lane / Nachlauf) | Merge |
|---|---|---|---|---|
| L-101 | Egress-Proxy | #145 | 30/30 inkl. `:network` / 29 ohne `:network` | d0476d1 |
| L-102 | Web-Connector | #96 | 19/19 / 19/19 | 250d707 |
| L-103 | Vault-Connector | #97 | 31/31 / 31/31 | 764fc4d |
| L-104 | RIS-Connector | #94 | 21/21 / 21/21 | a49c87f |
| L-105 | Vermittler-Gate | #144 | 93/93 / 113/113 nach Kanal-Merge | 6a6f7bf |
| L-106 | Kanal | #143 | 87 + 170 / 113 + 170 | 81ba174 |

### L-101 Egress-Proxy `komki-egress`

- **Frage:** Erzwingt der Proxy die Allowlist je Connector-Port und schützt er vor Umgehung?
- **Aufbau:** ExUnit mit lokalem Echo-Upstream und injiziertem Resolver. Smoke-Test mit curl gegen das
  Escript (Allowlist `api.search.brave.com:443`).
- **Ergebnis:**
  - Abgelehnt werden mit 403: nicht gelistete Hosts, gelistete Hosts mit anderem Port, Hosts eines
    anderen Connector-Ports, Klartext-GET und POST, IP-Literale (127.0.0.1, [::1], 169.254.169.254),
    Köpfe über 8 KiB. Header-Timeout gibt 408.
  - Rebinding: `localhost` mit echtem Resolver wird abgelehnt (`blocked_address`), und schon eine
    private Adresse unter mehreren genügt zur Ablehnung.
  - Smoke-Test: Brave über den Proxy liefert HTTP 301 (Tunnel steht), `https://example.com` bekommt 403
    (`not_allowed`), `http://example.com` bekommt 403 (`method`).
  - Das Log enthält keine Inhalte; eine GET-URL mit `token=` erscheint nicht.
- **Erkenntnis:** Die Host-Allowlist, die Seatbelt nicht ausdrücken kann (L-001), ist damit am einzigen
  Ausgang durchgesetzt. Status 403/408/502 statt pauschal 403 (README-Tabelle).
- **Folge:** Start und Profil durch `komki up` (#146).

### L-102 Web-Connector

- **Frage:** Liefert der Connector nur die Vertragsform, und bleibt der Key unsichtbar?
- **Aufbau:** ExUnit gegen einen OTP-Mock über einen echten Unix-Socket. CONNECT-Attrappe für den
  Proxy-Pfad.
- **Ergebnis:**
  - Form exakt `{results: [{title, url, snippet}], abrufdatum}`; HTML wird bereinigt, Längen
    begrenzt, nicht-HTTP-URLs werden verworfen.
  - Fehlercodes: 401 → `credential-missing`, 403, 429 und 500 → `upstream-error`, Timeout →
    `upstream-timeout`.
  - Der Key steht in keinem Log (Level debug), keiner Antwort und keinem `inspect`/`~p` des Zustands.
  - Die Proxy-Attrappe sieht `CONNECT api.search.brave.com:443` ohne Key.
  - **Echter Smoke-Test nicht gelaufen:** `security find-generic-password -s brave-search-api -w` hing
    über 20 s, vermutlich wegen eines Schlüsselbund-Dialogs, und wurde abgebrochen. Der Key wurde nie
    ausgegeben.
- **Erkenntnis:** Der Schlüsselbund verlangt beim ersten Zugriff über `security` eine Freigabe durch die
  nutzende Person. Das betrifft auch `komki up`.
- **Folge:** Echter Smoke-Test in der Integration mit der nutzenden Person; ein Hinweis in `komki doctor`
  ist wünschenswert.

### L-103 Vault-Connector

- **Frage:** Hält die Pfadhärtung gegen den omac-Fall (Symlink auf `~/.ssh/id_rsa`) und gegen eingeschleuste
  Labels?
- **Aufbau:** ExUnit über einen Socket mit einer tmp-Kopie des synthetischen Test-Vaults
  (`apps/komki_connector_vault/priv/test-vault`); die Symlinks legen die Tests an.
- **Ergebnis:**
  - `forbidden-path` für `../`, absolute Pfade, leere Segmente, `.obsidian/`, Symlink-Datei nach außen
    und auf `~/.ssh/id_rsa`, Symlink-Verzeichnis nach außen und innen, `komki-test` als Symlink oder Datei.
  - Über den Socket werden `%2e%2e` und NUL schon vom Schema abgewiesen.
  - Ungelabelte Notizen und solche mit ungültigem Label sind unsichtbar (`not-found`).
  - `write_test` überschreibt nie (`-2`, `-3`). Ein eingeschleustes `komki_labels` in Body oder Titel
    ändert die Labels nicht.
- **Erkenntnis:** Erlang bietet kein `O_NOFOLLOW`. Zwischen `lstat` und `open` bleibt ein TOCTOU-Fenster, das
  unter der Host-Annahme nur der Agent selbst nutzen könnte. pi hat aber keinen Schreibzugriff auf den
  Vault, und das Seatbelt-Profil ist die zweite Grenze.
- **Folge:** keine.

### L-104 RIS-Connector

- **Frage:** Bleiben nicht-öffentliche TOPs unsichtbar, auch über Zählung und Fehlermeldungen?
- **Aufbau:** ExUnit gegen den Mock (`priv/mock_ris.exs`) über einen Socket. Zusätzlich hat die Lane das
  Escript gegen die echte, öffentliche Gast-API geprüft (keine Credentials).
- **Ergebnis:**
  - „Bahnhofstraße“ ergibt 2 Treffer bei limit 20 und den richtigen bei limit 1.
  - Ein Wort, das nur in nicht-öffentlichen TOPs steht, ergibt `[]`, genau wie ein unbekanntes Wort.
  - `show` auf restricted, geschützten Teil, fehlende und falsch geformte IDs liefert identisch
    `not-found` / „TOP nicht gefunden“.
  - Echte API: search „friedhof“ fand 1 Treffer in 3,6 s; über einen lokalen CONNECT-Proxy besteht die
    TLS-Prüfung.
  - **Befund:** Die von ratsinfo genutzten Endpunkte (`meetings`, `agendaitems`, `fulltextsearch`) antworten
    ohne Token mit 401. Der Connector nutzt die Gast-Endpunkte (`guestmeetings`, `guestagendaitems`), und
    diese liefern `textsanddocsvisible: false`, also keine TOP-Texte.
- **Erkenntnis:** Ohne Credentials findet die RIS-Suche nur Titel. Öffentlich heißt in der Gast-API
  `restricted == false` und `protectedpart == false` (fail-closed).
- **Folge:** Folgeticket #148 „RIS-Connector: TOP-Texte über authentisierte API“.

### L-105 Vermittler: emit → Vollzug → admit

- **Frage:** Hält der Vermittler die Reihenfolge Vorbeleg vor Wirkung ein, und greift die
  Lethal-Trifecta-Sperre, bevor ein Connector etwas tut?
- **Aufbau:** `connector_gate_test.exs` (19 Tests) mit einem echten `KomkiConnector.Server` als Fake unter
  `/tmp/km<hex>/<id>.sock`. Der Fake prüft beim Aufruf die Journal-Länge.
- **Ergebnis:**
  - Beim Aufruf liegt 1 Journal-Datensatz vor (emit-PDR). emit- und admit-PDR tragen dieselbe `call_id`, und
    `Journal.verify` bestätigt die Hash-Kette.
  - Raum vertraulich: `web_search` und `ris_search` → deny `recipient_not_allowed`, **der Fake wird nicht
    aufgerufen**.
  - Raum recherche: `vault_read` einer vertraulichen Notiz → deny `label_not_included`, ohne Inhalt.
  - Fremde Labels, fehlende Labels, Zusatzfelder oder falsche Typen in der Connector-Antwort → `redacted`.
  - Raum ohne `workspace_bindings` → fail-closed. Connector down → `admitted: false` mit PDR.
- **Erkenntnis:**
  - anubis prüft Typ, Länge, Bereich und Pflichtfelder vor dem Tool und verwirft unbekannte Felder
    stillschweigend. Solche Verstöße erzeugen **keinen PDR**; nur Musterverstöße erreichen `Params.check`.
  - `vault_search` labelt die Vereinigung aller Treffer. Ein vertraulicher Treffer sperrt in recherche die
    ganze Suche: sicher, aber grob.
- **Folge:** Beides steht unter „offene Punkte“ unten.

### L-106 Kanal pi → Vermittler

- **Frage:** Erreicht nur der Inhaber des Tokens den Vermittler, und kommt die Session-ID im PDR an?
- **Aufbau:** ExUnit über einen echten Socket. Relay-Test mit `node`. Live: Wegwerf-Instanz unter
  `/private/tmp/kk` gegen den laufenden llama, `komki run` mit `admit_document`.
- **Ergebnis:**
  - Ohne oder mit falschem Token → 401, die Logzeile enthält den Token-Wert nicht. `/healthz` ohne Token →
    401. Socket `0600`, `run/` `0700`.
  - `lsof` zeigt keinen TCP-Socket des Vermittlers, und `127.0.0.1:49525` antwortet nicht.
  - Live-PDR: `{"tool":"admit_document","decision":"permit","outcome":"admitted","session_id":"ses-7534d7276d4fcbeb"}`.
- **Erkenntnis:** Die `mcp.json` im pi-Home bleibt für den Agenten schreibbar und wird nur bei `komki up` neu
  geschrieben. Ein in pis Sandbox eingetragener MCP-Server liefe zwar ebenfalls in pis Sandbox, aber die
  Konfiguration sollte trotzdem keinen Lauf überdauern. Das Relay wird schon bei jedem pi-Start neu
  geschrieben.
- **Folge:** `mcp.json` ebenfalls bei jedem pi-Start neu schreiben (Integration).

### L-107 Integration: Befunde beim Zusammenführen

- **Vault-Labels nach dem Schreiben:** Eine in recherche geschriebene Notiz trägt λ(y) = B_W, also auch
  `ris-oeffentlich@1` und `web-oeffentlich@1`, und wäre mit den alten `import_labels` nicht mehr lesbar
  gewesen (Befund von Lane B). Behoben: `import_labels` des Vault umfassen alle vier Bindungen, Commit dd40d8f.
- **Workspace scannt Agent-Worktrees:** Der Pre-commit-Hook `mix workspace compile` lud
  `.claude/worktrees/agent-*` als Projekte und scheiterte. Behoben: `.workspace.exs` ignoriert `.claude`.
- **Konflikte zwischen Gate und Kanal:** `supervisor.ex`, `cli.ex`, `http_test.exs` und README. Gelöst mit dem Kanal
  als Basis und `connectors_dir` in der Kanal-Map. Die Connector-Tools nutzen jetzt `Env.for_call(frame)`, damit
  `session_id` auch in Connector-PDR landet. Ergebnis: Vermittler 113/113, komki_cli 170/170, credo ohne Befund.

## Phase 2: Integration

*(folgt)*

## Phase 3: Sicherheitstests

*(folgt)*

## Phase 4: Nutzungstests

*(folgt)*

## Erkenntnisse und offene Punkte

*(folgt)*
