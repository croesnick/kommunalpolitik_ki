---
komki: patch
---

# komki-policy verify prüft die Snapshot-Voraussetzungen von emit, store und transfer

Für einen `emit`-, `store`- oder `transfer`-Intent bricht `komki-policy verify` jetzt wie `decide` mit einem Eingabefehler ab, wenn der Fakt `output_content_digest` fehlt (`emit_digest_missing`) oder das Objekt in Quarantäne liegt (`emit_object_not_classified`), Exit 2. Bisher bestätigte `verify` einen solchen Baum als `valid`, obwohl `decide` für denselben Snapshot gar nicht entschied.
