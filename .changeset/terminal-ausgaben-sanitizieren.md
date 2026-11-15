---
komki: patch
---

# Terminal-Ausgaben aus Log- und Dateidaten ohne Steuersequenzen

Der Denial-Footer (`komki run --capture-denials`), der Aufnahme-Header von
`komki session` und Fehlergründe mit Pfadangaben (etwa `--gguf-from`)
filtern jetzt Terminal-Steuersequenzen aus Daten von Dateisystem und
Unified Log heraus: OSC-52-Sequenzen können die Zwischenablage nicht mehr
schreiben, CSI-Folgen keine Zeilen mehr überschreiben. Datei- und Pfadnamen
bleiben lesbar; ein eingebetteter Zeilenumbruch in einem Dateinamen wird
sichtbar als `\n` gezeigt, statt eine zusätzliche Aufnahme-Zeile
vorzutäuschen.
