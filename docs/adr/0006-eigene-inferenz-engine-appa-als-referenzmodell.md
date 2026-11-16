---
status: accepted
---

# komki behält seine Inferenz-Engine, APPA ist Referenzmodell

APPA (arXiv 2607.24625) formalisiert die Vermittlungshälfte, die RFC 0003 beschreibt, und OpenAPPA implementiert es in Rust, unter MIT-Lizenz. Ticket #596 hat abgewogen, ob komki_policy an APPA angeglichen, durch OpenAPPA als Sidecar ersetzt oder parallel dazu betrieben werden soll. komki behält komki_policy als einzige Inferenz-Engine. APPA dient als Referenzmodell: Wo APPA weiter ist, übernimmt komki einzelne Mechanismen, aber keinen Code und nicht die Grundsemantik. Die Analyse mit allen Belegen steht in [2026-11-16-komki-policy-appa-openappa.md](../research/2026-11-16-komki-policy-appa-openappa.md). Die nutzende Person hat am 16.11.2026 ihr GO dazu gegeben.

## Begründung

- **APPA kann den Kern des RFC nicht ausdrücken.** Gemeinsam ist beiden nur der Empfängertest: komkis Empfängerkreis `R_Γ(L)` entspricht APPAs `audience`. Es fehlen der feste Raumvertrag `B_W`, die Zweckbedingungen `P_b`, der Inferenzweg unter den Beobachtern `ρ(c)` und die Quarantäne. In APPA sinkt das Label mit jedem gelesenen Wert, und die Verengung bestätigt der Agent selbst. R.4.1 verbietet genau das: Ein aktiver Raum ändert seine Bindungsmenge nicht.
- **Ein zweiter Vertrauenskern brächte wenig.** Damit der Vermittler die einzige Tür bleibt (R.4.4), müsste OpenAPPA ohne externe Dienste, Remedies, Authorities und Recorder laufen. Übrig blieben Empfänger und Trust, also die Dimension, die komki schon hat, und eine, die sich als Bindung schreiben lässt. Der Preis wären rund 205 000 Zeilen Rust und ein zweites Log neben dem Journal.
- **Preview-Status und Elixir-first.** Das README sagt: "config and wire surfaces may break without shims". Das CHANGELOG hat in drei Monaten zehn Abschnitte mit Breaking Changes, zwei davon ändern die Semantik. Ein Prozess in Rust wäre eine Abweichung nach AGENTS.md §1.

## Erwogene Optionen

- **Angleichen:** nur an einzelnen Stellen, siehe Folgen. Die Grundsemantik bleibt: fester Raumvertrag statt eines Labels, das mit dem Gelesenen sinkt.
- **Ersetzen:** verworfen. Es gingen die vier Eigenschaften und die Nichtinterferenz-Zusage aus Anhang A verloren. APPA lehnt diese Zusage ausdrücklich ab: "not general noninterference" (Paper §5).
- **Parallel betreiben:** vorerst verworfen. Die Frage kommt wieder auf, wenn eins davon eintritt: OpenAPPA erreicht eine stabile Version mit versioniertem Wire-Vertrag; komki bekommt Wirkungen ohne GO; komki geht in einen Mehrnutzerbetrieb mit wechselnden Gruppen.

## Folgen

- **Schon übernommen:** der Remedy-Katalog nach APPA Theorem 5 (CONTRACT § 2.8) und die beiden Gates vor und nach dem Aufruf im Vermittler.
- **Folgetickets:** #598 (zuständige Stelle einer Freigabe getrennt von 𝒪 prüfen), #599 (erwartete Entscheidungen als Daten, auch gegen den exportierten Γ), #600 (Zusagen aus Anhang A als Eigenschaftstests), #601 (Angriffskorpus als echte Läufe mit Messzahlen), #602 (Integrität ungeprüfter Quellen im RFC).
- **Γ bleibt für einen Lauf des Vermittlers fest.** Heute lädt der Vermittler Γ beim Start. Kommt einmal ein Neuladen im Betrieb, gilt eine Entscheidung nur, wenn sie unter dem aktuellen `gamma_hash` getroffen wurde. Laufende Räume folgen nicht der neuesten Policy, anders als in OpenAPPA.
- **Bei der Agentendelegation (R.7)** bekommt der Rückkanal eine begrenzte Form wie APPAs `attest-schema`, und keine Freigabe überschreitet die Grenze zwischen Eltern- und Kindraum (APPA Theorem 8).
- **Nicht übernommen:** das Accept durch den Agenten, Authorities als LLM oder Auto-Approver, Modelle als Erstklassifikatoren.
- **APPA-Begriffe** (Trajektorie, Authority, Annotator) erscheinen in komki-Dokumenten nur im Vergleich, nicht als komki-Vokabular.
