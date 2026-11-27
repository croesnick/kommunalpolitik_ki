#!/bin/sh
# Prints the axioms of the main theorems (Axioms.lean) and fails unless each
# one rests only on Lean's standard axioms. A `sorry` shows up as `sorryAx`,
# a home-made `axiom` under its own name; both fail here, and so does a main
# theorem that Axioms.lean no longer prints.
set -eu
cd "$(dirname "$0")"
if ! out=$(lake env lean Axioms.lean 2>&1); then
  printf '%s\n' "$out"
  exit 1
fi
printf '%s\n' "$out"
for theorem in verify_sound verify_sound_rfc derivable_permitted handover_within_admitted \
  verify_emit_assigns derive_sound derive_complete derive_permit_stable derive_deny_stable \
  derive_verifies verifyReport_verdict proofError_decodes snapshotError_validated registryError_compiledOk \
  Json.canonical_injective callHashInput_isSome callHashInput_injective \
  enginePath_preservation enginePath_handover enginePath_no_forbidden emit_assignment \
  Json.parse_strict Json.parse_canon Json.parse_canonical_injective \
  deriveCase_decides releaseCase_decides deriveCase_unsupported advanceCase_decides \
  verifyCase_decides verifyCase_verdict verifyCase_outputError cliCase_verify \
  cliCase_decide cliCase_decide_release cliCase_advance \
  decodeRegistry_transformations_sorted matchingTransformations_sorted \
  verifyReasons_grounded aktion_permit offenlegung_permit release_single_use advance_cas \
  catalog_aktion_effective catalog_offenlegung_effective catalog_gos \
  release_catalog_aktion_effective release_catalog_offenlegung_effective \
  release_catalog_offenlegung_grantable \
  release_remedies_aktion_effective release_remedies_offenlegung_effective \
  remedies_aktion_effective remedies_offenlegung_effective catalog_ascending \
  derive_blockers_named derive_evidence_named derive_fakt_deny derive_fakt_indeterminate \
  derive_transformations_listed remedies_transformation catalog_neuerRaum neuer_raum_necessary \
  neuer_raum_recipients_necessary \
  derive_deny_remedied derive_indeterminate_remedied release_remedied \
  eval_mono recipients_antitone permitted_antitone no_forbidden_recipient \
  Registry.compiledOk_sound Snapshot.validated_sound; do
  if ! printf '%s\n' "$out" | grep -q "^'KomkiSpec\.$theorem' "; then
    echo "Axioms.lean gibt den Hauptsatz $theorem nicht aus." >&2
    exit 1
  fi
done
allowed='(propext|Classical\.choice|Quot\.sound)'
if printf '%s\n' "$out" | grep -Ev "does not depend on any axioms\$|depends on axioms: \[$allowed(, $allowed)*\]\$"; then
  echo "Axiom außerhalb der Positivliste (Zeile oben)." >&2
  exit 1
fi
