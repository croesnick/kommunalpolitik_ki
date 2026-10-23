# CONTRACT.md — komki Connector-Vertrag v1

Stand: 2026-10-23. Gemeinsame Grundlage für Vermittler, Connectoren, Egress-Proxy und `komki_cli`.
Begründung und Abwägung: `docs/research/2026-10-20-tool-zugang-entscheidungshandbuch.md` (Abschnitte 1, 6a,
7.2). Änderungen an diesem Vertrag nur durch den Integrator. Eine Lane, die eine Lücke findet, schreibt
einen Kommentar ins Ticket und baut nicht daran vorbei.

## 1. Architektur in einem Bild

```
pi (Seatbelt) ──stdio──> komki-relay.js (in pis Sandbox)
                              │  HTTP über Unix-Socket, Bearer-Token
                              ▼
                 komki-mediator (eigenes Seatbelt-Profil, kein Outbound)
                 Gate 1 (emit) → Connector-Aufruf → Gate 2 (admit) → PDR
                              │  Unix-Socket je Connector, Frame-Protokoll §3
          ┌───────────────────┼────────────────────┐
          ▼                   ▼                    ▼
  komki-connector-ris  komki-connector-web  komki-connector-vault   (je eigenes Profil)
          │ HTTP(S) über      │ HTTPS über          │ nur Dateisystem:
          │ Egress-Proxy      │ Egress-Proxy        │ Test-Vault
          ▼                   ▼
             komki-egress (eigenes Profil, einziger Prozess mit Outbound *:443)
             CONNECT-Proxy, ein Loopback-Port je Connector, Host-Allowlist je Port
```

**Warum ein Egress-Proxy:** Seatbelt filtert ausgehenden Verkehr nicht nach Host oder IP, die Adresse
muss `*` oder `localhost` sein (geprüft 2026-10-23: `host must be * or localhost in network address`).
Die Host-Allowlist je Connector erzwingt deshalb `komki-egress`. Das Profil eines Connectors erlaubt
ausgehend nur `localhost:<sein Proxy-Port>`.

**Warum `komki up` alles startet:** Seatbelt lässt sich nicht verschachteln (`sandbox_apply: Operation
not permitted`). Ein gesandboxter Prozess kann keinen Kindprozess mit eigenem Profil starten. `komki up`
(nicht gesandboxt) startet deshalb llama-server, Egress-Proxy, Connectoren und Vermittler jeweils über
`sandbox-exec -f <profil>`.

**Annahme:** Der Host ist nicht kompromittiert (kein Gegner mit derselben uid, Handbuch 7.2). Gegner ist
der prompt-injizierte Agent in pis Sandbox.

## 2. Laufzeitverzeichnis

Alle Sockets liegen unter `<base>/run/` (Rechte `0700`, angelegt von `komki up`):

| Pfad | Bindet | Verbindet |
|---|---|---|
| `<base>/run/mediator.sock` | Vermittler (Bandit, HTTP) | `komki-relay.js`, `komki doctor/status` |
| `<base>/run/connectors/<id>.sock` | Connector `<id>` | Vermittler, `komki doctor` |
| `<base>/run/mediator.token` | — (Datei, `0600`, 32 Byte Zufall als Hex) | geschrieben von `komki up`, gelesen von Vermittler und `komki run/session` |

macOS begrenzt Unix-Socket-Pfade auf 103 Byte. `komki doctor` prüft die Länge. Ist sie zu lang, lehnt
`komki init` die Basis ab.

## 3. Frame-Protokoll Vermittler ↔ Connector

- Transport: Unix-Domain-Socket, Stream. **Eine Verbindung je Aufruf**: verbinden, eine Anfrage, eine
  Antwort, schließen.
- Framing: 4 Byte Länge (Big Endian, `:gen_tcp` `packet: 4`), dann UTF-8-JSON. Maximal 1 MiB je Frame. Ein
  größerer Frame ist ein Protokollfehler, und die Verbindung wird geschlossen.
- Anfrage:

  ```json
  {"v": 1, "call_id": "<pdr-id des emit-PDR>", "op": "<operation>", "params": {...}, "context": {...}}
  ```

  `context` ist optional und kommt nur vom Vermittler, nie aus pis Argumenten. Heute einziges Feld:
  `assigned_label` (Liste) für schreibende Operationen (§6.3).
