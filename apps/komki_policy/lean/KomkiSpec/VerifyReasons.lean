import KomkiSpec.Verify

/-!
# `verify`'s findings (CONTRACT.md § 5)

The reasons `KomkiPolicy.Verify.check/4` reports, in its order: the
structural steps 1–3 stop at the first step with findings; steps 4–8 collect
category by category, each in premise order; step 9 adds
`conclusion_mismatch` after any premise finding and `conclusion_unsupported`
for a conclusion other than `permit`. `verifyReport_verdict` ties the report
to `verify` (Verify.lean): no findings exactly when the verdict is `valid`,
so every theorem about `verify` holds for the report as well.
-/

namespace KomkiSpec

/-- One entry of `reasons`: `{"code", "binding", "fact"}`. -/
structure Reason where
  code : String
  binding : Option String := none
  fact : Option String := none
  deriving DecidableEq, Repr

def reasonIf (b : Bool) (r : Reason) : List Reason := if b then [r] else []

/-- `invalid`'s single finding for a computed premise that does not hold. -/
def failIf (ok : Bool) (code : String) : List Reason := reasonIf (!ok) { code }

/-! ## Steps 1–3: structure -/

/-- Step 1: `reference_reasons/4`. -/
def referenceReasons (Γ : Registry) (S : Snapshot) (I : Intent) (P : Proof) : List Reason :=
  reasonIf (P.snapshotRef != S.snapshotId) { code := "snapshot_mismatch" } ++
  reasonIf (P.registryRef != Γ.registryId) { code := "registry_mismatch" } ++
  reasonIf (P.intentRef != I.intentId) { code := "intent_mismatch" } ++
  if proofRules.contains P.rule then reasonIf (P.rule != I.operation) { code := "rule_mismatch" }
  else [{ code := "unsupported_rule" }]

/-- Step 2: `label_mismatch_reasons/2`. -/
def labelReasons (S : Snapshot) (P : Proof) : List Reason :=
  reasonIf (sortStrings P.checkedLabel != checkedLabel P.rule S) { code := "checked_label_mismatch" }

/-- Step 3: `required_set_reasons/2`: the missing fixed slots, then a missing
condition per binding of the checked label, then the premises that fit no
slot. -/
def requiredSetReasons (rule : String) (bindings : List String) (ps : List Premise) :
    List Reason :=
  ((fixedPremises rule).filter fun n => !ps.any (·.name == n)).map
    (fun _ => { code := "missing_required_premise" }) ++
  (bindings.filter fun b => !(conditionBindings ps).contains b).map
    (fun b => { code := "missing_required_premise", binding := some b }) ++
  (ps.filter fun p => !fitsSlot rule bindings p).map
    fun p => { code := "unknown_premise", binding := p.strField? "binding" }

/-! ## Steps 4–8: premises -/

/-- Step 4: `fact_premise_finding/2`, the claim before the value. Without a
`fact` (unreachable after step 3) `verify.ex` looks up `nil`. -/
def factReasons (S : Snapshot) (p : Premise) : List Reason :=
  let claim (f : String) : JVal → List Reason
    | .bool b =>
      if p.value != b then [{ code := "fact_value_mismatch", fact := some f }]
      else reasonIf (!b) { code := "premise_not_true", fact := some f }
    | _ => [{ code := "fact_value_mismatch", fact := some f }]
  match p.strField? "fact" with
  | none => [{ code := "fact_missing" }]
  | some f =>
    if f == "workspace_contract_valid" then claim f (.bool S.workspaceValid)
    else
      match S.fact? f with
      | none => [{ code := "fact_missing", fact := some f }]
      | some v => claim f v

/-- Step 5: `quarantine_reasons/2`. -/
def quarantineReasons (S : Snapshot) (p : Premise) : List Reason :=
  if S.classification != "classified" then [{ code := "object_quarantine" }]
  else reasonIf (!p.value) { code := "premise_not_true" }

