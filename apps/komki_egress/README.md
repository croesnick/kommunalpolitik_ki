# komki_egress

Egress-Proxy für die komki-Connectoren (Ticket #145, Vertrag:
[`apps/komki_connector/CONTRACT.md`](../komki_connector/CONTRACT.md) §1 und §9).

## Zweck

Seatbelt kann ausgehenden Verkehr nicht nach Host filtern, nur `*` oder
`localhost`. Deshalb darf ein Connector nur zu seinem eigenen Port auf
`127.0.0.1` verbinden, und `komki-egress` ist der einzige Prozess mit
Outbound. Er lässt je Port nur die Ziele zu, die exakt in der Allowlist
dieses Ports stehen. TLS wird nicht terminiert: der Proxy sieht nur das
Ziel, nie die Inhalte.

## Start

```bash
cd apps/komki_egress && mix escript.build
echo '{"ports": {"49601": {"connector": "web", "allow": ["api.search.brave.com:443"]}}}' \
  | ./komki-egress
```

Nach dem Binden aller Ports steht auf stdout eine Zeile
`{"komki_egress":"listening","ports":[49601]}`; danach läuft der Prozess,
bis er beendet wird. Gestartet wird er später von `komki up` (eigenes
Seatbelt-Profil, eigenes Ticket).

## Konfiguration

Genau eine JSON-Zeile auf stdin, keine Argumente:

```json
{"ports": {"<port>": {"connector": "<name>", "allow": ["host:port", "..."]}}}
```

- Port 1..65535, je Port ein Listener auf `127.0.0.1`.
- `connector`: Kleinbuchstaben, Ziffern, `_`, `-` (erscheint im Log).
- `allow`: nicht leere Liste von `host:port`. Hostnamen werden
  kleingeschrieben verglichen. Keine Wildcards, keine IP-Literale.

Ungültige Konfiguration oder ein belegter Port: Meldung auf stderr, Exit 2.

## Ablehnungsgründe

Jede Verbindung erzeugt eine JSON-Zeile auf stderr (Port, Connector, Ziel,
verbundene Adresse, Entscheidung, Grund, Bytes hin und zurück, Dauer),
ohne Inhalte.

| Grund | Antwort | Bedeutung |
|---|---|---|
| `method` | 403 | andere Methode als `CONNECT`, z. B. Klartext-`GET` |
| `malformed` | 403 | kaputte Request-Zeile oder kein `host:port` |
| `ip_literal` | 403 | IP-Adresse statt Hostname als Ziel |
| `not_allowed` | 403 | `host:port` steht nicht in der Allowlist dieses Ports (auch: anderer Port, Host eines anderen Connectors) |
| `blocked_address` | 403 | mindestens eine aufgelöste Adresse ist nicht öffentlich (privat, Loopback, Link-Local inkl. 169.254.169.254, CGNAT, Multicast, IPv4-mapped usw.; DNS-Rebinding-Schutz) |
| `header_too_large` | 403 | Request-Kopf größer als 8 KiB |
| `header_timeout` | 408 | Kopf nicht innerhalb von 10 s vollständig |
| `resolve_failed` | 502 | Hostname nicht auflösbar |
| `connect_failed` | 502 | keine der geprüften Adressen erreichbar |

Verbunden wird immer mit einer der geprüften Adressen, nie ein zweites Mal
über den Namen. Ein Tunnel ohne Verkehr wird nach 5 Minuten geschlossen.

## Tests

```bash
mix test                    # ohne Netz
mix test --include network  # zusätzlich echter CONNECT zu api.search.brave.com:443
```

Resolver und Adressprüfung lassen sich in `KomkiEgress.start/2` für Tests
ersetzen; über die Kommandozeile ist das nicht erreichbar.