- Antwort, Erfolg: `{"v": 1, "call_id": "...", "ok": true, "result": {...}}`
- Antwort, Fehler: `{"v": 1, "call_id": "...", "ok": false, "error": {"code": "<kebab>", "detail": "<text>"}}`
- Fehlercodes (geschlossen): `bad-request`, `unknown-op`, `not-found`, `upstream-error`, `upstream-timeout`,
  `credential-missing`, `forbidden-path`, `too-large`, `internal`.
- Reservierte Operation `ping` (ohne Parameter) liefert `{"fassung": "<fassung-id>", "ops": [...]}`. Sie
  dient `komki doctor` und ist **kein** MCP-Tool.
- Timeout auf Vermittler-Seite: 15 s je Aufruf, danach `upstream-timeout`.
- Implementierung: `KomkiConnector.Frame`, `KomkiConnector.Client`, `KomkiConnector.Server`.

## 4. Start eines Connectors

```
sandbox-exec -f <base>/profile/connector-<id>.sb <binary> --socket <base>/run/connectors/<id>.sock [--proxy 127.0.0.1:<port>] [--base-url <url>] [--vault-dir <pfad>]
```

- **Credentials kommen über stdin**: genau eine JSON-Zeile `{"<NAME>": "<wert>", ...}`, danach schließt
  `komki up` stdin. Ein Connector ohne Credentials liest `{}`. Credentials stehen nie in argv, nie in der
  Umgebung, nie in Logs und nie in Antworten.
- Der Connector liest stdin vollständig, bevor er den Socket bindet. Nach dem Binden setzt er die
  Socket-Datei auf `0600`.
- Log: stderr, umgeleitet nach `<base>/tmp/connector-<id>.log`. Payloads werden nicht geloggt, nur
  Operation, Dauer und Fehlercode.
- Beendet wird der Connector über SIGTERM (pidfile `<base>/tmp/connector-<id>.pid`).

## 5. Manifeste (`KomkiConnector.Manifest`)

Einzige Quelle für Fassung, Operationen, Netz, Dateisystem, Credentials und Import-Label. Vermittler,
`komki_cli` (Profilgenerator, Start, Doctor) und Connectoren lesen **dasselbe** Modul.

| Feld | Bedeutung |
|---|---|
| `id` | `ris`, `web`, `vault` |
| `fassung` | `komki-ris/1`, `komki-web/1`, `komki-vault/1` |
| `binary` | Name des Escripts |
| `ops` | Operation → Parameter-Schema (geschlossen, siehe unten) und `kind` (`read` oder `write`) |
| `egress_hosts` | Host-Allowlist für den Egress-Proxy (`host:port`). Leer heißt: kein Netz, kein Proxy-Port |
| `fs` | Platzhalter-Pfade (`{vault_dir}`) mit Modus `read` oder `write` |
| `credentials` | Name → Keychain-Service (`security find-generic-password -s <service> -w`) |
| `environment` | Umgebung für `emit` (modellierte Empfänger der Anfrage), z. B. `web-suche@1` |
| `import_labels` | erlaubte Labels für Antworten. Bei RIS und Web genau eines, bei Vault eine Menge, aus der die Notiz wählt |

Parameter-Schemas sind geschlossen: Typ `string` (mit `max` Zeichen und optional `pattern`) oder `integer`
(mit `min`/`max`). Unbekannte Felder sind ein Fehler. Kein Parameter nimmt eine URL, einen absoluten Pfad
oder einen Host an.

### 5.1 Fassungen

| Connector | MCP-Tool (Vermittler) | Operation | Parameter | Art |
|---|---|---|---|---|
| ris | `ris_search` | `search` | `text` (string, max 200), `limit` (integer 1..20, optional, Default 10) | read |
| ris | `ris_show` | `show` | `top_id` (string, max 64, pattern `^[A-Za-z0-9_-]+$`) | read |
| web | `web_search` | `search` | `query` (string, max 400), `count` (integer 1..10, optional, Default 5) | read |
| vault | `vault_search` | `search` | `text` (string, max 200) | read |
| vault | `vault_read` | `read` | `note_id` (string, max 200, pattern `^[A-Za-z0-9äöüÄÖÜß _./-]+\.md$`) | read |
| vault | `vault_write_test` | `write_test` | `title` (string, max 120), `body` (string, max 20000) | write |

