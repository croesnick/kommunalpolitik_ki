---
komki: patch
---

# Vermittler: Argumentgrenzen vor der Kanonisierung; Session-Angabe im Journal als behauptet

Ein `tools/call` mit tief verschachtelten Argumenten konnte den Vermittler
lahmlegen: Die Parameter-Vorprüfung band abgelehnte Aufrufe per kanonischem
Hash, und der kanonische Encoder rückt pro Ebene ein — rund 150 KB Anfrage
mit ~20 000 Verschachtelungsebenen trieben dabei Gigabytes an Allokation
(Θ(Tiefe²)). Die Vorprüfung begrenzt Tiefe (32 Ebenen) und Gesamtgröße
(256 KB Gewicht) der rohen Argumente jetzt vor der Schema-Prüfung und vor
dem Journal-Eintrag; übergroße Aufrufe werden billig und strukturiert
abgelehnt, der Hash bindet sie bis zur Grenze. Der Encoder selbst bekommt
eine explizite Tiefengrenze von 128 Ebenen mit strukturiertem Fehler.

Außerdem führt das Entscheidungs-Journal die `X-Komki-Session`-Angabe
nicht mehr als Sitzungsidentität, sondern als das, was sie ist: eine
unbelegte Behauptung des Aufrufers. Jeder Datensatz markiert die
Zuordnung seit `komki-pdr/6` mit `session_id_provenance: "caller-asserted"`;
eine spätere Journal-Auswertung schreibt Anrufe nicht mehr ungeprüft der
behaupteten Session zu.
