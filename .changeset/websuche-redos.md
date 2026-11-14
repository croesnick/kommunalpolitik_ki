---
komki: patch
---

# Websuche: feindliche Treffer binden den Connector nicht mehr

Suchergebnisse von Brave sind Fernsteuerung: Titel und Beschreibung eines Treffers
stehen auf fremden Seiten. Schickt die Suchmaschine einen überlangen '<'-Run als
Titel zurück, arbeitete der Connector die ganze Zeichenkette ab — am 2-MiB-Limit
der Antwort bis 62 ms pro Treffer, auf Regex-Engines ohne Bumpalong-Terminierung
(Sicherheits-Audit #467, Fund F11) Minuten bis Stunden. Jetzt wird jede
ferngesteuerte Eingabe vor der Bereinigung hart auf 8 KiB gekappt und der
Tag-Strip läuft als linearer Scan statt über einen Backtracking-Regex: Die
Bereinigung bleibt konstant schnell, egal was die Gegenseite schickt. Was hinter
mehr als 8 KiB Rohdaten liegt, wird nicht mehr rekonstruiert — Titel und
Beschreibungen enden ohnehin bei 300/1000 Zeichen, der Unterschied ist unsichtbar.
