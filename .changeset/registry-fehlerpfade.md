---
komki: patch
---

# Registry-Import meldet Fehler in Transformationen und Ausdrücken einheitlich

Ein Transformationslabel, das keine Zeichenkette ist (etwa `"input_labels": [7]`), ließ den Registry-Import abstürzen. Jetzt ergibt es den Eingabefehler `invalid_transformations`. Ein Ausdruck mit einem nicht deklarierten Feld meldet `unknown_fact_field` jetzt am Pfad des Ausdrucks, ohne den Anhang „ field“. Bei mehreren fehlerhaften Transformationen kommt der Fehler der ersten in Sortierreihenfolge.
