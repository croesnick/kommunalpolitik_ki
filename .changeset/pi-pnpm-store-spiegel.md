---
komki: patch
---

# Sitzungen mit pi ab 1.5.1 starten wieder

pi folgt seit Version 1.5.1 beim Laden von Extensions dem echten Pfad von
Symlinks. Bei global per pnpm installiertem pi landen diese Zugriffe im
pnpm-Store-Spiegel, den das Seatbelt-Profil nicht freigab — die Sitzung
wäre ab pi 1.5.1 beim Laden der Anzeige sofort beendet. Das Profil gibt
die Spiegel-Ziele der Abhängigkeits-Symlinks jetzt frei.
