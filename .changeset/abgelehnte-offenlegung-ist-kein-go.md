---
komki: patch
---

# Abgelehnte Offenlegung wird nicht mehr als Freigabe übermittelt

Bei einer Offenlegungsfreigabe konnte die Teile-Auswahl ohne das abschließende GO
als Freigabe geschrieben werden: Wer nach der Auswahl mit „n" antwortete oder die
Eingabe endete, dessen gewählte Teile wurden trotzdem dem Vorstand offengelegt —
die CLI meldete dabei „0 von 1 Anfragen freigegeben". Ohne Terminal (Skript, Pipe)
wurde die Offenlegung sogar automatisch für alle Teile erteilt. Eine Ablehnung
schreibt jetzt immer eine Absage (go:false); headless gibt es keine Offenlegung —
wie bei allen GO-Entscheidungen bleibt sie der Person am Terminal vorbehalten.