/-- Step 8: `condition_reasons/3`: expression, `fact_refs`, the recomputed
verdict, the claimed value. Without a registry entry only the expression
check and the claim run. A compiled registry's expressions parse; were one
not to, no tree would pass. -/
def conditionReasons (Γ : Registry) (S : Snapshot) (rule : String) (p : Premise) :
    List Reason :=
  let b := p.strField? "binding"
  let claimed := reasonIf (!p.value) { code := "condition_false", binding := b }
  match b.bind (Γ.ruleExpr? · rule) with
  | none => { code := "expression_mismatch", binding := b } :: claimed
  | some j =>
    reasonIf (!(p.get? "expression" == some j)) { code := "expression_mismatch", binding := b } ++
    (match Expr.ofJVal j with
     | none => [{ code := "condition_unknown", binding := b }]
     | some e =>
       reasonIf (!(p.get? "fact_refs" == some (strs (sortDedup e.fields))))
         { code := "fact_refs_mismatch", binding := b } ++
       match eval S.fact? e with
       | .true => []
       | .false => [{ code := "condition_false", binding := b }]
       | .unknown => [{ code := "condition_unknown", binding := b }]) ++
    claimed

/-- Steps 4–8 for one premise, dispatched as `premiseOk`. -/
def premiseReasons (Γ : Registry) (S : Snapshot) (rule : String) (p : Premise) : List Reason :=
  if p.kind == "fact" then factReasons S p
  else if p.kind == "object_check" then quarantineReasons S p
  else if p.kind == "condition" then conditionReasons Γ S rule p
  else if p.kind == "computed" then
    if p.name == "label_inclusion" then failIf (labelInclusionOk S p) "label_inclusion_false"
    else if p.name == "label_assignment" then
      failIf (rule != "emit" || labelAssignmentOk S p) "label_assignment_false"
    else if p.name == "label_preservation" then
      failIf (labelPreservationOk S rule p) "label_preservation_false"
    else if p.name == "recipient_inclusion" then
      failIf (recipientInclusionOk Γ S (checkedLabel rule S) p) "recipient_inclusion_false"
    else []
  else []

/-- The group a premise's findings come in: its kind, a computed premise's
name. -/
def category (p : Premise) : String := if p.kind == "computed" then p.name else p.kind

/-- The groups of `predicate_reasons/3`, in order. -/
def categories : List String :=
  ["fact", "object_check", "label_inclusion", "label_assignment", "label_preservation",
   "recipient_inclusion", "condition"]

def predicateReasons (Γ : Registry) (S : Snapshot) (rule : String) (ps : List Premise) :
    List Reason :=
  categories.flatMap fun c => (ps.filter (category · == c)).flatMap (premiseReasons Γ S rule)

/-- Step 9: `conclusion_reasons/2`. -/
def conclusionReasons (premiseFindings : List Reason) (conclusion : String) : List Reason :=
  reasonIf (!premiseFindings.isEmpty) { code := "conclusion_mismatch" } ++
  reasonIf (conclusion != "permit") { code := "conclusion_unsupported" }

/-! ## The report -/

/-- `check/4`'s answer: an input error's code, or the reasons (none: `valid`). -/
abbrev Report := Except String (List Reason)

/-- Steps 1–9 on input that passed validation. -/
def verifyReasons (Γ : Registry) (S : Snapshot) (I : Intent) (P : Proof) : List Reason :=
  let r1 := referenceReasons Γ S I P
  if !r1.isEmpty then r1 else
  let r2 := labelReasons S P
  if !r2.isEmpty then r2 else
  let r3 := requiredSetReasons P.rule (checkedLabel P.rule S) P.premises
  if !r3.isEmpty then r3 else
  let rs := predicateReasons Γ S P.rule P.premises
  rs ++ conclusionReasons rs P.conclusion

def verifyReport (Γ : Registry) (S : Snapshot) (I : Intent) (P : Proof) : Report :=
  if outputOperations.contains I.operation &&
      (S.facts.lookup "output_content_digest").isNone then .error "emit_digest_missing"
  else if outputOperations.contains I.operation && S.classification != "classified" then
    .error "emit_object_not_classified"
  else .ok (verifyReasons Γ S I P)

