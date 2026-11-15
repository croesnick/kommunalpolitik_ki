---
komki: patch
---

# RIS-Connector: Budgets gegen hostile Antworten, Quell-URL auf die Weboberfläche

Der RIS-Connector verarbeitet Antworten der Gegenstelle jetzt mit festen Grenzen, bevor
der eigentlichen Arbeit: Antwortkörper über 1 MiB und tiefer als 16 Ebenen verschachteltes
JSON werden als `upstream-error` abgelehnt, statt vollständig materialisiert zu werden;
Textblöcke über 64 KiB einzeln oder 192 KiB je Antwort enden ebenso in `upstream-error`.
Das Entfernen der HTML-Tags läuft in einem einzigen linearen Durchlauf statt über eine
Regex, die bei großen Blöcken in der Engine entgleiste, und die Frist des Aufrufs wird
vor jedem Block geprüft — ein feindliches RIS kann den Connector damit nicht mehr
minutenlang auf CPU festnageln.

Aus allen RIS-Feldern verschwinden Steuerzeichen (C0/C1; ein einzelnes CR kollabiert dabei
wie bisher zu einem Leerzeichen, statt Wörter zu verkleben), und Zahl-Entities auf
Steuerzeichen — etwa `&#155;` für CSI — werden nicht dekodiert, sondern bleiben als Klartext
stehen. Nummer, Titel, Sitzung und Block-Überschriften werden auf 1 000 Zeichen mit
„…"-Marker gekappt — Sequenzen aus Tagesordnungstexten können keine Terminal-Ausgaben mehr
fälschen.

`url` in Treffern, `ris show`, `ris sessions` und `ris agenda` zeigt jetzt auf die
Weboberfläche des RIS statt auf den API-Endpunkt, der im Browser nicht auflöst: Sitzungen
als `https://ris.komuna.net/vgbuchloe/app/sitzungen/<sitzungs-id>`, TOPs als
`https://ris.komuna.net/vgbuchloe/app/sitzungen/<sitzungs-id>/<top-id>` (an der echten
Oberfläche geprüft). Die Web-Basis ist konfigurierbar (`--web-url`, Default VG Buchloe) und
wird wie bisher nur aus Basis und geprüfter ID gebaut, nie aus Upstream-Text.
