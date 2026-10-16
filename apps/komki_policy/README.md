# komki_policy

Deterministischer Policy-Kern für Komki (Lieferung 2): Ableitung (`derive`)
für die Regelzweige `admit` und `emit`, Remedy-Katalog (§ 2.8),
Aktionsfreigabe-Mechanik (`decide_with_release`, `advance`), unabhängiger
Ableitungsprüfer (`verify`) sowie eine reine Escript-CLI (`komki-policy`) ohne
Runtime-Abhängigkeiten.

**Maßgeblich ist [`CONTRACT.md`](CONTRACT.md) im App-Verzeichnis** — der
verbindliche Datenvertrag (Version v2: `komki-registry/2`,
`komki-snapshot/1`, `komki-intent/1`, `komki-release/1`, `komki-stand/1`,
`komki-proof/1`) samt Sprachumfang, Befundcodes, Remedy-Ordnung und
Exit-Code-Semantik.

## Pflichtsatz (CONTRACT § 2.4)

> **Eine Ableitung ist keine Ausführungsrechte — der Kern führt nichts aus.**
> `permit` dokumentiert eine bewiesene Rechtslage in einem Datensatz; es
> öffnet keine Tür, es schreibt nichts, es startet nichts.

Zur Lieferung 2 gehört der Paarsatz (CONTRACT § 2.8):

> **Der Remedy-Katalog erzeugt keine Autorität.** `remedies` listet bei
> `deny`/`indeterminate` einen begrenzten Katalog legaler Fortsetzungen aus
> genau vier Übergangstypen (`fakt_nachreichen`, `registrierte_transformation`,
> `neuer_raum`, `aktionsfreigabe`); er wird von keiner Eingabe akzeptiert,
> keine Fortsetzung wird ausgeführt — normative Ordnung: ein GO steht nie an
> erster Stelle.

## CLI

```bash
cd apps/komki_policy
mix deps.get        # nur Dev-Werkzeuge (credo/dialyxir); workspace.lock unberührt
mix escript.build   # erzeugt ./komki-policy

./komki-policy validate --registry priv/fixtures/registry.json
./komki-policy decide   --registry priv/fixtures/registry.json \
                        --snapshot priv/fixtures/case_permit/snapshot.json \
                        --intent   priv/fixtures/case_permit/intent.json
./komki-policy decide   --registry priv/fixtures/registry.json \
                        --snapshot priv/fixtures/case_release_permit/snapshot.json \
                        --intent   priv/fixtures/case_release_permit/intent.json \
                        --release  priv/fixtures/case_release_permit/release.json \
                        --stand    priv/fixtures/case_release_permit/stand.json
./komki-policy verify   --registry priv/fixtures/registry.json \
                        --snapshot priv/fixtures/case_emit_permit/snapshot.json \
                        --intent   priv/fixtures/case_emit_permit/intent.json \
                        --proof    priv/fixtures/proofs/proof_emit_valid.json
./komki-policy advance  --stand  priv/fixtures/case_release_permit/stand.json \
                        --proposal <release-Objekt einer Freigabe-Permit-Decision>
```

`--release` und `--stand` sind nur paarweise gültig (einzeln → usage,
Exit 2). `advance` nimmt das `release`-Objekt einer Freigabe-Permit-Decision
(§ 4.6) als eigenständige Datei; Erfolg druckt den neuen Stand kanonisch
(Exit 0), Ablehnung druckt `{"result": "refused", "code": …}` (Exit 1) —
zwei konkurrierende Ausführungen desselben GOs können nicht beide
committen (Compare-and-Swap über die Versionsnummer).

Alle Ausgaben (Ergebnisse wie Fehlerdetails) sind kanonisch
(`KomkiPolicy.JSON.canonical/1`): byte-stabil, sortierte Schlüssel, genau
ein finales Newline — zwei identische Aufrufe erzeugen byte-identisches
stdout.

### Exit-Codes (CONTRACT § 7)

| Code | Bedeutung |
|---|---|
| `0` | Erfolg. Auch `deny`/`indeterminate` (decide), `valid` (verify) und der erfolgreiche `advance` sind legitime Ergebnisse — der Exit-Code sagt nur „Befehl ausgeführt“, nicht „erlaubt“. |
| `1` | `verify` hat den Beweis verworfen (`result: invalid`) **oder** `advance` hat den Standübergang abgelehnt (`refused`). |
| `2` | Eingabefehler: Parse-/Schema-/Kohärenzverstoß, fehlender `output_content_digest` bei `emit` (`emit_digest_missing`), emit-Snapshot mit `quarantine`-Objekt, fehlende Datei, fehlende/unerwartete/unbekannte Argumente, unbekannter Befehl. Immer mit strukturiertem Fehlerdatensatz auf stdout. |
| `3` | `unsupported`: nicht implementierter Regelzweig (inkl. `plan`), Freigabe-`kind: offenlegungsfreigabe` oder Nicht-`emit`-Operation — **niemals** ein `deny`. |
| `4` | Unerwarteter interner Fehler. Der Crash-Handler erzeugt **niemals** eine Decision und fällt **nie** auf `permit` zurück (CONTRACT § 1). |

## Semantik (Lieferung 2)

### `emit` ordnet das Raumlabel zu (RFC R.5.5)

