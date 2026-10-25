# Fixtures für die Anzeige-Extension

Jede Datei ist eine echte Antwort von `KomkiMediator.ConnectorGate.call/3`,
erzeugt mit den Fake-Connectoren aus der Testumgebung des Vermittlers
(`FakeConnector`, `TestHelpers`): `tool` und `args` sind der Aufruf, `text` ist
der JSON-Text, den pi als MCP-Ergebnis bekommt.

Die Inhalte sind erfunden (Sitzungen, Titel, Notizen, Treffer). Nur die
Antwortformen sind echt: zugelassen, abgelehnt (Gate 1 und Gate 2),
zurückgehalten, Connector nicht erreichbar, nicht gefunden, Vorprüfung
abgewiesen, keine Treffer.

Ändert der Vermittler eine Antwortform, gehören die betroffenen Fixtures neu
erzeugt: einen Wegwerf-Test unter `apps/komki_mediator/test/` anlegen, der
`ConnectorGate.call/3` wie in `connector_gate_test.exs` aufruft und das
Ergebnis hierher schreibt.
