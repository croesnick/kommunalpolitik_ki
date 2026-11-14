---
komki: patch
---

# Vault-Suche übersteht Notizen mit langer Leerzeichen-Zeile

Die Titel-Extraktion des Vault-Connectors suchte die erste `# `-Überschrift mit einer Regex, deren faule Gruppe über einer langen Leerzeichenfolge quadratisch zurückverfolgen konnte. Eine Notiz, deren erste Überschriftszeile aus rund 20 000 Leerzeichen vor einem weiteren Zeichen besteht — per `vault_write_test` pflanzbar oder einfach in den Vault synchronisiert —, verbrannte bei jeder Suche und jedem Lesen CPU bis zum vollen Regex-Budget und ließ die Suche danach mit einem internen Fehler für alle Räume scheitern; schon eine einzige solche Notiz genügte.

Die Überschrifts-Regex ist jetzt ohne Rückverfolgungs-Falle gebaut und bekommt ein an die Notizgröße gekoppeltes Engine-Budget, sodass der Aufwand je Notiz linear begrenzt ist. Bleibt das Laden einer einzelnen Notiz trotzdem fehlerhaft, überspringt die Suche nur diese Notiz, statt die ganze Operation abreißen zu lassen. Suchen und Lesen verhalten sich danach wie dokumentiert: Treffer und Ergebnisse ändern sich nicht.
