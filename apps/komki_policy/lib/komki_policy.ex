defmodule KomkiPolicy do
  @moduledoc """
  Deterministischer Policy-Kern `komki_policy` (Lieferung 2 und 3: Regelzweige
  `admit`, `emit`, `store` und `transfer`, Remedy-Katalog, Aktionsfreigabe).

  Der Kern kann aus einer Registry (`komki-registry/2`), einem
  `ContextSnapshot` (`komki-snapshot/1`) und einem `Intent` (`komki-intent/1`)
  auf regelwerksbasierter Herleitung entscheiden (`derive`), mit vorgelegter
  Aktionsfreigabe und Offenlegungsstand den Freigabe-Zweig laufen lassen
  (`decide_with_release`), den gefundenen Beweisbaum unabhängig prüfen
  (`verify`) und als Escript (`komki-policy`) aufgerufen werden.

  Die Datensätze und die kanonische Darstellung sind im verbindlichen
  Datenvertrag festgelegt: siehe `CONTRACT.md` im App-Verzeichnis
  (§ 2 Datensätze, § 6 Kanonische Darstellung & strenge JSON-Basis).

  Der Kern ist seiteneffektfrei: keine Uhr, kein Zufall, kein Netz, kein
  Dateizugriff. Alle Eingaben sind explizite Argumente; logische Zeit ist
  Eingabe, nie Systemzeit. Eine Ableitung ist keine Ausführungsrechte.
  """
end
