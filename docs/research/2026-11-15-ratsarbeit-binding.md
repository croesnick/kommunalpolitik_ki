# Bestandsaufnahme `ratsarbeit@1` (Ticket #592)

Stand: 2026-11-15. Grundlage sind Quelltext, Verträge, Schemas und synthetische Fixtures. Echte nicht-öffentliche RIS-Inhalte, Kassetten und PDFs wurden nicht geöffnet.

## Kurzfassung

`ratsarbeit@1` existiert heute als Bindung in der Label-Store-Vorlage und wird von der Engine schemakonform kompiliert. Es gibt aber keinen Raum, keinen Connector und keinen Abrufweg, der diese Bindung tatsächlich mit nicht-öffentlichen RIS-Inhalten füllt. Der öffentliche RIS-Connector filtert nicht-öffentliche TOPs ausdrücklich weg. Für einen eigenen Arbeitsraum `ratsarbeit@1` fehlen damit vor allem der Datenweg, die Operationsregeln für Ausgaben und die Verbindung zum Startvertrag/Journal.

## Vorhanden

### Label-Store

- `KomkiMediator.Templates.label_store_seed/0` führt `ratsarbeit@1` als Bindung: Bezeichnung „Nichtöffentliche Ratsunterlagen“, Leser `nutzende-person` und `pi-agent`, `admit` genau dann, wenn `purpose == "mandat"`; keine `emit`-, `transfer`- oder `store`-Regel, keine Lockerungsbefugnis (`apps/komki_mediator/lib/komki_mediator/templates.ex:198-201`).
- Das Importformat `komki-label-store/2` ist geschlossen und validiert Bindungen über `KomkiPolicy.Registry.compile/1`; die Store-Zusatzfelder (`bezeichnung`, `geltungsbereich`, `verantwortliche_stelle`, `auflagen`, `relaxation_authorities`) prüft der Store lokal (`apps/komki_cli/lib/komki_cli/label_store.ex:277-294`, `:366-374`, `:442-454`).
- Die SQLite-Ablage hat eine `bindings`-Tabelle mit Lesern, Operationen, Auflagen und Lockerungsbefugnissen (`apps/komki_cli/lib/komki_cli/label_store.ex:116-126`); der Import ist unveränderlich, kanonisch identischer Re-Import ein No-op (`:156-167`).
- Die Engine-Projektion des Seeds enthält `ratsarbeit@1` unverändert; der Export ist `komki-registry/2` (`apps/komki_mediator/lib/komki_mediator/templates.ex:249-261`).

### Policy-Engine

- Das Bindungsschema ist generisch und deckt `readers`, `operations` und `relaxation_authorities` ab (`apps/komki_policy/lib/komki_policy/registry.ex:25`). Zulässige Operationen sind `start`, `admit`, `emit`, `transfer`, `store` (`:29`); fehlt eine Regel, ist die Operation verbietend (`apps/komki_policy/CONTRACT.md:59-61`).
- `ratsarbeit@1` kompiliert mit `admit`-Bedingung und leeren Lockerungsbefugnissen (`apps/komki_policy/test/komki_policy/registry_test.exs:82-106`, Fixture `apps/komki_policy/priv/fixtures/registry.json:105-123`).
- Die Testwelt der Offenlegungsfälle nutzt `ratsarbeit@1` als Beispiel für eine Bindung ohne Befugnis; erwartet werden `recipient_not_allowed` und `missing_operation_rule` ohne GO-Angebot (`apps/komki_policy/CONTRACT.md:615-616`, Fixtures unter `apps/komki_policy/priv/fixtures/case_offenlegung_*`).
- Die Ausgabearten sind geschlossen; `sitzungsmappe` ist deklariert, aber nicht entscheidbar. Nur `readers` × `ratsprojekte-essenz` hat einen entscheidbaren Zweig (`apps/komki_policy/lib/komki_policy/registry.ex:31-40`, `apps/komki_policy/CONTRACT.md:60`).

### Connector und Manifest

