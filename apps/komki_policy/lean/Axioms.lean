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
#print axioms verifyReport_verdict
#print axioms proofError_decodes
#print axioms snapshotError_validated
#print axioms registryError_compiledOk
#print axioms Json.canonical_injective
#print axioms callHashInput_isSome
#print axioms callHashInput_injective
#print axioms enginePath_preservation
#print axioms enginePath_handover
#print axioms enginePath_no_forbidden
#print axioms emit_assignment
#print axioms Json.parse_strict
#print axioms Json.parse_canon
#print axioms Json.parse_canonical_injective
#print axioms deriveCase_decides
#print axioms releaseCase_decides
#print axioms deriveCase_unsupported
#print axioms advanceCase_decides
#print axioms verifyCase_decides
#print axioms verifyCase_verdict
#print axioms verifyCase_outputError
#print axioms cliCase_verify
#print axioms cliCase_decide
#print axioms cliCase_decide_release
#print axioms cliCase_advance
#print axioms decodeRegistry_transformations_sorted
#print axioms matchingTransformations_sorted
#print axioms verifyReasons_grounded
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
