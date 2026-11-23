import KomkiKalkuel

/-!
# PROTOTYPE (throwaway): RFC 0003 D.1 run through the Lean engine

A public file (λ(x) = ∅) in the Bürgerfall room. Label inclusion and the
recipient test pass, the case binding's scope condition is false, so `admit`
must deny. A deliberately broken engine that checks only λ(x) permits.
-/

open KomkiKalkuel

def factsOf (l : List (String × Value)) : Facts := fun k => l.lookup k

def d1Registry : Registry String String where
  observers := ["cloud-ki", "lokale-fallverarbeitung", "nutzende-person", "oeffentlichkeit"]
  readers
    | "buergerfall-4711@1" => ["lokale-fallverarbeitung", "nutzende-person"]
    | _ => []
  admitRule
    | "buergerfall-4711@1" =>
      some (.all [.eq "zweck" (.str "antwort-fall-4711"),
                  .eq "datei_im_fallumfang" (.bool true)])
    | _ => none

def baseOk : List (String × Value) :=
  baseFacts.map fun n => (n, .bool true)

def d1 (scope : List (String × Value)) : AdmitInput String String where
  workspaceBindings := ["buergerfall-4711@1"]
  objectLabels := []
  environmentObservers := ["nutzende-person", "lokale-fallverarbeitung"]
  facts := factsOf (baseOk ++ [("zweck", .str "antwort-fall-4711")] ++ scope)

/-- The broken engine D.1 warns about: validates against λ(x) instead of B_W. -/
def admitBroken (Γ : Registry String String) (i : AdmitInput String String) : Decision :=
  admit Γ { i with workspaceBindings := i.objectLabels }

/-- Premises with their CONTRACT.md names, to show the full state. -/
def premises (Γ : Registry String String) (i : AdmitInput String String) :=
  (baseFacts ++ ["label_inclusion", "recipient_inclusion"] ++
    i.workspaceBindings.map ("binding_condition " ++ ·)).zip (admitPremises Γ i)

def outOfScope := d1 [("datei_im_fallumfang", .bool false)]
def inScope := d1 [("datei_im_fallumfang", .bool true)]
def scopeMissing := d1 []

#eval premises d1Registry outOfScope
#eval (admit d1Registry outOfScope, admitBroken d1Registry outOfScope)  -- (deny, permit)
#eval admit d1Registry inScope                                           -- permit
#eval admit d1Registry scopeMissing                                      -- indeterminate
#eval admit d1Registry { inScope with
  environmentObservers := ["nutzende-person", "cloud-ki"] }              -- deny: recipient
#eval allowedRecipients d1Registry []                                    -- R_Γ(∅) = 𝒪

/-- Why `mem_allowedRecipients` needs `WellFormed`: a binding whose readers
leave 𝒪. The Elixir formula then names a recipient outside the observer space. -/
def notWellFormed : Registry String String :=
  { d1Registry with readers := fun _ => ["fremder-dienst"] }

#eval (allowedRecipients notWellFormed ["buergerfall-4711@1"],
       decide ("fremder-dienst" ∈ notWellFormed.observers))              -- (["fremder-dienst"], false)

-- No `sorry`: each theorem rests only on Lean's standard axioms.
#print axioms recipients_antitone
#print axioms permitted_antitone
#print axioms no_forbidden_recipient
#print axioms eval_mono
#print axioms mem_allowedRecipients
#print axioms admit_sound
