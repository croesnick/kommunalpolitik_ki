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
#print axioms eval_mono
#print axioms recipients_antitone
#print axioms permitted_antitone
#print axioms no_forbidden_recipient
