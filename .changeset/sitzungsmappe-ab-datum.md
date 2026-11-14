---
komki: major
---

# /sitzungsmappe findet die Sitzung im RIS und liest die ganze Tagesordnung

`/sitzungsmappe 17.11.` sucht jetzt zuerst die Sitzung an diesem Tag, holt ihre öffentliche Tagesordnung, liest jeden Tagesordnungspunkt und sucht frühere Beratungen im RIS und passende Notizen im Vault. Die Mappe hat je Punkt einen Abschnitt „Vorgeschichte“ und belegt RIS-Aussagen mit Link und Abrufdatum. Gibt es an dem Tag keine oder mehrere Sitzungen, fragt pi nach. Dafür kennt pi zwei neue Werkzeuge: `ris_sessions` listet Sitzungen eines Zeitraums mit Uhrzeit und Gremium, `ris_agenda` liefert die öffentlichen Tagesordnungspunkte einer Sitzung. Nicht-öffentliche Punkte liefert komki weiterhin nicht. pi kennt jetzt das heutige Datum und rät bei einem Datum ohne Jahr keins mehr.
