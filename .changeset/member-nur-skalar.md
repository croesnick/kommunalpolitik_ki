---
komki: patch
---

# komki-policy: `member` nur auf skalaren Feldern

Eine Registry mit `{"member": [feld, []]}` auf einem `string_set`-Feld kompiliert nicht mehr, sondern scheitert mit `expression_type_mismatch`, wie CONTRACT.md § 3 es verlangt. Bisher ließ die leere Literalmenge die Typprüfung durch. Mit Literalen war `member` auf `string_set` schon vorher abgelehnt; die Vorlage-Registry ist nicht betroffen.
