---
ratsprojekte: patch
---

# `ratsprojekte recover` liest den Wiederherstellungscode verdeckt

Der Wiederherstellungscode ist der Schlüssel der Datenbank. Wer ihn beim
Wiederherstellen eintippte, tippte im Terminal mit Echo: Der Code blieb im
Scrollback und in Bildschirmaufnahmen sichtbar — für jeden lesbar, der den
Bildschirm später sieht. `ratsprojekte recover` schaltet das Echo während
der Eingabe ab (wie komki es bei Passwörtern tut) und stellt es danach
wieder her. Ohne Terminal, etwa aus einem Skript oder einer Pipe, verweigert
der Befehl die Eingabe und bittet darum, ihn im Terminal auszuführen.
