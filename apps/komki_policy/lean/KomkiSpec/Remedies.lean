import KomkiSpec.Release

/-!
# The whole remedy catalog (CONTRACT.md § 2.8)

`catalogGos` in `Release.lean` models the GO offers the theorems are about;
this file adds the other transitions, so the differential test can compare
`Remedies.catalog/3` entry by entry: `fakt_nachreichen` with its fact,
`registrierte_transformation`, `neuer_raum` with its required bindings and
recipients, in the normative order, with the decision-wide GO planning of
`withhold_call_go/3` and a `neuer_raum` wherever nothing else is left.
-/

namespace KomkiSpec

/-- A finding the catalog continues: a blocker or missing evidence. -/
structure Finding where
  code : String
  evidence : Bool
  condition : Option String := none
  fact : Option String := none

def Blocker.finding (b : Blocker) : Finding := { code := b.code, evidence := false, condition := b.condition }
def Evidence.finding (e : Evidence) : Finding := { code := e.code, evidence := true, fact := e.fact }

inductive Transition where
  | fakt (facts : List String)
  | transformation (id : String) (outputLabels : List String)
  | neuerRaum (requiredBindings requiredRecipients : List String)
  | go (g : Go)

/-- The normative order `fakt_nachreichen` < `registrierte_transformation` <
`neuer_raum` < `aktionsfreigabe` < `offenlegungsfreigabe`. -/
def Transition.rank : Transition → Nat
  | .fakt _ => 0
  | .transformation _ _ => 1
  | .neuerRaum _ _ => 2
  | .go (.aktion _) | .go (.object _) => 3
  | .go (.offenlegung _ _ _) => 4

/-- `ordered/1`: stable within a type; a `fakt_nachreichen` without a field is dropped. -/
def ordered (ts : List Transition) : List Transition :=
  ([0, 1, 2, 3, 4].flatMap fun r => ts.filter (·.rank == r)).filter fun
    | .fakt [] => false
    | _ => true

/-- `required_bindings_for/1`. -/
def requiredBindingsFor (c : CatalogCtx) : List String :=
  if c.rule == "admit" then sortStrings c.objectLabels else []

def neuerRaum (c : CatalogCtx) : Transition := .neuerRaum (requiredBindingsFor c) c.rho

/-- `matching_transformations/2`: inputs within λ(x), outputs within the checked label. -/
def matchingTransformations (Γ : Registry) (c : CatalogCtx) : List Transition :=
  (Γ.transformations.filter fun (_, input, output) =>
      input.all c.objectLabels.contains && output.all c.checked.contains).map
    fun (id, _, output) => .transformation id output

def callGo (c : CatalogCtx) : List Transition :=
  if outputOperations.contains c.rule then
    match c.callHash with
    | some h => [.go (.aktion h)]
    | none => []
  else []

/-- `regular_transitions/4`. -/
def regularTransitions (Γ : Registry) (c : CatalogCtx) (f : Finding) : List Transition :=
  if f.code == "object_quarantine" then [.go (.object c.objectRef)]
  else if unbridgeableCodes.contains f.code then [neuerRaum c]
  else if !f.evidence &&
      ["basis_right_false", "binding_condition_false", "audit_path_not_ready"].contains f.code then
    [.fakt f.condition.toList, neuerRaum c] ++ callGo c
  else if f.code == "label_not_included" then matchingTransformations Γ c ++ [neuerRaum c]
  else if ["recipient_not_allowed", "missing_operation_rule"].contains f.code then
    [neuerRaum c] ++ callGo c
  else if f.evidence && ["missing_fact", "recipients_unproven"].contains f.code then
    [.fakt f.fact.toList, neuerRaum c]
  else []

/-- `release_transitions/2`. -/
def releaseTransitions (c : CatalogCtx) (f : Finding) : List Transition :=
  if c.releaseKind == some "offenlegungsfreigabe" then
    if unbridgeableCodes.contains f.code || offenlegungUnbridgeableCodes.contains f.code ||
        f.code == "recipient_not_allowed" then [.neuerRaum [] c.rho]
    else [.go (.offenlegung (c.callHash.getD "") (c.ausgabeart.getD "") c.ziellabel)]
  else if unbridgeableCodes.contains f.code then [.neuerRaum [] c.rho]
  else [.go (.aktion (c.callHash.getD ""))]

/-- `catalog/3`: per finding, after `withhold_call_go/3`. -/
def catalog (Γ : Registry) (c : CatalogCtx) (fs : List Finding) : List (List Transition) :=
  let codes := fs.map (·.code)
  let stripAktion0 := codes.any (unbridgeableFor c.rule) || observersUnproven c
  let stripOff := codes.any (fun k => unbridgeableCodes.contains k ||
      offenlegungUnbridgeableCodes.contains k) ||
    (c.rule == "release" && codes.contains "recipient_not_allowed") || observersUnproven c
  let instead := c.rule == "store" && codes.contains "recipient_not_allowed" &&
    c.rule != "release" && offenlegungOfferable Γ c && !stripOff
  let built := fs.map fun f =>
    (f, ordered (if c.rule == "release" then releaseTransitions c f else regularTransitions Γ c f))
  -- `:keep` fills nothing up. Observably the same as filling: every code
  -- `derive` reports already has a continuation (`derive_deny_remedied`).
  if !(stripAktion0 || stripOff || instead) then built.map (·.2)
  else built.map fun (f, ts) =>
    let kept := ts.filter fun
      | .go (.aktion _) => !(stripAktion0 || instead)
      | .go (.offenlegung _ _ _) => !stripOff
      | _ => true
    let added := kept ++ (if instead && callGoCodes.contains f.code then
      [.go (.offenlegung (c.callHash.getD "") (c.ausgabeart.getD "") c.ziellabel)] else [])
    if added.isEmpty then [neuerRaum c] else added

end KomkiSpec