- `KomkiConnector.Manifest` kennt die Connectoren `documents`, `ratsprojekte`, `ris`, `vault`, `web` (`apps/komki_connector/lib/komki_connector/manifest.ex:42`). Kein Manifest importiert `ratsarbeit@1`.
- Der RIS-Connector importiert ausschließlich `ris-oeffentlich@1` (`apps/komki_connector/lib/komki_connector/manifest.ex:161`) und filtert nicht-öffentliche TOPs vor Zählung und Ausgabe (`apps/komki_connector/CONTRACT.md:167-193`). Der Login über `RIS_ZUGANG` ändert daran nichts (`:183-190`).
- Der Dokument-Connector führt nur `admit_document` aus; seine `import_labels` sind leer, Labels und Umgebung spielen für die Entscheidung keine Rolle (`apps/komki_connector/lib/komki_connector/manifest.ex:69-92`).
- Die Γ-Konventionen des Connector-Vertrags (§7) führen nur `ris-oeffentlich@1`, `web-oeffentlich@1`, `vault-oeffentlich@1` und `vault-vertraulich@1`; `ratsarbeit@1` fehlt in der Tabelle (`apps/komki_connector/CONTRACT.md:304-334`). §10 nennt die Vereinheitlichung von `admit_document` mit `workspace_bindings` ausdrücklich als offen (`:372`).

### Raumvertrag und `admit_document`

- `room.json` kann `workspace_bindings` als B_W tragen; fehlt das Feld, gibt es keine Raumdokumente (fail-closed) (`apps/komki_mediator/lib/komki_mediator/room.ex:8-13`, `:105`, `:199-204`).
- `admit_document` löst nur Objekte vom Typ `document` auf und entscheidet die Aufnahme gegen B_W (`apps/komki_mediator/lib/komki_mediator/room.ex:130-137`, `:190-204`; `apps/komki_mediator/lib/komki_mediator/gate.ex:85-143`, `:180-235`).
- Die Default-Räume der Vorlage sind `recherche`, `vertraulich`, `projektraum` und `fraktion`; `ratsarbeit@1` kommt in keiner B_W-Liste vor (`apps/komki_mediator/lib/komki_mediator/templates.ex:304-347`). Der Default-Raum `recherche` hat `purpose = "offene-recherche"`, nicht `mandat` (`:387-391`).
- Der Startvertrag kann `bindings` als B_W tragen; `ratsarbeit@1` steht dort nur als Beispiel in der Modulbeschreibung (`apps/komki_cli/lib/komki_cli/start_contract.ex:11-18`, `:20-33`).

### PDR und Journal

- PDR `komki-pdr/5` ist generisch und trägt unter anderem `rule`, `call_id`, `checked_label`, `assigned_label`, `authorized_by` und `offenlegung` (`apps/komki_mediator/lib/komki_mediator/pdr.ex:1-51`).
- Das Journal schreibt append-only, mit Hash-Kette und `chflags uappnd`; Datensätze sind kanonisches JSON (`apps/komki_mediator/lib/komki_mediator/journal.ex:1-34`, `:100-124`).
- `admit_document` erzeugt PDR mit B_W als `checked_label`; eine gesonderte `ratsarbeit`-Behandlung gibt es nicht (`apps/komki_mediator/lib/komki_mediator/gate.ex:124-132`).

### Tests und Fixtures

- Die Vorlagen-Tests prüfen, dass `ratsarbeit@1` keine Lockerungsbefugnis bekommt und die Registry kompiliert (`apps/komki_mediator/test/komki_mediator/templates_test.exs:227-229`, `apps/komki_mediator/test/komki_mediator/gamma_test.exs:91`).
- Gegenprobe 13.1 nutzt einen Raum mit `ratsarbeit@1` und prüft, dass kein Offenlegungsfenster entsteht und der Connector nie gerufen wird (`apps/komki_mediator/test/komki_mediator/go_essenz_test.exs:267-299`).
- Der CLI-Startvertrag und die Dateiaufnahme werden mit `ratsarbeit@1` als B_W getestet, allerdings gegen den synthetischen Seed mit `purpose = "sitzungsvorbereitung"` (`apps/komki_cli/test/komki_cli/session_intake_test.exs:27-58`; Fixture `apps/komki_cli/priv/fixtures/registry-seed.json:15-25`).
- Label-Store-Tests ändern `ratsarbeit@1` gezielt (Bezeichnung, Leser, Lockerungsbefugnisse) und prüfen die Unveränderlichkeit (`apps/komki_cli/test/komki_cli/label_store_test.exs:44-48`, `:337-393`).
- Das Szenario `radweg-bahnhofstrasse` beschreibt `ratsarbeit@1` als Bindung für nicht-öffentliche RIS-Unterlagen und Vault-Wissen: Leser Miriam und `pi-agent`, Zweck `mandat`, keine Lockerung durch Miriam (`docs/szenarien/radweg-bahnhofstrasse.md:155-158`). Es nennt außerdem eine Bindungsvorlage „Ratsarbeit Bayern“ als noch zu bauen (`:284`, `:1013`).

