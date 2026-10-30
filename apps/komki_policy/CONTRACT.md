# CONTRACT.md — Komki.Policy Datenvertrag v2 (Lieferung 1: `admit`; Lieferung 2: `emit`, Remedy-Katalog, Aktionsfreigabe; Lieferung 3: `store`; Lieferung 4: `transfer`)

**Status:** verbindlicher gemeinsamer Vertrag. Änderungen nur durch den Integrator.
**Normative Basis:** RFC 0001 Revision 4, SHA-256 `b4364bebfd77284aae7ee6a28e39bef8eb2736fc1f2ea301efb2e908c9ec5dcf` (Lieferung 1); fortgeführt durch RFC 0003 (denselben Text mit Anhang-E-Revisionen) und Ticket #93: APPA Theorem 5 (vier Übergangstypen), PACE-Mechanik (Fenster + Nonce + Hash-Bindung, vgl. `docs/research/2026-10-13-agent-policy-models-openappa-pace.md` Move 1), Fides/Prudentia-Schärfungen (Reihenfolge, Objekt-Level-Endorsement, Metriken) aus dem Ticket-Kommentar.
**Maßgebliche RFC-Abschnitte:** 2–6 (Modell), 5.4 (Aufnahme), 5.5 (Erzeugen), 5.6 (Übergabe und Speicherung, Lieferung 3 / Ticket #205 und Lieferung 4 / Ticket #298), 6 (Freigaben: R.6.1–R.6.5), 9.1, B.3–B.8, D.1, D.4, Anhang A.2/A.7.
**Geltungsbereich:** ausschließlich synthetische Fixtures, lokale Entwicklung, keine produktiven Daten, kein Netz, keine Uhr, kein LLM, keine reale Aufnahme. Eine Ableitung ist keine Ausführungsrechte (RFC 9.1, B.8). Der Remedy-Katalog erzeugt keine Autorität (§ 2.8); die Aktionsfreigabe erzeugt keine Herabstufungsbefugnis (R.6.2).

---

## 1. Betriebsgrenzen

Implementiert sind die Regelzweige `admit` (Lieferung 1), `emit` (Lieferung 2), `store` (Lieferung 3, § 4.7) und `transfer` (Lieferung 4, § 4.8) mit Ableitung (`derive`), Remedy-Katalog (§ 2.8), Aktionsfreigabe-Mechanik (§ 2.6, § 4.6), unabhängigem Ableitungsprüfer (`verify`) sowie CLI. `emit`-, `store`- und `transfer`-Entscheidungen mit vorgelegter Aktionsfreigabe laufen als eigener Regelzweig (B.5 Schritt 6), niemals als stiller Fallback der normalen Entscheidung.

- Nicht implementierte Regelzweige (`start`, Planer `infer_plan`, Offenlegungsfreigabe als Release-`kind`): `unsupported` — **keine** `Decision`, eigener Exit-Pfad (Exit 3). Sie werden niemals als `deny` ausgegeben (deny wäre die falsche Behauptung, der Zweig sei geprüft worden und verbiete).
- Der Kern ist deterministisch und seiteneffektfrei: keine Uhr, kein Zufall, kein Netz, kein Dateizugriff, kein LLM-Aufruf, kein globales Zustandslesen. Alle Eingaben sind explizite Argumente. Logische Zeit (Offenlegungsstand `as_of`, Fenster) ist Eingabe über den vertrauenswürdigen Kontext, nie Engine-Zustand.
- `derive` verbraucht keine Freigabe: die Aktionsfreigabe-Prüfung liest den Offenlegungsstand und plant den Verbrauch als deklarative Wirkung; der atomare Standübergang ist die eigene reine Funktion `advance` (§ 2.7) — Urteil und Vollzug getrennt (B.8).
- Struktur- und Validierungsfehler sind **getrennte Eingabefehler** (Exit 2), niemals eine `Decision` mit einem der drei Werte (RFC B.6).
- Das Decision-Alphabet ist strikt: `permit` | `deny` | `indeterminate`. Es gibt keinen vierten Wert und keinen Fallback auf `permit` — auch nicht bei Ressourcenproblemen (RFC B.5).

## 2. Datensätze (geschlossene, versionierte Schemas)

Alle JSON-Datensätze tragen ein Pflichtfeld `schema` mit exakt den unten genannten Werten. Unbekannte Felder, doppelte Schlüssel (schon beim Parsen), falsche Typen, nichtleere unbekannte Feldmengen und widersprüchliche Referenzen werden abgewiesen (Eingabefehler). Mengen werden als sortierte, duplikatfreie Arrays dargestellt.

### 2.1 `Registry` — `komki-registry/2`

```json
{
  "schema": "komki-registry/2",
  "registry_id": "<kebab-id>",
  "observers": ["<observer-id>", "..."],
  "fact_fields": { "<feld-name>": "string|boolean|integer|string_set" },
  "environments": {
    "<umgebung-id>@<int>": { "observers": ["<observer-id>", "..."] }
  },
  "bindings": {
    "<bindung-id>@<int>": {
      "readers": ["<observer-id>", "..."],
      "operations": { "admit": "<Expression>", "emit": "<Expression>" },
      "relaxation_authorities": []
    }
  },
  "transformations": {
    "<transformations-id>@<int>": {
      "input_labels": ["<bindung-id>@<int>", "..."],
      "output_labels": ["<bindung-id>@<int>", "..."]
    }
  }
}
```

Regeln:

- `registry_id`: kebab-case ASCII (`^[a-z0-9]+(?:-[a-z0-9]+)*$`).
- `observers`: nicht leer, eindeutig, kebab-case. Dies ist 𝒪, der modellierte Beobachterraum.
- `fact_fields`: deklariert die zulässigen prädikatfähigen Felder mit Typ. Ausdrücke in `operations` dürfen nur hier deklarierte Felder referenzieren (Typ-kompatibel, siehe §3).
- `environments`: mindestens eine Umgebung; `observers` je Umgebung nicht leer, eindeutig, ⊆ `observers`. Eine Umgebung mit leerer Beobachterliste ist ungültig (verarbeitende Umgebungen haben mindestens die betreibende Stelle).
- `bindings`: mindestens eine Bindung. Bindungs- und Umgebungskennungen folgen `<kebab>@<nicht-negativer Integer>`; verschiedene Versionen derselben Bindung sind verschiedene Kennungen (kein „latest“-Rollover, RFC A.1).
- `readers`: nicht leer, eindeutig, ⊆ `observers`. Dies ist R_b, der zulässige Empfängerkreis der Bindung.
- `operations`: Map Regelname → Expression. Zulässige Regelnamen (geschlossene Menge): `start`, `admit`, `emit`, `transfer`, `store`. Nur die Engine-seitig implementierten Zweige sind entscheidbar (v2: `admit`, `emit`, `store`, `transfer`); die übrigen dürfen deklariert, aber nicht entschieden werden.
- `relaxation_authorities`: Array (L1: immer `[]`; nicht bewertet).
- Eine Bindung ohne `admit`-Eintrag in `operations` erlaubt `admit` ausdrücklich **nicht** (RFC B.4: fehlende Operationsregel ≠ leere Konjunktion). Eine bewusst uneingeschränkte Operation wird ausdrücklich mit `true` eingetragen. Dasselbe gilt pro Operation: auch `emit`-Einträge folgen dieser Regel.
- `transformations`: optionale Map (fehlt der Abschnitt, gilt `{}`). Kennungen folgen `<kebab>@<nicht-negativer Integer>`. `input_labels`: nicht leer, eindeutig, sortiert, nur in `bindings` existierende Bindungen. `output_labels`: eindeutig, sortiert, ⊆ `bindings`; **darf leer sein** (das erzeugte Objekt trägt dann keine Bindung). Eine registrierte Transformation pinnt nur die erlaubte Label-Transition (APPA: registrierter, vertrauenswürdiger Übergang mit deklariertem Ziel-Label). Ihre **Ausführung** ist nicht implementiert: keine Operation wendet sie an, und der Remedy-Katalog (§ 2.8) zählt sie nur auf — ein Eintrag autorisiert nichts.
- **Zulässige Bibliotheksoberfläche:** Konsumierende der Engine (z. B. der Label-Store in `apps/komki_cli`) validieren Registry-Daten ausschließlich über `KomkiPolicy.Registry.compile/1` und dürfen vorab die öffentlichen Kennungsprädikate nutzen: `KomkiPolicy.Registry.kebab_id?/1` (kebab-case, wie `registry_id`) und `KomkiPolicy.Registry.reference_id?/1` (`<kebab>@<nicht-negativer Integer>`, wie Bindungs- und Umgebungskennungen). Eigene Schema-Prüfungen für engine-seitige Datenformate schreiben Konsumierende nicht.

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
  "remedies": null,
  "proof": { }
}
```

- `checked_label` ist für `admit` und `emit` **immer** B_W = `workspace.bindings`, nie λ(x) (RFC 5.4) und nie λ(y) (RFC 5.5). Für `store` und `transfer` ist es λ(y) = `object.labels` (sortiert): gespeichert oder übergeben wird ein schon erzeugtes Objekt unter seinem Ausgabelabel (RFC 5.6, § 4.7, § 4.8).
- `remedies`: bei `deny`/`indeterminate` nicht-leer, `permit`: `null` (§ 2.8).
- `emit`-Entscheidungen tragen zusätzlich die Felder `content_digest` (immer; Echo des technischen Fakts `output_content_digest`, § 4.5), `assigned_label` (bei `permit`: B_W, die vom Vermittler zugeordnete Ausgabe-Menge λ(y); sonst `null`) und — nur bei Permit durch Aktionsfreigabe — `release` (Form § 4.6). `admit`-Entscheidungen bleiben unverändert. `store`- und `transfer`-Entscheidungen tragen `content_digest` (immer) und — nur bei Permit durch Aktionsfreigabe — `release`; kein `assigned_label` (Speichern und Übergeben ordnen kein Label zu).
- `blockers`: nur bei `deny`, nicht-leer. Jedes Element ist ein geschlossenes Objekt mit **genau** den Schlüsseln `code` (string), `binding` (string|null), `condition` (string|null). `binding` benennt die betroffene Bindung (oder `null`), `condition` das betroffene Fakt-Feld (oder `null`).
- Blocker-Codes (vollständig, feste Bedeutung):
  - `object_quarantine` — Prämisse 1 verletzt (`binding: null`, `condition: null`)
  - `workspace_invalid` — Prämisse 2 verletzt
  - `basis_right_false` — `has_operation_right` oder `has_object_access_right` ist `false` (`condition` = Faktname)
  - `audit_path_not_ready` — `audit_path_ready` ist `false` (`condition: "audit_path_ready"`)
  - `label_not_included` — λ(x) ⊄ B_W (`binding: null`, `condition: null`)
  - `recipient_not_allowed` — ρ_Γ(c) ⊄ R_Γ(`checked_label`) (`binding: null`, `condition: null`)
  - `label_not_preserved` — nur `store` und `transfer`: B_W ⊄ λ(y), das Objekt hätte eine Raumbindung verloren (`binding: null`, `condition: null`)
  - `missing_operation_rule` — Bindung hat keinen Eintrag für die geprüfte Operation (`binding` = Bindung, `condition: null`)
  - `binding_condition_false` — Bedingung als `false` bewertet (`binding` = Bindung, `condition` = erstes falsch bewertetes Feld des Ausdrucks in Auswertungsordnung, sonst `null`)
  - Aktionsfreigabe-Zweig (§ 4.6), alle mit `binding: null`, `condition: null`: `release_call_mismatch` (GO bindet nicht an den exakten Call — deckt Inhaltstausch, Ziel-/Objekt-/Operations-Tausch), `release_not_yet_valid` (`as_of < valid_from`), `release_expired` (`as_of > valid_until`), `release_nonce_consumed` (Nonce bereits im Offenlegungsstand verbraucht — Replay), `release_scope_mismatch` (Geltungsbereich des GO ≠ Geltungsbereich des Standes), `release_authority_unknown` (zuständige Stelle ∉ Registry-Beobachter)
- `missing_evidence`: nur bei `indeterminate`, nicht-leer. Elemente: `{code, fact, binding}` mit `fact` (string), `binding` (string|null). Codes: `missing_fact` (Fakt fehlt im Snapshot; bei Bedingungs-Unknown ist `binding` die prüfende Bindung) und `recipients_unproven` (`fact: "environment_observers_complete"`, `binding: null`).
- `proof`: nur bei `permit` des **normalen** Zweigs, der kanonische Beweisbaum (§2.5/§4.3/§4.5). Bei `deny`/`indeterminate` und bei Permit durch Aktionsfreigabe ist `proof` `null` (die Freigabe-Entscheidung ruht auf der validierten Aktionsfreigabe und dem geplanten Verbrauch, nicht auf einem Erlaubt-Baum).
- Kein Feld `effect` mit Ausführungsversprechen; die deklarative Wirkung der Aktionsfreigabe steht im `release`-Objekt (§ 4.6). Die Ausgabe dokumentiert im `README`, dass eine Ableitung keine Ausführungsrechte erzeugt. Der Kern führt nichts aus.

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

- `premises`: geordnete Liste in fester Reihenfolge (§4.3 für `admit`, §4.5 für `emit`, §4.7 für `store`). Jede Prämisse: `{"name": ..., "kind": ..., "value": true, ...}` mit kinds `object_check`, `fact`, `computed`, `condition`.
- Prämissenobjekte im Einzelnen (nur diese Schlüssel, alle Mengen sortiert):
  - `not_quarantine`: `{"name": "not_quarantine", "kind": "object_check", "value": true, "object": "<id@v>", "classification": "classified"}`
  - `workspace_contract_valid`: `{"name": "workspace_contract_valid", "kind": "fact", "fact": "workspace_contract_valid", "value": true, "source": "<workspace.valid>"}`
  - Basisfakten: `{"name": "<name>", "kind": "fact", "fact": "<name>", "value": true, "source": "<source>", "source_kind": "<kind>"}`
  - `label_inclusion`: `{"name": "label_inclusion", "kind": "computed", "value": true, "object_labels": [...], "checked_label": [...]}`
  - `recipient_inclusion`: `{"name": "recipient_inclusion", "kind": "computed", "value": true, "actual_recipients": [...], "allowed_recipients": [...]}`
  - `label_preservation` (nur `store` und `transfer`): `{"name": "label_preservation", "kind": "computed", "value": true, "workspace_bindings": [...], "checked_label": [...]}` — B_W ⊆ λ(y).
  - `binding_condition`: `{"name": "binding_condition", "kind": "condition", "binding": "<id>", "expression": <Expression wie in Registry>, "value": true, "fact_refs": [...]}`
  - `label_assignment` (nur `emit`): `{"name": "label_assignment", "kind": "computed", "value": true, "assigned_label": [...], "checked_label": [...]}` — dokumentiert die Vermittler-Zuordnung λ(y) := B_W (RFC 5.5). Beide Mengen sind in der `emit`-Prämisse identisch B_W.
- `conclusion` ist stets `permit`; `deny`/`indeterminate` werden als `Decision` mit `blockers`/`missing_evidence` dargestellt, nicht als Beweisbaum. `verify` prüft Permit-Bäume der Zweige `admit`, `emit`, `store` und `transfer` (regelabhängige Sollmenge, § 5).
- `fact_refs` bei `binding_condition`: die sortierte Menge der im Expression-AST referenzierten Feldnamen (nur Felder, die im Snapshot tatsächlich aufgelöst werden müssen; `true`/`false`-Ausdrücke haben `[]`).

### 2.6 `Release` (Aktionsfreigabe) — `komki-release/1`

```json
{
  "schema": "komki-release/1",
  "release_id": "<kebab-id>",
  "kind": "aktionsfreigabe",
  "operation": "emit",
  "object": "<object_id>@<version>",
  "workspace": "<workspace_id>",
  "content_digest": "<sha256-hex>",
  "call_hash": "<sha256-hex>",
  "scope": "<kebab-id>",
  "authority": "<observer-id>",
  "valid_from": 1000,
  "valid_until": 1100,
  "nonce": "<kebab-id>"
}
```

Regeln (R.6.2 — autorisiert wird ein Ereignis, nicht nur ein Text):

- Geschlossene Feldmenge; unbekannte Felder, falsche Typen, `valid_from > valid_until` sind Eingabefehler.
- `kind`: geschlossen `{aktionsfreigabe, offenlegungsfreigabe}`. Nur `aktionsfreigabe` ist entscheidbar (§ 4.6); `offenlegungsfreigabe` ergibt `unsupported` (Exit 3) — die Lockerungsprüfung (R.5.7, `BerechtigtZurLockerung`) ist nicht Teil dieser Lieferung. Unbekannte `kind`-Werte sind Eingabefehler.
- `operation`: eine Aktionsfreigabe autorisiert `emit`, `store` oder `transfer`; andere bekannte Operationen ergeben `unsupported` (Exit 3), unbekannte Eingabefehler. Die Operation geht in den `call_hash` ein: ein GO für `emit` passt nie auf `store` oder `transfer` desselben Objekts, eines für `store` nie auf `transfer`.
- `object`, `workspace`: reine Referenzen; die Bindung an den Call geschieht ausschließlich über `call_hash` (kein separater Referenzvergleich — ein abweichender Call fällt durch den Hash-Abgleich auf, nicht durch eine behauptete Referenz).
- `content_digest`: SHA-256 (Hex, kleingeschrieben) der exakten Ausgabe-Bytes — auch undurchsichtige Bytes werden so an das GO gebunden (R.6.2 exakter Inhalt; B.8 Inhaltsreferenz statt Dateipfad).
- **Call-Hash (verbindliche Formel):** `call_hash = sha256(JSON.canonical({"content_digest": <digest>, "object": "<object_id>@<version>", "operation": <operation>, "workspace": <workspace_id>}))` als Hex kleingeschrieben, wobei `JSON.canonical` exakt die byte-stabile Ausgabe des kanonischen Encoders (§ 6) inklusive des finalen Newlines ist.
- `scope`: Geltungsbereich des Offenlegungsstands (R.6.3), muss exakt `stand.scope` entsprechen.
- `authority`: zuständige Stelle; muss Element der Registry-Beobachtermenge 𝒪 sein. Das Modell ist kein Beobachter — der Agent kann also keine Aktionsfreigabe ausstellen; die Durchsetzungsgrenze ist die 𝒪-Mitgliedschaft. Die Identität der Bearbeitung darf `authority` sein (GO-Prinzip im Einzelnutzer-Betrieb: das menschliche GO erteilt die nutzende Person selbst).
- `valid_from`/`valid_until`: **Frische-Fenster** als logische Ganzzahlen im Zeitbereich des Offenlegungsstands (`stand.as_of`); die Engine hat keine Uhr (§ 1). Prüfung: `valid_from <= as_of <= valid_until`.
- `nonce`: einmalige Kennung je GO (KEBAB). Verbrauch wird über den Offenlegungsstand geführt (§ 2.7): **atomarer Reservierung/Verbrauch**, kein zweiter erfolgreicher Commit desselben GOs (B.8).
- Eine Aktionsfreigabe ist **keine** wiederverwendbare Herabstufungsbefugnis (R.6.2): sie erlaubt genau den gebundenen Call, entfernt keine Bindung und ändert λ(y) ⊇ B_W nicht. Das `assigned_label` der Freigabe-Entscheidung bleibt B_W.

### 2.7 `Offenlegungsstand` — `komki-stand/1`

```json
{
  "schema": "komki-stand/1",
  "stand_id": "<kebab-id>",
  "version": 5,
  "scope": "<kebab-id>",
  "as_of": 1050,
  "consumed": {"<nonce>": "<release_id>"}
}
```

- Versionierter Stand (R.6.3): `version` nicht-negativer Integer, monoton; `as_of` logische Ist-Zeit aus dem vertrauenswürdigen Kontext; `consumed` mappt verbrauchte Noncen auf die verbrauchende `release_id` (Fortschreibung als Mini-Ledger — Prudentias Endorsement ohne Ledger/ohne Widerruf wird ausdrücklich **nicht** übernommen; Einträge entstehen und ändern sich nur über versionierte Standübergänge).
- **Standübergang (`advance`):** Die Permit-Entscheidung des Aktionsfreigabe-Zweigs trägt ein `release`-Objekt (Form in § 4.6) — das ist der Verbrauchs-Vorschlag. `advance(stand, vorschlag)` ist rein und atomar: Erfolg nur, wenn `vorschlag.stand_ref == "<stand_id>@<version>"` des aktuellen Standes, `vorschlag.stand_version_after == version + 1` (der Vorschlag muss exakt den nächsten Stand adressieren) **und** `vorschlag.nonce ∉ consumed`; Ergebnis ist der nächste Stand (`version + 1`, `consumed` um `nonce → release_id` erweitert). Sonst `refused` (`stand_version_conflict` bzw. `nonce_already_consumed`). Zwei konkurrierende Ausführungen desselben GOs können nicht beide erfolgreich committen — der Versionsabgleich ist das Compare-and-Swap; das Führen des aktuellen Standes ist Vollzug außerhalb des Kerns (B.8).

### 2.8 Remedy-Katalog (Legal Fortsetzungen statt nacktem `deny`)

APPA Theorem 5 umgesetzt: zu jedem Blocker und jedem fehlenden Beleg ein begrenzter, aufzählbarer Katalog legaler Fortsetzungen aus **genau vier Übergangstypen**. Der Katalog ist reine Ausgabe („der Katalog erzeugt keine Autorität“): keine Eingabe akzeptiert ihn, keine Fortsetzung wird ausgeführt.

- `remedies`-Eintrag bei `deny` (spiegelt das Blocker-Element in `blockers`-Ordnung): `{"code": ..., "binding": ..., "condition": ..., "transitions": [...]}`.
- `remedies`-Eintrag bei `indeterminate` (spiegelt das `missing_evidence`-Element in dessen Ordnung): `{"code": ..., "fact": ..., "binding": ..., "transitions": [...]}`.

Übergangstypen (geschlossene Menge, feste Payload-Schlüssel):

| Typ | Bedeutung | Payload |
|---|---|---|
| `fakt_nachreichen` | Autoritative (Nach-)Reichen des benannten Fakts über den Verwaltungsweg — der Agent liefert keine Fakten | `{"type": "fakt_nachreichen", "facts": ["<feld>", ...]}` |
| `registrierte_transformation` | Aufzählung anwendbarer registrierter Transformationen (§ 2.1): `input_labels ⊆ λ(x)` und `output_labels ⊆ B_W` | `{"type": "registrierte_transformation", "transformation": "<id>@<int>", "output_labels": [...]}` |
| `neuer_raum` | Fortsetzung in einem neuen Raum; notwendige (nicht hinreichende, B.7) Bedingungen gegen den aktuellen Snapshot | `{"type": "neuer_raum", "required_bindings": [...], "required_recipients": [...]}` |
| `aktionsfreigabe` (scope `call`) | Ein GO für den exakten Call — benennt den Hash, den ein gültiges GO tragen muss | `{"type": "aktionsfreigabe", "scope": "call", "call_hash": "<hex>"}` |
| `aktionsfreigabe` (scope `object`) | Objekt-Level-Endorsement: ein menschliches GO pro Objekt (Erstklassifikation R.2.5), reicher als ein Trust-Upgrade — Bindungen (Empfängerkreis + Bedingungen); Ledger und Widerruf über versionierte Verwaltungsakte | `{"type": "aktionsfreigabe", "scope": "object", "object": "<id@v>"}` |

**Ordnung (normativ):** `fakt_nachreichen` < `registrierte_transformation` < `neuer_raum` < `aktionsfreigabe` — nicht-verletzende Fortsetzungen VOR GO-Einträgen. Fides' „compensatory leakage“ (Rückfall auf die verletzende Aktion, nachdem eine legitime Strategie scheitert) wird durch den Katalog nicht legalisiert: das GO steht nie an erster Stelle.

**Anwendbarkeit (deny, Zweig `admit`):**

| Code | fakt | transformation | neuer_raum | aktionsfreigabe |
|---|---|---|---|---|
| `object_quarantine` | — | — | — | `object` (Erstklassifikation) |
| `workspace_invalid` | — | — | ✓ | — |
| `basis_right_false` | ✓ `facts: [condition]` | — | ✓ | — |
| `audit_path_not_ready` | ✓ `audit_path_ready` | — | ✓ | — |
| `label_not_included` | — | ✓ (passende `t`) | ✓ | — |
| `recipient_not_allowed` | — | — | ✓ | — |
| `label_not_preserved` (nur `store`, `transfer`) | — | — | ✓ | — |
| `missing_operation_rule` | — | — | ✓ | — |
| `binding_condition_false` | ✓ `facts: [condition]` | — | ✓ | — |

**Anwendbarkeit (Zweige `emit`, `store` und `transfer`, normal):** wie `admit`, zusätzlich `aktionsfreigabe` scope `call` für `basis_right_false`, `audit_path_not_ready`, `recipient_not_allowed`, `missing_operation_rule`, `binding_condition_false` (die Aktionsfreigabe deckt verbindliche Wirkungen des Erzeugens, Speicherns und Übergebens; `workspace_invalid` und `label_not_preserved` bleiben unüberbrückbar — ein GO stellt keine entfernte Bindung wieder her — ein GO belebt keinen ungültigen Vertrag). Für `indeterminate` (`missing_fact`, `recipients_unproven`) gilt `fakt_nachreichen` + `neuer_raum`, **nie** `aktionsfreigabe` — ein GO kann keine Belege herstellen.

**Aktionsfreigabe-Zweig (§ 4.6):** jeder Release-Blocker erhält genau einen `aktionsfreigabe`-scope-`call`-Eintrag mit dem **neu berechneten** korrekten `call_hash` (der Katalog sagt dem Menschen, woran ein gültiges GO gebunden sein muss). `workspace_invalid` behält seinen `neuer_raum`-Eintrag.

**Payload-Regeln:** `neuer_raum.required_bindings` = λ(x) bei `admit`, `[]` bei `emit`, `store` und `transfer` (notwendige Bedingung: der neue Raum muss mindestens die Objekt-Labels decken; ein leichterer Zielraum bleibt legal, B.7 — die kleinste Zuweisung kann trotzdem unzulässig sein). `neuer_raum.required_recipients` = ρ_Γ(c) des aktuellen Snapshot. `registrierte_transformation` listet je Blocker alle passenden Transformationen aufsteigend nach Kennung. `fakt_nachreichen` fällt weg, wenn kein Feld benennbar ist (`condition: null`, etwa bei einer Literal-Regel `false`): eine Fortsetzung ohne benanntes Feld ist keine Fakt-Fortsetzung. Der Katalog je Blocker bleibt nicht-leer (`neuer_raum`, im `emit`-, `store`- und `transfer`-Fall zusätzlich `aktionsfreigabe`).

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
- Der Auswerter erhält ausschließlich (Fakten, Expression). Er hat **keinen Zugriff** auf das Validierungslabel, andere Bindungen oder den Regelkontext — ein Prädikat darf nicht davon abhängen, welche weiteren Bindungen geprüft werden (RFC 5.2, B.4 Monotonie A.2).

## 4. Regelzweig `admit` — Prämissen, Ordnung, Entscheidung

### 4.1 Validierungslabel

Das Validierungslabel ist **immer** `workspace.bindings` (B_W). Auch eine öffentliche Datei (λ(x) = ∅) wird gegen **alle** Raumbindungen geprüft (RFC 5.4, D.1).

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
6. `environment_observers_complete` — Fakt. `false`/fehlt → Empfänger nicht beweisbar → `unknown` (unbekannte Empfänger sind fehlende Belege, nicht ∅; RFC 5.1, D.4).
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

### 4.5 Regelzweig `emit` — Erzeugen (RFC R.5.5)

Der Vermittler ordnet jeder Ausgabe das Raumlabel zu, auch undurchsichtigen Bytes; der Agent setzt keine Labels (λ(y) ⊇ B_W ist die Invariante, λ(y) = B_W die normale Zuordnung).

Erzeugen ist ein Schritt im Raum: die Umgebung des Snapshots ist die Umgebung, in der y entsteht (beim Vermittler die Raumumgebung). Wer y danach außerhalb des Raums sieht, prüft `transfer` (§ 4.8) oder `store` (§ 4.7) unter λ(y). Für `emit` bleiben damit Basis, Empfängertest der Raumumgebung, die `emit`-Bedingungen der Bindungen von B_W und die Labelzuordnung.

- **Snapshot-Voraussetzung:** `emit`-Snapshots müssen den technischen Fakt `output_content_digest` (Registry-`fact_fields`-Deklaration, Typ `string`, SHA-256-Hex der exakten Ausgabe-Bytes) enthalten; Fehlen ist ein Eingabefehler (`emit_digest_missing`) — der Call ist ohne Inhaltsreferenz nicht identifizierbar (B.3, B.8). Der Kern liest die Bytes nie: er bindet sie ausschließlich über den Digest.
- Der Snapshot-Objektabschnitt beschreibt den Ausgabe-Kandidaten. `object.labels` ist für `emit` bedeutungslos (Vor-Zuordnung `[]`); der Kern liest es nicht. `object.classification` muss `classified` sein — ein `quarantine`-Objekt wird nicht erzeugt (Eingabefehler, keine `object_quarantine`-Entscheidung: Quarantäne ist ein Eingangs-, kein Ausgabezustand).
- Prämissen (feste Ordnung, § 2.5-Baum):
  1. `workspace_contract_valid` — Verstoß → `workspace_invalid`
  2. `has_operation_right` — `false` → `basis_right_false`; fehlt → `missing_fact` (kein `has_object_access_right`: Erzeugen liest kein Quell-Objekt)
  3. `audit_path_ready` — `false` → `audit_path_not_ready`; fehlt → `missing_fact`
  4. `environment_observers_complete` — wie `admit` P6 (nur Beleg)
  5. `recipient_inclusion` — ρ_Γ(c) ⊆ R_Γ(B_W); Verstoß → `recipient_not_allowed`
  6. `binding_condition(b)` — für **jede** Bindung b ∈ B_W in sortierter Ordnung: Auswertung von `bindings[b].operations["emit"]` (fehlt → **verbietend**, `missing_operation_rule`; dreiwertig wie § 3)
  7. `label_assignment` — berechnet, immer wahr auf Permit: λ(y) := B_W (`assigned_label` = `checked_label` = B_W)
- Permit-Ausgabe: `decision: permit`, `rule: emit`, `assigned_label` = B_W, `content_digest` = Digest-Fakt, Beweisbaum § 2.5. **Keine Eingabe kann `assigned_label` beeinflussen** — der Intent trägt keine Labels (§ 2.3), der Kern liest `object.labels` für `emit` nicht; ein Fakt „diese Ausgabe verwendet die geheimen Eingaben nicht“ existiert nicht als Ausnahme (R.5.5).
- Falscher Zweck, fehlende Rechte, unzulässige Empfänger, fehlende `emit`-Regel: `deny`/`indeterminate` wie § 4.4, mit Remedies § 2.8.

### 4.6 Aktionsfreigabe-Zweig (eigener Regelzweig, B.5 Schritt 6)

`decide` mit vorgelegter Aktionsfreigabe (`--release`/`--stand`) ist nie ein stiller Fallback: normaler Zweig und Freigabe-Zweig sind getrennte Entscheidungen.

1. Struktur: Release (§ 2.6) und Stand (§ 2.7) werden als geschlossene Schemas validiert (Eingabefehler, Exit 2); `kind: offenlegungsfreigabe` oder Operation ∉ {`emit`, `store`, `transfer`} → `unsupported` (Exit 3). Snapshot/Intent-Kohärenz wie § 2.3; Digest-Pflicht wie § 4.5.
2. `workspace_contract_valid` bleibt Prämisse (`workspace_invalid`): ein GO belebt keinen ungültigen Vertrag.
3. Release-Prüfungen in fester Ordnung, jede Verletzung ein Blocker: Call-Hash neu berechnet aus Intent (mit Operation) + Snapshot-Digest, Vergleich mit `release.call_hash` → `release_call_mismatch`; Fenster `valid_from ≤ as_of ≤ valid_until` → `release_not_yet_valid`/`release_expired`; `nonce ∈ stand.consumed` → `release_nonce_consumed`; `release.scope ≠ stand.scope` → `release_scope_mismatch`; `release.authority ∉ 𝒪` → `release_authority_unknown`.
4. Permit nur ohne Befund: `decision: permit`, `rule` = Operation des Intents, bei `emit` `assigned_label` = B_W (die Aktionsfreigabe ändert λ(y) nicht — Lockerung wäre Offenlegungsfreigabe), `checked_label` wie § 2.4, `proof: null`, Remedies `null`, plus `release`-Objekt als deklarative Wirkung:
   ```json
   {
     "release_id": "<id>",
     "nonce": "<nonce>",
     "stand_ref": "<stand_id>@<version>",
     "stand_version_after": <version + 1>,
     "call_hash": "<hex>"
   }
   ```
   Der Ausführer muss den Verbrauch über `advance` committen, **bevor** die Wirkung eintritt (commit-before-effect, B.8, PACE-Nonce); zwei konkurrierende Ausführungen verliert genau eine am Versionsabgleich (§ 2.7).
5. Befunde → `deny` mit Remedies § 2.8 (Aktionsfreigabe-Zweig: ein `aktionsfreigabe`-call-Eintrag je Release-Blocker mit neu berechnetem korrektem `call_hash`; `workspace_invalid` → `neuer_raum`).

### 4.7 Regelzweig `store` — Speicherung (RFC R.5.6)

Ein schon erzeugtes Objekt y wird in einen dauerhaften Speicher gelegt; die Umgebung des Snapshots ist der Speicher (ihre Beobachter sehen den Bestand). Der Vermittler ruft `store` **nach** einem `emit`-Permit für dasselbe Objekt; `emit` ordnet λ(y) zu, `store` erhält es. Fehlt allen Bindungen eine `store`-Regel, ist jedes Speichern verboten (`missing_operation_rule`, B.4) und nur mit Aktionsfreigabe für den exakten Call zulässig.

- **Snapshot-Voraussetzung:** wie § 4.5 (`output_content_digest`, `classification: classified`). `object.labels` ist λ(y), das Ausgabelabel aus der `emit`-Entscheidung.
- **Prüflabel:** `checked_label` = λ(y) (sortiert), nicht B_W.
- Prämissen (feste Ordnung, § 2.5-Baum):
  1. `workspace_contract_valid` — Verstoß → `workspace_invalid`
  2. `has_operation_right` — wie § 4.5
  3. `audit_path_ready` — wie § 4.5
  4. `environment_observers_complete` — wie § 4.5 (nur Beleg)
  5. `label_preservation` — B_W ⊆ λ(y); Verstoß → `label_not_preserved` (Speichern entfernt keine Bindung)
  6. `recipient_inclusion` — ρ_Γ(Speicher) ⊆ R_Γ(λ(y)); Verstoß → `recipient_not_allowed`
  7. `binding_condition(b)` — für **jede** Bindung b ∈ λ(y) in sortierter Ordnung: Auswertung von `bindings[b].operations["store"]` (fehlt → **verbietend**, `missing_operation_rule`)
- Permit-Ausgabe: `decision: permit`, `rule: store`, `content_digest`, Beweisbaum § 2.5; kein `assigned_label`.
- Deny/indeterminate wie § 4.4, Remedies § 2.8 (wie `emit`, inklusive `aktionsfreigabe` scope `call` mit dem `store`-Call-Hash).

### 4.8 Regelzweig `transfer` — Übergabe (RFC R.5.6)

Ein schon erzeugtes Objekt y wird an ein Ziel Z übergeben, etwa als Anfrage an einen externen Dienst; die Umgebung des Snapshots ist das Ziel (ihre Beobachter sehen y, einschließlich der weiteren Verarbeitung beim Empfänger). Entschieden wird Erlaubt_Γ(Übergabe(y, Z), λ(y)). Der Vermittler ruft `transfer` **nach** einem `emit`-Permit für dasselbe Objekt; `emit` ordnet λ(y) zu, `transfer` erhält es. Die Form ist die von `store` (§ 4.7), nur mit den `transfer`-Regeln der Bindungen. Fehlt einer Bindung von λ(y) die `transfer`-Regel, ist die Übergabe verboten (`missing_operation_rule`, B.4).

- **Snapshot-Voraussetzung:** wie § 4.7 (`output_content_digest`, `classification: classified`, `object.labels` = λ(y)).
- **Prüflabel:** `checked_label` = λ(y) (sortiert), nicht B_W.
- Prämissen (feste Ordnung, § 2.5-Baum):
  1. `workspace_contract_valid` — Verstoß → `workspace_invalid`
  2. `has_operation_right` — wie § 4.5
  3. `audit_path_ready` — wie § 4.5
  4. `environment_observers_complete` — wie § 4.5 (nur Beleg)
  5. `label_preservation` — B_W ⊆ λ(y); Verstoß → `label_not_preserved`. Auch ein unveränderter Payload trägt die Auswahlentscheidung des Raums (R.5.6: das Übergabeereignis trägt mindestens B_W).
  6. `recipient_inclusion` — ρ_Γ(Ziel) ⊆ R_Γ(λ(y)); Verstoß → `recipient_not_allowed`
  7. `binding_condition(b)` — für **jede** Bindung b ∈ λ(y) in sortierter Ordnung: Auswertung von `bindings[b].operations["transfer"]` (fehlt → **verbietend**, `missing_operation_rule`)
- Permit-Ausgabe: `decision: permit`, `rule: transfer`, `content_digest`, Beweisbaum § 2.5; kein `assigned_label`.
- Deny/indeterminate wie § 4.4, Remedies § 2.8 (wie `store`, inklusive `aktionsfreigabe` scope `call` mit dem `transfer`-Call-Hash). Die Aktionsfreigabe überbrückt wie bei `emit` auch `recipient_not_allowed`; ob ein unzulässiger Empfänger nach R.5.7 stattdessen eine Offenlegungsfreigabe verlangt, ist offen (Ticket #298, Kommentar).
- Ein Zielarbeitsraum (zusätzlich dessen Aufnahmeregel, R.5.6) ist nicht Teil dieser Lieferung (Ticket #270).

## 5. `verify` — unabhängiger Ableitungsprüfer

Der Prüfer **ruft `derive` niemals auf** und **glaubt kein `permit`**. Er prüft den vorgelegten Baum gegen genau die mitgeführte Registry, den mitgeführten Snapshot und Intent (RFC B.2, B.5, D.4 `ableitungspruefer`).

Prüfschritte (Befunde werden gesammelt, soweit die Prüfung nicht strukturell abbricht; ≥1 Befund → `invalid`):

1. **Struktur:** Proof-Schema (falsches/fehlerhaftes Proof-Datensatzformat ist ein Eingabefehler, Exit 2 — kein `invalid`-Urteil), Referenzkohärenz (`registry_ref`, `snapshot_ref`, `intent_ref` müssen exakt den mitgeführten Eingaben entsprechen — fremder Snapshot → `snapshot_mismatch`, fremde Registry → `registry_mismatch`, fremder Intent → `intent_mismatch`), Regel ∈ {`admit`, `emit`, `store`, `transfer`} (andere → `unsupported_rule`), Regel = Operation des Intents (sonst `rule_mismatch`: `store`- und `transfer`-Bäume haben dieselbe Form, ein Baum belegt nur die Operation, für die er abgeleitet wurde).
2. **Validierungslabel:** `checked_label` muss **mengengleich** dem aus Snapshot und Regel neu berechneten Prüflabel sein (sortierter Vergleich): `workspace.bindings` für `admit`/`emit`, `object.labels` für `store`/`transfer`. Verkürztes Validierungslabel → `checked_label_mismatch`. Eine ausgelassene Raumbindung darf nicht durch einen verkürzten Baum verschwinden (RFC B.5).
3. **Required-Set:** Die Prämissenmenge wird **aus dem Regeltyp gegen den Snapshot rekonstruiert** (RFC B.5), je Regel verschieden: für `admit` die acht festen Prämissen (§ 4.3), für `emit` die sieben festen Prämissen (§ 4.5: `workspace_contract_valid`, `has_operation_right`, `audit_path_ready`, `environment_observers_complete`, `recipient_inclusion`, `label_assignment`, ohne `not_quarantine`/`has_object_access_right`/`label_inclusion`), für `store` und `transfer` die sieben festen Prämissen (§ 4.7, § 4.8: wie `emit`, aber `label_preservation` statt `label_assignment`), jeweils plus je `binding_condition` für jedes Element des Prüflabels (nach Schritt 2 mengengleich `checked_label`); geprüft werden die Ausdrücke der Regel des Baums. Eine Prämisse erfüllt ihren Slot **nur mit der zugeordneten Art aus §2.5** (name↔kind-Bindung; z. B. `label_inclusion`/`label_assignment` nur als `kind: "computed"`, `has_operation_right` nur als `kind: "fact"`); abweichende Art → `unknown_premise`. Fehlt eine → `missing_required_premise`; unbekannte zusätzliche Prämisse → `unknown_premise`. `binding_condition`-Slots werden nur aus `kind: "condition"`-Prämissen erfüllt.
4. **Faktprämissen:** Der Fakt muss im Snapshot existieren (`fact_missing`) und der behauptete `value` muss mit dem Snapshot-Wert übereinstimmen (`fact_value_mismatch`). `workspace_contract_valid` wird gegen `workspace.valid` geprüft.
5. **`not_quarantine`:** Klassifikation im Snapshot muss `classified` sein, sonst `object_quarantine`.
6. **`label_inclusion`** (nur `admit`): neu berechnet aus Snapshot: λ(x) ⊆ `checked_label`, sonst `label_inclusion_false`. Behauptete `object_labels`/`checked_label`-Werte in der Prämisse müssen mit den berechneten übereinstimmen, sonst ebenfalls `label_inclusion_false`. **`label_assignment`** (nur `emit`): neu berechnet; `assigned_label` muss mengengleich `workspace.bindings` (= `checked_label`) sein, sonst `label_assignment_false`; behauptete Werte müssen übereinstimmen. **`label_preservation`** (nur `store`, `transfer`): neu berechnet B_W ⊆ λ(y); behauptete `workspace_bindings`/`checked_label` müssen übereinstimmen, sonst `label_preservation_false`.
7. **`recipient_inclusion`:** neu berechnet aus Registry: Umgebung ⊆ R_Γ(`checked_label`), sonst `recipient_inclusion_false`; behauptete Empfängerlisten müssen übereinstimmen, sonst ebenfalls `recipient_inclusion_false`.
8. **`binding_condition(b)`:** Die in der Prämisse behauptete `expression` muss **exakt** (strukturelle Gleichheit) der Registry-Expression der Bindung für die Regel des Baums (`admit`-, `emit`-, `store`- bzw. `transfer`-Eintrag) entsprechen, sonst `expression_mismatch` (ein gefälschter, leichterer Ausdruck ist ein Angriff). Hat die Bindung **keinen** Eintrag für die Regel, feuert ebenfalls `expression_mismatch`; `fact_refs`-Vergleich und Neuauswertung werden in diesem Fall übersprungen (kein `fact_refs_mismatch`, kein `condition_false`/`condition_unknown`, kein Crash). Der Ausdruck wird gegen die Snapshot-Fakten **neu ausgewertet**: Ergebnis `false` → `condition_false`; `unknown` → `condition_unknown`. Der behauptete `value` muss `true` sein, sonst `condition_false`. `fact_refs` müssen der aus der **Registry-Expression** (dem autoritativen AST, nicht dem behaupteten) bestimmten Feldmenge entsprechen, sonst `fact_refs_mismatch` — verify vertraut dem Baum die Abhängigkeiten nicht.
9. **`conclusion`:** `permit` ist nur gültig, wenn **alle** neu geprüften Prämissen `true` ergeben. Meldet ein prädikatsbezogener Schritt (4–8) einen Befund, wird **zusätzlich** `conclusion_mismatch` gemeldet (die `permit`-Behauptung ist nicht getragen). Melden ausschließlich die strukturellen Schritte 1–3 einen Befund, endet die Prüfung **sofort** mit allen Befunden des ersten befundhaltenden Schritts — auch spätere strukturelle Schritte laufen dann nicht mehr, und die Prämissen werden nicht weiter geprüft. `conclusion ≠ permit` → `conclusion_unsupported` (L1 prüft nur Permit-Bäume).

Ausgabe: `{"result": "valid"}` bzw. `{"result": "invalid", "reasons": [{"code": ..., "binding": ..., "fact": ...}]}` (Reasons sortiert in fester Prüfordnung). Strukturfehler in den Eingaben sind Eingabefehler (Exit 2), keine `invalid`-Urteile.

## 6. Kanonische Darstellung & strenge JSON-Basis

- **Eigener strenger JSON-Parser** (stdlib-only, keine Runtime-Abhängigkeit): verwirft doppelte Schlüssel (mit JSON-Pfad in der Fehlermeldung), nachgestellte Kommas, `NaN`/`Infinity`, führende Pluszeichen, untermengte Literale; Zahlen nur Integer und Floats; Unicode gemäß RFC-8259-Sicht (kein `sort_keys`-Beweis, RFC F.4 — unsere Kanonisierung ist eine eigene, versionierte, eindeutige Darstellung).
- **Kanonischer Encoder:** Objektschlüssel aufsteigend sortiert (bytewise UTF-8), 2-Space-Einrückung, LF-Zeilenenden, keine Leerzeilen, finales Newline. Mengen (Labels, Beobachter, `fact_refs`, `reasons`) sortiert aufsteigend, duplikatfrei. Prämissenliste in fester Reihenfolge §4.3. Ganzzahlen dezimal ohne Vorzeichennullen. **Floats kommen in keiner L1-Ausgabe vor** (Fixtures nutzen ausschließlich Integer, Strings, Booles, Arrays, Objekte).
- Tests vergleichen strukturgleicher Daten über `canonical(parse(x)) == canonical(parse(y))`; CLI-Determinismus byte-identisch über zwei Aufrufe.

## 7. CLI `komki-policy` (Escript, null Runtime-Deps)

```bash
komki-policy validate --registry <registry.json>
komki-policy decide   --registry <r.json> --snapshot <s.json> --intent <i.json> \
                      [--release <g.json> --stand <st.json>]   # Freigabe-Zweig § 4.6
