import KomkiSpec.Model

/-!
# `verify` for `admit`, `emit`, `store` and `transfer` (CONTRACT.md § 5)

Mirrors `KomkiPolicy.Verify.check/4` step by step. Only the verdict is
modelled: `verify.ex` reports reason codes and stops early after the
structural steps 1–3, but any finding means `invalid`, so the verdict is the
conjunction of all checks. Of the input errors, only the snapshot
prerequisites of the output rules are modelled (#628); the others mark the
edge of the validated domain.
-/

namespace KomkiSpec

/-- `Derive.proof_rules/0`. -/
def proofRules : List String := ["admit", "emit", "transfer", "store"]

/-- `Derive.output_operations/0`: the rules with an output object (§ 4.5). -/
def outputOperations : List String := ["emit", "transfer", "store"]

/-- `Derive.handover_operations/0`: decided under λ(y) (§ 4.7, § 4.8). -/
def handoverOperations : List String := ["transfer", "store"]

/-- Base facts among the § 4.3 premises. -/
def admitBaseFacts : List String :=
  ["has_operation_right", "has_object_access_right", "audit_path_ready",
   "environment_observers_complete"]

/-- Base facts of the output rules: no `has_object_access_right` (§ 4.5). -/
def outputBaseFacts : List String :=
  ["has_operation_right", "audit_path_ready", "environment_observers_complete"]

def baseFacts (rule : String) : List String :=
  if rule == "admit" then admitBaseFacts else outputBaseFacts

/-- The fixed slots, i.e. `required_premises(rule) -- ["binding_condition"]`,
in the order of § 4.3, § 4.5, § 4.7 and § 4.8. -/
def fixedPremises (rule : String) : List String :=
  if rule == "admit" then
    ["not_quarantine", "workspace_contract_valid"] ++ admitBaseFacts ++
    ["label_inclusion", "recipient_inclusion"]
  else if rule == "emit" then
    ["workspace_contract_valid"] ++ outputBaseFacts ++ ["recipient_inclusion", "label_assignment"]
  else
    ["workspace_contract_valid"] ++ outputBaseFacts ++ ["label_preservation", "recipient_inclusion"]

/-- `Derive.required_premises/1`, in order. -/
def requiredPremises (rule : String) : List String := fixedPremises rule ++ ["binding_condition"]

/-- `Derive.checked_label/3`: B_W for `admit` and `emit`, λ(y) for `store`
and `transfer` (§ 2.4). `Context` has checked that λ(y) is sorted and
unique, so `Enum.sort(Enum.uniq(_))` keeps it as it is. -/
def checkedLabel (rule : String) (S : Snapshot) : List String :=
  if handoverOperations.contains rule then S.objectLabels else S.workspaceBindings

/-- `@premise_kinds_by_name` in `verify.ex` (§ 2.5). -/
def kindTable : List (String × String) :=
  [("not_quarantine", "object_check"),
   ("workspace_contract_valid", "fact"),
   ("has_operation_right", "fact"),
   ("has_object_access_right", "fact"),
   ("audit_path_ready", "fact"),
   ("environment_observers_complete", "fact"),
   ("label_inclusion", "computed"),
   ("label_assignment", "computed"),
   ("label_preservation", "computed"),
   ("recipient_inclusion", "computed"),
   ("binding_condition", "condition")]

/-! ## Steps 1–3: structure -/

/-- Step 1: references and rule. -/
def referencesOk (Γ : Registry) (S : Snapshot) (I : Intent) (P : Proof) : Bool :=
  P.snapshotRef == S.snapshotId && P.registryRef == Γ.registryId &&
  P.intentRef == I.intentId && proofRules.contains P.rule && P.rule == I.operation

/-- A `binding_condition` slot exists only for a binding of the checked label. -/
def boundTo (bindings : List String) (p : Premise) : Bool :=
  match p.strField? "binding" with
  | some b => bindings.contains b
  | none => false

/-- `fits_slot_in_rule?/3`: a known name of the rule, with the kind the
table assigns, a fact premise only for the fact its name names (#479). -/
def fitsSlot (rule : String) (bindings : List String) (p : Premise) : Bool :=
  (requiredPremises rule).contains p.name &&
  kindTable.lookup p.name == some p.kind &&
  (p.kind != "fact" || p.strField? "fact" == some p.name) &&
  (p.name != "binding_condition" || boundTo bindings p)

/-- Bindings that carry a `binding_condition` premise of kind `condition`. -/
def conditionBindings (ps : List Premise) : List String :=
  ps.filterMap fun p =>
    if p.kind == "condition" && p.name == "binding_condition" then p.strField? "binding"
    else none

/-- Step 3: every fixed slot named, a condition for every binding of the
checked label, no unknown premise. -/
def requiredSetOk (rule : String) (bindings : List String) (ps : List Premise) : Bool :=
  (fixedPremises rule).all (fun n => ps.any (·.name == n)) &&
  bindings.all (conditionBindings ps).contains &&
  ps.all (fitsSlot rule bindings)

/-! ## Steps 4–8: premises, recomputed from registry and snapshot -/

/-- Step 4: the claim mirrors the snapshot, and the snapshot value is `true` (#480). -/
def factPremiseOk (S : Snapshot) (p : Premise) : Bool :=
  match p.strField? "fact" with
  | some f =>
    if f == "workspace_contract_valid" then p.value == S.workspaceValid && S.workspaceValid
    else
      match S.fact? f with
      | some (.bool b) => p.value == b && b
      | _ => false
  | none => false

/-- Step 5. -/
def quarantineOk (S : Snapshot) (p : Premise) : Bool :=
  S.classification == "classified" && p.value

/-- Step 6 for `admit`: λ(x) ⊆ B_W, claims as computed. -/
def labelInclusionOk (S : Snapshot) (p : Premise) : Bool :=
  S.objectLabels.all S.workspaceBindings.contains && p.value &&
  p.get? "object_labels" == some (strs (sortStrings S.objectLabels)) &&
  p.get? "checked_label" == some (strs S.workspaceBindings)

/-- The strings of a JSON array; `none` if one element is no string. -/
def strings? (xs : List JVal) : Option (List String) :=
  xs.mapM fun
    | .str s => some s
    | _ => none

/-- Step 6 for `emit`: `assigned_label` is B_W as a set, the other claims
exactly (`label_assignment_ok?/2`). -/
def labelAssignmentOk (S : Snapshot) (p : Premise) : Bool :=
  (match p.get? "assigned_label" with
   | some (.arr xs) =>
     match strings? xs with
     | some ls => sortDedup ls == S.workspaceBindings
     | none => false
   | _ => false) &&
  p.get? "checked_label" == some (strs S.workspaceBindings) && p.value

/-- Step 6 for `store` and `transfer`: B_W ⊆ λ(y), claims as computed. Never
holds in a tree of another rule. -/
def labelPreservationOk (S : Snapshot) (rule : String) (p : Premise) : Bool :=
  handoverOperations.contains rule &&
  S.workspaceBindings.all (checkedLabel rule S).contains && p.value &&
  p.get? "workspace_bindings" == some (strs S.workspaceBindings) &&
  p.get? "checked_label" == some (strs (checkedLabel rule S))

/-- `Calculus.allowed_recipients/2`: R_Γ(∅) = 𝒪, otherwise the sorted
intersection of all readers. Readers are unique (`Registry.compile/1`), so
the filtered list equals Elixir's sorted `MapSet` without deduplication. -/
def allowedRecipients (Γ : Registry) : List String → List String
  | [] => Γ.observers
  | b :: bs =>
    sortStrings ((Γ.readersOf b).filter fun o => bs.all fun b' => (Γ.readersOf b').contains o)

/-- Step 7: ρ_Γ(c) ⊆ R_Γ(checked label), claims as computed. -/
def recipientInclusionOk (Γ : Registry) (S : Snapshot) (checked : List String) (p : Premise) :
    Bool :=
  match Γ.environment? S.environment with
  | none => false
  | some env =>
    let rho := sortStrings env
    let allowed := allowedRecipients Γ checked
    rho.all allowed.contains && p.value &&
    p.get? "actual_recipients" == some (strs rho) &&
    p.get? "allowed_recipients" == some (strs allowed)

/-- Step 8: the registry's expression for the tree's rule, exactly as
claimed, evaluates to `true` (#477). -/
def conditionOk (Γ : Registry) (S : Snapshot) (rule : String) (p : Premise) : Bool :=
  match p.strField? "binding" with
  | none => false
  | some b =>
    match Γ.ruleExpr? b rule with
    | none => false
    | some j =>
      match Expr.ofJVal j with
      | none => false
      | some e =>
        p.get? "expression" == some j &&
        p.get? "fact_refs" == some (strs (sortDedup e.fields)) &&
        eval S.fact? e == .true && p.value

/-- Steps 4–8 for one premise of a tree for `rule`, dispatched by kind and
name as in `predicate_reasons/3`. -/
def premiseOk (Γ : Registry) (S : Snapshot) (rule : String) (p : Premise) : Bool :=
  if p.kind == "fact" then factPremiseOk S p
  else if p.kind == "object_check" then quarantineOk S p
  else if p.kind == "condition" then conditionOk Γ S rule p
  else if p.kind == "computed" then
    if p.name == "label_inclusion" then labelInclusionOk S p
    else if p.name == "label_assignment" then rule != "emit" || labelAssignmentOk S p
    else if p.name == "label_preservation" then labelPreservationOk S rule p
    else if p.name == "recipient_inclusion" then recipientInclusionOk Γ S (checkedLabel rule S) p
    else true
  else true

/-- `Context.ensure_output_input/1`: the digest fact and a classified object (§ 4.5, #628). -/
def outputInputOk (S : Snapshot) : Bool :=
  (S.facts.lookup "output_content_digest").isSome && S.classification == "classified"

inductive Outcome where
  | valid
  | invalid
  /-- `emit_digest_missing` or `emit_object_not_classified`. -/
  | inputError
  deriving DecidableEq, Repr

/-- `verify` for one tree; step 9 is the conjunction itself plus `conclusion = permit`. -/
def verify (Γ : Registry) (S : Snapshot) (I : Intent) (P : Proof) : Outcome :=
  if outputOperations.contains I.operation && !outputInputOk S then .inputError
  else if !referencesOk Γ S I P then .invalid
  else if sortStrings P.checkedLabel != checkedLabel P.rule S then .invalid
  else if !requiredSetOk P.rule (checkedLabel P.rule S) P.premises then .invalid
  else if P.premises.all (premiseOk Γ S P.rule) && P.conclusion == "permit" then .valid
  else .invalid

end KomkiSpec
