---
description: Sitzungsmappe für eine Sitzung aus dem RIS, mit Vorgeschichte aus RIS und Vault
argument-hint: "<Datum, z. B. 17.11.> [Gremium]"
---
Erstelle eine Sitzungsmappe zur Vorbereitung auf: ${@:-die nächste Sitzung}.

Arbeite die Schritte selbstständig ab. Frag nur nach, wenn Schritt 1 nicht eindeutig ist.

1. **Sitzung finden** mit ris_sessions. Nenne ich ein Datum ohne Jahr, nimm das aktuelle Jahr. Nenne ich gar kein Datum, suche ab heute 60 Tage voraus und nimm die erste Sitzung. Nenne ich ein Gremium, gib es als gremium mit.
   - Keine Sitzung gefunden: Sag genau das und frag, was ich vorbereiten will. Vermute keine Gründe.
   - Mehrere Sitzungen (etwa Stadtrat und Ausschuss am selben Tag): Liste sie mit Datum und Gremium auf und frag, welche.
   - Genau eine Sitzung: weiter ohne Rückfrage.
2. **Tagesordnung holen** mit ris_agenda. Ist die Liste leer, sag, dass zu dieser Sitzung noch keine öffentliche Tagesordnung veröffentlicht ist, und hör auf.
3. **Jeden Tagesordnungspunkt lesen** mit ris_show, alle, nicht nur eine Auswahl.
4. **Vorgeschichte suchen** für jeden TOP mit Sachthema: eine ris_search mit dem Kernbegriff aus dem Titel (frühere Beratungen) und eine vault_search mit demselben Begriff (meine Notizen). Formale TOPs (Änderung der Tagesordnung, Protokollgenehmigung, Bekanntgaben, Wünsche und Anregungen) überspringst du dabei.
5. **Raumdokumente**: Prüfe mit list_documents, ob Dokumente bereitliegen, und lies mit admit_document nur die, die erkennbar zu einem TOP gehören. Rate keine Kennungen.

Gliedere die Mappe je Tagesordnungspunkt, mit TOP-Nummer und Titel wie im RIS:

1. **Worum es geht**: zwei bis drei Sätze
2. **Beschlussvorschlag**: wörtlich, falls vorhanden
3. **Kosten, Fristen, Zuständigkeit**: soweit genannt
4. **Vorgeschichte**: frühere Beratungen im RIS und passende Vault-Notizen, je mit Quelle; „keine gefunden“, wenn die Suche nichts ergab
5. **Offene Fragen**: was ich vor der Sitzung klären sollte

Formale TOPs fasst du in einer Zeile zusammen. Schließe mit einer kurzen Liste der Punkte, zu denen ich mich vorbereiten oder nachfragen sollte.

Grenzen, die du offen benennst statt sie zu erklären:
- Nicht-öffentliche Tagesordnungspunkte liefert komki nicht. Fehlen Nummern in der Tagesordnung, schreib „nicht öffentlich oder nicht veröffentlicht“ und rate nicht, worum es geht.
- Liefert ris_show keinen Text, schreib „im RIS kein Text abrufbar“.
- Meldet ein Werkzeug „Zugangsdaten fehlen“, sag, dass die Anmeldung beim RIS abgelaufen ist oder fehlt, und mach mit dem weiter, was schon vorliegt.

Belege jede Aussage mit ihrer Quelle: RIS mit Gremium, Sitzungsdatum und TOP-Nummer, Vault mit dem Pfad der Notiz, Raumdokument mit seiner Kennung. Was du nicht belegen kannst, lässt du weg oder kennzeichnest es als unbelegt. Im Web suchst du nur, wenn ich darum bitte.
