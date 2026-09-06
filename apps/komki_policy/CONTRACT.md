# CONTRACT.md — Komki.Policy Datenvertrag v1 (Lieferung 1: `admit`)

**Status:** verbindlicher gemeinsamer Vertrag für Lieferung 1. Änderungen nur durch den Integrator.
**Normative Basis:** RFC 0001 Revision 4, SHA-256 `b4364bebfd77284aae7ee6a28e39bef8eb2736fc1f2ea301efb2e908c9ec5dcf`.
**Maßgebliche RFC-Abschnitte:** 2–6 (Modell), 5.4 (Aufnahme), 9.1, B.3–B.6, D.1, D.4 (`aufnahme-raumbindung`, `quarantaene`, `empfaengergrenze`, `leeres-label`, `ableitungspruefer`), Anhang A.2/A.7.
**Geltungsbereich:** ausschließlich synthetische Fixtures, lokale Entwicklung, keine produktiven Daten, kein Netz, keine Uhr, kein LLM, keine reale Aufnahme. Eine Ableitung ist keine Ausführungsrechte (RFC 9.1, B.8).

---

## 1. Betriebsgrenzen von Lieferung 1

Implementiert ist ausschließlich der Regelzweig `admit` mit Ableitung (`derive`) und unabhängigem Beweisprüfer (`verify`) sowie CLI.

- Nicht implementierte Regelzweige (`start`, `emit`, `transfer`, `store`, Freigaben, Lockerung, Planer `infer_plan`): `unsupported` — **keine** `Decision`, eigener Exit-Pfad (Exit 3). Sie werden niemals als `deny` ausgegeben (deny wäre die falsche Behauptung, der Zweig sei geprüft worden und verbiete).
- Der Kern ist deterministisch und seiteneffektfrei: keine Uhr, kein Zufall, kein Netz, kein Dateizugriff, kein LLM-Aufruf, kein globales Zustandslesen. Alle Eingaben sind explizite Argumente.
- Struktur- und Validierungsfehler sind **getrennte Eingabefehler** (Exit 2), niemals eine `Decision` mit einem der drei Werte (RFC B.6).
- Das Decision-Alphabet ist strikt: `permit` | `deny` | `indeterminate`. Es gibt keinen vierten Wert und keinen Fallback auf `permit` — auch nicht bei Ressourcenproblemen (RFC B.5).

## 2. Datensätze (geschlossene, versionierte Schemas)

Alle JSON-Datensätze tragen ein Pflichtfeld `schema` mit exakt den unten genannten Werten. Unbekannte Felder, doppelte Schlüssel (schon beim Parsen), falsche Typen, nichtleere unbekannte Feldmengen und widersprüchliche Referenzen werden abgewiesen (Eingabefehler). Mengen werden als sortierte, duplikatfreie Arrays dargestellt.

### 2.1 `Registry` — `komki-registry/1`

```json
{
  "schema": "komki-registry/1",
  "registry_id": "<kebab-id>",
  "observers": ["<observer-id>", "..."],
  "fact_fields": { "<feld-name>": "string|boolean|integer|string_set" },
  "environments": {
    "<umgebung-id>@<int>": { "observers": ["<observer-id>", "..."] }
  },
  "bindings": {
    "<bindung-id>@<int>": {
      "readers": ["<observer-id>", "..."],
      "operations": { "admit": "<Expression>" },
      "relaxation_authorities": []
    }
  }
}
```

Regeln:

