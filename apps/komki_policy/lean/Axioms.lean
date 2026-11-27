import KomkiSpec

/-!
Prints the axioms each main theorem rests on. `check-axioms.sh` runs this
file and fails unless every theorem below depends only on Lean's standard
axioms (`propext`, `Classical.choice`, `Quot.sound`): a `sorry` shows up as
`sorryAx`, a home-made `axiom` under its own name. `lake build` already
fails on any `sorry`, since every warning is an error.
-/

open KomkiSpec

#print axioms verify_sound
#print axioms verify_sound_rfc
#print axioms admitDerivable_permitted
#print axioms eval_mono
#print axioms recipients_antitone
#print axioms permitted_antitone
#print axioms no_forbidden_recipient
