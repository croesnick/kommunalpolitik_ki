# komki_mediator

Vermittler (Ticket #102, MVP): der MCP-Layer zwischen pi (dem gesandboxten
Coding-Agent) und den Connector-Operationen. pi bekommt Tool-Zugriff
ausschliesslich durch diesen Vermittler: jeder Aufruf durchlaeuft Tor 1
(eine Policy-Entscheidung durch komki_policy VOR dem Vollzug), jede Antwort
durchlaeuft Tor 2 (Hash, Label und unabhaengige Beweispruefung, BEVOR sie
zur MCP-Antwort wird). Fuer jeden Aufruf entsteht ein PDR-Auditdatensatz
im Journal.

## Bau und Lauf

```bash
cd apps/komki_mediator
mix deps.get        # aktualisiert ggf. apps/workspace.lock
mix escript.build   # erzeugt ./komki-mediator

./komki-mediator --base ~/var/komki --port 49525
# default --base: KOMKI_HOME oder ~/.local/share/komki
# default --port: 49525
```

Nach dem Start erscheint eine einzeilige Startnotiz auf stdout; dann
blockiert der Escript.

## HTTP-Oberflaeche (nur loopback, 127.0.0.1)

| Route | Zweck |
|---|---|
| `GET /healthz` | Status + Fassung (`fassung_id`, `tools`, `registry_id`, `gamma_hash`) |
| `/mcp` | MCP StreamableHTTP (anubis_mcp) mit den Tools `ping` und `admit_document` |

## Raum unter `<base>/mediator/`

```
mediator/
├── registry.json   # Gamma: Verbindungsregeln, Bindungen, Befugnisse
├── room.json       # Raum: Identitaet, Arbeitsraum, Fakten, Objekte
├── documents/      # die drei Beispieldokumente (doc-oeffentlich u. a.)
└── journal/pdr.jsonl  # PDR-Auditjournal (eine kanonische JSON-Zeile je Aufruf)
```

Ein fehlender Raum wird beim Start provisioniert; ein vorhandener wird
NIEMALS ueberschrieben (Idempotenz).

## Tor 1 / Tor 2 / PDR

* **Tor 1**: gerenderter Aufruf → canonische Bytes → `intent_hash`; Objekt,
  Intent, Snapshot → `KomkiPolicy.Derive.decide`. Ein `deny`/`indeterminate`
  ist kein nackter Fehler, sondern ein Remedy-Plan (behebbare Schritte,
  Relaxationsbefugnisse inklusive).
* **Tor 2**: nur nach einem `permit` vollzieht der Connector; das Ergebnis
  wird gehasht und durch `KomkiPolicy.Verify.check` unabhaengig neu
  geprueft. Faellt die Pruefung, wird der Inhalt zurueckgehalten
  (`"admitted" => "redacted"`).
* **PDR**: jeder Ablauf haengt einen Auditdatensatz an das Journal
  (separater Writer-Prozess; stirbt er, stirbt die Vermittlung — die
  Auditkette dunkelt nie still ab) und bettet die `decision_id` in die
  Antwort ein.

## Komponenten

| Modul | Aufgabe |
|---|---|
| `KomkiMediator.Fassung` | festgedrehte Tool-Auflage (R.4.3) |
| `KomkiMediator.Gate` | Tor 1 + Tor 2 + PDR |
| `KomkiMediator.Gamma` | Registry-Snapshot + Stand-Hash |
| `KomkiMediator.Room` | Raum-Zustand, Objekt-/Snapshot-Bildung |
| `KomkiMediator.Remedy` | Abhilfeplaene aus Blockern/Evidenzen |
| `KomkiMediator.Journal` | getrennter PDR-Writer (R.4.4) |
| `KomkiMediator.Env` | geladene Umgebung fuer die Tools |
| `KomkiMediator.Templates` | Default-Raum (idempotent provisioniert) |
| `KomkiMediator.HTTP` | /healthz + /mcp (Plug.Router) |
| `KomkiMediator.Supervisor` | Kinderordnung, `:one_for_all` (fail-closed) |
| `KomkiMediator.CLI` | Escript-Einstieg |

## Lizenz

`anubis_mcp` ist LGPL-3.0 und wird als Runtime-Abhängigkeit eingebunden
(dynamische Nutzung, kein Linken in ein verteiltes Produkt). Lizenzangaben
des Projekts siehe Repo-Wurzel.
