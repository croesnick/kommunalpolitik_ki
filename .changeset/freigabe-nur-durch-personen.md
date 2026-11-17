---
komki: minor
---

# Eine Freigabe gilt nur, wenn eine Person sie erteilt hat

komki prüft jetzt selbst, wer ein GO oder eine Offenlegung erteilt: Nur ein
Beobachter vom Typ Person darf das, nie der Agent oder ein Dienst. Ebenso lässt
sich eine Lockerungsbefugnis nur einer Person geben; ein Γ, das sie einer
Verarbeitungsdomäne gibt, lehnt komki beim Import ab. `komki label export`
schreibt dafür das Format `komki-registry/3` mit den Beobachtertypen.
