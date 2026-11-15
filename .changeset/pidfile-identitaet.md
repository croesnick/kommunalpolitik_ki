---
komki: patch
---

# Stale Pidfiles: komki stoppt nur noch eigene Prozesse

Pidfiles (llama-server, Vermittler, Connectoren, Egress) nannten bisher nur
eine Prozessnummer. Lief unter dieser Nummer ein fremder Prozess, konnte
`komki down` ihn treffen. Jetzt prüft komki vor jedem Signal die
Kommandozeile des Prozesses und bindet sie an die eigene Basis: Ein fremder
oder gestoßene Prozess bleibt unberührt, das pidfile wird wie ein stale
pidfile aufgeräumt, und `komki status` meldet „stale oder fremd“ statt zu
töten. Egress, das ohne Argumente startet, ist über seine offene Log-Datei
an die Basis gebunden.