- `registry_id`: kebab-case ASCII (`^[a-z0-9]+(?:-[a-z0-9]+)*$`).
- `observers`: nicht leer, eindeutig, kebab-case. Dies ist 𝒪, der modellierte Beobachterraum.
- `fact_fields`: deklariert die zulässigen prädikatfähigen Felder mit Typ. Ausdrücke in `operations` dürfen nur hier deklarierte Felder referenzieren (Typ-kompatibel, siehe §3).
- `environments`: mindestens eine Umgebung; `observers` je Umgebung nicht leer, eindeutig, ⊆ `observers`. Eine Umgebung mit leerer Beobachterliste ist ungültig (verarbeitende Umgebungen haben mindestens die betreibende Stelle).
- `bindings`: mindestens eine Bindung. Bindungs- und Umgebungskennungen folgen `<kebab>@<nicht-negativer Integer>`; verschiedene Versionen derselben Bindung sind verschiedene Kennungen (kein „latest"-Rollover, RFC A.1).
- `readers`: nicht leer, eindeutig, ⊆ `observers`. Dies ist R_b, der zulässige Empfängerkreis der Bindung.
- `operations`: Map Regelname → Expression. Zulässige Regelnamen (geschlossene Menge): `start`, `admit`, `emit`, `transfer`, `store`. Nur die Engine-seitig implementierten Zweige sind entscheidbar (L1: `admit`); die übrigen dürfen deklariert, aber nicht entschieden werden.
- `relaxation_authorities`: Array (L1: immer `[]`; nicht bewertet).
- Eine Bindung ohne `admit`-Eintrag in `operations` erlaubt `admit` ausdrücklich **nicht** (RFC B.4: fehlende Operationsregel ≠ leere Konjunktion). Eine bewusst uneingeschränkte Operation wird ausdrücklich mit `true` eingetragen.

### 2.2 `ContextSnapshot` — `komki-snapshot/1`

```json
{
  "schema": "komki-snapshot/1",
  "snapshot_id": "<kebab-id>",
  "registry_ref": "<registry_id>",
  "identity": "<observer-id>",
  "workspace": {
    "workspace_id": "<kebab-id>",
    "bindings": ["<bindung-id>@<int>", "..."],
    "valid": true,
    "environment": "<umgebung-id>@<int>"
  },
  "object": {
    "object_id": "<kebab-id>",
    "version": "<kebab-id>",
    "classification": "classified",
    "labels": ["<bindung-id>@<int>", "..."]
  },
  "facts": {
    "<feld-name>": {
      "value": "<typgerechter Wert>",
      "source": "<quelle>",
      "source_kind": "administered|technical|assumption|test"
    }
  }
}
```

Regeln:

- Der Snapshot ist die **autoritativ aufgelöste Faktenlage für genau diese Entscheidung** (RFC B.3). Sicherheitsangaben stammen nie aus Agentenargumenten.
- `registry_ref` muss exakt die `registry_id` der mitgeführten Registry sein.
- `identity` ∈ Registry `observers`.
- `workspace.bindings`: eindeutig, sortiert, jede Kennung muss in Registry `bindings` existieren. B_W ist unveränderlich (RFC 4.1); der Snapshot enthält den aktuellen, geprüften Vertragsausschnitt.
- `workspace.valid`: aktuelle Vertragsgültigkeit (Gültig_Γ(W)). `false` ist ein bekannter verbietender Befund.
- `workspace.environment` muss in Registry `environments` existieren. Dessen `observers` sind ρ_Γ(c) — die tatsächlichen Empfänger der Verarbeitung in dieser Umgebung (mitverarbeitende Stellen inklusive, RFC 3, 5.2).
- `object.classification`: `classified` | `quarantine`. **`quarantine` ist kein reguläres Label und kein leeres Label** (RFC 2.5, B.3). Ein Quarantäneobjekt erfüllt die Aufnahmevoraussetzungen nicht (RFC 5.4).
- `object.labels`: λ(x), eindeutig, sortiert, nur in Registry existierende Bindungen. Fehlende Klassifikation wird nicht als `[]` behandelt; die Kennung muss existieren.
- `facts`: Schlüssel ⊆ (Registry `fact_fields` ∪ Basisfakten §4.2). `source` = benannte Herkunftsstelle (Freitext, dokumentativ). `source_kind` unterscheidet verwaltete Fakten, nachgewiesene technische Eigenschaften, ausdrücklich akzeptierte Betreiberannahmen und Test-Fakten (RFC B.3). L1 bewertet nur `value`; die Herkunftsunterscheidung ist Datenpflicht, keine Entscheidungsbasis.
- Objektversion im Intent muss mit `object.version` übereinstimmen.

### 2.3 `Intent` — `komki-intent/1`

```json
{
  "schema": "komki-intent/1",
  "intent_id": "<kebab-id>",
  "operation": "admit",
  "object": "<object_id>@<version>",
  "workspace": "<workspace_id>"
}
```

Regeln:

- `operation` ∈ {`start`, `admit`, `emit`, `transfer`, `store`} (geschlossene Menge).
- `object` und `workspace` sind reine Referenzen; der Intent trägt **keine** Rechte, Labels, Empfänger oder Behauptungen (keine Autorität aus Agentenargumenten, RFC 2.1, B.2).
- Kohärenz: `intent.workspace == snapshot.workspace.workspace_id` und `intent.object == object_id@version` des Snapshots, sonst Eingabefehler.

### 2.4 `Decision` — Ausgabe von `derive`

```json
{
  "decision": "permit",
  "rule": "admit",
  "registry_ref": "<registry_id>",
  "snapshot_ref": "<snapshot_id>",
  "intent_ref": "<intent_id>",
  "identity": "<observer-id>",
  "workspace": "<workspace_id>",
  "object": {"object_id": "<id>", "version": "<v>"},
  "checked_label": ["<bindung-id>@<int>", "..."],
  "blockers": null,
  "missing_evidence": null,
  "proof": { }
}
```

- `checked_label` ist **immer B_W = `workspace.bindings`**, nie λ(x) (RFC 5.4).
- `blockers`: nur bei `deny`, nicht-leer. Jedes Element ist ein geschlossenes Objekt mit **genau** den Schlüsseln `code` (string), `binding` (string|null), `condition` (string|null). `binding` benennt die betroffene Bindung (oder `null`), `condition` das betroffene Fakt-Feld (oder `null`).
- Blocker-Codes (vollständig, feste Bedeutung):
  - `object_quarantine` — Prämisse 1 verletzt (`binding: null`, `condition: null`)
  - `workspace_invalid` — Prämisse 2 verletzt
  - `basis_right_false` — `has_operation_right` oder `has_object_access_right` ist `false` (`condition` = Faktname)
  - `audit_path_not_ready` — `audit_path_ready` ist `false` (`condition: "audit_path_ready"`)
  - `label_not_included` — λ(x) ⊄ B_W (`binding: null`, `condition: null`)
  - `recipient_not_allowed` — ρ_Γ(c) ⊄ R_Γ(B_W) (`binding: null`, `condition: null`)
  - `missing_operation_rule` — Bindung hat keinen `admit`-Eintrag (`binding` = Bindung, `condition: null`)
  - `binding_condition_false` — Bedingung als `false` bewertet (`binding` = Bindung, `condition` = erstes falsch bewertetes Feld des Ausdrucks in Auswertungsordnung, sonst `null`)
- `missing_evidence`: nur bei `indeterminate`, nicht-leer. Elemente: `{code, fact, binding}` mit `fact` (string), `binding` (string|null). Codes: `missing_fact` (Fakt fehlt im Snapshot; bei Bedingungs-Unknown ist `binding` die prüfende Bindung) und `recipients_unproven` (`fact: "environment_observers_complete"`, `binding: null`).
- `proof`: nur bei `permit`, der kanonische Beweisbaum (§2.5/§4.3). Bei `deny`/`indeterminate` ist `proof` `null`.
- Kein Feld `effect` mit Ausführungsversprechen; die Ausgabe dokumentiert im `README`, dass eine Ableitung keine Ausführungsrechte erzeugt. Der Kern führt nichts aus.

### 2.5 `Proof` — `komki-proof/1`

```json
{
  "schema": "komki-proof/1",
  "rule": "admit",
  "conclusion": "permit",
  "registry_ref": "<registry_id>",
  "snapshot_ref": "<snapshot_id>",
  "intent_ref": "<intent_id>",
  "checked_label": ["<bindung-id>@<int>", "..."],
  "premises": [ ]
}
```

- `premises`: geordnete Liste in fester Reihenfolge (§4). Jede Prämisse: `{"name": ..., "kind": ..., "value": true, ...}` mit kinds `object_check`, `fact`, `computed`, `condition`.
- Prämissenobjekte im Einzelnen (nur diese Schlüssel, alle Mengen sortiert):
  - `not_quarantine`: `{"name": "not_quarantine", "kind": "object_check", "value": true, "object": "<id@v>", "classification": "classified"}`
  - `workspace_contract_valid`: `{"name": "workspace_contract_valid", "kind": "fact", "fact": "workspace_contract_valid", "value": true, "source": "<workspace.valid>"}`
  - Basisfakten: `{"name": "<name>", "kind": "fact", "fact": "<name>", "value": true, "source": "<source>", "source_kind": "<kind>"}`
  - `label_inclusion`: `{"name": "label_inclusion", "kind": "computed", "value": true, "object_labels": [...], "checked_label": [...]}`
  - `recipient_inclusion`: `{"name": "recipient_inclusion", "kind": "computed", "value": true, "actual_recipients": [...], "allowed_recipients": [...]}`
  - `binding_condition`: `{"name": "binding_condition", "kind": "condition", "binding": "<id>", "expression": <Expression wie in Registry>, "value": true, "fact_refs": [...]}`
- `conclusion` ist in L1 stets `permit`; `deny`/`indeterminate` werden als `Decision` mit `blockers`/`missing_evidence` dargestellt, nicht als Beweisbaum. `verify` prüft nur Permit-Bäume.
- `fact_refs` bei `binding_condition`: die sortierte Menge der im Expression-AST referenzierten Feldnamen (nur Felder, die im Snapshot tatsächlich aufgelöst werden müssen; `true`/`false`-Ausdrücke haben `[]`).

## 3. Beschränkte Policy-Sprache (vollständige B.4-Grammatik)

```text
Expression :=
    true
  | false
  | {"eq": ["<feld>", <literal>]}
  | {"member": ["<feld>", [<literal>, ...]]}
  | {"subset": ["<feld>", [<literal>, ...]]}
  | {"at_most": ["<feld>", <integer>]}
  | {"all": [<Expression>, ...]}
  | {"any": [<Expression>, ...]}
```

- Ausdrucksobjekte haben **exakt einen** Schlüssel. Unbekannte Ausdrucksformen (z. B. `{"not": ...}`) werden **beim Kompilieren der Registry abgewiesen** (Eingabefehler `unsupported_expression`) — der engere Sprachumfang wird nicht durch Annahmen verborgen.
- Feldtypen aus Registry `fact_fields`: `eq`/`member` auf `string`/`integer`/`boolean`-Feld mit typgleichem Literal; `subset` auf `string_set`-Feld mit String-Literalmenge; `at_most` auf `integer`-Feld mit nicht-negativem Integer. Typverstöße = Eingabefehler zur Compile-Zeit.
- Auswertung ist dreiwertig: `true` | `false` | `unknown`.
  - Fehlender Fakt im Snapshot → `unknown`, **kein Default** (RFC 5.2, B.4).
  - `all`: enthält ein bekanntes `false` → `false`; nur `true` → `true`; sonst `unknown`. Leere `all` → `true`.
  - `any`: enthält ein bekanntes `true` → `true`; nur `false` → `false`; sonst `unknown`. Leere `any` → `false`.
  - `member`: Feld unbekannt → `unknown`; sonst Wert ∈ Literalmenge.
  - `subset`: Feld unbekannt → `unknown`; sonst Wertmenge ⊆ Literalmenge.
  - `at_most`: Feld unbekannt → `unknown`; sonst Wert ≤ Literal.
- Der Auswerter erhält ausschließlich (Fakten, Expression). Er hat **keinen Zugriff** auf das Prüflabel, andere Bindungen oder den Regelkontext — ein Prädikat darf nicht davon abhängen, welche weiteren Bindungen geprüft werden (RFC 5.2, B.4 Monotonie A.2).

## 4. Regelzweig `admit` — Prämissen, Ordnung, Entscheidung

### 4.1 Prüflabel

Das Prüflabel ist **immer** `workspace.bindings` (B_W). Auch eine öffentliche Datei (λ(x) = ∅) wird gegen **alle** Raumbindungen geprüft (RFC 5.4, D.1).

### 4.2 Basisfakten (durch den Vertrag festgelegt)

Boolesche Fakten, die der Snapshot enthalten muss (fehlend → `unknown`, `false` → verbietend):

| Fakt | Bedeutung | RFC-Bezug |
|---|---|---|
| `has_operation_right` | Grundlegendes Aufnahmerecht vorhanden | 5.2, B.5 Schritt 3, D.1 |
| `has_object_access_right` | Objektzugriffsrecht vorhanden | 5.2, B.5 Schritt 3 |
| `audit_path_ready` | Vorgesehener Journal-/Belegweg zugelassen | 5.2, B.5 Schritt 3, 11 |
| `environment_observers_complete` | Umgebungsbeobachterliste vollständig (kein unbekannter Diagnosedienst) | 3, D.2, D.4 `unvollstaendige-umgebung` |

Dazu `workspace.valid` (Vertragsfeld, kein Fakt) als Prämisse `workspace_contract_valid`.

### 4.3 Erforderliche Prämissen von `admit` (feste Ordnung)

Der Ableitungsprüfer rekonstruiert **diese Menge aus dem Regeltyp** und akzeptiert keine Teilmenge (RFC B.5). Reihenfolge ist normativ (kanonische Darstellung):

1. `not_quarantine` — `object.classification ≠ "quarantine"`. Verstoß → verbietend (`object_quarantine`).
2. `workspace_contract_valid` — `workspace.valid == true`. Verstoß → verbietend (`workspace_invalid`).
3. `has_operation_right` — Fakt. `false` → verbietend (`basis_right_false`); fehlt → `unknown`.
4. `has_object_access_right` — Fakt. `false` → verbietend (`basis_right_false`); fehlt → `unknown`.
5. `audit_path_ready` — Fakt. `false` → verbietend (`audit_path_not_ready`); fehlt → `unknown`.
6. `environment_observers_complete` — Fakt. `false`/fehlt → Empfänger nicht beweisbar → `unknown` (unbekannte Empfänger sind fehlende Evidenz, nicht ∅; RFC 5.1, D.4).
7. `label_inclusion` — λ(x) ⊆ B_W. Verstoß → verbietend (`label_not_included`).
8. `recipient_inclusion` — ρ_Γ(c) = `environments[workspace.environment].observers` ⊆ R_Γ(B_W) = ∩ readers(b) für b ∈ B_W. Bei B_W = ∅ ist R_Γ(B_W) = 𝒪 (alle Registry-Beobachter). Verstoß → verbietend (`recipient_not_allowed`). **Dieser Test ist fester Kernbestandteil; keine Operationsbedingung kann ihn erweitern oder ersetzen** (RFC 5.2).
9. `binding_condition(b)` — für **jede** Bindung b ∈ B_W in sortierter Ordnung: Auswertung von `bindings[b].operations["admit"]` (fehlt → **verbietend**, `missing_operation_rule` — die Operation ist damit nicht erlaubt) gegen die Snapshot-Fakten dreiwertig.
10. `conclusion` — `permit` nur wenn alle Prämissen `true` sind.

### 4.4 Entscheidung

- **deny**, wenn mindestens eine Prämisse bekannt-falsch/verbietend ist. Alle verbietenden Befunde werden als `blockers` gelistet.
- **indeterminate**, wenn kein verbietender Befund vorliegt, aber mindestens eine Prämisse `unknown` ist. Alle unbekannten Prämissen werden unter `missing_evidence` mit betroffenem Fakt/Bindung benannt.
- **permit** nur bei vollständig bewiesenen Prämissen, mit Beweisbaum.
- Bekannt-falsch schlägt unbekannt (RFC B.5). Strukturfehler sind keine Entscheidungen.
- Determinismus: gleiche Eingaben erzeugen identische Entscheidungen und byte-identische kanonische Ausgaben.

## 5. `verify` — unabhängiger Ableitungsprüfer

Der Prüfer **ruft `derive` niemals auf** und **glaubt kein `permit`**. Er prüft den vorgelegten Baum gegen genau die mitgeführte Registry, den mitgeführten Snapshot und Intent (RFC B.2, B.5, D.4 `ableitungspruefer`).

Prüfschritte (Befunde werden gesammelt, soweit die Prüfung nicht strukturell abbricht; ≥1 Befund → `invalid`):

1. **Struktur:** Proof-Schema (falsches/fehlerhaftes Proof-Datensatzformat ist ein Eingabefehler, Exit 2 — kein `invalid`-Urteil), Referenzkohärenz (`registry_ref`, `snapshot_ref`, `intent_ref` müssen exakt den mitgeführten Eingaben entsprechen — fremder Snapshot → `snapshot_mismatch`, fremde Registry → `registry_mismatch`, fremder Intent → `intent_mismatch`), Regel = `admit` (andere → `unsupported_rule`).
2. **Prüflabel:** `checked_label` muss **mengengleich** `workspace.bindings` sein (sortierter Vergleich). Verkürztes Prüflabel → `checked_label_mismatch`. Eine ausgelassene Raumbindung darf nicht durch einen verkürzten Baum verschwinden (RFC B.5).
3. **Required-Set:** Die Prämissenmenge wird **aus dem Regeltyp gegen den Snapshot rekonstruiert** (RFC B.5): die acht festen Prämissen plus je `binding_condition` für jedes Element von `workspace.bindings` (nach Schritt 2 mengengleich `checked_label`). Eine Prämisse erfüllt ihren Slot **nur mit der zugeordneten Art aus §2.5** (name↔kind-Bindung; z. B. `label_inclusion` nur als `kind: "computed"`, `has_operation_right` nur als `kind: "fact"`); abweichende Art → `unknown_premise`. Fehlt eine → `missing_required_premise`; unbekannte zusätzliche Prämisse → `unknown_premise`. `binding_condition`-Slots werden nur aus `kind: "condition"`-Prämissen erfüllt.
4. **Faktprämissen:** Der Fakt muss im Snapshot existieren (`fact_missing`) und der behauptete `value` muss mit dem Snapshot-Wert übereinstimmen (`fact_value_mismatch`). `workspace_contract_valid` wird gegen `workspace.valid` geprüft.
5. **`not_quarantine`:** Klassifikation im Snapshot muss `classified` sein, sonst `object_quarantine`.
6. **`label_inclusion`:** neu berechnet aus Snapshot: λ(x) ⊆ `checked_label`, sonst `label_inclusion_false`. Behauptete `object_labels`/`checked_label`-Werte in der Prämisse müssen mit den berechneten übereinstimmen, sonst ebenfalls `label_inclusion_false`.
7. **`recipient_inclusion`:** neu berechnet aus Registry: Umgebung ⊆ R_Γ(`checked_label`), sonst `recipient_inclusion_false`; behauptete Empfängerlisten müssen übereinstimmen, sonst ebenfalls `recipient_inclusion_false`.
8. **`binding_condition(b)`:** Die in der Prämisse behauptete `expression` muss **exakt** (strukturelle Gleichheit) der Registry-Expression der Bindung für `admit` entsprechen, sonst `expression_mismatch` (ein gefälschter, leichterer Ausdruck ist ein Angriff). Hat die Bindung **keinen** `admit`-Eintrag, feuert ebenfalls `expression_mismatch`; `fact_refs`-Vergleich und Neuauswertung werden in diesem Fall übersprungen (kein `fact_refs_mismatch`, kein `condition_false`/`condition_unknown`, kein Crash). Der Ausdruck wird gegen die Snapshot-Fakten **neu ausgewertet**: Ergebnis `false` → `condition_false`; `unknown` → `condition_unknown`. Der behauptete `value` muss `true` sein, sonst `condition_false`. `fact_refs` müssen der aus der **Registry-Expression** (dem autoritativen AST, nicht dem behaupteten) bestimmten Feldmenge entsprechen, sonst `fact_refs_mismatch` — verify vertraut dem Baum die Abhängigkeiten nicht.
9. **`conclusion`:** `permit` ist nur gültig, wenn **alle** neu geprüften Prämissen `true` ergeben. Meldet ein prädikatsbezogener Schritt (4–8) einen Befund, wird **zusätzlich** `conclusion_mismatch` gemeldet (die `permit`-Behauptung ist nicht getragen). Melden ausschließlich die strukturellen Schritte 1–3 einen Befund, endet die Prüfung **sofort** mit allen Befunden des ersten befundhaltenden Schritts — auch spätere strukturelle Schritte laufen dann nicht mehr, und die Prämissen werden nicht weiter geprüft. `conclusion ≠ permit` → `conclusion_unsupported` (L1 prüft nur Permit-Bäume).

Ausgabe: `{"result": "valid"}` bzw. `{"result": "invalid", "reasons": [{"code": ..., "binding": ..., "fact": ...}]}` (Reasons sortiert in fester Prüfordnung). Strukturfehler in den Eingaben sind Eingabefehler (Exit 2), keine `invalid`-Urteile.

## 6. Kanonische Darstellung & strenge JSON-Basis

- **Eigener strenger JSON-Parser** (stdlib-only, keine Runtime-Abhängigkeit): verwirft doppelte Schlüssel (mit JSON-Pfad in der Fehlermeldung), nachgestellte Kommas, `NaN`/`Infinity`, führende Pluszeichen, untermengte Literale; Zahlen nur Integer und Floats; Unicode gemäß RFC-8259-Sicht (kein `sort_keys`-Beweis, RFC F.4 — unsere Kanonisierung ist eine eigene, versionierte, eindeutige Darstellung).
- **Kanonischer Encoder:** Objektschlüssel aufsteigend sortiert (bytewise UTF-8), 2-Space-Einrückung, LF-Zeilenenden, keine Leerzeilen, finales Newline. Mengen (Labels, Beobachter, `fact_refs`, `reasons`) sortiert aufsteigend, duplikatfrei. Prämissenliste in fester Reihenfolge §4.3. Ganzzahlen dezimal ohne Vorzeichennullen. **Floats kommen in keiner L1-Ausgabe vor** (Fixtures nutzen ausschließlich Integer, Strings, Booles, Arrays, Objekte).
- Tests vergleichen strukturgleicher Daten über `canonical(parse(x)) == canonical(parse(y))`; CLI-Determinismus byte-identisch über zwei Aufrufe.

## 7. CLI `komki-policy` (Escript, null Runtime-Deps)

```bash
komki-policy validate --registry <registry.json>
komki-policy decide   --registry <r.json> --snapshot <s.json> --intent <i.json>
komki-policy verify   --registry <r.json> --snapshot <s.json> --intent <i.json> --proof <p.json>
komki-policy plan     # → unsupported
```

Exit-Codes: `0` Erfolg (auch `deny`/`indeterminate`/`invalid` sind legitime Ergebnisse); `1` `verify` hat Beweis verworfen; `2` Eingabefehler (Parse/Validierung/Kohärenz, mit strukturierten Fehlerdetails auf stdout); `3` `unsupported` (nicht implementierter Regelzweig); `4` unerwarteter interner Fehler — fällt **niemals** auf `permit` zurück.

## 8. Erwartungsfälle (synthetisch; erwartete Prämissen unabhängig vom Produktionscode festgelegt)

Alle Fälle nutzen `priv/fixtures/registry.json` (Bürgerfall-Bindung `buergerfall-4711@1` mit `admit`-Bedingung: Zweck passt **und** Datei gehört zum genehmigten Fallumfang; Lizenzbindung `lizenz-namensnennung@1` mit `admit: true` und weitem Empfängerkreis; Bindung `nur-start-test@1` **ohne** `admit`-Eintrag, nur `start`; Umgebungen `lokale-fallverarbeitung@1` mit Beobachtern `{carsten, lokale-fallverarbeitung}` und `recherche-webdienst@1` mit Beobachtern `{carsten, webdienst-x}`).

| Fall | Kurzfassung | Erwartung |
|---|---|---|
| `case_permit` | Öffentliche Datei (λ=∅), Scope-Fakt `true`, Zweck passt, Basis alles `true`, Empfänger `{carsten, lokale-fallverarbeitung}` = R_Γ(B_W) | **permit**, `checked_label` = `[buergerfall-4711@1]`, vollständiger Baum §4.3 |
| `case_deny` | Wie permit, aber Scope-Fakt `false` (D.1: Labelinklusion und Empfängertest erfüllt, Bedingung falsch) | **deny**, Blocker `binding_condition_false` (buergerfall-4711@1) |
| `case_deny_licensed` | Objekt λ=`[lizenz-namensnennung@1]` (eigene Lizenzregel `true` erfüllt), B_W=`[buergerfall-4711@1, lizenz-namensnennung@1]`, Scope `false` — nur wer λ(x) statt B_W prüft, würde erlauben | **deny**, Blocker `binding_condition_false` (buergerfall-4711@1), `checked_label` = beide Bindungen |
| `case_indeterminate` | Wie permit, Scope-Fakt fehlt (fehlende, nicht als falsch bekannte Evidenz, D.1) | **indeterminate**, `missing_evidence` → Fakt `input_in_approved_case_scope` (Bedingung `unknown`) |
| `case_quarantine` | Objekt `classification: quarantine`, λ=`[]` — Quarantäne ist kein leeres Label (RFC 2.5, D.4) | **deny**, Blocker `object_quarantine` |
| `case_deny_no_basis` | Öffentlicher Raum B_W=∅, öffentliche Datei, `has_operation_right: false` (D.4 `leeres-label`: ohne Basisrechte erlaubt nichts) | **deny**, Blocker `basis_right_false` |
| `case_unsupported` | Intent `operation: transfer` | **unsupported** (keine Decision, Exit 3) |
| `case_deny_recipient` | B_W=`[buergerfall-4711@1, lizenz-namensnennung@1]`, λ=`[lizenz-namensnennung@1]` (eigene Regel `true` erfüllt), Umgebung `recherche-webdienst@1` mit `webdienst-x` ∉ R_Γ(B_W) (D.4 `empfaengergrenze`: objektbezogenes `true` schaltet keinen unzulässigen Empfänger frei) | **deny**, Blocker `recipient_not_allowed`, `checked_label` = beide Bindungen |
| `case_deny_missing_rule` | B_W=`[nur-start-test@1]` (Bindung ohne `admit`-Eintrag), alle Fakten `true` (B.4: fehlende Operationsregel ≠ leere Konjunktion `true`) | **deny**, Blocker `missing_operation_rule` (nur-start-test@1) |
| `case_indeterminate_env_false` | Wie permit, aber `environment_observers_complete: false` (D.4 `unvollstaendige-umgebung`) | **indeterminate**, `missing_evidence` → `recipients_unproven` / `environment_observers_complete` |
| `case_indeterminate_env_missing` | Wie permit, aber Fakt `environment_observers_complete` fehlt (kein Leer-Default, §2.2) | **indeterminate**, `missing_evidence` → `recipients_unproven` / `environment_observers_complete` |
| `case_deny_precedence` | Scope-Fakt `false` **und** `has_operation_right` fehlt gleichzeitig (B.5: bekannt-falsch schlägt unbekannt) | **deny**, Blocker `binding_condition_false`, `missing_evidence: null` |
| `case_deny_multi_blockers` | Quarantäne-Klassifikation **und** `workspace.valid: false` gleichzeitig; alle übrigen Prämissen true (§4.4: alle verbietenden Befunde, Reihenfolge §4.3) | **deny**, Blocker `[object_quarantine, workspace_invalid]` |
| `case_indeterminate_multi_evidence` | `has_operation_right` **und** `audit_path_ready` fehlen gleichzeitig; alle übrigen Prämissen true (§4.4: alle unbekannten Prämissen, Reihenfolge §4.3) | **indeterminate**, `missing_evidence` = zwei `missing_fact`-Einträge in Ordnung (`has_operation_right`, `audit_path_ready`) |
| `case_deny_label_not_included` | Objekt λ=`[lizenz-namensnennung@1]`, B_W=`[buergerfall-4711@1]` — Label außerhalb der Raumbindungen; Empfänger und Bedingungen erfüllt (Angriffsseite des label_inclusion-Tests) | **deny**, Blocker `label_not_included` |

Ungültige Eingaben (Eingabefehler, keine Entscheidungen):

| Fixture | Erwartung |
|---|---|
| `invalid/registry_duplicate_key.json` | Parse-Fehler `duplicate_json_key` |
| `invalid/registry_unknown_field.json` | Validierungsfehler `unknown_field` |
| `invalid/registry_unknown_expression.json` | Compile-Fehler `unsupported_expression` (Sprachumfang wird nicht versteckt) |
| `invalid/snapshot_unknown_binding_ref.json` | Validierungsfehler `unknown_binding_reference` |
| `invalid/intent_version_mismatch.json` | Kohärenzfehler `intent_snapshot_mismatch` |

Manipulierte Beweise (alle von `verify` zu verwerfen):

| Fixture | Verifikationskontext | Erwartung |
|---|---|---|
| `case_permit/proof_valid.json` | case_permit | `valid` (Referenzbaum, handgeschrieben aus §4.3) |
| `proofs/proof_missing_binding_condition.json` | case_permit | `invalid` → `missing_required_premise` (Raumbindung weglassen) |
| `proofs/proof_checked_label_shortened.json` | case_permit | `invalid` → `checked_label_mismatch` (Prüflabel ∅, Baum „prüft" nur λ(x)) |
| `proofs/proof_false_condition.json` | **case_deny** (Scope `false`) | `invalid` → `condition_false` + `conclusion_mismatch` (gefälschte Bedingung `true`) |
| `proofs/proof_missing_fact_condition.json` | **case_indeterminate** (Scope fehlt) | `invalid` → `condition_unknown` + `conclusion_mismatch` (Beweis behauptet `true` ohne Fakt) |
| `proofs/proof_foreign_snapshot.json` | case_permit | `invalid` → `snapshot_mismatch` (fremde Snapshot-Referenz) |
| `proofs/proof_false_fact_value.json` | **case_deny_no_basis** (`has_operation_right: false`) | `invalid` → `fact_value_mismatch` + `conclusion_mismatch` (gefälschte Faktquelle: `true` behauptet; D.4 `leeres-label`-Gegenprobe) |
| `proofs/proof_easier_expression.json` | case_permit | `invalid` → `expression_mismatch` + `fact_refs_mismatch` + `conclusion_mismatch` (leichterer Ausdruck `true` statt Registry-Expression) |
| `proofs/proof_disguised_label_inclusion.json` | **case_deny_label_not_included** (λ ⊄ B_W) | `invalid` → `unknown_premise` (art-getarnte Prämisse erfüllt ihren Slot nicht — der Prüfer lässt sich nicht umgehen) |
| `proofs/proof_admitless_condition.json` | **case_deny_missing_rule** (Bindung ohne `admit`) | `invalid` → `expression_mismatch` + `conclusion_mismatch` (Neuauswertung übersprungen, kein Crash) |

Die erwarteten Verify-Ergebnisse (Kontext-Snapshot/Intent je Beweis, `result` und **vollständige** `reasons`-Liste in fester Prüfordnung §5) liegen maschinenlesbar in `priv/fixtures/proofs/verify_expectations.json` (`komki-verify-expectations/1`). Pfade sind relativ zu `priv/fixtures/`.

Auswerter-Orakel: `priv/fixtures/expressions/evaluate_expectations.json` (`komki-expression-expectations/1`) pinnt die dreiwertige Auswertung je B.4-Grammatikbaustein inklusive der Grenzfälle (leere `all` → `true`, leere `any` → `false`, unknown-Propagation in `all`/`any`, `member`/`subset`/`at_most` bei fehlendem Feld). Fakten dort sind reiner Auswerter-Input `{feld: {value}}` ohne Registry-Bindung; die Registry-Compile-Validierung wird separat über `invalid/` orakelt.

Kopplung derive↔Beweis (RFC A.7): Der `proof` von `derive(case_permit)` muss strukturgleich (kanonisch, §6) mit `case_permit/proof_valid.json` sein, und `verify` muss diesen Baum als `valid` bestätigen. Die deny/indeterminate-Orakel tragen `"proof": null` gemäß §2.4.

Testmanifeste (`expected_decision.json`, `expected_result.json`, `verify_expectations.json`, `evaluate_expectations.json`) sind test-only-Datensätze und unterliegen keiner der Laufzeit-Schemata aus §2.

Eingabe-Fixtures (Registry, Snapshots, Intents, `invalid/`) sind **bewusst nicht byte-kanonisch** sortiert (menschenlesbare Schlüsselordnung); §6-Kanonisierung gilt für Ausgaben und für Vergleiche (`canonical(parse())`). Der Kanonitäts-Tripwire der Tests deckt entsprechend nur den byte-kanonisch gepinnten Teil des Korpus (Decision-, Proof- und Manifest-Dateien).

## 9. Explizite Nichtziele von Lieferung 1

- Keine Ausführung, kein Connector, kein Schreibzugriff, keine Freigaben, kein Offenlegungsstand, kein Journal, kein Simulator, keine Zwei-Ausführungs-Prüfung.
- `plan`/`infer_plan`, `start`, `emit`, `transfer`, `store`, Lockerungsprüfung: `unsupported`.
- Der Auswerter bewertet keine `source_kind`-Semantik (Herkunft ist Datenpflicht, nicht Tor).
- Keine produktiven Registry-Stände; alle Bezeichner sind synthetisch. Die `gribs`-/AZ-/RIS-Welt wird nicht referenziert.
- `verify` prüft nur Permit-Bäume des Zweigs `admit`; historische Audit-Prüfung (Anhang F) ist nicht Teil dieser Lieferung.