komki-policy verify   --registry <r.json> --snapshot <s.json> --intent <i.json> --proof <p.json>
komki-policy advance  --stand <st.json> --proposal <p.json>   # atomarer Standübergang § 2.7
komki-policy plan     # → unsupported
```

- `--release` und `--stand` sind nur gemeinsam gültig (einzeln übergeben: `usage`, Exit 2). `advance --proposal` nimmt das `release`-Objekt einer Permit-Entscheidung (§ 4.6) als eigenständige Datei.
- Exit-Codes: `0` Erfolg (auch `deny`/`indeterminate`/`invalid`/`refused` sind legitime Ergebnisse); `1` `verify` hat Beweis verworfen **oder** `advance` hat den Übergang abgelehnt (`stand_version_conflict`/`nonce_already_consumed` — die Ausgabe ist dann `{"result": "refused", ...}`); `2` Eingabefehler (Parse/Validierung/Kohärenz, mit strukturierten Fehlerdetails auf stdout); `3` `unsupported` (nicht implementierter Regelzweig, inkl. Release-`kind: offenlegungsfreigabe`); `4` unerwarteter interner Fehler — fällt **niemals** auf `permit` zurück.

## 8. Erwartungsfälle (synthetisch; erwartete Prämissen unabhängig vom Produktionscode festgelegt)

Alle Fälle nutzen `priv/fixtures/registry.json` (Bürgerfall-Bindung `buergerfall-4711@1` mit `admit`- und `emit`-Bedingung: Zweck passt **und** Datei/Ausgabe gehört zum genehmigten Fallumfang; Lizenzbindung `lizenz-namensnennung@1` mit `admit: true`, `emit: true` und weitem Empfängerkreis; Bindung `nur-start-test@1` **ohne** `admit`-Eintrag, nur `start` — kein `emit`; Umgebungen `lokale-fallverarbeitung@1` mit Beobachtern `{nutzende-person, lokale-fallverarbeitung}` und `recherche-webdienst@1` mit Beobachtern `{nutzende-person, webdienst-x}`; `fact_fields` um `output_content_digest: string` erweitert; eine registrierte Transformation `presse-auszug@1`: `input_labels: [lizenz-namensnennung@1]`, `output_labels: []`).

| Fall | Kurzfassung | Erwartung |
|---|---|---|
| `case_permit` | Öffentliche Datei (λ=∅), Scope-Fakt `true`, Zweck passt, Basis alles `true`, Empfänger `{nutzende-person, lokale-fallverarbeitung}` = R_Γ(B_W) | **permit**, `checked_label` = `[buergerfall-4711@1]`, vollständiger Baum §4.3 |
| `case_deny` | Wie permit, aber Scope-Fakt `false` (D.1: Labelinklusion und Empfängertest erfüllt, Bedingung falsch) | **deny**, Blocker `binding_condition_false` (buergerfall-4711@1) |
| `case_deny_licensed` | Objekt λ=`[lizenz-namensnennung@1]` (eigene Lizenzregel `true` erfüllt), B_W=`[buergerfall-4711@1, lizenz-namensnennung@1]`, Scope `false` — nur wer λ(x) statt B_W prüft, würde erlauben | **deny**, Blocker `binding_condition_false` (buergerfall-4711@1), `checked_label` = beide Bindungen |
| `case_indeterminate` | Wie permit, Scope-Fakt fehlt (fehlende, nicht als falsch bekannte Belege, D.1) | **indeterminate**, `missing_evidence` → Fakt `input_in_approved_case_scope` (Bedingung `unknown`) |
| `case_quarantine` | Objekt `classification: quarantine`, λ=`[]` — Quarantäne ist kein leeres Label (RFC 2.5, D.4) | **deny**, Blocker `object_quarantine` |
| `case_deny_no_basis` | Öffentlicher Raum B_W=∅, öffentliche Datei, `has_operation_right: false` (D.4 `leeres-label`: ohne Basisrechte erlaubt nichts) | **deny**, Blocker `basis_right_false` |
| `case_unsupported` | Intent `operation: start` | **unsupported** (keine Decision, Exit 3) |
| `case_deny_recipient` | B_W=`[buergerfall-4711@1, lizenz-namensnennung@1]`, λ=`[lizenz-namensnennung@1]` (eigene Regel `true` erfüllt), Umgebung `recherche-webdienst@1` mit `webdienst-x` ∉ R_Γ(B_W) (D.4 `empfaengergrenze`: objektbezogenes `true` schaltet keinen unzulässigen Empfänger frei) | **deny**, Blocker `recipient_not_allowed`, `checked_label` = beide Bindungen |
| `case_deny_missing_rule` | B_W=`[nur-start-test@1]` (Bindung ohne `admit`-Eintrag), alle Fakten `true` (B.4: fehlende Operationsregel ≠ leere Konjunktion `true`) | **deny**, Blocker `missing_operation_rule` (nur-start-test@1) |
| `case_indeterminate_env_false` | Wie permit, aber `environment_observers_complete: false` (D.4 `unvollstaendige-umgebung`) | **indeterminate**, `missing_evidence` → `recipients_unproven` / `environment_observers_complete` |
| `case_indeterminate_env_missing` | Wie permit, aber Fakt `environment_observers_complete` fehlt (kein Leer-Default, §2.2) | **indeterminate**, `missing_evidence` → `recipients_unproven` / `environment_observers_complete` |
| `case_deny_precedence` | Scope-Fakt `false` **und** `has_operation_right` fehlt gleichzeitig (B.5: bekannt-falsch schlägt unbekannt) | **deny**, Blocker `binding_condition_false`, `missing_evidence: null` |
| `case_deny_multi_blockers` | Quarantäne-Klassifikation **und** `workspace.valid: false` gleichzeitig; alle übrigen Prämissen true (§4.4: alle verbietenden Befunde, Reihenfolge §4.3) | **deny**, Blocker `[object_quarantine, workspace_invalid]` |
| `case_indeterminate_multi_evidence` | `has_operation_right` **und** `audit_path_ready` fehlen gleichzeitig; alle übrigen Prämissen true (§4.4: alle unbekannten Prämissen, Reihenfolge §4.3) | **indeterminate**, `missing_evidence` = zwei `missing_fact`-Einträge in Ordnung (`has_operation_right`, `audit_path_ready`) |
| `case_deny_label_not_included` | Objekt λ=`[lizenz-namensnennung@1]`, B_W=`[buergerfall-4711@1]` — Label außerhalb der Raumbindungen; Empfänger und Bedingungen erfüllt (Angriffsseite des label_inclusion-Tests) | **deny**, Blocker `label_not_included` |

**Remedy-Pins:** die `expected_decision.json` aller `deny`/`indeterminate`-Fälle tragen ab v2 den `remedies`-Katalog gemäß § 2.8 in § 2.8-Ordnung; die Permit-Fälle tragen `"remedies": null`. Die `admit`-Fälle führen **keinen** `aktionsfreigabe`-call-Eintrag (bewusste Lücke, siehe § 9).

### 8.1 `emit`-Fälle (Erzeugen, § 4.5)

| Fall | Kurzfassung | Erwartung |
|---|---|---|
| `case_emit_permit` | Raum B_W=`[buergerfall-4711@1]`, Zweck passt, Scope-Fakt `true`, Basis `true`, Empfänger ok, Digest vorhanden | **permit**, `rule: emit`, `assigned_label = [buergerfall-4711@1]`, `content_digest`-Echo, Baum § 4.5 |
| `case_emit_deny_purpose` | Wie permit, aber `purpose: anderer-zweck` → `emit`-Bedingung falsch | **deny**, Blocker `binding_condition_false` (buergerfall-4711@1); Remedies: `fakt_nachreichen [purpose]`, `neuer_raum`, `aktionsfreigabe (call)` |
| `case_emit_indeterminate` | Wie permit, aber `input_in_approved_case_scope` fehlt | **indeterminate**, `missing_evidence` → Fakt; Remedies: `fakt_nachreichen`, `neuer_raum` — kein GO |
| `case_emit_no_rule` | B_W=`[nur-start-test@1]` (Bindung ohne `emit`-Eintrag), Fakten `true` | **deny**, Blocker `missing_operation_rule` (nur-start-test@1); Remedies inkl. `aktionsfreigabe (call)` |
| `case_emit_recipient` | Umgebung `recherche-webdienst@1`: `webdienst-x` ∉ R_Γ(B_W) | **deny**, Blocker `recipient_not_allowed`; Remedies inkl. `aktionsfreigabe (call)` |
| `case_emit_opaque` | Zwei Snapshot-Datensätze, identisch bis auf `output_content_digest` (zwei unterschiedliche Byte-Mengen) und die zwingend verschiedene `snapshot_id` | Beide **permit**; Entscheidungen identisch modulo `content_digest` und `snapshot_ref`; `assigned_label` bleibt B_W — Labels ohne Inhaltsblick (R.5.5) |
| `case_emit_workspace_invalid` | `workspace.valid: false` | **deny**, Blocker `workspace_invalid`; Remedies: nur `neuer_raum` — kein GO-Eintrag |

### 8.2 Aktionsfreigabe-Fälle (§ 4.6, mit Offenlegungsstand `stand.json` je Fall)

| Fall | Kurzfassung | Erwartung |
|---|---|---|
| `case_release_permit` | Kontext von `case_emit_deny_purpose`, aber gültiges GO: korrekter `call_hash`, Fenster enthält `as_of`, Nonce frisch, `scope`/`authority` ok | **permit**, `proof: null`, `assigned_label = B_W`, `release`-Objekt mit `stand_ref`/`stand_version_after`; `advance` liefert Stand `version + 1` mit `nonce → release_id` |
| `case_release_swap` | GO trägt `call_hash` für **andere Bytes** (Digest getauscht) — Inhaltstausch | **deny**, Blocker `release_call_mismatch` (B.9: Inhaltstausch erkannt); Remedies: `aktionsfreigabe (call)` mit neu berechnetem Hash |
| `case_release_replay` | Nonce steht bereits in `stand.consumed` | **deny**, Blocker `release_nonce_consumed` |
| `case_release_expired` | `as_of > valid_until` | **deny**, Blocker `release_expired` |
| `case_release_not_yet_valid` | `as_of < valid_from` | **deny**, Blocker `release_not_yet_valid` |
| `case_release_scope` | `release.scope ≠ stand.scope` | **deny**, Blocker `release_scope_mismatch` |
| `case_release_authority` | `authority` ∉ Registry-Beobachter | **deny**, Blocker `release_authority_unknown` (fremde Zuständigkeit) |
| `advance`-CAS | Dasselbe Proposal zweimal: erster Commit `stand@v → stand@v+1`; zweiter Commit gegen `stand@v+1` | zweiter `refused` mit `stand_version_conflict` (CLI: `{"result": "refused"}`, Exit 1) — zwei konkurrierende Ausführungen desselben GOs können nicht beide erfolgreich committen (B.8) |

### 8.3 Abnahmemetriken (Tests als Entscheidungsbeweis)

- **HITL load:** ein Szenario-Test skriptet die erlaubten menschlichen GOs entlang der Katalog-Fortsetzungen: Quarantäne-Objekt braucht genau **ein** Objekt-Level-GO (Erstklassifikation über eine neue Snapshot-Version), danach laufen wiederholte Aufnahmen desselben Objekts ohne weiteres GO; die `fakt_nachreichen`-Pfade brauchen null GOs. Die GO-Anzahl wird im Test gezählt und gegen den Schwellenwert geprüft.
- **TCR@k:** über den Szenario-Korpus der Fixtures folgt der Test der billigsten Fortsetzung aus dem Katalog (deterministische Skript-Spur: Fakt nachreichen → neuer Raum → GO) und misst, innerhalb wievieler Schritte (k) Permit erreicht wird; die Quote wird berechnet und gegen den Schwellenwert geprüft. „Alles zu verweigern reicht nicht“ wird damit messbar. Die konkreten Messwerte werden im Abschlusskommentar des Tickets berichtet.

Ungültige Eingaben (Eingabefehler, keine Entscheidungen):

| Fixture | Erwartung |
|---|---|
| `invalid/registry_duplicate_key.json` | Parse-Fehler `duplicate_json_key` |
| `invalid/registry_unknown_field.json` | Validierungsfehler `unknown_field` |
| `invalid/registry_unknown_expression.json` | Compile-Fehler `unsupported_expression` (Sprachumfang wird nicht versteckt) |
| `invalid/snapshot_unknown_binding_ref.json` | Validierungsfehler `unknown_binding_reference` |
| `invalid/intent_version_mismatch.json` | Kohärenzfehler `intent_snapshot_mismatch` |
| `invalid/release_unknown_field.json` | Validierungsfehler `unknown_field` (Release-Schema § 2.6) |
| `invalid/release_bad_window.json` | Validierungsfehler `invalid_window` (`valid_from > valid_until`) |
| `invalid/emit_digest_missing_intent.json` + `invalid/emit_digest_missing_snapshot.json` | `decide` auf `emit` ohne Fakt `output_content_digest` → Eingabefehler `emit_digest_missing` (§ 4.5) |

Manipulierte Beweise (alle von `verify` zu verwerfen):

| Fixture | Verifikationskontext | Erwartung |
|---|---|---|
| `case_permit/proof_valid.json` | case_permit | `valid` (Referenzbaum, handgeschrieben aus §4.3) |
| `proofs/proof_missing_binding_condition.json` | case_permit | `invalid` → `missing_required_premise` (Raumbindung weglassen) |
| `proofs/proof_checked_label_shortened.json` | case_permit | `invalid` → `checked_label_mismatch` (Validierungslabel ∅, Baum „prüft" nur λ(x)) |
| `proofs/proof_false_condition.json` | **case_deny** (Scope `false`) | `invalid` → `condition_false` + `conclusion_mismatch` (gefälschte Bedingung `true`) |
| `proofs/proof_missing_fact_condition.json` | **case_indeterminate** (Scope fehlt) | `invalid` → `condition_unknown` + `conclusion_mismatch` (Beweis behauptet `true` ohne Fakt) |
| `proofs/proof_foreign_snapshot.json` | case_permit | `invalid` → `snapshot_mismatch` (fremde Snapshot-Referenz) |
| `proofs/proof_false_fact_value.json` | **case_deny_no_basis** (`has_operation_right: false`) | `invalid` → `fact_value_mismatch` + `conclusion_mismatch` (gefälschte Faktquelle: `true` behauptet; D.4 `leeres-label`-Gegenprobe) |
| `proofs/proof_easier_expression.json` | case_permit | `invalid` → `expression_mismatch` + `fact_refs_mismatch` + `conclusion_mismatch` (leichterer Ausdruck `true` statt Registry-Expression) |
| `proofs/proof_disguised_label_inclusion.json` | **case_deny_label_not_included** (λ ⊄ B_W) | `invalid` → `unknown_premise` (art-getarnte Prämisse erfüllt ihren Slot nicht — der Prüfer lässt sich nicht umgehen) |
| `proofs/proof_admitless_condition.json` | **case_deny_missing_rule** (Bindung ohne `admit`) | `invalid` → `expression_mismatch` + `conclusion_mismatch` (Neuauswertung übersprungen, kein Crash) |
| `proofs/proof_emit_valid.json` | case_emit_permit | `valid` (Referenzbaum § 4.5, handgeschrieben) |
| `proofs/proof_emit_missing_label_assignment.json` | case_emit_permit | `invalid` → `missing_required_premise` (Zuordnungsprämisse weglassen — λ(y) soll durch den verkürzten Baum verschwinden) |
| `proofs/proof_emit_forged_assignment.json` | case_emit_permit | `invalid` → `label_assignment_false` (behauptet ein leichteres `assigned_label` als B_W) |

Die erwarteten Verify-Ergebnisse (Kontext-Snapshot/Intent je Beweis, `result` und **vollständige** `reasons`-Liste in fester Prüfordnung §5) liegen maschinenlesbar in `priv/fixtures/proofs/verify_expectations.json` (`komki-verify-expectations/1`). Pfade sind relativ zu `priv/fixtures/`.

Testorakel: `priv/fixtures/expressions/evaluate_expectations.json` (`komki-expression-expectations/1`) pinnt die dreiwertige Auswertung je B.4-Grammatikbaustein inklusive der Grenzfälle (leere `all` → `true`, leere `any` → `false`, unknown-Propagation in `all`/`any`, `member`/`subset`/`at_most` bei fehlendem Feld). Fakten dort sind reiner Auswerter-Input `{feld: {value}}` ohne Registry-Bindung; die Registry-Compile-Validierung wird separat über `invalid/` orakelt.

Kopplung derive↔Beweis (RFC A.7): Der `proof` von `derive(case_permit)` muss strukturgleich (kanonisch, §6) mit `case_permit/proof_valid.json` sein, und `verify` muss diesen Baum als `valid` bestätigen; ebenso `derive(case_emit_permit)` ↔ `proofs/proof_emit_valid.json`. Die deny/indeterminate-Orakel tragen `"proof": null` gemäß §2.4.

Testmanifeste (`expected_decision.json`, `expected_result.json`, `verify_expectations.json`, `evaluate_expectations.json`) sind test-only-Datensätze und unterliegen keiner der Laufzeit-Schemata aus §2.

Eingabe-Fixtures (Registry, Snapshots, Intents, `invalid/`) sind **bewusst nicht byte-kanonisch** sortiert (menschenlesbare Schlüsselordnung); §6-Kanonisierung gilt für Ausgaben und für Vergleiche (`canonical(parse())`). Der Kanonizitäts-Tripwire der Tests deckt entsprechend nur den byte-kanonisch gepinnten Teil des Korpus (Decision-, Proof- und Manifest-Dateien).

### 8.4 `store`-Fälle (Speicherung, § 4.7)

Die Fixture-Registry trägt dafür bei `lizenz-namensnennung@1` die Regel `store: true`; `buergerfall-4711@1` hat keine `store`-Regel.

| Fall | Kurzfassung | Erwartung |
|---|---|---|
| `case_store_permit` | B_W = λ(y) = `[lizenz-namensnennung@1]`, Speicher `lokale-fallverarbeitung@1` | **permit**, `rule: store`, Beweisbaum mit `label_preservation`; `verify` bestätigt |
| `case_store_no_rule` | B_W = λ(y) = `[buergerfall-4711@1]` (keine `store`-Regel) | **deny**, Blocker `missing_operation_rule`; Remedies `neuer_raum`, `aktionsfreigabe (call)` mit `store`-Call-Hash |
| `case_store_wider_label` | B_W = `[lizenz-namensnennung@1]`, λ(y) = `[buergerfall-4711@1, lizenz-namensnennung@1]` | **deny**, Blocker `missing_operation_rule` (buergerfall-4711@1): entschieden wird unter λ(y), nicht unter B_W |
| `case_store_label_not_preserved` | B_W = `[lizenz-namensnennung@1]`, λ(y) = `[]` | **deny**, Blocker `label_not_preserved`; Remedies nur `neuer_raum` |
| `case_release_store_permit` | Kontext von `case_store_no_rule`, gültiges GO mit `operation: store` | **permit**, `rule: store`, `proof: null`, `release`-Objekt; ein GO mit dem `emit`-Hash desselben Objekts ergibt `release_call_mismatch` |

### 8.5 `transfer`-Fälle (Übergabe, § 4.8)

Die Fixture-Registry trägt dafür bei `lizenz-namensnennung@1` die Regel `transfer: true` und bei `buergerfall-4711@1` eine `transfer`-Regel mit derselben Bedingung wie `emit`; `nur-start-test@1` hat keine `transfer`-Regel.

| Fall | Kurzfassung | Erwartung |
|---|---|---|
| `case_transfer_permit` | B_W = λ(y) = `[lizenz-namensnennung@1]`, Ziel `recherche-webdienst@1` (`webdienst-x` ∈ R_Γ(λ(y))) | **permit**, `rule: transfer`, Beweisbaum mit `label_preservation`; `verify` bestätigt; derselbe Baum mit `rule: store` ergibt `rule_mismatch` |
| `case_transfer_recipient` | B_W = λ(y) = `[buergerfall-4711@1]`, Ziel `recherche-webdienst@1`, Bedingung erfüllt | **deny**, Blocker `recipient_not_allowed`; Remedies `neuer_raum`, `aktionsfreigabe (call)` mit `transfer`-Call-Hash |
| `case_transfer_no_rule` | B_W = λ(y) = `[nur-start-test@1]` (keine `transfer`-Regel) | **deny**, Blocker `missing_operation_rule` (nur-start-test@1) |
| `case_transfer_label_not_preserved` | B_W = `[lizenz-namensnennung@1]`, λ(y) = `[]` | **deny**, Blocker `label_not_preserved`; Remedies nur `neuer_raum` |
| `case_release_transfer_permit` | Kontext von `case_transfer_recipient`, gültiges GO mit `operation: transfer` | **permit**, `rule: transfer`, `proof: null`, `release`-Objekt; ein GO mit dem `store`-Hash desselben Objekts ergibt `release_call_mismatch` |

## 9. Explizite Nichtziele und bewusste Lücken

- Keine Ausführung, kein Connector, kein Schreibzugriff, kein Journal, kein Simulator, keine Zwei-Ausführungs-Prüfung. Kein Freigabe-Register im Kern: der Offenlegungsstand ist Eingabe/Ausgabe, `advance` ist ein reiner Übergang — das Führen des aktuellen Standes ist Vollzug außerhalb des Kerns.
- `plan`/`infer_plan`, `start`, Offenlegungsfreigabe (`kind`), Lockerungsprüfung/BerechtigtZurLockerung: `unsupported`. Zielarbeitsräume als `transfer`-Ziel (Aufnahmeregel des Ziels): Ticket #270. Die Aktionsfreigabe deckt in diesem Schnitt **nur `emit`, `store` und `transfer`** (verbindliche Wirkungen des Erzeugens, Speicherns und Übergebens); eine `admit`-Aktionsfreigabe ist bewusst nicht angeboten.
- Der Remedy-Katalog erzeugt keine Autorität: er ist reine Ausgabe, wird von keiner Eingabe akzeptiert und führt keine Fortsetzung aus. Registrierte Transformationen werden aufgezählt, aber nicht angewendet.
- Der Auswerter bewertet keine `source_kind`-Semantik (Herkunft ist Datenpflicht, nicht Gate).
- Keine produktiven Registry-Stände; alle Bezeichner sind synthetisch. Die Portal-/AZ-/RIS-Welt wird nicht referenziert.
- `verify` prüft nur Permit-Bäume der Zweige `admit`, `emit`, `store` und `transfer`; Freigabe-Permits tragen keinen Baum (§ 2.4); historische Audit-Prüfung (Anhang F) ist nicht Teil dieser Lieferung.
- Der `neuer_raum`-Katalog-Eintrag nennt notwendige Bedingungen, keine Pläne: der vollständige Planer `infer_plan` (B.6/B.7) bleibt `unsupported`; die kleinste Zuweisung kann trotzdem unzulässig sein.