def Report.verdict : Report → Outcome
  | .error _ => .inputError
  | .ok [] => .valid
  | .ok (_ :: _) => .invalid

/-! ## Each step finds nothing exactly when its check holds -/

theorem reasonIf_nil {b : Bool} {r : Reason} : reasonIf b r = [] ↔ b = false := by
  cases b <;> simp [reasonIf]

theorem referenceReasons_nil {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof} :
    referenceReasons Γ S I P = [] ↔ referencesOk Γ S I P = true := by
  unfold referenceReasons referencesOk
  by_cases h : P.rule ∈ proofRules <;> simp [h, reasonIf_nil, and_assoc]

theorem labelReasons_nil {S : Snapshot} {P : Proof} :
    labelReasons S P = [] ↔ (sortStrings P.checkedLabel != checkedLabel P.rule S) = false :=
  reasonIf_nil

theorem requiredSetReasons_nil {rule : String} {bindings : List String} {ps : List Premise} :
    requiredSetReasons rule bindings ps = [] ↔ requiredSetOk rule bindings ps = true := by
  simp [requiredSetReasons, requiredSetOk, List.filter_eq_nil_iff, and_assoc]

theorem factReasons_nil {S : Snapshot} {p : Premise} :
    factReasons S p = [] ↔ factPremiseOk S p = true := by
  unfold factReasons factPremiseOk
  cases p.strField? "fact" with
  | none => simp
  | some f =>
    by_cases hw : f = "workspace_contract_valid"
    · cases hv : S.workspaceValid <;> cases p.value <;> simp [hw, reasonIf]
    · simp only [hw, beq_iff_eq, ite_false]
      cases S.fact? f with
      | none => simp
      | some v =>
        cases v with
        | bool b => cases b <;> cases p.value <;> simp [reasonIf]
        | _ => simp

theorem quarantineReasons_nil {S : Snapshot} {p : Premise} :
    quarantineReasons S p = [] ↔ quarantineOk S p = true := by
  unfold quarantineReasons quarantineOk
  by_cases h : S.classification = "classified" <;> simp [h, reasonIf_nil]

theorem conditionReasons_nil {Γ : Registry} {S : Snapshot} {rule : String} {p : Premise} :
    conditionReasons Γ S rule p = [] ↔ conditionOk Γ S rule p = true := by
  unfold conditionReasons conditionOk
  cases p.strField? "binding" with
  | none => simp
  | some b =>
    simp only [Option.bind_some]
    cases Γ.ruleExpr? b rule with
    | none => simp
    | some j =>
      rcases he : Expr.ofJVal j with _ | e
      · simp [he]
      · cases hv : eval S.fact? e <;> simp [he, hv, reasonIf_nil, and_assoc]

theorem failIf_nil {ok : Bool} {code : String} : failIf ok code = [] ↔ ok = true := by
  cases ok <;> simp [failIf, reasonIf]

theorem premiseReasons_nil {Γ : Registry} {S : Snapshot} {rule : String} {p : Premise} :
    premiseReasons Γ S rule p = [] ↔ premiseOk Γ S rule p = true := by
  unfold premiseReasons premiseOk
  split
  · exact factReasons_nil
  split
  · exact quarantineReasons_nil
  split
  · exact conditionReasons_nil
  split
  · split
    · exact failIf_nil
    split
    · exact failIf_nil
    split
    · exact failIf_nil
    split
    · exact failIf_nil
    · simp
  · simp

