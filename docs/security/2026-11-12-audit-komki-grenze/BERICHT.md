# Sicherheits-Audit der komki-Grenze (Ticket #467)

Erster KI-gestützter Sicherheits-Audit der komki-Grenze nach dem Bedrohungsmodell aus RFC 0003 (R.8), gelaufen am 12./13. November 2026. Werkzeug: das Claude-Security-Plugin v0.11.0 (auf Commit `c447c3207a42` gepinnt; README und Job-Rezepte vor dem Lauf gelesen), Scan-Pipeline mit Inventory, Threat-Modell, 133 Researchern, zwei Sweeps, Secrets-Pass, dreilinsigem adversarialem Panel und Red-Team-Phase, gefahren aus der Haupt-Session im frischen Worktree, effort `max`. Der englische Vollbericht mit allen 34 Funden liegt daneben: [CLAUDE-SECURITY-RESULTS.md](CLAUDE-SECURITY-RESULTS.md) (dazu JSONL und SARIF für Maschinen, plus Revision-Stamp). Die Fund-Tickets folgen einzeln; ihre Nummern stehen in der Tabelle unten, sobald sie stehen.

## Auftrag und Einordnung

Auftrag war der Scanner-Entwurf aus dem Ticket: Agent-Code, Agent-Ausgaben und importierte Dokumente gelten als angreiferkontrolliert (R.8.1); ihre Wirkung wird durch Policy-Entscheidung, GO-Freigabe, Connector-Ausführung, Aufnahme, Dateizugriff und Netz-Egress verfolgt. Kein Fund ist ein gezeigter Bypass am laufenden System — alle sind Lektüre-Befunde des verifizierten Panels; Aussagen über Seatbelt und Secure Enclave bleiben ungeprüfte Hypothesen, bis ein Lauf auf macOS sie belegt.

## Messung