## Fehlt

### Label-Store

- Kein Raumprofil und keine B_W-Liste, die `ratsarbeit@1` führt (`apps/komki_mediator/lib/komki_mediator/templates.ex:304-347`).
- Keine `emit`-, `transfer`- oder `store`-Regel. Jede Ausgabe aus einem `ratsarbeit`-Raum ist damit ohne GO nicht möglich; ein freier Anfragekanal fehlt bewusst, ist aber auch nicht als geregelter Weg vorhanden (`apps/komki_mediator/lib/komki_mediator/templates.ex:198-201`).
- Keine Auflagen für Quellenangabe, Aufbewahrung oder Weitergabe, obwohl R.2.2 sie vorsieht (`docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md:448-454`).
- Keine eigene Umgebung für einen Mandatsraum; die Vorlage kennt nur `lokaler-arbeitsraum@1`, `ris-abruf@1`, `vault-lokal@1`, `web-suche@1` und `ratsprojekte-bestand@1` (`apps/komki_mediator/lib/komki_mediator/templates.ex:130-136`).
- Keine Bindungsvorlage im Sinne des Szenarios („Ratsarbeit Bayern“, `auftrag-sitzung-*`); B10 ist dort ausdrücklich als zu bauen markiert (`docs/szenarien/radweg-bahnhofstrasse.md:1013`).

### Policy-Engine

- Kein entscheidbarer Zweig für `sitzungsmappe` oder eine Faktenfreigabe; `fakten-oeffentlicher-sitzungsteil` aus dem Szenario fehlt im geschlossenen Vokabular (`apps/komki_policy/lib/komki_policy/registry.ex:31-40`; Szenario `docs/szenarien/radweg-bahnhofstrasse.md:547-548`).
- Keine Regel, die eine Freigabe von Tatsachen mit öffentlicher Quelle als Lockerung von `ratsarbeit@1` abbildet (Szenario K1, `docs/szenarien/radweg-bahnhofstrasse.md:923`).
- Keine besondere Behandlung nicht-öffentlicher RIS-Labels; die Engine arbeitet nur mit Labels und Bindungen. Der Unterschied öffentlich/nicht-öffentlich entsteht ausschließlich im Connector.

### Connector und Manifest

- Kein Connector und keine Operation, die `ratsarbeit@1` importiert oder ausgibt (`apps/komki_connector/lib/komki_connector/manifest.ex:42`, `:161`, `:233`).
- Kein nicht-öffentlicher RIS-Abruf. Der RIS-Connector ist öffentlich-only; Issue #198 ist das Bau-Ticket dafür (`apps/komki_connector/CONTRACT.md:167-190`; Ticket #584 nennt #198 als Bau-Ticket).
- Kein Dokument-/OCR-Weg für nicht-öffentliche Vorlagen; der Dokument-Connector liest nur bereits im Raum liegende Dateien (`apps/komki_connector/lib/komki_connector/manifest.ex:69-92`).
- `ratsarbeit@1` fehlt in den Γ-Konventionen des Connector-Vertrags, also auch in der dortigen Default-Registry (`apps/komki_connector/CONTRACT.md:304-334`).

### Raumvertrag und `admit_document`

- Kein Mandatsraum mit `purpose = "mandat"` und `ratsarbeit@1` in B_W; der Default-Raum ist `recherche` mit `purpose = "offene-recherche"` (`apps/komki_mediator/lib/komki_mediator/templates.ex:358-416`).
- Keine Raumdokumente mit `ratsarbeit@1`; die Vorlage legt nur `doc-oeffentlich`, `doc-vertraulich` und `doc-pending-freigabe` an (`apps/komki_mediator/lib/komki_mediator/templates.ex:393-414`, `:516-525`).
- Kein Weg, nicht-öffentliche RIS-Dokumente in den Raum zu bringen; `admit_document` setzt ein bereits klassifiziertes Raumobjekt voraus (`apps/komki_mediator/lib/komki_mediator/room.ex:130-137`).
- Der Startvertrag nennt `ratsarbeit@1` nur als Dokumentationsbeispiel; eine Vorlage oder einen erzeugten Mandatsvertrag gibt es nicht (`apps/komki_cli/lib/komki_cli/start_contract.ex:11-18`).

### PDR und Journal

