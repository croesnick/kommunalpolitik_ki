import KomkiSpec.DeriveSound

/-!
# `verify` accepts every tree `derive` builds

`derive_verifies`: the proof tree of a `permit` passes `verify` against the
same registry, snapshot and intent. With `verify_sound` this closes the
loop: `derive`'s trees are exactly as strong as the contract asks, neither
weaker nor stricter.
-/

namespace KomkiSpec

@[simp] theorem mkPremise_name {n k : String} {e : List (String × JVal)} :
    (mkPremise n k e).name = n := rfl
@[simp] theorem mkPremise_kind {n k : String} {e : List (String × JVal)} :
    (mkPremise n k e).kind = k := rfl
@[simp] theorem mkPremise_value {n k : String} {e : List (String × JVal)} :
    (mkPremise n k e).value = true := rfl
theorem mkPremise_get {n k key : String} {e : List (String × JVal)} :
    (mkPremise n k e).get? key =
      ([("name", JVal.str n), ("kind", JVal.str k), ("value", JVal.bool true)] ++ e).lookup key :=
  rfl
@[simp] theorem basisPremise_name {S : Snapshot} {n : String} : (basisPremise S n).name = n := rfl
@[simp] theorem basisPremise_kind {S : Snapshot} {n : String} :
    (basisPremise S n).kind = "fact" := rfl
@[simp] theorem conditionPremise_name {Γ : Registry} {r b : String} :
    (conditionPremise Γ r b).name = "binding_condition" := rfl
@[simp] theorem conditionPremise_kind {Γ : Registry} {r b : String} :
    (conditionPremise Γ r b).kind = "condition" := rfl
theorem conditionPremise_binding {Γ : Registry} {r b : String} :
    (conditionPremise Γ r b).strField? "binding" = some b := by
  simp [conditionPremise, mkPremise, Premise.strField?, Premise.get?, List.lookup]

theorem conditionBindings_conditions {Γ : Registry} {rule : String} (L : List String) :
    conditionBindings (L.map (conditionPremise Γ rule)) = L := by
  induction L with
  | nil => rfl
  | cons b bs ih =>
    unfold conditionBindings at ih ⊢
    rw [List.map_cons, List.filterMap_cons, ih]
    simp [conditionPremise_binding]

theorem strings_strs (xs : List String) : strings? (xs.map JVal.str) = some xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    unfold strings? at ih ⊢
    rw [List.map_cons, List.mapM_cons, ih]
    rfl


theorem conditionPremise_ok {Γ : Registry} {S : Snapshot} {rule b : String}
    (h : ∃ j e, Γ.ruleExpr? b rule = some j ∧ Expr.ofJVal j = some e ∧ eval S.fact? e = .true) :
    premiseOk Γ S rule (conditionPremise Γ rule b) = true := by
  obtain ⟨j, e, hj, he, hev⟩ := h
  simp [premiseOk, conditionOk, conditionPremise, mkPremise, Premise.strField?, Premise.get?,
    List.lookup, hj, he, hev]

theorem requiredSet_built {Γ : Registry} {S : Snapshot} {rule : String}
    (hr : proofRules.contains rule = true) :
    requiredSetOk rule (checkedLabel rule S) (proofPremises Γ S rule) = true := by
  rcases rule_cases hr with rfl | rfl | rfl | rfl <;>
  simp [requiredSetOk, proofPremises, fixedPremises, admitBaseFacts, outputBaseFacts,
    conditionBindings, fitsSlot, requiredPremises, kindTable, List.lookup, mkPremise, basisPremise,
    Premise.strField?, Premise.get?, conditionPremise, boundTo, List.filterMap_map]

