---
komki: patch
---

# komki run läuft ohne Terminal (Datei, Pipe, Hintergrund)

`komki run` brach in Skripten und Cron-Läufen ab, sobald die Ausgabe nicht am
Terminal hing: bei einer Umleitung in eine Datei, in einer Hintergrund-Subshell
oder aus einem Agenten-Werkzeug heraus starb pi beim Start mit SIGABRT (Exit
134). Ursache war der geerbte stderr-Kanal: node prüft ihn beim Start, und das
Sandbox-Profil verweigert die Prüfung, wenn dahinter eine Datei liegt. komki
leitet stderr des pi-Laufs jetzt in die Port-Pipe um — damit laufen alle
Aufrufformen, und der frühere Workaround `2>&1 | cat` ist nicht mehr nötig.
pi-Fehlermeldungen erscheinen jetzt gesammelt in der Lauf-Ausgabe statt
ungeordnet im Terminal.
