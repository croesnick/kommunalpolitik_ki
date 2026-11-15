---
komki: patch
---

# Update übersteht alte Vorlagen, Zustandsdateien nur noch eigentümerlesbar

Ein Update, dessen Vorlage mitgelieferte Bindungen ändert, bricht bisher am
Label-Store ab. Enthält der Store nur die alte Vorlage — keine Objekte,
keine Entscheidungen, keine eigenen Bindungen —, ersetzt `komki up`/`setup`
ihn jetzt automatisch: Der alte Store wird gesichert, eine Zeile in der
Ausgabe nennt die Sicherung. Hat der Store eigene Inhalte, bricht der Start
weiter ab, und die Meldung nennt den nächsten Schritt (registry.db
beiseitelegen, setup erneut).

Zugleich entstehen die Zustandsdateien des Vermittlers und des Label-Stores
nur noch für die Eigentümerin lesbar: die Instanzbasis, `mediator/`, `go/`,
`journal/` und `documents/` mit 0700, registry.db samt Begleitdateien,
registry.json, room.json, GO-Anfragen, stand.json und das PDR-Journal mit
0600 — wie es für run/ und die Token bereits galt. Vorhandene zu offene
Rechte werden beim nächsten Start korrigiert. Ein über `--db` frei gewählter
Store-Pfad härtet nur seine eigenen Dateien und lässt das umgebende
Verzeichnis unangetastet. Der RIS-Mock härtet sein
Zustandsverzeichnis genauso (0700/0600) und verweigert für Replay-Kassetten
ein `--dir` innerhalb eines Git-Repos, wie es der Recorder für seine
Kassetten schon tut.
