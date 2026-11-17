## 0.1.1 (2026-11-17)

### Fehlerbehebungen

#### Entsperr-Freigabe an den Prüfcode der anfragenden Stelle gebunden

Der Touch-ID-Dialog beim Entsperren sah für jede Anfrage gleich aus, egal wer
sie gestellt hatte: Ein Programm im eigenen Benutzerkonto konnte über den
Verwaltungs-Socket eine Entsperr-Anfrage stellen, und die Freigabe am Mac
öffnete diesem Programm den Hub mit allen Projekten und Entwürfen
(Sicherheits-Audit #467, Fund F21). Jede Entsperr-Anfrage trägt jetzt einen
sechsstelligen Prüfcode: `ratsprojekte open` zeigt ihn im Terminal, die
Sperrseite im Browser neben der Schaltfläche, und der Touch-ID-Dialog nennt ihn
im Grund. Freigeben gehört nur bei übereinstimmendem Code — ein Dialog mit
fremdem Code gehört zu einem anderen Programm. Ohne Prüfcode fragt der Socket
gar nicht mehr nach, und es läuft höchstens eine Entsperr-Anfrage gleichzeitig;
weitere weist der Hub klar ab. Das Sperren räumt den Platz einer laufenden
Anfrage nicht: Der Socket nimmt `sperren` von jedem Programm im Benutzerkonto
an, und nur die Anfrage selbst gibt den Platz frei — über die Freigabe, den
Abbruch des Dialogs oder das Ende des Programms.
