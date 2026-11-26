---
komki: patch
---

# komki-policy verify vergleicht behauptete Ausdrücke strikt

Ein Permit-Baum, dessen `binding_condition` den Registry-Ausdruck nur zahlengleich wiedergibt, etwa `3.0` statt `3`, wird jetzt mit `expression_mismatch` verworfen, wie CONTRACT.md § 5 es verlangt. Ausgewertet wurde schon vorher der Registry-Ausdruck; ein falsches `permit` war so nicht möglich.