Der Vermittler ordnet jeder Ausgabe das Raumlabel zu, auch undurchsichtigen
Bytes: **λ(y) := B_W** (`assigned_label` = `workspace.bindings`). Keine
Eingabe kann `assigned_label` beeinflussen — der Intent trägt keine Labels,
der Kern liest `object.labels` für `emit` nicht. Der Call ist ausschließlich
über den technischen Fakt `output_content_digest` identifizierbar (fehlend →
Eingabefehler `emit_digest_missing`); der Kern liest die Bytes nie.

### Der Remedy-Katalog berät ohne Autorität (§ 2.8)

`deny`/`indeterminate`-Decisions tragen `remedies` in derselben Ordnung wie
die Befunde; `permit` trägt `"remedies": null`. Übergangstypen (feste
Payload-Formen): `fakt_nachreichen` (facts), `registrierte_transformation`
(id, output_labels), `neuer_raum` (required_bindings, required_recipients),
`aktionsfreigabe` (scope `call` mit call_hash / scope `object` für die
Erstklassifikation). Ordnung normativ: fakt < transformation < neuer Raum <
aktionsfreigabe. Bei `admit` erscheint kein call-GO (bewusste Lücke, § 9);
bei `emit` zusätzlich das call-GO für die fünf weichen Blocker. Für
`indeterminate` nie ein GO — ein GO kann keine Belege herstellen.

### Aktionsfreigabe trennt Urteil und Vollzug (§ 4.6)

Der Freigabe-Zweig ist ein eigener Regelzweig, nie ein stiller Fallback.
`workspace_contract_valid` bleibt Prämisse (ein GO belebt keinen ungültigen
Vertrag); die Release-Prüfungen laufen in fester Ordnung (call hash → Fenster
→ Nonce → scope → authority). Permit trägt `proof: null` und das
`release`-Objekt als **deklarative** Wirkung; der Verbrauch committet über
`advance` (commit-before-effect, B.8, PACE-Nonce). Eine Aktionsfreigabe ist
keine Herabstufungsbefugnis: `assigned_label` bleibt B_W.

## Architektur

| Modul | Aufgabe |
|---|---|
| `KomkiPolicy.JSON` | Strenger JSON-Parser (keine doppelten Schlüssel, kein `NaN`) + kanonischer Encoder (§ 6) |
| `KomkiPolicy.Registry` | Registry-Compiler (`komki-registry/2`): typgeprüfte B.4-Ausdrücke + registrierte Transformationen (§ 2.1) |
| `KomkiPolicy.Context` | Snapshot-Validierung, Intent-Kohärenz |
| `KomkiPolicy.Evaluator` | Dreiwertige Ausdrucksauswertung (kein Default für fehlende Fakten) |
| `KomkiPolicy.Calculus` | Reine Mengenfunktionen (R_Γ, ρ_Γ, Label-Subsets) |
| `KomkiPolicy.Derive` | Ableitung `admit`/`emit` in fester Prämissenordnung (§ 4/§ 4.5), Freigabe-Zweig `decide_with_release/5` (§ 4.6), Beweisbäume |
| `KomkiPolicy.Remedies` | Remedy-Katalog (§ 2.8): reine Ausgabe, beratend ohne Autorität |
| `KomkiPolicy.Release` | Aktionsfreigabe-Validierung (`komki-release/1`) + verbindliche call-hash-Formel (§ 2.6) |
| `KomkiPolicy.Stand` | Offenlegungsstand (`komki-stand/1`) + atomarer Standübergang `advance/2` (§ 2.7) |
| `KomkiPolicy.Verify` | Unabhängiger Prüfer (§ 5): ruft `derive` nie auf, glaubt kein `permit`, regelabhängige Sollmengen admit/emit |
| `KomkiPolicy.CLI` | Escript-Eingang; Datei-I/O nur hier im Modul, Rest pur |

Der Kern ist rein: keine Uhr, kein Zufall, kein Netz, kein Dateizugriff
(exklusive CLI), keine Runtime-Deps (§ 7: `null Runtime-Deps`);
`:crypto` (Erlang-Stdlib) liefert sha256 für den call hash. Logische Zeit
(Fenster, `as_of`) ist immer Eingabe.

## Demo

```bash
bash apps/komki_policy/priv/demo.sh
```

## Tests & Werkzeuge

```bash
mix workspace.run -t test --affected   # aus dem Repo-Root
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors
mix dialyzer
```

Abnahmemetriken als Tests (`test/komki_policy/metrics_test.exs`, § 8.3):
HITL load (Quarantäne = genau ein Objekt-Level-GO; `fakt_nachreichen`-Pfade
= 0 GOs) und TCR@k (deterministische Skript-Spur über den Fixture-Korpus).

## Umgebung & Grenzen

- **Synthetische Fixtures only** (`priv/fixtures/`): keine produktiven
  Daten, alle Bezeichner sind synthetisch; keine reale Aufnahme, kein Netz,
  kein LLM.
- Nur-lesen: die CLI schreibt nichts, sie produziert nur Datensätze. Der
  Kern verbraucht keine Freigabe — `advance` ist ein reiner Übergang, das
  Führen des aktuellen Standes ist Vollzug außerhalb des Kerns (CONTRACT § 9).
- Lizenz: stdlib-only, keine Runtime-Deps; Build-Werkzeuge (credo/dialyxir)
  nur `:dev`. Lizenzangaben des Projekts siehe Repo-Root.
