defmodule KomkiPolicy do
  @moduledoc """
  Deterministischer Policy-Kern `komki_policy` (Lieferung 1, Regelzweig `admit`).

  Der Kern kann aus einem `Registry` (`komki-registry/1`), einem
  `ContextSnapshot` (`komki-snapshot/1`) und einem `Intent` (`komki-intent/1`)
  auf regelwerksbasierter Herleitung entscheiden (`derive`), den gefundenen
  Beweisbaum unabhängig prüfen (`verify`) und als Escript (`komki-policy`)
  aufgerufen werden.

  Die Datensätze und die kanonische Darstellung sind im verbindlichen
  Datenvertrag festgelegt: siehe `CONTRACT.md` im App-Verzeichnis
  (§ 2 Datensätze, § 6 Kanonische Darstellung & strenge JSON-Basis).

  Der Kern ist seiteneffektfrei: keine Uhr, kein Zufall, kein Netz, kein
  Dateizugriff. Alle Eingaben sind explizite Argumente.
  """
end
