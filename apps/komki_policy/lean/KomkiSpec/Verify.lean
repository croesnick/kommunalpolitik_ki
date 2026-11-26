import KomkiSpec.Model

/-!
# `verify` for the `admit` branch (CONTRACT.md § 5)

Mirrors `KomkiPolicy.Verify.check/4` step by step. Only the verdict is
modelled: `verify.ex` reports reason codes and stops early after the
structural steps 1–3, but any finding means `invalid`, so the verdict is the
conjunction of all checks. Trees for `emit`, `store` and `transfer` are
`outOfScope` until their branches are modelled.
-/

namespace KomkiSpec

/-- `Derive.proof_rules/0`. -/
def proofRules : List String := ["admit", "emit", "transfer", "store"]

/-- Base facts among the § 4.3 premises. -/
def admitBaseFacts : List String :=
  ["has_operation_right", "has_object_access_right", "audit_path_ready",
   "environment_observers_complete"]

/-- The fixed § 4.3 slots, i.e. `required_premises("admit") -- ["binding_condition"]`. -/
def admitFixed : List String :=
  ["not_quarantine", "workspace_contract_valid"] ++ admitBaseFacts ++
  ["label_inclusion", "recipient_inclusion"]

/-- `Derive.required_premises("admit")`, in order. -/
def admitPremises : List String := admitFixed ++ ["binding_condition"]

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
def fitsSlot (bindings : List String) (p : Premise) : Bool :=
  admitPremises.contains p.name &&
  kindTable.lookup p.name == some p.kind &&
  (p.kind != "fact" || p.strField? "fact" == some p.name) &&
  (p.name != "binding_condition" || boundTo bindings p)

/-- Bindings that carry a `binding_condition` premise of kind `condition`. -/
def conditionBindings (ps : List Premise) : List String :=
  ps.filterMap fun p =>
    if p.kind == "condition" && p.name == "binding_condition" then p.strField? "binding"
    else none

/-- Step 3: every fixed slot named, a condition for every binding, no unknown premise. -/
def requiredSetOk (bindings : List String) (ps : List Premise) : Bool :=
  admitFixed.all (fun n => ps.any (·.name == n)) &&
  bindings.all (conditionBindings ps).contains &&
  ps.all (fitsSlot bindings)

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

/-- Step 6: λ(x) ⊆ B_W, claims as computed. -/
def labelInclusionOk (S : Snapshot) (p : Premise) : Bool :=
  S.objectLabels.all S.workspaceBindings.contains && p.value &&
  p.get? "object_labels" == some (strs (sortStrings S.objectLabels)) &&
  p.get? "checked_label" == some (strs S.workspaceBindings)

/-- `Calculus.allowed_recipients/2`: R_Γ(∅) = 𝒪, otherwise the sorted
intersection of all readers. Readers are unique (`Registry.compile/1`), so
the filtered list equals Elixir's sorted `MapSet` without deduplication. -/
def allowedRecipients (Γ : Registry) : List String → List String
  | [] => Γ.observers
  | b :: bs =>
    sortStrings ((Γ.readersOf b).filter fun o => bs.all fun b' => (Γ.readersOf b').contains o)

/-- Step 7: ρ_Γ(c) ⊆ R_Γ(B_W), claims as computed. -/
def recipientInclusionOk (Γ : Registry) (S : Snapshot) (p : Premise) : Bool :=
  match Γ.environment? S.environment with
  | none => false
  | some env =>
    let rho := sortStrings env
    let allowed := allowedRecipients Γ S.workspaceBindings
    rho.all allowed.contains && p.value &&
    p.get? "actual_recipients" == some (strs rho) &&
    p.get? "allowed_recipients" == some (strs allowed)

/-- Step 8: the registry's admit expression, exactly as claimed, evaluates to `true` (#477). -/
def conditionOk (Γ : Registry) (S : Snapshot) (p : Premise) : Bool :=
  match p.strField? "binding" with
  | none => false
  | some b =>
    match Γ.ruleExpr? b "admit" with
    | none => false
    | some j =>
      match Expr.ofJVal j with
      | none => false
      | some e =>
        p.get? "expression" == some j &&
        p.get? "fact_refs" == some (strs (sortDedup e.fields)) &&
        eval S.fact? e == .true && p.value

/-- Steps 4–8 for one premise, dispatched by kind as in `predicate_reasons/3`.
`label_preservation` never holds for `admit`; step 3 already rejects it. -/
def premiseOk (Γ : Registry) (S : Snapshot) (p : Premise) : Bool :=
  if p.kind == "fact" then factPremiseOk S p
  else if p.kind == "object_check" then quarantineOk S p
  else if p.kind == "condition" then conditionOk Γ S p
  else if p.kind == "computed" then
    if p.name == "label_inclusion" then labelInclusionOk S p
    else if p.name == "recipient_inclusion" then recipientInclusionOk Γ S p
    else p.name != "label_preservation"
  else true

inductive Outcome where
  | valid
  | invalid
  /-- A tree for a rule branch this model does not cover yet. -/
  | outOfScope
  deriving DecidableEq, Repr

/-- `verify` for one tree; step 9 is the conjunction itself plus `conclusion = permit`. -/
def verify (Γ : Registry) (S : Snapshot) (I : Intent) (P : Proof) : Outcome :=
  if !referencesOk Γ S I P then .invalid
  else if P.rule != "admit" then .outOfScope
  else if sortStrings P.checkedLabel != S.workspaceBindings then .invalid
  else if !requiredSetOk S.workspaceBindings P.premises then .invalid
  else if P.premises.all (premiseOk Γ S) && P.conclusion == "permit" then .valid
  else .invalid

end KomkiSpec