Der Vermittler bietet damit `ping`, `admit_document` und diese sechs Tools an. Das ist Fassung
`komki-mediator/2`, und der D.9-Pin bricht absichtlich.

### 5.2 Ergebnisformen (Connector → Vermittler)

- `ris.search`: `{"results": [{"top_id", "titel", "sitzung", "datum", "url"}], "abrufdatum"}`. Nicht-öffentliche
  TOPs filtert der Connector **vor** Begrenzung und Zählung heraus. Ihre Existenz ist nicht erkennbar,
  auch nicht über die Anzahl.
- `ris.show`: `{"top_id", "titel", "sitzung", "datum", "text", "url", "abrufdatum"}`. Ein nicht-öffentlicher TOP
  ergibt `not-found`, genau wie ein nicht existierender.
- `web.search`: `{"results": [{"title", "url", "snippet"}], "abrufdatum"}`
- `vault.search`: `{"results": [{"note_id", "title", "labels"}]}`. Notizen ohne gültiges `komki_labels` erscheinen
  nicht.
- `vault.read`: `{"note_id", "title", "content", "labels"}`
- `vault.write_test`: `{"note_id", "labels"}`

## 6. Ablauf im Vermittler (Gate 1, Vollzug, Gate 2)

Jeder Connector-Aufruf besteht aus **zwei Entscheidungen** der Engine und **zwei PDR**.

### 6.1 Gate 1: `emit` (die Anfrage ist eine Ausgabe, R.4.2/R.4.3)

1. Schema-Prüfung der Parameter gegen das Manifest. Bei Verstoß: `decision: error`, PDR, kein Vollzug.
2. `call_bytes = JSON.canonical({"tool", "params"})`, `intent_hash = sha256(call_bytes)`.
3. Snapshot: `workspace.bindings = room.workspace_bindings` (B_W), `workspace.environment =
   manifest.environment` (Empfänger der Anfrage), Objekt `out-<digest12>` / Version `v1` / Labels `[]`,
   Fakten des Raums plus `output_content_digest = intent_hash`.
4. `Derive.decide(..., intent{operation: "emit"})`. Kein permit: Antwort mit Remedies, PDR, **kein
   Vollzug**.
5. permit: **emit-PDR wird geschrieben, bevor der Connector aufgerufen wird** (Vorbeleg vor Wirkung, R.11).
   Die `decision_id` dieses PDR ist die `call_id` im Frame.

### 6.2 Gate 2: `admit` (die Antwort ist ein neuer Eingang)

1. Connector-Antwort gegen die Ergebnisform §5.2 prüfen. Bei Verstoß: zurückhalten (`redacted`).
2. Labels vergeben: RIS und Web bekommen fest `import_labels` des Manifests. Bei Vault gelten die Labels der
   Notiz, die ⊆ `import_labels` sein müssen, sonst `redacted`. **Die Selbstauskunft des Connectors wird nie
   über das Manifest hinaus geglaubt.**
3. Objekt `in-<digest12 der Ergebnis-Bytes>` / `v1` / Labels, `workspace.environment = room.environment`.
4. `Derive.decide(admit)` und `Verify.check`. permit: Antwort mit `labels`, `decision_id`,
   `emit_decision_id` und `payload_hash`. Sonst Remedies bzw. `redacted`.
5. admit-PDR mit Verweis auf den emit-PDR (`call_id`).

### 6.3 Schreibende Operationen (`vault.write_test`)

`emit` mit `environment = vault-lokal@1`. Bei permit schickt der Vermittler `context.assigned_label =
decision.assigned_label` (= B_W) mit. Der Connector schreibt genau diese Labels als `komki_labels` in das
Frontmatter (λ(y) = B_W, R.5.5) und gibt `note_id` und `labels` zurück. Gate 2 prüft, dass die
zurückgemeldeten Labels gleich `assigned_label` sind.

## 7. Γ-Konventionen (Default-Registry und Räume)

Beobachter: `nutzende-person`, `pi-agent`, `ris-betreiber`, `brave-search`.

| Umgebung | Beobachter |
|---|---|
| `lokaler-arbeitsraum@1` | nutzende-person, pi-agent |
| `ris-abruf@1` | nutzende-person, pi-agent, ris-betreiber |
| `web-suche@1` | nutzende-person, pi-agent, brave-search |
| `vault-lokal@1` | nutzende-person, pi-agent |

