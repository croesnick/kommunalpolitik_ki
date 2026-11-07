# komki_mock

Laufzeit für zustandsbehaftete HTTP-Mocks externer Systeme (RIS, Brave, …),
damit `mix test` und Agents, die die echten CLIs als Subprozess fahren, komki
ohne echtes Netz durchspielen können. Ein Mock läuft als eigener Prozess auf
zwei Loopback-Ports. Er hält seinen Zustand in echten Dateien und lässt sich
seeden, zurücksetzen und in Fehlerszenarien schalten.

Das Paket ist nicht Teil des Homebrew-Releases: Keine App des Releases hängt
davon ab.

## Starten

```bash
cd apps/komki_mock
mix komki_mock.serve --adapter KomkiMock.Adapters.Notes --dir /tmp/mock-notes
# komki_mock: Daten auf http://127.0.0.1:51234/, Steuerung auf http://127.0.0.1:51235/ (Zustand: /tmp/mock-notes)
```

Aus Elixir: `KomkiMock.Server.start_link(adapter: …, dir: …)`. Optionen:
`--seed` (Standard `default`), `--data-port`, `--control-port` (Standard 0,
also ein freier Port). Ein vorhandenes `state.json` hat Vorrang vor `--seed`.

## Zustandsverzeichnis

| Datei | Inhalt |
|---|---|
| `state.json` | `seed`, `scenario`, `delay_ms`, `data`; überlebt einen Neustart, wird atomar geschrieben |
| `ports.json` | `data` und `control` dieses Laufs |
| `requests.jsonl` | eine Zeile je Anfrage an den Daten-Port: Zeit, Methode, Pfad, Query, Status, Szenario |

## Steuer-Port

```bash
curl 127.0.0.1:51235/state
curl -X POST 127.0.0.1:51235/seed     -d '{"name": "empty"}'
curl -X POST 127.0.0.1:51235/reset
curl -X POST 127.0.0.1:51235/scenario -d '{"name": "slow", "delay_ms": 500}'
curl 127.0.0.1:51235/log
```

`seed` und `reset` setzen das Szenario auf `ok` und leeren das Request-Log.
`reset` lädt den aktuellen Seed neu, `state.json` ist danach byteweise
gleich wie nach dem Seeden.

Der Steuer-Port gehört nicht in eine Egress-Allowlist: Nur Tests und Harness
sprechen ihn an, nie das System unter Test.

## Szenarien

| Szenario | Daten-Port |
|---|---|
| `ok` | Der Adapter antwortet. |
| `error` | Jede Anfrage bekommt HTTP 500, die Daten bleiben unverändert. |
| `slow` | Jede Antwort wartet `delay_ms` (Standard 3000). |
| `refused` | Der Port nimmt keine Verbindungen an (ECONNREFUSED). Mit einem anderen Szenario öffnet er wieder auf derselben Nummer. |

HTTP-Formen wie 403 oder 429 (Rate-Limit) sind Sache der Adapter.

## Adapter schreiben

Ein Adapter implementiert `KomkiMock.Adapter`: `seed/1` liefert die Daten
eines benannten Seeds, `handle/2` beantwortet eine Anfrage und gibt die
(eventuell geänderten) Daten zurück. Die Daten sind ein JSON-Wert mit
String-Schlüsseln. Alle Anfragen laufen nacheinander durch einen Prozess,
parallele Anfragen sehen also nie einen halben Zustand. Vorlage:
`KomkiMock.Adapters.Notes`.