- Kein PDR-Feld für Herkunft, Klassifikationsentscheidung (`decided_by`, `basis`) oder Bindungsprovenienz. Das Journal belegt die Entscheidung, nicht woher das nicht-öffentliche Objekt stammt (`apps/komki_mediator/lib/komki_mediator/pdr.ex:74-100`).
- Keine `audit_labels`/`journal`-Felder aus dem RFC-Beispiel; das Journal ist generisch und kennt keine `ratsarbeit`-spezifische Partition (`docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md:2113-2119`).
- Keine Aufbewahrungs- oder Löschregel im Journal für nicht-öffentliche Inhalte; das ist in #584 ausdrücklich noch offen.

## Unklar

- **Zwei Definitionen derselben Kennung.** Die Vorlage definiert `ratsarbeit@1` mit `purpose = "mandat"` und ohne Lockerung (`templates.ex:198-201`). Der synthetische CLI-Seed definiert dieselbe Kennung mit `purpose = "sitzungsvorbereitung"`, `workspace_scope_ok` und Lockerungsbefugnis `auflagen → sitzungsmappe` (`apps/komki_cli/priv/fixtures/registry-seed.json:15-25`). Bindungen sind unveränderlich; welche Fassung kanonisch ist, muss entschieden werden. Für die Tests ist der Unterschied bewusst, für eine echte Registry wäre er ein Konflikt.
- **Bindung oder Raumlabel.** Das Szenario trägt `ratsarbeit@1` sowohl als Bindung von Objekten als auch als Raumlabel (`docs/szenarien/radweg-bahnhofstrasse.md:158`, `:393`, `:404`). Der Startvertrag führt Bindungen als B_W, nicht als Objektlabel; ob ein Mandatsraum selbst `ratsarbeit@1` tragen soll, ist nicht festgelegt.
- **Sitzungsmappe als Ausgabe.** Der RFC beschreibt einen Sitzungsmappenraum mit `ratsarbeit@1` und geschütztem Speicher (`docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md:765-783`). Die Engine deklariert `sitzungsmappe` als Ausgabeart, entscheidet sie aber nicht (`registry.ex:40`). Unklar ist, ob die Mappe ein `store`, ein eigener Connector oder nur ein Dateipfad ist.
- **Empfängerkreis bei einem nicht-öffentlichen RIS-Connector.** Der RIS-Connector ist heute `ris-betreiber` in `ris-abruf@1`; für nicht-öffentliche Abrufe wäre zu klären, ob `ris-betreiber` im Empfängerkreis von `ratsarbeit@1` liegen muss. Die aktuelle Bindung nennt nur `nutzende-person` und `pi-agent` (`templates.ex:199`).
- **Fixture-Lage.** Das Szenario behauptet vorhandene nicht-öffentliche RIS-Fixtures (`docs/szenarien/radweg-bahnhofstrasse.md:105-111`). Diese wurden hier nicht geprüft; sie können echte oder synthetische Strukturen enthalten. Der Test-Vault führt `ratsarbeit` jedenfalls nicht, dort steht `vault-vertraulich@1` (`apps/komki_connector_vault/priv/test-vault/Vertraulich/Grundstück Gewerbegebiet Nord.md:3`).
- **Auflagen und Lockerung.** Das Szenario lässt Miriam nur Tatsachen mit öffentlicher Quelle freigeben (K1, `:923`), die Vorlage gibt ihr gar keine Lockerungsbefugnis. Ob `ratsarbeit@1` eine bedingte Befugnis bekommen soll, ist offen.

## Quellen

- `apps/komki_mediator/lib/komki_mediator/templates.ex`
- `apps/komki_cli/lib/komki_cli/label_store.ex`
- `apps/komki_policy/lib/komki_policy/registry.ex`
- `apps/komki_policy/CONTRACT.md`, `apps/komki_connector/CONTRACT.md`
- `apps/komki_connector/lib/komki_connector/manifest.ex`
- `apps/komki_mediator/lib/komki_mediator/{room,gate,pdr,journal}.ex`
- `apps/komki_cli/lib/komki_cli/start_contract.ex`
- `docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md`, `docs/szenarien/radweg-bahnhofstrasse.md`
- Tests und Fixtures: `apps/komki_policy/test/komki_policy/registry_test.exs`, `apps/komki_mediator/test/komki_mediator/{templates,gamma,go_essenz}_test.exs`, `apps/komki_cli/test/komki_cli/{session_intake,label_store}_test.exs`, `apps/komki_policy/priv/fixtures/registry.json`, `apps/komki_cli/priv/fixtures/registry-seed.json`
