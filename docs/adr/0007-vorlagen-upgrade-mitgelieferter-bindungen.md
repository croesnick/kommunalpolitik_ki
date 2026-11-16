---
status: accepted
---

# Mitgelieferte Bindungen dürfen per Vorlagen-Upgrade eine neue Fassung bekommen

RFC 0003 R.2.2 zählt die Lockerungsbefugnis zur Bindung, und eine Bindung trägt eine unveränderliche Kennung mit Version. Der Label-Store setzt das durch: Weicht eine registrierte Bindung von einer importierten ab, bricht der Import ab. Ticket #354 gibt vier mitgelieferten Bindungen eine Befugnis für die Ausgabeart `suchanfrage`: `vault-vertraulich@1`, `ratsprojekte@1`, `fraktion-intern@1` und `fraktionsprojekt-radweg@1`. Ohne Ausweg würde `komki up` auf jeder bestehenden Installation abbrechen. komki ersetzt deshalb eine mitgelieferte Bindung beim Import der Vorlage, wenn der Store genau eine frühere mitgelieferte Fassung davon enthält. Die nutzende Person hat das am 16.11.2026 entschieden.

## Begründung

- **Neue Versionen gehen nicht überall.** `ratsprojekte@1` steht in der Stand-Schnittstelle zum Hub: „`label` … immer `ratsprojekte@1`“ ([stand.md](../schnittstellen/stand.md)). Eine Fassung `@2` bräuchte eine Änderung im Hub. `vault-vertraulich@2` hätte den Filter des Vault-Connectors berührt.
- **Den Store beiseitezulegen kostet Daten.** So lief es bei #298 ([Wenn es hakt](../site/src/content/docs/komki/wenn-es-hakt.mdx)). Dabei gehen eigene Bindungen und Erstklassifikationen verloren oder müssen neu importiert werden.
- **Der Übergang bleibt ausdrücklich.** RFC A.1: „Regelmigration, Widerruf und Änderung der Umgebung sind explizite administrative Übergänge.“ Das Upgrade läuft nur beim Import der Vorlage in `komki up`, nur für Fassungen, deren Fingerabdruck die Vorlage nennt (`Templates.superseded_bindings/0`), und hält jeden Übergang in der Tabelle `binding_upgrades` fest. Der Vermittler entscheidet weiter unter dem Γ, mit dem er gestartet ist (ADR 0006, F6), und hält dessen Hash im Journal fest.

## Erwogene Optionen

- **Neue Versionen `@2`:** konform mit R.2.2, aber nur für drei der vier Bindungen ohne Eingriff in den Hub. Der Projektraum hätte die Websuche per GO verloren, bis der Hub `ratsprojekte@2` schreibt.
- **Ändern wie bei #298:** einfach, aber jede bestehende Installation bricht ab, und der Ausweg kostet Daten.

## Folgen

- Das ist eine bewusste Abweichung von R.2.2 für mitgelieferte Bindungen. RFC R.2.2 nennt sie.
- Eine selbst angelegte oder veränderte Bindung bleibt unveränderlich. `komki label import` übergibt nie ein Upgrade.
- Wer eine mitgelieferte Bindung ändert, trägt den Fingerabdruck der bisherigen Fassung in `@superseded_bindings` ein (`KomkiCli.LabelStore.binding_fingerprint/1`). Ein Test in `gamma_test.exs` prüft, dass der Abdruck die alte Fassung trifft.
- Eine Entscheidung, die vor dem Upgrade fiel, bleibt über den Γ-Hash im Journal nachprüfbar. Dieselbe Kennung bedeutet danach aber eine andere Befugnis. Wo das nicht hinnehmbar ist, bekommt eine Bindung eine neue Version statt eines Upgrades.
