---
komki: patch
---

`KomkiPolicy.Context.ensure_coherence/2` meldet einen Kohärenzfehler als Map `%{code, path, detail}`, wie seine Spezifikation und `validate_intent/1`; vorher kam ein Tupel. `decide` und `verify` verhalten sich unverändert.
