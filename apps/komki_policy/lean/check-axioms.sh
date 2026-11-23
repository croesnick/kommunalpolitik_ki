#!/bin/sh
# Prints the axioms of the main theorems (Axioms.lean) and fails unless each
# one rests only on Lean's standard axioms. A `sorry` shows up as `sorryAx`,
# a home-made `axiom` under its own name; both fail here.
set -eu
cd "$(dirname "$0")"
out=$(lake env lean Axioms.lean)
printf '%s\n' "$out"
expected=$(grep -c '^#print axioms' Axioms.lean)
printed=$(printf '%s\n' "$out" | grep -c 'axioms' || true)
if [ "$printed" -ne "$expected" ]; then
  echo "Axioms.lean: $expected Sätze erwartet, $printed ausgegeben." >&2
  exit 1
fi
allowed='(propext|Classical\.choice|Quot\.sound)'
if printf '%s\n' "$out" | grep -Ev "does not depend on any axioms\$|depends on axioms: \[$allowed(, $allowed)*\]\$"; then
  echo "Axiom außerhalb der Positivliste (Zeile oben)." >&2
  exit 1
fi
