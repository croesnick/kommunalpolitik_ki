import KomkiSpec

/-!
The main theorems and the axioms they rest on. CI fails if `sorryAx`
appears; `lake build` already fails on any `sorry` warning.
-/

open KomkiSpec

#print axioms verify_sound
#print axioms verify_sound_rfc
#print axioms derivable_permitted
#print axioms handover_within_admitted
#print axioms verify_emit_assigns
#print axioms derive_sound
#print axioms derive_complete
#print axioms derive_permit_stable
#print axioms derive_deny_stable
#print axioms derive_verifies
#print axioms aktion_permit
#print axioms offenlegung_permit
#print axioms release_single_use
#print axioms advance_cas
#print axioms catalog_aktion_effective
#print axioms catalog_offenlegung_effective
#print axioms catalog_ascending
#print axioms derive_deny_remedied
#print axioms derive_indeterminate_remedied
#print axioms eval_mono
#print axioms recipients_antitone
#print axioms permitted_antitone
#print axioms no_forbidden_recipient
