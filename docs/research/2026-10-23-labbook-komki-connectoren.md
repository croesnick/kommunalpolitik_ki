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

*(wird nach Abschluss der Lanes ergänzt)*

## Phase 2: Integration

*(folgt)*

## Phase 3: Sicherheitstests

*(folgt)*

## Phase 4: Nutzungstests

*(folgt)*

## Erkenntnisse und offene Punkte

*(folgt)*
