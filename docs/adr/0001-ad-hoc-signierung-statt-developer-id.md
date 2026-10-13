---
status: accepted
---

# Ad-hoc-Signierung statt Developer ID und Notarisierung

komki-Binaries werden über GitHub-Releases verteilt; macOS hängt Downloads `com.apple.quarantine` an, und Gatekeeper blockiert den ersten Start. Wir veröffentlichen weiterhin ad-hoc linker-signierte Binaries und machen die Abhilfe (`xattr -d com.apple.quarantine <datei>`) zum festen Pflichtbestandteil der Release-Notes — statt Developer ID plus Notarisierung einzuführen. Grund: Letzteres setzt ein Apple-Developer-Programm-Mitglied voraus (99 $/Jahr), und die nutzende Person ist kein Mitglied und wird keines werden; der Verteilungskreis ist klein und bekannt, deshalb wiegt der Verzicht geringer als Kosten und Prozess.
