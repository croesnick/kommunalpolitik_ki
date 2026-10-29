# komki_connector_ris

RIS-Connector für den komki-Vermittler (Ticket #94). Er beantwortet die Operationen `search` und
`show` der Fassung `komki-ris/1` über **öffentliche** Tagesordnungspunkte (TOPs) des
Ratsinformationssystems der VG Buchloe. Vertrag, Frame-Protokoll und Ergebnisform:
[`apps/komki_connector/CONTRACT.md`](../komki_connector/CONTRACT.md) (§3, §4, §5.2).

Das Label (`ris-oeffentlich@1`) vergibt der Vermittler, nicht der Connector.

## Start

```bash
cd apps/komki_connector_ris && mix escript.build
echo '{}' | ./komki-connector-ris --socket /tmp/kmris.sock [--base-url <url>] [--proxy 127.0.0.1:<port>]
```

- `--socket`: Unix-Socket, den der Connector bindet (Rechte `0600`). macOS erlaubt höchstens 103 Byte Pfadlänge.
- `--base-url`: Basis der RIS-API, Default `https://risapi1.komuna.net/web/`.
- `--proxy`: HTTPS läuft dann per CONNECT über diesen Proxy (`komki-egress`). Klartext-HTTP (nur der
  Mock auf Loopback) geht direkt.
- stdin: genau eine Credentials-Zeile. RIS braucht keine, also `{}`. Der Connector liest stdin bis
  EOF, bevor er den Socket bindet.

Im Betrieb startet `komki up` den Connector unter seinem Seatbelt-Profil (CONTRACT §4).

## Was der Connector abfragt

Nur die Gast-Endpunkte der API, die ohne Anmeldung antworten (geprüft am 2026-10-23):

| Endpunkt | Zweck |
|---|---|
| `guestmeetings?client=32&from=…&until=…` | Sitzungen eines Zeitfensters |
| `guestmeetings/{id}` | Tagesordnung mit `parts[].protectedpart` und `agendaitems[].restricted` |
| `guestagendaitems/{meetingId-agendaItemId}` | TOP-Details mit Textblöcken (Base64-HTML) |

`ratsinfo` nutzt die angemeldeten Gegenstücke (`meetings/{id}`, `agendaitems/{id}`, `fulltextsearch`).
Ohne Token antworten diese mit 401.

**Öffentlich** ist ein TOP nur, wenn `restricted` den Wert `false` hat und sein Sitzungsteil
`protectedpart: false` trägt. Fehlt eines der Felder oder steht dort etwas anderes, gilt der TOP als
nicht-öffentlich (fail-closed). Nicht-öffentliche TOPs fallen weg, bevor verglichen, begrenzt oder
gezählt wird. `show` auf einen solchen TOP liefert denselben Fehler wie auf einen fehlenden:
`not-found` mit „TOP nicht gefunden“.

## Suchstrategie

Die Volltextsuche der API verlangt eine Anmeldung. Der Connector sucht deshalb selbst:

1. Sitzungen der letzten 180 Tage und der nächsten 60 Tage laden, neueste zuerst.
2. Je Sitzung die Tagesordnung laden und die Titel der öffentlichen TOPs vergleichen.
3. Mit dem Restbudget die Textblöcke der übrigen öffentlichen TOPs laden und vergleichen.
4. Schluss bei `limit` Treffern, nach 40 Upstream-Anfragen oder nach 12 s.

Verglichen wird als Teilstring, ohne Rücksicht auf Groß- und Kleinschreibung. Eine einzelne Anfrage
darf höchstens 5 s dauern, sodass ein Aufruf unter den 15 s des Vermittlers bleibt. Ein Timeout ergibt
`upstream-timeout`, jeder andere HTTP- oder Verbindungsfehler `upstream-error`. Fehlermeldungen
enthalten keinen Upstream-Text, und das Log enthält weder Suchtexte noch Ergebnisse.

`url` im Ergebnis ist `<base-url>guestagendaitems/<top_id>`. Der Connector baut sie aus der
Basis-URL und der geprüften ID, nie aus Upstream-Text. `abrufdatum` ist ISO-8601 in UTC.

## Mock

`priv/mock_ris.exs` bildet die drei Gast-Endpunkte nach. Er braucht nur OTP und läuft auch außerhalb
der Tests:

```bash
elixir apps/komki_connector_ris/priv/mock_ris.exs --port 4010 [--mode ok|error500|slow]
echo '{}' | apps/komki_connector_ris/komki-connector-ris --socket /tmp/kmris.sock --base-url http://127.0.0.1:4010/
```

Seine Daten enthalten öffentliche und nicht-öffentliche TOPs. „Bahnhofstraße“ steht in zwei
öffentlichen TOPs und in zwei nicht-öffentlichen, einem mit `restricted: true` und einem im
geschützten Sitzungsteil. Damit lässt sich prüfen, dass die Trefferzahl nichts verrät. TOP `1001-3`
trägt eine Prompt-Injection im öffentlichen Text für Red-Team-Tests. Anders als die echte Gast-API
liefert der Mock auch nicht-öffentliche TOPs samt Text aus, damit der Filter des Connectors geprüft
wird. Modus `error500` antwortet immer mit HTTP 500, `slow` antwortet erst nach 3 s, `replay` spielt
Aufzeichnungen des Recorders zurück (siehe unten).

## Aufzeichnung und Replay echter Antwortformate

Die Daten des Mocks sind handgespiegelt. Um die Antwortformate gegen das echte RIS zu verifizieren
und komki ohne echtes RIS testen zu können, gibt es einen Aufzeichnungs-Proxy
(`priv/ris_recorder.exs`, Ticket #231). Er ist rein deterministischer Code ohne LLM.

```bash
elixir apps/komki_connector_ris/priv/ris_recorder.exs --port 4020 \
  [--upstream https://risapi1.komuna.net/web/] [--out <verzeichnis>]
```

Der Proxy reicht Anfragen 1:1 an das echte RIS weiter und schreibt jeden Austausch als Kassette
(JSON, Body base64). Kassette heißt hier: eine aufgezeichnete Anfrage samt Antwort, wie bei VCR
oder ExVCR.

**Die Kassetten enthalten echte, auch nicht-öffentliche Inhalte.** Deshalb gilt:

- Sie liegen nie im Repo-Baum. Standard ist `~/.local/share/kommunalpolitik_ki/ris-cassettes/<zeitstempel>/`;
  ein `--out` innerhalb eines Git-Repos (auch eines Worktrees) weist der Recorder ab. So kann kein
  Werkzeug, das im Repo arbeitet, die Aufzeichnungen nebenbei lesen.
- Verzeichnis und Dateien sind nur für den Eigentümer lesbar (`0700`/`0600`).
- Geschwärzt wird beim Schreiben (`"<redacted>"`): die Kopfzeilen `authorization`, `cookie` und
  `set-cookie`; beim Login (`auth`) jeder Wert in Anfrage und Antwort, auch in Feldern, die
  niemand vorhergesehen hat (die Struktur bleibt); sonst die Felder `token`/`access_token`/`jwt`.
  Client und Upstream erhalten alles ungeschwärzt, nur die Datei ist geschwärzt.

Gegen den Recorder aufzeichnen:

- komki: `"ris_mock_port": 4020` in komkis `config.json`. Loopback gilt als Mock, der
  Egress-Proxy bleibt aus.
- `ratsinfo`: `RIS_BASE_URL=http://127.0.0.1:4020/` (ohne `/web/`; der Proxy ergänzt den Präfix
  upstream-seitig). `ratsinfo` nimmt hier nur Loopback-Adressen an, weil an diese Adresse auch die
  Zugangsdaten gehen.

Zurückspielen, sodass komki gegen die Aufzeichnung statt gegen das echte RIS läuft:

```bash
elixir apps/komki_connector_ris/priv/mock_ris.exs --port 4010 --mode replay --cassette <verzeichnis>
```

Replay sucht den exakten Treffer für `(Methode, Pfad, Query)`. Nur bei `guestmeetings`, wo die Query
lediglich das Zeitfenster wählt, greift es bei abweichender Query auf die erste Aufnahme desselben
Pfads zurück. Überall sonst, etwa bei `fulltextsearch` mit anderem Suchbegriff, gibt es 404 statt
der Antwort auf eine andere Frage. Nicht Aufgezeichnetes antwortet ebenfalls mit 404.

### Was der Recorder erfasst

Er ist ein transparenter Proxy: Kassette wird, was die Clients wirklich abfragen. Das sind Methode,
Pfad, Query, Kopfzeilen und Body der Anfrage sowie Status, Kopfzeilen und Body der Antwort.
Binärkörper (PDF-Downloads) stehen bytetreu base64 in der Kassette. gzip fordert er nicht an, damit
die Kassetten deterministisch bleiben. Grenzen:

- Umleitungen reicht er unverändert an den Client weiter. Zeigt `Location` auf eine absolute
  Upstream-URL, folgt der Client ihr direkt zum echten RIS, und dieser Hop fehlt in der Aufzeichnung.
- Chunked Request-Bodies versteht er nicht (kein Client hier sendet sie).

Damit sind alle Endpunkte erfasst, die komki und ratsinfo nutzen:

| Client | Endpunkt | Anmerkung |
|---|---|---|
| beide | `guestmeetings`, `guestmeetings/{id}`, `guestagendaitems/{id}` | Gast-API, ohne Anmeldung |
| ratsinfo | `POST auth` | Login; in der Kassette ist jeder Wert geschwärzt |
| ratsinfo | `meetings/{id}`, `agendaitems/{id}`, `committees` | authentifiziert |
| ratsinfo | `fulltextsearch` | Suchterme stehen in der Query und werden mit aufgezeichnet |
| ratsinfo | `agendaitems/documents/{docId}` | Binär-Download, bytetreu |

Nicht erfasst wird, was kein Client abfragt, denn der Recorder ist passiv. Für vollständige
Abdeckung eine Aufzeichnungs-Session mit allen Flows fahren und die Suchterme variieren: komki
`search`/`show` (mehrere Terme, auch nicht-öffentliche Treffer), ratsinfo-Login (Zugangsdaten wie
üblich aus `RIS_EMAIL`/`RIS_PASSWORD`), Sitzungsliste, TOP-Details, Volltextsuche mit mehreren
Termen, Anlagen-Downloads, Gremienliste.

Committbare Testdaten entstehen nie aus den Kassetten selbst, sondern aus synthetischen Inhalten im
echten Format. Format-Extraktion und Generator dafür sind Ticket #232.

## Grenzen

- **Texte für Gäste meist leer.** Die echte Gast-API liefert bei den geprüften TOPs
  `textsanddocsvisible: false` und keine Textblöcke. Praktisch findet die Suche dann nur Titel, und
  `show` liefert einen leeren `text`.
- **Unvollständige Treffer möglich.** Budget und Frist begrenzen die Suche. Ältere Sitzungen außerhalb
  des Zeitfensters werden nicht durchsucht.
- **Kein Stemming, kein ß/ss-Ausgleich.** „Bahnhofstrasse“ findet „Bahnhofstraße“ nicht.
- **`url` zeigt auf die API-Ressource**, nicht auf eine Seite der RIS-Weboberfläche. Deren
  Link-Schema ist nicht dokumentiert.
- Der Mock ignoriert das Zeitfenster (`from`/`until`) und liefert immer alle Sitzungen.

## Entwicklung

```bash
cd apps/komki_connector_ris
mix deps.get
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
mix escript.build
```

Lizenz der Abhängigkeiten: nur OTP (`:httpc`, `:ssl`, `:json`) und die Repo-Bibliothek
`komki_connector`.
