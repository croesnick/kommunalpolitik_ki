import KomkiSpec.Verify

/-!
# `derive`, the normal branch (CONTRACT.md § 4.3–§ 4.5, § 4.7, § 4.8)

Mirrors `KomkiPolicy.Derive.decide/3` for `admit`, `emit`, `store` and
`transfer`: the premises in their fixed order, each yielding blockers (known
false) or missing evidence (unknown), the decision by § 4.4, and on `permit`
the proof tree of § 2.5. Not modelled: the remedy catalog (§ 2.8) and the
release branches (§ 4.6, § 4.9). Of the input errors, the model has the
ones `derive` raises after `Context`'s schema checks: an unknown environment
and the snapshot prerequisites of the output rules.
-/

namespace KomkiSpec

/-- A blocker of a `deny` (§ 2.4); `outside` only for `recipient_not_allowed` (#417). -/
structure Blocker where
  code : String
  binding : Option String := none
  condition : Option String := none
  outside : Option (List String) := none

/-- Missing evidence of an `indeterminate` (§ 2.4). -/
structure Evidence where
  code : String
  fact : Option String
  binding : Option String := none

/-- What one premise contributes to the decision. -/
structure Findings where
  blockers : List Blocker := []
  evidence : List Evidence := []

inductive Decision where
  | permit (proof : Proof)
  | deny (blockers : List Blocker)
  | indeterminate (evidence : List Evidence)

inductive Derived where
  | decision (d : Decision)
  | inputError (code : String)
  /-- A rule branch without an implementation, e.g. `start`: never a `deny` (§ 1). -/
  | unsupported

def blocking (b : Blocker) : Findings := { blockers := [b] }
def lacking (e : Evidence) : Findings := { evidence := [e] }
def holds : Findings := {}

/-! ## The premises -/

/-- `fact_state/2`: a present value counts by Elixir truthiness. -/
def factState (S : Snapshot) (n : String) : Verdict :=
  match S.fact? n with
  | none => .unknown
  | some (.bool false) | some .null => .false
  | some _ => .true

/-- `admit` P1: only `quarantine` blocks, as in `premise_quarantine/1`. -/
def quarantineFindings (S : Snapshot) : Findings :=
  if S.classification == "quarantine" then blocking { code := "object_quarantine" } else holds

def workspaceFindings (S : Snapshot) : Findings :=
  if S.workspaceValid then holds else blocking { code := "workspace_invalid" }

/-- `premise_basis_fact/2`: false blocks, missing lacks evidence. -/
def basisFindings (S : Snapshot) (n : String) : Findings :=
  match factState S n with
  | .true => holds
  | .false =>
    if n == "audit_path_ready" then blocking { code := "audit_path_not_ready", condition := some n }
    else blocking { code := "basis_right_false", condition := some n }
  | .unknown => lacking { code := "missing_fact", fact := some n }

/-- `premise_env_flag/1`: an unproven observer list is missing evidence,
never a blocker (§ 4.3 item 6). -/
def envFindings (S : Snapshot) : Findings :=
  if factState S "environment_observers_complete" == .true then holds
  else lacking { code := "recipients_unproven", fact := some "environment_observers_complete" }

/-- `Calculus.labels_subset?/2`. -/
def subsetOf (xs ys : List String) : Bool := xs.all ys.contains

def labelInclusionFindings (S : Snapshot) (checked : List String) : Findings :=
  if subsetOf S.objectLabels checked then holds else blocking { code := "label_not_included" }

def labelPreservationFindings (S : Snapshot) (checked : List String) : Findings :=
  if subsetOf S.workspaceBindings checked then holds else blocking { code := "label_not_preserved" }

/-- `premise_recipient_inclusion/1`: ρ_Γ(c) -- R_Γ(checked label). -/
def recipientFindings (Γ : Registry) (rho checked : List String) : Findings :=
  let allowed := allowedRecipients Γ checked
  match rho.filter fun o => !allowed.contains o with
  | [] => holds
  | outside => blocking { code := "recipient_not_allowed", outside := some outside }

mutual
/-- `locate_field/3`: the first field, in evaluation order, of a clause
with the verdict `kind`. -/
def locate (facts : Facts) (kind : Verdict) : Expr → Option String
  | .tt | .ff => none
  | .eq f _ | .member f _ | .subset f _ | .atMost f _ => some f
  | .all cs | .any cs => locateFirst facts kind cs

def locateFirst (facts : Facts) (kind : Verdict) : List Expr → Option String
  | [] => none
  | c :: cs =>
    if eval facts c == kind then (locate facts kind c).orElse fun _ => locateFirst facts kind cs
    else locateFirst facts kind cs
end

/-- `premise_binding_conditions/3` for one binding. A missing rule blocks
(B.4); so does an expression outside B.4, which `Registry.compile/1` never
lets through. -/
def conditionFindings (Γ : Registry) (S : Snapshot) (rule b : String) : Findings :=
  match (Γ.ruleExpr? b rule).bind Expr.ofJVal with
  | none => blocking { code := "missing_operation_rule", binding := some b }
  | some e =>
    match eval S.fact? e with
    | .true => holds
    | .false =>
      blocking { code := "binding_condition_false", binding := some b,
                 condition := locate S.fact? .false e }
    | .unknown =>
      lacking { code := "missing_fact", fact := locate S.fact? .unknown e, binding := some b }

/-- ρ_Γ(c), sorted. -/
def actualRecipients (Γ : Registry) (S : Snapshot) : List String :=
  sortStrings ((Γ.environment? S.environment).getD [])

/-- The premises of `run_admit/3`, `run_emit/3` and `run_handover/4`, in order. -/
def premiseFindings (Γ : Registry) (S : Snapshot) (rule : String) : List Findings :=
  let checked := checkedLabel rule S
  let recipient := recipientFindings Γ (actualRecipients Γ S) checked
  let conditions := checked.map (conditionFindings Γ S rule)
  if rule == "admit" then
    [quarantineFindings S, workspaceFindings S, basisFindings S "has_operation_right",
     basisFindings S "has_object_access_right", basisFindings S "audit_path_ready", envFindings S,
     labelInclusionFindings S checked, recipient] ++ conditions
  else if rule == "emit" then
    [workspaceFindings S, basisFindings S "has_operation_right",
     basisFindings S "audit_path_ready", envFindings S, recipient] ++ conditions
  else
    [workspaceFindings S, basisFindings S "has_operation_right",
     basisFindings S "audit_path_ready", envFindings S, labelPreservationFindings S checked,
     recipient] ++ conditions

/-! ## The proof tree (§ 2.5) -/

def mkPremise (name kind : String) (extra : List (String × JVal)) : Premise :=
  { name, kind, value := true,
    fields := [("name", .str name), ("kind", .str kind), ("value", .bool true)] ++ extra }

def basisPremise (S : Snapshot) (n : String) : Premise :=
  let src := (S.factSources.lookup n).getD ("", "")
  mkPremise n "fact" [("fact", .str n), ("source", .str src.1), ("source_kind", .str src.2)]

def conditionPremise (Γ : Registry) (rule b : String) : Premise :=
  let j := (Γ.ruleExpr? b rule).getD .null
  let refs := match Expr.ofJVal j with
    | some e => sortDedup e.fields
    | none => []
  mkPremise "binding_condition" "condition"
    [("binding", .str b), ("expression", j), ("fact_refs", strs refs)]

/-- `build_proof/4`: the premises in the order of § 4.3, § 4.5 and § 4.7;
`label_assignment` closes the `emit` tree. -/
def proofPremises (Γ : Registry) (S : Snapshot) (rule : String) : List Premise :=
  let checked := checkedLabel rule S
  let workspace := mkPremise "workspace_contract_valid" "fact"
    [("fact", .str "workspace_contract_valid"), ("source", .str "workspace.valid")]
  let recipient := mkPremise "recipient_inclusion" "computed"
    [("actual_recipients", strs (actualRecipients Γ S)),
     ("allowed_recipients", strs (allowedRecipients Γ checked))]
  let conditions := checked.map (conditionPremise Γ rule)
  if rule == "admit" then
    [mkPremise "not_quarantine" "object_check"
       [("object", .str S.objectRef), ("classification", .str "classified")],
     workspace, basisPremise S "has_operation_right", basisPremise S "has_object_access_right",
     basisPremise S "audit_path_ready", basisPremise S "environment_observers_complete",
     mkPremise "label_inclusion" "computed"
       [("object_labels", strs S.objectLabels), ("checked_label", strs checked)],
     recipient] ++ conditions
  else if rule == "emit" then
    [workspace, basisPremise S "has_operation_right", basisPremise S "audit_path_ready",
     basisPremise S "environment_observers_complete", recipient] ++ conditions ++
    [mkPremise "label_assignment" "computed"
       [("assigned_label", strs checked), ("checked_label", strs checked)]]
  else
    [workspace, basisPremise S "has_operation_right", basisPremise S "audit_path_ready",
     basisPremise S "environment_observers_complete",
     mkPremise "label_preservation" "computed"
       [("workspace_bindings", strs S.workspaceBindings), ("checked_label", strs checked)],
     recipient] ++ conditions

def buildProof (Γ : Registry) (S : Snapshot) (I : Intent) : Proof :=
  { rule := I.operation, conclusion := "permit", registryRef := Γ.registryId,
    snapshotRef := S.snapshotId, intentRef := I.intentId,
    checkedLabel := checkedLabel I.operation S, premises := proofPremises Γ S I.operation }

/-! ## The decision (§ 4.4) -/

def blockersOf (fs : List Findings) : List Blocker := (fs.map (·.blockers)).flatten
def evidenceOf (fs : List Findings) : List Evidence := (fs.map (·.evidence)).flatten

/-- Known false beats unknown beats permit. -/
def decideRule (Γ : Registry) (S : Snapshot) (I : Intent) : Decision :=
  let fs := premiseFindings Γ S I.operation
  if !(blockersOf fs).isEmpty then .deny (blockersOf fs)
  else if !(evidenceOf fs).isEmpty then .indeterminate (evidenceOf fs)
  else .permit (buildProof Γ S I)

/-- `decide/3`: `start` is unsupported before the snapshot is read; the
snapshot's environment must exist (`unknown_environment`); the output rules
need their prerequisites (#628). -/
def derive (Γ : Registry) (S : Snapshot) (I : Intent) : Derived :=
  if !proofRules.contains I.operation then .unsupported
  else if (Γ.environment? S.environment).isNone then .inputError "unknown_environment"
  else if outputOperations.contains I.operation &&
      (S.facts.lookup "output_content_digest").isNone then .inputError "emit_digest_missing"
  else if outputOperations.contains I.operation && S.classification != "classified" then
    .inputError "emit_object_not_classified"
  else .decision (decideRule Γ S I)

end KomkiSpec
