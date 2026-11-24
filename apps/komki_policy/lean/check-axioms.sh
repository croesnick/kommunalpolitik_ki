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
  verify_emit_assigns \
  eval_mono recipients_antitone permitted_antitone no_forbidden_recipient; do
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
