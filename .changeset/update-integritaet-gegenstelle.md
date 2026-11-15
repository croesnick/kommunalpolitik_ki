---
komki: minor
---

# Updates, Pins und Gegenstelle: komki startet neu oder verweigert, statt still weiterzulaufen

Nach einem Update liefen Connectoren der alten Fassung weiter: `komki setup` endete
rot, ohne zu sagen, was zu tun ist. `komki up` (und damit `setup`) startet jetzt
jeden laufenden Connector neu, dessen `ping` eine andere Fassung meldet als das
Manifest — derselbe Drift-Check gilt für den Vermittler, wenn das Programm eine
Fassung meldet. Bleibt die Fassung trotzdem falsch, nennt die Doctor-Meldung den
nächsten Schritt (`komki down && komki up`).

`komki journal verify` führt den Vermittler jetzt erst aus, wenn jedes Programm
seinem Pin entspricht — dasselbe Pin-Gate wie bei `komki up`. Ein am gepinnten
Pfad getauschtes Vermittler-Programm kann kein gefälschtes „Journal ok“ mehr
drucken.

Der RIS-Connector sondiert beim Start seine Gegenstelle (die Sitzungsliste des
heutigen Tages, ohne Zugang) und meldet das Ergebnis auf `ping`. `komki doctor`
kennt damit eine unbekannte Gegenstelle — falscher Mandant, umgezogene Adresse,
tote Gegenstelle — schon beim Start statt erst beim ersten Aufruf und zeigt sie
als FAIL mit festem Text.

Stufe minor: die Start-Sonde ist eine kleine Neuerung im Doctor; die beiden
anderen Änderungen (#553, #499) wären für sich Fehlerbehebungen.
