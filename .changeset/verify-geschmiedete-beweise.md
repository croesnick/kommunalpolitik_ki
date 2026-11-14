---
komki: patch
---

# komki-policy verify verwirft weitere geschmiedete Beweise

Drei Klassen geschmiedeter Permit-Bäume, die `komki-policy verify` (und die Bibliotheksprüfung `KomkiPolicy.Verify.check/4`) fälschlich als gültig bescheinigt hat, werden jetzt verworfen:

- Eine `binding_condition`-Prämisse mit `"expression": null` kann eine fehlende Operationsregel nicht mehr kaschieren: Die Eingabevalidierung lehnt `null` als Ausdruck ab (Eingabefehler, Exit 2), und ohne Registry-Eintrag feuert `expression_mismatch` immer — unabhängig vom behaupteten Wert.
- Eine Fakt-Prämisse entlädt ihren Slot nur noch mit der Tatsache, die ihr Name benennt (`fact == name`); eine auf eine andere, wahre Tatsache umgelenkte Prämisse ist eine unbekannte Prämisse (Exit 1).
- Ein Permit-Baum, dessen nachgerechnete Prämisse nicht `true` ergibt — Basisfakt, Vertragsfeld `workspace.valid` oder Objektprüfung —, wird mit dem neuen Befund `premise_not_true` verworfen; der behauptete Wert der `not_quarantine`-Prämisse wird gegen die nachgerechnete Klassifikation verglichen, statt ignoriert zu werden.

Der Befund `fact_value_mismatch` bei `workspace_contract_valid` benennt jetzt die Tatsache im `fact`-Feld (vorher `null`).