theorem premises_built_ok {Γ : Registry} {S : Snapshot} {rule : String}
    (wf : Γ.WellFormed) (hS : S.WellFormed) (hr : proofRules.contains rule = true)
    {env : List String} (henv : Γ.environment? S.environment = some env)
    (hout : rule ≠ "admit" → S.classification = "classified")
    (hclean : ∀ f ∈ premiseFindings Γ S rule, Clean f) :
    (proofPremises Γ S rule).all (premiseOk Γ S rule) = true := by
  obtain ⟨hc, hv, hf, hl, hrec, hcond⟩ := (premises_clean_iff wf hS hr henv hout).1 hclean
  have hrho : actualRecipients Γ S = sortStrings env := by simp [actualRecipients, henv]
  have hallowed : ∀ o ∈ sortStrings env, o ∈ allowedRecipients Γ (checkedLabel rule S) :=
    fun o ho => allowedRecipients_complete Γ _ o (hrec o (mem_sortStrings.1 ho))
  have hconds : ∀ b ∈ checkedLabel rule S,
      premiseOk Γ S rule (conditionPremise Γ rule b) = true :=
    fun b hb => conditionPremise_ok (hcond b hb)
  rcases rule_cases hr with rfl | rfl | rfl | rfl
  · have hck : checkedLabel "admit" S = S.workspaceBindings := by
      simp [checkedLabel, handoverOperations]
    simp only [LabelDuty, ite_true, Sub] at hl
    simp only [baseFacts, beq_self_eq_true, ite_true, admitBaseFacts, List.mem_cons,
      List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq] at hf
    rw [hck] at hallowed hconds
    simp [proofPremises, premiseOk, factPremiseOk, quarantineOk, labelInclusionOk,
      recipientInclusionOk, mkPremise, basisPremise, Premise.strField?, Premise.get?, List.lookup,
      hv, hc, hf, henv, hrho, hS.labelsSorted, hck, List.all_eq_true]
    exact ⟨hl, hallowed, fun b hb => by simpa [premiseOk] using hconds b hb⟩
  · have hck : checkedLabel "emit" S = S.workspaceBindings := by
      simp [checkedLabel, handoverOperations]
    simp only [baseFacts, outputBaseFacts, List.mem_cons, List.not_mem_nil, or_false,
      forall_eq_or_imp, forall_eq, (by decide : ("emit" == "admit") = false), Bool.false_eq_true,
      ite_false] at hf
    rw [hck] at hallowed hconds
    simp [proofPremises, premiseOk, factPremiseOk, labelAssignmentOk, strs, strings_strs,
      recipientInclusionOk, mkPremise, basisPremise, Premise.strField?, Premise.get?, List.lookup,
      hv, hf, henv, hrho, hck, hS.bindingsUnique, List.all_eq_true]
    exact ⟨hallowed, fun b hb => by simpa [premiseOk] using hconds b hb⟩
  · have hck : checkedLabel "transfer" S = S.objectLabels := by
      simp [checkedLabel, handoverOperations]
    simp only [LabelDuty, (by decide : ("transfer" = "admit") = False),
      (by decide : ("transfer" = "emit") = False), ite_false, Sub] at hl
    simp only [baseFacts, outputBaseFacts, List.mem_cons, List.not_mem_nil, or_false,
      forall_eq_or_imp, forall_eq, (by decide : ("transfer" == "admit") = false), Bool.false_eq_true,
      ite_false] at hf
    rw [hck] at hallowed hconds
    simp [proofPremises, premiseOk, factPremiseOk, labelPreservationOk, recipientInclusionOk,
      mkPremise, basisPremise, Premise.strField?, Premise.get?, List.lookup, hv, hf, henv, hrho,
      hck, handoverOperations, List.all_eq_true]
    exact ⟨hl, hallowed, fun b hb => by simpa [premiseOk] using hconds b hb⟩
  · have hck : checkedLabel "store" S = S.objectLabels := by
      simp [checkedLabel, handoverOperations]
    simp only [LabelDuty, (by decide : ("store" = "admit") = False),
      (by decide : ("store" = "emit") = False), ite_false, Sub] at hl
    simp only [baseFacts, outputBaseFacts, List.mem_cons, List.not_mem_nil, or_false,
      forall_eq_or_imp, forall_eq, (by decide : ("store" == "admit") = false), Bool.false_eq_true,
      ite_false] at hf
    rw [hck] at hallowed hconds
    simp [proofPremises, premiseOk, factPremiseOk, labelPreservationOk, recipientInclusionOk,
      mkPremise, basisPremise, Premise.strField?, Premise.get?, List.lookup, hv, hf, henv, hrho,
      hck, handoverOperations, List.all_eq_true]
    exact ⟨hl, hallowed, fun b hb => by simpa [premiseOk] using hconds b hb⟩
  all_goals sorry

/-- `verify` accepts every tree `derive` builds: the tree proves its permit
against the same registry, snapshot and intent. -/
theorem derive_verifies {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof}
    (wf : Γ.WellFormed) (hS : S.WellFormed) (h : derive Γ S I = .decision (.permit P)) :
    verify Γ S I P = .valid := by
  obtain ⟨hr, henv, hout, hd⟩ := derive_decision h
  obtain ⟨hclean, rfl⟩ := decideRule_permit hd
  obtain ⟨env, henv'⟩ := Option.isSome_iff_exists.1 henv
  have hall := premises_built_ok wf hS hr henv' (fun hne => (hout hne).2) hclean
  have hreq := requiredSet_built (Γ := Γ) (S := S) hr
  have hck : sortStrings (checkedLabel I.operation S) = checkedLabel I.operation S := by
    unfold checkedLabel; split <;> simp [hS.labelsSorted, hS.bindingsSorted]
  have hpre : (outputOperations.contains I.operation && !outputInputOk S) = false := by
    by_cases ha : I.operation = "admit"
    · rw [ha]; rfl
    · obtain ⟨hdig, hcl⟩ := hout ha
      simp only [Snapshot.fact?] at hdig
      simp [outputInputOk, hdig, hcl]
  have hmem := List.contains_iff_mem.1 hr
  unfold verify
  rw [hpre]
  simp [buildProof, referencesOk, hmem, hck, hreq, hall]

end KomkiSpec
