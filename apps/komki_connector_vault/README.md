# komki_connector_vault

Vault-Connector für komki (Ticket #97, Fassung `komki-vault/1`). Er liest und durchsucht einen lokalen
Markdown-Vault und legt Testnotizen an. Er spricht ausschließlich mit dem Vermittler über das
Frame-Protokoll aus [`apps/komki_connector/CONTRACT.md`](../komki_connector/CONTRACT.md) (§3, §4, §5.2,
§6.3). Netz braucht er nicht, das `obsidian`-CLI auch nicht.

```
komki-connector-vault --socket <base>/run/connectors/vault.sock --vault-dir <pfad>
```

Credentials kommen über stdin (hier `{}`). Das Log geht auf stderr und enthält nur Operation, `call_id`,
Ergebnis und Dauer, keine Inhalte. Gestartet wird der Connector von `komki up` unter seinem eigenen
Seatbelt-Profil: Lesen unter `{vault_dir}`, Schreiben nur unter `{vault_dir}/komki-test`.

## Operationen

| Operation | Parameter | Ergebnis |
|---|---|---|
| `search` | `text` | `{"results": [{"note_id", "title", "labels"}]}`, höchstens 20, sortiert nach `note_id` |
| `read` | `note_id` (relativer Pfad, `.md`) | `{"note_id", "title", "content", "labels"}`; `content` ist der Text ohne Frontmatter |
| `write_test` | `title`, `body`, dazu `context.assigned_label` vom Vermittler | `{"note_id", "labels"}` |

Der Connector liefert öffentliche und vertrauliche Notizen gleichermaßen, jeweils mit ihren Labels. Ob
eine Antwort in den Arbeitsraum darf, entscheidet der Vermittler in Gate 2.

## Labels

Eine Notiz ist nur sichtbar, wenn ihr Frontmatter das Feld `komki_labels` trägt, und zwar als nicht
leere Liste, deren Einträge alle in den `import_labels` des Manifests stehen (`vault-oeffentlich@1`,
`vault-vertraulich@1`). Erlaubt sind die Inline-Form `[a, b]` und die Blockliste (`- a` je Zeile).
Alles andere gilt als ungültig: ein Skalar, ein doppelter Schlüssel, ein unbekanntes Label. Notizen ohne
gültige Labels tauchen in `search` nicht auf, und `read` liefert für sie `not-found`, als gäbe es sie
nicht.

Frontmatter ist nur ein Block, der in der ersten Zeile mit `---` beginnt. Ein `---`-Block weiter unten ist
Inhalt. Der Titel kommt aus dem Frontmatter-Feld `title`, sonst aus der ersten `# `-Überschrift, sonst
aus dem Dateinamen.

## Pfadhärtung

Anlass ist ein realer Fall: Ein Dienst außerhalb der Sandbox hat auf Wunsch eines Agenten über einen
Symlink `~/.ssh/id_rsa` gelesen. Deshalb gilt:

- `read` lehnt mit `forbidden-path` ab: absolute Pfade, `..`, leere Segmente, NUL, versteckte Segmente
  (alles, was mit `.` beginnt) und jede Komponente, die per `lstat` ein Symlink ist. Zusätzlich muss der
  kanonische Pfad unter dem kanonischen Vault-Root liegen. Gelesen werden nur reguläre Dateien bis
  1 MiB; alles andere ist `not-found`.
- `search` überspringt versteckte Verzeichnisse (`.obsidian`, `.trash`, …), Dateien über 1 MiB und
  Symlinks. Symlinks werden nie verfolgt, weder auf Dateien noch auf Verzeichnisse.
- Der Vault-Root selbst darf über einen Symlink angegeben werden (etwa `/tmp` → `/private/tmp`). Er wird
  beim Start einmal kanonisiert.
- Restrisiko: Zwischen `lstat` und `open` liegt ein Zeitfenster (TOCTOU), weil Erlang kein `O_NOFOLLOW`
  anbietet. Unter der Host-Annahme aus CONTRACT.md §1 (kein Gegner mit derselben uid) kann der Agent den
  Vault aber nicht verändern, sondern nur über diesen Connector schreiben, und zwar ausschließlich neue
  reguläre Dateien in `komki-test/`. Die zweite Grenze ist das Seatbelt-Profil.

## Schreiben (`write_test`)

- Labels kommen ausschließlich aus `context.assigned_label`, einer nicht leeren Teilmenge der
  `import_labels`. Andernfalls antwortet der Connector mit `forbidden-path`.
- Ziel ist `<vault>/komki-test/<YYYY-MM-DD>-<ascii-slug>.md` mit UTC-Datum. Der Ordner wird bei Bedarf
  angelegt. Ist `komki-test` ein Symlink oder eine Datei, antwortet der Connector mit `forbidden-path`.
- Überschrieben wird nie: Die Datei wird exklusiv angelegt (`O_EXCL`, folgt auch keinem Symlink am Ziel).
  Bei einer Kollision kommt das Suffix `-2`, `-3` usw. dazu.
- Das Frontmatter enthält `komki_labels`, `title` (als JSON-String, Steuerzeichen werden zu Leerzeichen)
  und `created`, danach folgt der Body unverändert. Ein `---`-Block im Body ändert die Labels nicht.
- Der GO-Flow für Schreiben ist noch offen (#98).

## Synthetischer Test-Vault

`priv/test-vault/` ist ein erfundener, deutschsprachiger Vault aus der Stadtratsarbeit (Buchloe, fiktiv).
Der echte Vault der nutzenden Person wird nie berührt. Symlinks sind nicht eingecheckt; die Tests legen sie
in einer tmp-Kopie an.

| Notiz | Labels | Zweck |
|---|---|---|
| `Projekte/Bürgerhaus Sanierung.md` | öffentlich (inline) | Umlaut und Leerzeichen im Dateinamen, Titel aus Frontmatter, Wikilink |
| `Projekte/Verkehr/Radverkehrskonzept.md` | öffentlich (Blockliste) | verschachtelter Ordner, Titel aus Überschrift |
| `Sitzungen/2026-09-17 Bauausschuss.md` | öffentlich (in Anführungszeichen) | Titel nur im Frontmatter |
| `Sitzungen/Notizen Haushalt.md` | öffentlich | Titel aus Dateiname |
| `Presse/Leserbrief Bahnhofstraße.md` | öffentlich | Prompt-Injection-Text |
| `Vertraulich/Grundstück Gewerbegebiet Nord.md` | vertraulich | Geheimnis-Marker `GEHEIM-MARKER-7Q4Z` für Abfluss-Tests |
| `Vertraulich/Personalangelegenheit Bauhof.md` | vertraulich (Blockliste) | zweite vertrauliche Notiz |
| `Fraktion/Haushaltsklausur 2027.md` | öffentlich + vertraulich | Notiz mit zwei Labels |
| `Eingang/Ohne Label.md` | keine | unsichtbar |
| `Eingang/Falsches Label.md` | öffentlich + `vault-geheim@1` | unsichtbar (ein ungültiges Label genügt) |
| `.obsidian/app.json`, `.obsidian/Versteckte Notiz.md` | öffentlich | versteckter Ordner, wird nie gelesen |

## Entwicklung

```bash
cd apps/komki_connector_vault
mix deps.get
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
mix escript.build   # erzeugt ./komki-connector-vault (gitignored)
```

Die Tests laufen über einen echten Unix-Socket (`/tmp/kmX…`) gegen eine tmp-Kopie des Test-Vaults.
