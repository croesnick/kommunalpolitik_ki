---
komki: patch
ratsprojekte: patch
---

# Touch-ID-Freigabe zeigt Fingerabdruck und Anfrage-Kennung zum Abgleichen

Der Dialog beim Öffnen eines Siegels zeigte nur den Text des aufrufenden
Programms — komkis eigene Rückfrage und die eines anderen Programms deines
Nutzers sahen gleich aus. Der Dialog zeigt jetzt zuerst einen Fingerabdruck
des Siegels (erste 8 Hexzeichen von SHA-256 über Schlüsselverweis und
Sitzungsschlüssel) und eine frische Anfrage-Kennung; komki und der
ratsprojekte-Hub schreiben dieselbe Kombination vorher ins Terminal, und du
gleichst beide im Dialog ab. Der Text des Aufrufers bleibt sichtbar, aber
als unvertraut gekennzeichnet. Der Aufruf ohne Anfrage-Kennung ist jetzt
unmöglich: Freigeben nur, wenn Siegel und Anfrage zur Terminalzeile passen;
im Zweifel ablehnen.
