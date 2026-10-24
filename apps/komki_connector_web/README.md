# komki_connector_web

Connector `web` (Fassung `komki-web/1`, Ticket #96): Websuche über die
[Brave Search API](https://api-dashboard.search.brave.com/app/documentation/web-search/get-started)
für den Vermittler. Eine Operation, `search(query, count)`. Vertrag:
[`apps/komki_connector/CONTRACT.md`](../komki_connector/CONTRACT.md) (§3 Frame-Protokoll,
§4 Start, §5 Manifest und Ergebnisform).

Der Suchtext verlässt den Rechner und ist beim Suchanbieter sichtbar. Deshalb
entscheidet der Vermittler vor jedem Aufruf (Gate 1, Umgebung `web-suche@1`),
und die Antwort bekommt das Label `web-oeffentlich@1` (Gate 2).

## Aufruf

```
komki-connector-web --socket <pfad> [--proxy 127.0.0.1:<port>] [--base-url <url>]
```

| Option | Bedeutung |
|---|---|
| `--socket` | Unix-Socket, den der Connector bindet (Rechte `0600`). Pflicht. |
| `--proxy` | Egress-Proxy `komki-egress` als `host:port`. HTTPS läuft dann per `CONNECT api.search.brave.com:443` durch den Proxy. |
| `--base-url` | Nur für Tests und Mock. Default `https://api.search.brave.com/`. |

Gestartet wird der Connector von `komki up` unter seinem Seatbelt-Profil.

## Credentials

Eine JSON-Zeile über stdin: `{"BRAVE_API_KEY": "..."}`. `komki up` holt den
Schlüssel aus dem macOS-Schlüsselbund (Service `brave-search-api`). Der
Schlüssel steht nie in argv, Umgebung, Log oder Antwort. Im Prozess liegt er in
einer Closure im Zustand, und die Inspect-Implementierung des Zustands lässt das
Feld weg. So taucht er auch in Crash-Reports nicht auf.

Fehlt der Schlüssel (oder ist er leer), bindet der Socket trotzdem. `ping`
funktioniert, und jede Suche liefert `credential-missing`.

## Operation `search`

Parameter (geschlossenes Schema aus `KomkiConnector.Manifest`): `query`
(String, max. 400 Zeichen) und `count` (1 bis 10, Default 5).

Anfrage: `GET /res/v1/web/search?q=<query>&count=<count>` mit
`Accept: application/json` und `X-Subscription-Token`.

Ergebnis (CONTRACT.md §5.2), keine weiteren Felder:

```json
{"results": [{"title": "...", "url": "https://...", "snippet": "..."}], "abrufdatum": "2026-10-23T19:42:28Z"}
```

- Quelle sind die Einträge in `web.results[]`. Fehlt `web`, ist die Liste leer.
- `snippet` kommt aus `description`. HTML-Tags (`<strong>` usw.) werden
  entfernt, Entities dekodiert, Leerraum zusammengefasst. Für `title` gilt
  dasselbe.
- Nur absolute `http`- und `https`-URLs mit Host. Treffer mit anderen URLs
  oder ohne Titel werden verworfen, bevor gezählt wird.
- Höchstens `count` Treffer. Titel werden auf 300, Snippets auf 1000 Zeichen gekürzt.
- `abrufdatum` ist der Abrufzeitpunkt in UTC (ISO 8601, Sekunden).

## Fehlercodes

| Situation | Code |
|---|---|
| Schlüssel fehlt | `credential-missing` |
| HTTP 401 (Brave lehnt den Schlüssel ab) | `credential-missing`: nur die nutzende Person kann abhelfen, mit einem neuen Schlüssel im Schlüsselbund |
| HTTP 403 (Schlüssel bekannt, Abo-Plan erlaubt die Anfrage nicht) | `upstream-error` |
| HTTP 429 | `upstream-error` mit Hinweis auf das Rate-Limit |
| anderer Status ungleich 200, kaputtes JSON, Antwort > 2 MiB, Verbindungsfehler | `upstream-error` |
| keine Antwort innerhalb von 10 s | `upstream-timeout` |

Der Timeout liegt mit 10 s unter dem Vermittler-Timeout von 15 s. Fehlertexte
enthalten keine httpc-Gründe, denn die könnten Teile der Anfrage enthalten.

## Technik

- HTTP über `:httpc`, TLS über `:ssl`, JSON über `:json`. Alles OTP, keine Hex-Laufzeit-Deps.
- TLS mit `verify_peer`, dem CA-Speicher des Systems (`:public_key.cacerts_get/0`),
  SNI und Hostname-Prüfung. Keine Redirects.
- Eigenes httpc-Profil je Connector-Instanz. Mit `--proxy` wird nur
  `https_proxy` gesetzt. Klartext-HTTP geht nie über den Proxy.
- Log nach stderr, ohne Payload: Operation, Ergebnis, Dauer.

## Entwicklung

```bash
cd apps/komki_connector_web
mix deps.get
mix test              # Mock-HTTP-Server (OTP) und echter Unix-Socket unter /tmp
mix credo --strict
mix dialyzer
mix escript.build     # erzeugt ./komki-connector-web (gitignored)
```

## Lizenzen

Keine Laufzeit-Abhängigkeiten außer OTP (Apache-2.0) und `komki_connector` (Repo-intern).
