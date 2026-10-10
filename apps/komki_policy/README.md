# komki_policy

Deterministischer Policy-Kern für Komki (Lieferung 1): Ableitung (`derive`)
und unabhängiger Beweisprüfer (`verify`) für den Regelzweig `admit`, dazu
eine reine Escript-CLI (`komki-policy`) ohne Runtime-Abhängigkeiten.

**Maßgeblich ist [`CONTRACT.md`](CONTRACT.md) im App-Verzeichnis** — der
verbindliche Datenvertrag (`komki-registry/1`, `komki-snapshot/1`,
`komki-intent/1`, `komki-proof/1`) samt Sprachumfang, Befundcodes und
Exit-Code-Semantik.

## Pflichtsatz (CONTRACT § 2.4)

> **Eine Ableitung ist keine Ausführungsrechte — der Kern führt nichts aus.**
> `permit` dokumentiert eine bewiesene Rechtslage in einem Datensatz; es
> öffnet keine Tür, es schreibt nichts, es startet nichts.

## CLI

```bash
cd apps/komki_policy
mix deps.get        # nur Dev-Werkzeuge (credo/dialyxir); workspace.lock unberührt
mix escript.build   # erzeugt ./komki-policy

./komki-policy validate --registry priv/fixtures/registry.json
./komki-policy decide   --registry priv/fixtures/registry.json \
                        --snapshot priv/fixtures/case_permit/snapshot.json \
                        --intent   priv/fixtures/case_permit/intent.json
./komki-policy verify   --registry priv/fixtures/registry.json \
                        --snapshot priv/fixtures/case_permit/snapshot.json \
                        --intent   priv/fixtures/case_permit/intent.json \
                        --proof    priv/fixtures/case_permit/proof_valid.json
```

Alle Ausgaben (Ergebnisse wie Fehlerdetails) sind kanonisch
(`KomkiPolicy.JSON.canonical/1`): byte-stabil, sortierte Schlüssel, genau ein
finales Newline — zwei identische Aufrufe erzeugen byte-identisches stdout.

### Exit-Codes (CONTRACT § 7)

| Code | Bedeutung |
|---|---|
| `0` | Erfolg. Auch `deny`/`indeterminate` (decide) und `valid` (verify) sind legitime Ergebnisse — der Exit-Code sagt nur „Befehl ausgeführt", nicht „erlaubt". |
| `1` | `verify` hat den Beweis verworfen (`result: invalid`). |
| `2` | Eingabefehler: Parse-/Schema-/Kohärenzverstoß, fehlende Datei, fehlende/unerwartete/u. unbekannte Argumente, unbekannter Befehl. Immer mit strukturiertem Fehlerdatensatz auf stdout (`result: error`, `code`, `path`, `detail`). |
| `3` | `unsupported`: nicht implementierter Regelzweig (inkl. `plan`) — **niemals** ein `deny`. |
| `4` | Unerwarteter interner Fehler. Der Crash-Handler erzeugt **niemals** eine Decision und fällt **nie** auf `permit` zurück (CONTRACT § 1). |

Deterministische Wahl für Grenzfälle: `plan` → unsupported (Exit 3, der
Regelzweig ist bewusst nicht geliefert); jeder sonstige unbekannte Befehl →
Usage-Fehler (Exit 2, `code: "unknown_command"`); fehlende Argumente → Exit 2,
`code: "usage"`; fehlende Datei → Exit 2, `code: "read_error"`.

## Architektur

| Modul | Aufgabe |
|---|---|
| `KomkiPolicy.JSON` | Strenger JSON-Parser (keine doppelten Schlüssel, kein `NaN`) + kanonischer Encoder (§ 6) |
| `KomkiPolicy.Registry` | Registry-Compiler und Schemavalidierer, typgeprüfte B.4-Ausdrücke |
| `KomkiPolicy.Context` | Snapshot-Validierung, Intent-Kohärenz |
| `KomkiPolicy.Evaluator` | Dreiwertige Ausdrucksauswertung (kein Default für fehlende Fakten) |
| `KomkiPolicy.Derive` | Ableitung `admit` in fester Prämissenordnung (§ 4), Beweisbaum |
| `KomkiPolicy.Verify` | Unabhängiger Prüfer (§ 5): ruft `derive` nie auf, glaubt kein `permit` |
| `KomkiPolicy.CLI` | Escript-Eingang; Datei-I/O nur hier im Modul, Rest pur |

Der Kern ist rein: keine Uhr, kein Zufall, kein Netz, kein Dateizugriff
(exklusive CLI), keine Runtime-Deps (§ 7: `null Runtime-Deps`).

## Demo

```bash
bash apps/komki_policy/priv/demo.sh
```

baut den Escript und führt die Abnahme-Kernpfade aus (decide über
permit/deny/indeterminate/unsupported, verify über valid/verworfen) mit
expliziten Exit-Code-Checks.

## Tests & Werkzeuge

```bash
mix workspace.run -t test --affected   # aus dem Repo-Root
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors
mix dialyzer
```

## Umgebung & Grenzen

- **Synthetische Fixtures only** (`priv/fixtures/`): keine produktiven Daten,
  alle Bezeichner sind synthetisch; keine reale Aufnahme, kein Netz, kein LLM.
- Nur-lesen: die CLI schreibt nichts, sie produziert nur
  Datensätze. Freigaben/Ausführung sind explizite Nichtziele (CONTRACT § 9).
- Lizenz: stdlib-only, keine Runtime-Deps; Build-Werkzeuge (credo/dialyxir)
  nur `:dev`. Lizenzangaben des Projekts siehe Repo-Wurzel.
