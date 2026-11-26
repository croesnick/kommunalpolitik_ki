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
#print axioms catalog_gos
#print axioms release_catalog_aktion_effective
#print axioms release_catalog_offenlegung_effective
#print axioms release_catalog_offenlegung_grantable
#print axioms release_remedies_aktion_effective
#print axioms release_remedies_offenlegung_effective
#print axioms remedies_aktion_effective
#print axioms remedies_offenlegung_effective
#print axioms catalog_ascending
#print axioms derive_blockers_named
#print axioms derive_evidence_named
#print axioms derive_fakt_deny
#print axioms derive_fakt_indeterminate
#print axioms derive_transformations_listed
#print axioms remedies_transformation
#print axioms catalog_neuerRaum
#print axioms neuer_raum_necessary
#print axioms neuer_raum_recipients_necessary
#print axioms derive_deny_remedied
#print axioms derive_indeterminate_remedied
#print axioms release_remedied
#print axioms eval_mono
#print axioms recipients_antitone
#print axioms permitted_antitone
#print axioms no_forbidden_recipient
#print axioms Registry.compiledOk_sound
#print axioms Snapshot.validated_sound