| Bindung | readers (R_b) | operations |
|---|---|---|
| `ris-oeffentlich@1` | alle vier | admit true, emit true |
| `web-oeffentlich@1` | alle vier | admit true, emit true |
| `vault-oeffentlich@1` | alle vier | admit true, emit true |
| `vault-vertraulich@1` | nutzende-person, pi-agent | admit true, emit true |

`fact_fields` bekommt zusätzlich `output_content_digest: string`.

`room.json` bekommt das Feld `workspace_bindings` (B_W für Connector-Operationen; sortiert). Ein Raum ohne
das Feld bietet keine Connector-Operationen an (fail-closed). `admit_document` bleibt unverändert.

Zwei Referenzräume für Tests:

- **recherche**: B_W = `[ris-oeffentlich@1, vault-oeffentlich@1, web-oeffentlich@1]`. Websuche, RIS und
  öffentliche Vault-Notizen sind erlaubt. Eine vertrauliche Notiz scheitert an `label_inclusion`.
- **vertraulich**: B_W = `[ris-oeffentlich@1, vault-oeffentlich@1, vault-vertraulich@1, web-oeffentlich@1]`.
  Vertrauliche Notizen sind lesbar. **Jede Websuche und jede RIS-Anfrage wird abgelehnt**
  (`recipient_not_allowed`: brave-search bzw. ris-betreiber ∉ R(vault-vertraulich@1)). Das ist die
  Lethal-Trifecta-Sperre.

## 8. Kanal pi → Vermittler

- Der Vermittler lauscht **nur** auf `<base>/run/mediator.sock` (Bandit `ip: {:local, path}`), nicht mehr auf
  Loopback-TCP.
- Jede Anfrage braucht `Authorization: Bearer <token>` (Vergleich in konstanter Zeit). Ohne oder mit
  falschem Token: 401, Logeintrag, kein Tool. `/healthz` verlangt das Token ebenfalls.
- `X-Komki-Session: <session-id>` (von `komki run/session` erzeugt) geht als `session_id` in jeden PDR. Das
  dient der Zuordnung, nicht der Authentisierung.
- `komki-relay.js`: von `komki_cli` geschrieben nach `<base>/pi-home/.pi/agent/komki-relay.js`. pi startet
  es als stdio-MCP-Server (`command: <node>`, `args: [relay]`). Es übersetzt JSON-RPC-Zeilen auf stdin in
  `POST /mcp` über den Socket, verwaltet `Mcp-Session-Id` und versteht JSON- und SSE-Antworten. Token und
  Session-ID kommen aus der Umgebung (`KOMKI_MEDIATOR_TOKEN`, `KOMKI_SESSION_ID`) bzw. aus den
  `env`-Feldern der pi-MCP-Konfiguration.
- pis Profil erlaubt `network-outbound` zu `(remote unix-socket (path-literal "<base>/run/mediator.sock"))`
  und zum llama-Port, sonst nichts.

## 9. Egress-Proxy `komki-egress`

- HTTP-CONNECT-Proxy. Je Connector mit `egress_hosts` ein eigener Port auf `127.0.0.1`. Die Zuordnung
  Port → Allowlist kommt per stdin als JSON von `komki up`.
- Erlaubt nur `CONNECT host:port`, wenn `host:port` exakt in der Allowlist des Ports steht. Kein Klartext-HTTP,
  keine Wildcards. Die aufgelöste IP darf nicht privat, Loopback, Link-Local oder Metadaten-Adresse sein
  (DNS-Rebinding-Schutz: auflösen, prüfen, mit genau dieser IP verbinden).
- Log je Verbindung: Connector-Port, Host, Entscheidung, Bytes hin und zurück, Dauer. Keine Inhalte.
- Für Mock-Betrieb (RIS-Mock auf Loopback) geht der Connector **nicht** über den Proxy. Sein Profil erlaubt
  dann `localhost:<mock-port>`, und `komki_cli` setzt `--base-url http://127.0.0.1:<mock-port>/`.

## 10. Nicht in v1 (bewusst offen)

GO-Flow für schreibende Operationen (#98; `write_test` schreibt nur in den Testordner), Page-Fetch-Connector,
AZ und Nextcloud, Peer-PID-Prüfung (nicht nötig unter der Host-Annahme), Vereinheitlichung von
`admit_document` mit `workspace_bindings`.
