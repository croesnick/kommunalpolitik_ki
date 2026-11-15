---
komki: patch
---

# komki-tresor läuft nur mit passendem Programmpin

`komki secret set`, `komki secret erzeugen` und der Geheimnis-Schritt von `komki setup` führen `komki-tresor` jetzt nur aus, wenn der festgehaltene Programmpin passt — dasselbe Urteil wie der Doctor-Pin beim Start (`komki up`), gesprochen vor dem Start des Programms. Ein ausgetauschtes oder gepflanztes `komki-tresor` kann keine frischen Geheimnisse mehr versiegeln und keine Siegel mehr öffnen; komki verweigert vorher mit der Meldung des Doctor-Pins (etwa „verändert seit dem Festhalten … ‚komki setup‘ (fragt nach)“) und speichert nichts. Nach einem gewollten Update wie bisher `komki setup` ausführen und die Rückfrage bestätigen.
