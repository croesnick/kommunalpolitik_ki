---
description: Sitzungsmappe für eine Sitzung aus dem RIS, mit Vorgeschichte aus RIS und Vault
argument-hint: "[Datum, z. B. 17.11.] [Gremium]"
---
Erstelle eine Sitzungsmappe zur Vorbereitung auf: ${@:-die nächste Sitzung}.

Arbeite die Schritte selbstständig ab. Frag nur nach, wenn Schritt 1 nicht eindeutig ist.

1. **Sitzung finden** mit ris_sessions, ohne gremium und mit limit 50.
   - Nenne ich ein Datum ohne Jahr, nimm das nächste Vorkommen ab heute (ist der Tag in diesem Jahr schon vorbei, das nächste Jahr). Nenne ich kein Datum, suche ab heute 60 Tage voraus.
   - Nenne ich ein Gremium, wähle die Sitzung selbst anhand des Gremiumsnamens aus der Liste. Ähnliche Namen zählen („Bauausschuss“ passt zu „Bau-, Umwelt- und Verkehrsausschuss“). Ohne Datum nimm die erste passende Sitzung.
   - Keine passende Sitzung: Sag genau das und frag, was ich vorbereiten will. Vermute keine Gründe.
   - Mehrere passende Sitzungen (etwa Stadtrat und Ausschuss am selben Tag): Liste sie mit Datum, Uhrzeit und Gremium auf und frag, welche.
   - Genau eine passende Sitzung: weiter ohne Rückfrage.
2. **Tagesordnung holen** mit ris_agenda. Ist die Liste leer, sag, dass das RIS zu dieser Sitzung keine öffentlichen Tagesordnungspunkte führt, und hör auf.
3. **Jeden Tagesordnungspunkt lesen** mit ris_show, alle, nicht nur eine Auswahl.
4. **Vorgeschichte suchen** für jeden TOP mit Sachthema: eine ris_search mit dem Kernbegriff aus dem Titel (frühere Beratungen) und eine vault_search mit demselben Begriff (meine Notizen). Lies je TOP höchstens die drei passendsten früheren RIS-Treffer mit ris_show und höchstens fünf Notizen mit vault_read. Formale TOPs (Änderung der Tagesordnung, Protokollgenehmigung, Bekanntgaben, Wünsche und Anregungen) überspringst du dabei.
5. **Raumdokumente**: Prüfe mit list_documents, ob Dokumente bereitliegen, und lies mit admit_document nur die, die erkennbar zu einem TOP gehören. Rate keine Kennungen.

Gliedere die Mappe je Tagesordnungspunkt, mit TOP-Nummer und Titel wie im RIS:

1. **Worum es geht**: zwei bis drei Sätze
2. **Beschlussvorschlag**: wörtlich, falls vorhanden
3. **Kosten, Fristen, Zuständigkeit**: soweit genannt
4. **Vorgeschichte**: frühere Beratungen im RIS und passende Vault-Notizen, je mit Quelle; „keine gefunden“, wenn die Suche nichts ergab
5. **Offene Fragen**: was ich vor der Sitzung klären sollte

Formale TOPs fasst du in einer Zeile zusammen. Schließe mit einer kurzen Liste der Punkte, zu denen ich mich vorbereiten oder nachfragen sollte.

Was fehlt, benennst du offen, ohne Gründe zu erfinden:
- Nicht-öffentliche Tagesordnungspunkte liefert komki nicht. Schreib nichts darüber, was dort stehen könnte.
- Liefert ris_show keinen Text, schreib „im RIS kein Text abrufbar“.
- Meldet ein Werkzeug „Zugangsdaten fehlen“, sag, dass die Anmeldung beim RIS abgelaufen ist oder fehlt, und mach mit dem weiter, was schon vorliegt.
- Ist ein Aufruf gesperrt, sag, was gesperrt ist, und mach ohne ihn weiter. Such keinen Umweg über andere Werkzeuge.

Belege jede Aussage mit ihrer Quelle: RIS mit Gremium, Sitzungsdatum, TOP-Nummer, der URL aus der Antwort und dem Abrufdatum; Vault mit dem Pfad der Notiz; Raumdokument mit seiner Kennung. Was du nicht belegen kannst, lässt du weg oder kennzeichnest es als unbelegt. Im Web suchst du nur, wenn ich darum bitte.