/-- A premise outside every group finds nothing. -/
theorem premiseReasons_uncategorized {Γ : Registry} {S : Snapshot} {rule : String}
    {p : Premise} (h : category p ∉ categories) : premiseReasons Γ S rule p = [] := by
  unfold category categories at h
  unfold premiseReasons
  by_cases hc : p.kind = "computed"
  · simp only [hc, beq_self_eq_true, ite_true, List.mem_cons, List.not_mem_nil, or_false,
      not_or] at h
    obtain ⟨_, _, h1, h2, h3, h4, _⟩ := h
    simp [hc, h1, h2, h3, h4]
  · simp only [hc, beq_iff_eq, ite_false, List.mem_cons, List.not_mem_nil, or_false,
      not_or] at h
    obtain ⟨h1, h2, _, _, _, _, h3⟩ := h
    simp [hc, h1, h2, h3]

theorem predicateReasons_nil {Γ : Registry} {S : Snapshot} {rule : String}
    {ps : List Premise} :
    predicateReasons Γ S rule ps = [] ↔ ps.all (premiseOk Γ S rule) = true := by
  simp only [predicateReasons, List.flatMap_eq_nil_iff, List.mem_filter, beq_iff_eq,
    List.all_eq_true, ← premiseReasons_nil]
  constructor
  · intro h p hp
    by_cases hc : category p ∈ categories
    · exact h _ hc p ⟨hp, rfl⟩
    · exact premiseReasons_uncategorized hc
  · intro h c _ p ⟨hp, _⟩
    exact h p hp

theorem conclusionReasons_nil {rs : List Reason} {c : String} :
    conclusionReasons rs c = [] ↔ rs = [] ∧ (c == "permit") = true := by
  cases rs <;> by_cases h : c = "permit" <;> simp [conclusionReasons, reasonIf, h]

/-- Steps 1–9 find nothing exactly when every check of `verify` holds. -/
theorem verifyReasons_nil {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof} :
    verifyReasons Γ S I P = [] ↔
      referencesOk Γ S I P = true ∧
      (sortStrings P.checkedLabel != checkedLabel P.rule S) = false ∧
      requiredSetOk P.rule (checkedLabel P.rule S) P.premises = true ∧
      P.premises.all (premiseOk Γ S P.rule) = true ∧ (P.conclusion == "permit") = true := by
  rw [← referenceReasons_nil, ← labelReasons_nil, ← requiredSetReasons_nil,
    ← predicateReasons_nil]
  unfold verifyReasons
  by_cases h1 : referenceReasons Γ S I P = []
  · by_cases h2 : labelReasons S P = []
    · by_cases h3 : requiredSetReasons P.rule (checkedLabel P.rule S) P.premises = []
      · simp only [h1, h2, h3, List.isEmpty_nil, Bool.not_true, Bool.false_eq_true, ite_false,
          List.append_eq_nil_iff, conclusionReasons_nil, true_and]
        constructor
        · exact fun ⟨hp, _, hc⟩ => ⟨hp, hc⟩
        · exact fun ⟨hp, hc⟩ => ⟨hp, hp, hc⟩
      · simp [h1, h2, h3]
    · simp [h1, h2]
  · simp [h1]

/-- Main theorem: the report's verdict is `verify`'s. No findings exactly when
the tree is `valid`, and an input error exactly when `verify` has one. -/
theorem verifyReport_verdict {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof} :
    (verifyReport Γ S I P).verdict = verify Γ S I P := by
  have key := @verifyReasons_nil Γ S I P
  unfold verifyReport verify outputInputOk
  generalize referencesOk Γ S I P = a at key ⊢
  generalize (sortStrings P.checkedLabel != checkedLabel P.rule S) = b at key ⊢
  generalize requiredSetOk P.rule (checkedLabel P.rule S) P.premises = c at key ⊢
  generalize P.premises.all (premiseOk Γ S P.rule) = d at key ⊢
  generalize (P.conclusion == "permit") = e at key ⊢
  generalize verifyReasons Γ S I P = l at key ⊢
  generalize outputOperations.contains I.operation = o
  by_cases hc : S.classification = "classified" <;>
    cases S.facts.lookup "output_content_digest" <;> cases o <;>
    cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases l <;>
    simp_all [Report.verdict]

end KomkiSpec