| Messgröße | Wert |
|---|---|
| Laufzeit | Workflow-Job 6 h 22 min laut Stamp (`duration_s: 22912`; reine Workflow-Pipeline 6 h 18 min, inkl. Fehlstart ~7,5 h Session) |
| Kosten | ~33,2 Mio. Subagent-Tokens, 456 Agents, 15 131 Werkzeugaufrufe, 0 Agent-Fehler (Token-/Agent-Zahlen aus dem Lauf, nicht im Stamp belegt; Stamp belegt 133/133 Researcher und 301 Panel-Stimmen) |
| Abdeckung | 17/17 Grenz-Apps, 890 Dateien im Scope, 255/256 Produktionsdateien gelesen, 0 unabgerechnet; Tests/Fixtures/priv bewusst Hintergrund (Begründungen im Vollbericht) |
| Funde | 88 Roh-Kandidaten → 73 dedupliziert → **34 bestätigt** (31 einstimmig, 3 mit 2/3 und Red-Team — die drei bilden die „plausibel"-Klasse des Tickets ab), **39 verworfen** (12 Red-Team, 5 Repanel, 22 Panel) |
| Verifikationsstatus | `verified` (aus der Stimmakte berechnet, im Revision-Stamp) |

## Fundübersicht (34 bestätigt: 4 HIGH, 17 MEDIUM, 13 LOW)

Nicht jede Zeile trifft eine R.8.3-Zusage der RFC 0003: Die Zeilen mit „Datenschutz-Grenze (§8)" benennen AGENTS.md §8, F21 benennt die Hub-Zugangskontrolle aus ADR 0004, und Verfügbarkeits-Funde treffen keine Zusage, sondern R.8.4-Pflichten oder schlicht den Betrieb.

| Fund | Severity | App / Senke | Verletzte Zusage / Grenze | Ticket |
|---|---|---|---|---|
| F1 | HIGH | komki_mediator: `JSON.canonical` Θ(depth²) auf rohen MCP-Argumenten → DoS | Auditierbare Vermittlung (Vermittler und Journal legbar; vollständige Vermittlung gefährdet) | #473 |
| F2 | HIGH | seatbelt: Mach-O-Load-Commands werden ungeprüft zu `file-read*`-Grants | Vertrauensbasis Isolation (R.8.1); Nichtinterferenz ohne Lockerung kollabiert | #474 |
| F3/F18/F20 | HIGH/MED/MED | komki-tresor: ECDH-Shared-Secret an jeden gleich-UID-Prozess, Prompt-Text vom Aufrufer | Vertrauensbasis Identitätsprüfung (R.8.1) — Touch-ID-Einwilligung ist fälschbar | #475 |
| F4 | HIGH | komki_cli `go_steps.ex`: verweigerte Offenlegung wird als `go: true` geschrieben | Kein Autoritätsgewinn; Begrenzte Faktenfreigabe (Freigabe trotz „n") | #476 |
| F5/F7/F8 | MED | komki_policy `verify.ex`: drei Schmiede-Lücken (geschmiedete Proof-Bäume validieren) | Kein Autoritätsgewinn; Auditierbare Vermittlung | #477, #479, #480 |
| F6 | MED | komki_connector_vault `note.ex`: ReDoS in der Titel-Regex | Verfügbarkeit des Vault-Suchdienstes (keine R.8.3-Zusage; R.8.4-Suchdienst-Pflicht berührt) | #478 |
| F9 | MED | komki_mock: Kassetten-State mit 0644 statt 0600 | Datenschutz-Grenze (§8): nicht-öffentliche Ratsinhalte lokal lesbar | #481 |
| F10/F14 | MED | komki_mediator `connector_gate.ex`: Γ-Rotation vor Silent-Filter → Existenz-Orakel | R.8.4: verweigerter Aufruf darf Existenz verborgener Notizen nicht verraten | #482 |
| F11 | MED | komki_connector_web `text.ex`: ReDoS im Tag-Strip ferngesteuerter Treffer | Verfügbarkeit des Connectors (R.8.4 Suchdienst-Pflicht verwandt) | #483 |
| F12 | MED | komki_mediator `gate.ex`: admit_document als Existenz-Orakel | R.8.4: Existenz vertraulicher Dokumente nicht verraten | #484 |
| F13 | MED | komki_mediator: GO-/Journal-Verzeichnisse mit Default-Rechten | Begrenzte Faktenfreigabe (verweigerte Ausgaben lokal lesbar) | #485 |
| F15 | MED | komki_connector_ris `top.ex`: quadratische Tag-Strip-Regex | Verfügbarkeit des RIS-Connectors | #486 |
| F16 | MED | komki_connector_ris: RIS-Text ungefiltert in den Kontext (indirekte Prompt-Injection) | Kein Autoritätsgewinn (Steuerung im Raum); R.7.1.4 benennt den Fall | #487 |
| F17 | MED | komki_connector_documents: PDF-Renderung im Connector-VM ohne Speichergrenze | Verfügbarkeit der Aufnahme (Gate-2-Weg) | #488 |
| F19 | MED | komki_cli `tresor/core.ex`: komki-tresor ohne Pin-Prüfung ausgeführt | Vertrauensbasis: Neusealed Secrets gehen an ein gepflanztes Binary | #489 |
| F21 | MED | ratsprojekte `verwaltung.ex`: Einweg-Link hinter nicht-zurechenbarem Touch-ID-Prompt | Hub-Zugangskontrolle (ADR 0004): Einwilligung fälschbar | #490 |
| F22 | LOW | wegwerf_hub: `{:more,_}` unbehandelt → 500 statt 400 | Robustheit der Connector-Grenzstelle | #491 |
| F23 | LOW | ratsprojekte: Recovery-Code (SQLCipher-Masterschlüssel) mit Terminal-Echo | Datenschutz-Grenze (§8): Schlüssel im Scrollback | #492 |
| F24/F25 | LOW | komki_cli `steps.ex`: llama-API-Key in models.json mit 0644 | Datenschutz-Grenze: Schlüssel lokal lesbar | #493 |
| F26/F31 | LOW | komki_cli: Terminal-Control-Sequenzen aus Denial-/Dateinamen | Entscheidungs-Oberfläche fälschbar (Kein-Autoritätsgewinn-Umfeld) | #494 |
| F27 | LOW | komki_mediator `http.ex`: Session-Header unbelegt ins PDR-Journal | Auditierbare Vermittlung (Fehlzuschreibung) | #495 |
| F28 | LOW | komki_connector_web `brave.ex`: echter API-Key über `http://` | Datenschutz-Grenze: bezahlter Schlüssel im Klartext | #496 |
| F29 | LOW | komki_connector_ris `http.ex`: Antwortkörper ohne Größen-/Tiefengrenze | Verfügbarkeit | #497 |
| F30 | LOW | komki_cli `connectors.ex`: Dokumenten-Store mit Default-Rechten | Datenschutz-Grenze: Raumdokumente lokal lesbar | #498 |
| F32 | LOW | komki_cli `steps.ex`: `komki journal verify` ohne Pin-Gate | Auditierbare Vermittlung (gefälschtes Journal-Urteil) | #499 |
| F33/F34 | LOW | komki_cli `label_store.ex`: registry.db mit Default-Rechten | Datenschutz-Grenze: Sicherheitsmodell lokal lesbar | #500 |

Die Spalte „Ticket" wird mit den Einzeltickets befüllt (je Senke ein Ticket; die Paare/Triplets oben teilen sich je ein Ticket).

## Entscheidung über Wiederholung

Der erste Lauf hat geliefert: 34 bestätigte Funde auf der Grenze, darunter vier HIGH, verteilt über Vermittlung, Sandbox, Siegel, GO-Weg und Policy-Verify. Wiederkehrende KI-Reviews lohnen sich — in zwei Formen:

- **Wöchentlich, headless**: ein `scan-changes`-Lauf auf dem Diff seit dem zuletzt geprüften Commit (billig, automatisch; das Plugin rechnet den Tally selbst).
- **Auf Abruf**: ein Whole-Boundary-Lauf in `max` wie dieser nach großen Umbauten an der Grenze.

Die Einrichtung des wöchentlichen Laufs ist ein eigenes Ticket: #501.

## Grenzen des Laufs

Lektüre-Befund, kein Lauf: kein Fund wurde am laufenden komki demonstriert; Seatbelt- und Secure-Enclave-Aussagen gelten als Hypothese. Tests, Fixtures und `priv`-Kassetten waren bewusst Hintergrund (mit Secrets-Pass über die Fixtures). `apps/ratsinfo`, `tools/`, `skills/`, `docs/`, `scripts/`, `packaging/` lagen außerhalb des Scopes. Scans sind nichtdeterministisch — ein sauberer Bereich heißt „in diesem Lauf nicht gefunden", nicht „sicher". Die Regressionstests je bestätigtem Fund entstehen mit den Fixes in den Einzeltickets #473–#500; zum Zeitpunkt dieses Berichts existieren sie noch nicht — der Prüfbericht im Abschluss-PR stuft den Prüfpunkt daher als nicht bestanden aus.
