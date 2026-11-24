import KomkiSpec.Derive
import KomkiSpec.Soundness

/-!
# `derive` decides exactly the contract's rules

`derive_sound` and `derive_complete`: `derive` permits if and only if the
intent's rule is derivable under CONTRACT.md § 4.3, § 4.5, § 4.7 or § 4.8
(`Derivable`, the same statement `verify_sound` ends in). `derive_permit_stable`
and `derive_deny_stable`: more facts never turn a `permit` or a `deny` into
something else; only an `indeterminate` resolves (R.5.2, B.4: a missing fact
is no default).
-/

namespace KomkiSpec

/-- What `Context.validate_snapshot/2` guarantees and these theorems use. -/
structure Snapshot.WellFormed (S : Snapshot) : Prop where
  classification : S.classification = "classified" ∨ S.classification = "quarantine"
  baseFactsBoolean : ∀ n ∈ admitBaseFacts, ∀ v, S.fact? n = some v → ∃ b, v = .bool b
  /-- B_W and λ(x) are sorted and unique (§ 2.2). -/
  bindingsSorted : sortStrings S.workspaceBindings = S.workspaceBindings
  bindingsUnique : sortDedup S.workspaceBindings = S.workspaceBindings
  labelsSorted : sortStrings S.objectLabels = S.objectLabels

/-- Nothing blocks, nothing is missing. -/
def Clean (f : Findings) : Prop := f.blockers = [] ∧ f.evidence = []

/-! ## One premise at a time -/

theorem clean_quarantine {S : Snapshot} (hS : S.WellFormed) :
    Clean (quarantineFindings S) ↔ S.classification = "classified" := by
  unfold Clean quarantineFindings
  rcases hS.classification with h | h <;> simp [h, blocking, holds]

theorem clean_workspace {S : Snapshot} :
    Clean (workspaceFindings S) ↔ S.workspaceValid = true := by
  unfold Clean workspaceFindings
  cases S.workspaceValid <;> simp [blocking, holds]

theorem factState_true {S : Snapshot} {n : String} (hS : S.WellFormed) (hn : n ∈ admitBaseFacts) :
    factState S n = .true ↔ S.fact? n = some (.bool true) := by
  constructor
  · intro h
    cases hv : S.fact? n with
    | none => simp [factState, hv] at h
    | some v =>
      obtain ⟨b, rfl⟩ := hS.baseFactsBoolean n hn v hv
      cases b
      · simp [factState, hv] at h
      · rfl
  · intro h; simp [factState, h]

theorem clean_basis {S : Snapshot} {n : String} :
    Clean (basisFindings S n) ↔ factState S n = .true := by
  unfold Clean basisFindings
  cases factState S n <;> simp [blocking, lacking, holds] <;> split <;> simp

theorem clean_env {S : Snapshot} :
    Clean (envFindings S) ↔ factState S "environment_observers_complete" = .true := by
  unfold Clean envFindings
  cases factState S "environment_observers_complete" <;> simp [lacking, holds]

theorem subsetOf_iff {xs ys : List String} : subsetOf xs ys = true ↔ ∀ x ∈ xs, x ∈ ys := by
  simp [subsetOf, List.all_eq_true]

theorem clean_labelInclusion {S : Snapshot} {checked : List String} :
    Clean (labelInclusionFindings S checked) ↔ ∀ l ∈ S.objectLabels, l ∈ checked := by
  unfold Clean labelInclusionFindings
  rw [← subsetOf_iff]
  cases subsetOf S.objectLabels checked <;> simp [blocking, holds]

theorem clean_labelPreservation {S : Snapshot} {checked : List String} :
    Clean (labelPreservationFindings S checked) ↔ ∀ b ∈ S.workspaceBindings, b ∈ checked := by
  unfold Clean labelPreservationFindings
  rw [← subsetOf_iff]
  cases subsetOf S.workspaceBindings checked <;> simp [blocking, holds]

theorem clean_recipient {Γ : Registry} {rho checked : List String} :
    Clean (recipientFindings Γ rho checked) ↔ ∀ o ∈ rho, o ∈ allowedRecipients Γ checked := by
  have key : (rho.filter fun o => !(allowedRecipients Γ checked).contains o) = [] ↔
      ∀ o ∈ rho, o ∈ allowedRecipients Γ checked := by
    simp [List.filter_eq_nil_iff]
  unfold Clean recipientFindings
  dsimp only
  rw [← key]
  cases hf : (rho.filter fun o => !(allowedRecipients Γ checked).contains o) with
  | nil => simp [holds]
  | cons x xs => simp [blocking]

theorem clean_condition {Γ : Registry} {S : Snapshot} {rule b : String} :
    Clean (conditionFindings Γ S rule b) ↔
      ∃ j e, Γ.ruleExpr? b rule = some j ∧ Expr.ofJVal j = some e ∧ eval S.fact? e = .true := by
  unfold Clean conditionFindings
  split
  · next h =>
    simp only [blocking, List.cons_ne_nil, false_and, false_iff, not_exists, not_and]
    intro j e hj he _
    simp [hj, he] at h
  · next e h =>
    obtain ⟨j, hj, he⟩ := Option.bind_eq_some_iff.1 h
    constructor
    · intro hc
      refine ⟨j, e, hj, he, ?_⟩
      revert hc
      cases eval S.fact? e <;> simp [blocking, lacking, holds]
    · rintro ⟨j', e', hj', he', hev⟩
      rw [hj] at hj'; cases hj'
      rw [he] at he'; cases he'
      simp [hev, holds]

/-- The computed list holds all of R_Γ(L). -/
theorem allowedRecipients_complete (Γ : Registry) (L : List String) (o : String)
    (h : recipients Γ.rules (· ∈ L) o) : o ∈ allowedRecipients Γ L := by
  obtain ⟨hO, hR⟩ := h
  cases L with
  | nil => exact hO
  | cons b bs =>
    simp only [allowedRecipients, mem_sortStrings, List.mem_filter, List.all_eq_true,
      List.contains_iff_mem]
    exact ⟨hR b List.mem_cons_self, fun b' hb' => hR b' (List.mem_cons_of_mem _ hb')⟩

/-! ## The decision -/

theorem decideRule_permit {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof}
    (h : decideRule Γ S I = .permit P) :
    (∀ f ∈ premiseFindings Γ S I.operation, Clean f) ∧ P = buildProof Γ S I := by
  unfold decideRule at h
  dsimp only at h
  split at h
  · cases h
  split at h
  · cases h
  next hb he =>
    cases h
    simp only [Bool.not_eq_true', List.isEmpty_eq_false_iff, ne_eq, Decidable.not_not] at hb he
    refine ⟨fun f hf => ⟨?_, ?_⟩, rfl⟩
    · exact List.flatten_eq_nil_iff.1 hb _ (List.mem_map.2 ⟨f, hf, rfl⟩)
    · exact List.flatten_eq_nil_iff.1 he _ (List.mem_map.2 ⟨f, hf, rfl⟩)

theorem decideRule_of_clean {Γ : Registry} {S : Snapshot} {I : Intent}
    (h : ∀ f ∈ premiseFindings Γ S I.operation, Clean f) :
    decideRule Γ S I = .permit (buildProof Γ S I) := by
  have hb : blockersOf (premiseFindings Γ S I.operation) = [] :=
    List.flatten_eq_nil_iff.2 fun l hl => by
      obtain ⟨f, hf, rfl⟩ := List.mem_map.1 hl
      exact (h f hf).1
  have he : evidenceOf (premiseFindings Γ S I.operation) = [] :=
    List.flatten_eq_nil_iff.2 fun l hl => by
      obtain ⟨f, hf, rfl⟩ := List.mem_map.1 hl
      exact (h f hf).2
  unfold decideRule
  simp [hb, he]

/-- What `derive` asks for besides the premises: a supported rule, a known
environment and, for the output rules, the prerequisites (#628). -/
theorem derive_decision {Γ : Registry} {S : Snapshot} {I : Intent} {d : Decision}
    (h : derive Γ S I = .decision d) :
    proofRules.contains I.operation = true ∧ (Γ.environment? S.environment).isSome = true ∧
    (I.operation ≠ "admit" → (S.fact? "output_content_digest").isSome = true ∧
      S.classification = "classified") ∧ decideRule Γ S I = d := by
  unfold derive at h
  split at h; · cases h
  next hr =>
  split at h; · cases h
  next henv =>
  split at h; · cases h
  next hd =>
  split at h; · cases h
  next hc =>
  cases h
  simp only [Bool.not_eq_true', Bool.not_eq_false] at hr
  simp only [Option.isNone_iff_eq_none, ← ne_eq, Option.ne_none_iff_isSome] at henv
  refine ⟨hr, henv, fun hne => ?_, rfl⟩
  have ho := output_rules I.operation (List.contains_iff_mem.1 hr) hne
  simp only [ho, Bool.true_and, Option.isNone_iff_eq_none, ← ne_eq,
    Option.ne_none_iff_isSome] at hd
  simp only [ho, Bool.true_and, bne_iff_ne, ne_eq, Decidable.not_not] at hc
  exact ⟨hd, hc⟩

/-! ## Soundness and completeness -/

/-- The findings of a rule are clean exactly when its premises hold. -/
theorem premises_clean_iff {Γ : Registry} {S : Snapshot} {rule : String}
    (wf : Γ.WellFormed) (hS : S.WellFormed) (hr : proofRules.contains rule = true)
    {env : List String} (henv : Γ.environment? S.environment = some env)
    (hout : rule ≠ "admit" → S.classification = "classified") :
    (∀ f ∈ premiseFindings Γ S rule, Clean f) ↔
      (S.classification = "classified" ∧ S.workspaceValid = true ∧
       (∀ n ∈ baseFacts rule, S.fact? n = some (.bool true)) ∧ LabelDuty rule S ∧
       (∀ o ∈ env, recipients Γ.rules (· ∈ checkedLabel rule S) o) ∧
       ∀ b ∈ checkedLabel rule S, ∃ j e, Γ.ruleExpr? b rule = some j ∧
         Expr.ofJVal j = some e ∧ eval S.fact? e = .true) := by
  have hrho : actualRecipients Γ S = sortStrings env := by simp [actualRecipients, henv]
  have hrec : (∀ o ∈ sortStrings env, o ∈ allowedRecipients Γ (checkedLabel rule S)) ↔
      ∀ o ∈ env, recipients Γ.rules (· ∈ checkedLabel rule S) o := by
    constructor
    · intro h o ho
      exact allowedRecipients_sound Γ wf _ o (h o (mem_sortStrings.2 ho))
    · intro h o ho
      exact allowedRecipients_complete Γ _ o (h o (mem_sortStrings.1 ho))
  have hcond : (∀ f ∈ (checkedLabel rule S).map (conditionFindings Γ S rule), Clean f) ↔
      ∀ b ∈ checkedLabel rule S, ∃ j e, Γ.ruleExpr? b rule = some j ∧
        Expr.ofJVal j = some e ∧ eval S.fact? e = .true := by
    simp only [List.mem_map, forall_exists_index, and_imp, forall_apply_eq_imp_iff₂]
    exact forall₂_congr fun b _ => clean_condition
  have hfact : ∀ n ∈ admitBaseFacts, Clean (basisFindings S n) ↔ S.fact? n = some (.bool true) :=
    fun n hn => clean_basis.trans (factState_true hS hn)
  have henvf : Clean (envFindings S) ↔
      S.fact? "environment_observers_complete" = some (.bool true) :=
    clean_env.trans (factState_true hS (by decide))
  rcases rule_cases hr with rfl | rfl | rfl | rfl
  · have hck : checkedLabel "admit" S = S.workspaceBindings := by
      simp [checkedLabel, handoverOperations]
    simp only [premiseFindings, beq_self_eq_true, ite_true, List.forall_mem_append,
      List.forall_mem_cons, hcond, hrho]
    rw [clean_quarantine hS, clean_workspace, hfact "has_operation_right" (by decide),
      hfact "has_object_access_right" (by decide), hfact "audit_path_ready" (by decide), henvf,
      clean_labelInclusion, clean_recipient, hrec]
    simp [baseFacts, admitBaseFacts, LabelDuty, Sub, hck, and_assoc]
  · have hck : checkedLabel "emit" S = S.workspaceBindings := by
      simp [checkedLabel, handoverOperations]
    have hcl := hout (by decide)
    simp only [premiseFindings, (by decide : ("emit" == "admit") = false), beq_self_eq_true,
      Bool.false_eq_true, ite_false, ite_true, List.forall_mem_append, List.forall_mem_cons, hcond,
      hrho]
    rw [clean_workspace, hfact "has_operation_right" (by decide),
      hfact "audit_path_ready" (by decide), henvf, clean_recipient, hrec]
    simp [baseFacts, outputBaseFacts, LabelDuty, hck, hcl, and_assoc]
  · have hck : checkedLabel "transfer" S = S.objectLabels := by
      simp [checkedLabel, handoverOperations]
    have hcl := hout (by decide)
    simp only [premiseFindings, (by decide : ("transfer" == "admit") = false),
      (by decide : ("transfer" == "emit") = false), Bool.false_eq_true, ite_false,
      List.forall_mem_append, List.forall_mem_cons, hcond, hrho]
    rw [clean_workspace, hfact "has_operation_right" (by decide),
      hfact "audit_path_ready" (by decide), henvf, clean_labelPreservation, clean_recipient, hrec]
    simp [baseFacts, outputBaseFacts, LabelDuty, Sub, hck, hcl, and_assoc]
  · have hck : checkedLabel "store" S = S.objectLabels := by
      simp [checkedLabel, handoverOperations]
    have hcl := hout (by decide)
    simp only [premiseFindings, (by decide : ("store" == "admit") = false),
      (by decide : ("store" == "emit") = false), Bool.false_eq_true, ite_false,
      List.forall_mem_append, List.forall_mem_cons, hcond, hrho]
    rw [clean_workspace, hfact "has_operation_right" (by decide),
      hfact "audit_path_ready" (by decide), henvf, clean_labelPreservation, clean_recipient, hrec]
    simp [baseFacts, outputBaseFacts, LabelDuty, Sub, hck, hcl, and_assoc]

/-- `derive` permits only what the contract derives, with the tree of § 2.5. -/
theorem derive_sound {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof}
    (wf : Γ.WellFormed) (hS : S.WellFormed) (h : derive Γ S I = .decision (.permit P)) :
    Derivable Γ S I.operation ∧ P = buildProof Γ S I := by
  obtain ⟨hr, henv, hout, hd⟩ := derive_decision h
  obtain ⟨env, henv'⟩ := Option.isSome_iff_exists.1 henv
  obtain ⟨hclean, hP⟩ := decideRule_permit hd
  obtain ⟨hc, hv, hf, hl, hrec, hcond⟩ :=
    (premises_clean_iff wf hS hr henv' fun hne => (hout hne).2).1 hclean
  exact ⟨{ classified := hc, digest := fun hne => (hout hne).1, valid := hv, facts := hf,
           labels := hl, recipients := ⟨env, henv', hrec⟩, conditions := hcond }, hP⟩

/-- `derive` permits whatever the contract derives. -/
theorem derive_complete {Γ : Registry} {S : Snapshot} {I : Intent}
    (wf : Γ.WellFormed) (hS : S.WellFormed) (hr : proofRules.contains I.operation = true)
    (h : Derivable Γ S I.operation) :
    derive Γ S I = .decision (.permit (buildProof Γ S I)) := by
  obtain ⟨env, henv, hrec⟩ := h.recipients
  have hclean := (premises_clean_iff wf hS hr henv fun _ => h.classified).2
    ⟨h.classified, h.valid, h.facts, h.labels, hrec, h.conditions⟩
  have hdig : (outputOperations.contains I.operation &&
      (S.facts.lookup "output_content_digest").isNone) = false := by
    by_cases ha : I.operation = "admit"
    · rw [ha]; rfl
    · have hs := h.digest ha
      simp only [Snapshot.fact?] at hs
      simp [hs]
  have hcls : (outputOperations.contains I.operation && S.classification != "classified") =
      false := by simp [h.classified]
  unfold derive
  simp only [hr, henv, hdig, hcls, Bool.not_true, Bool.false_eq_true, ite_false,
    Option.isNone_some]
  rw [decideRule_of_clean hclean]

/-! ## More facts, the same verdict -/

/-- `S'` knows at least the facts of `S` and agrees on everything else. -/
structure Snapshot.Refines (S S' : Snapshot) : Prop where
  facts : Extends S.fact? S'.fact?
  bindings : S'.workspaceBindings = S.workspaceBindings
  valid : S'.workspaceValid = S.workspaceValid
  environment : S'.environment = S.environment
  classification : S'.classification = S.classification
  labels : S'.objectLabels = S.objectLabels

theorem Snapshot.Refines.checked {S S' : Snapshot} (hR : S.Refines S') (rule : String) :
    checkedLabel rule S' = checkedLabel rule S := by
  simp only [checkedLabel, hR.labels, hR.bindings]

theorem derivable_refines {Γ : Registry} {S S' : Snapshot} {rule : String} (hR : S.Refines S')
    (h : Derivable Γ S rule) : Derivable Γ S' rule := by
  obtain ⟨hc, hd, hv, hf, hl, ⟨env, henv, hrec⟩, hcond⟩ := h
  refine ⟨hR.classification ▸ hc, fun hne => ?_, hR.valid ▸ hv,
    fun n hn => hR.facts _ _ (hf n hn), ?_, ⟨env, hR.environment ▸ henv, ?_⟩, ?_⟩
  · obtain ⟨v, hv⟩ := Option.isSome_iff_exists.1 (hd hne)
    rw [hR.facts _ _ hv]; rfl
  · unfold LabelDuty at hl ⊢; rw [hR.labels, hR.bindings]; exact hl
  · rw [hR.checked]; exact hrec
  · intro b hb
    rw [hR.checked] at hb
    obtain ⟨j, e, hj, he, hev⟩ := hcond b hb
    exact ⟨j, e, hj, he, eval_true_stable hR.facts hev⟩

/-- A `permit` stays a `permit` when more facts are known. -/
theorem derive_permit_stable {Γ : Registry} {S S' : Snapshot} {I : Intent} {P : Proof}
    (wf : Γ.WellFormed) (hS : S.WellFormed) (hS' : S'.WellFormed) (hR : S.Refines S')
    (h : derive Γ S I = .decision (.permit P)) :
    derive Γ S' I = .decision (.permit (buildProof Γ S' I)) :=
  derive_complete wf hS' (derive_decision h).1 (derivable_refines hR (derive_sound wf hS h).1)

/-- A blocking base fact stays blocking: a known `false` stays known. -/
theorem blocks_basis {S S' : Snapshot} {n : String} (hR : S.Refines S')
    (h : (basisFindings S n).blockers ≠ []) : (basisFindings S' n).blockers ≠ [] := by
  have hf : factState S n = .false := by
    unfold basisFindings at h
    cases hs : factState S n <;> simp [hs, holds, lacking] at h ⊢
  have hf' : factState S' n = .false := by
    unfold factState at hf ⊢
    cases hv : S.fact? n with
    | none => simp [hv] at hf
    | some v => rw [hR.facts n v hv]; simpa [hv] using hf
  simp only [basisFindings, hf']
  split <;> simp [blocking]

/-- A blocking condition stays blocking: a missing rule stays missing, a
known `false` stays `false` (`eval_mono`). -/
theorem blocks_condition {Γ : Registry} {S S' : Snapshot} {rule b : String} (hR : S.Refines S')
    (h : (conditionFindings Γ S rule b).blockers ≠ []) :
    (conditionFindings Γ S' rule b).blockers ≠ [] := by
  unfold conditionFindings at h ⊢
  split
  · simp [blocking]
  · next e he =>
    rw [he] at h
    dsimp only at h
    have hfalse : eval S.fact? e = .false := by
      cases hv : eval S.fact? e <;> simp [hv, holds, lacking] at h ⊢
    have hfalse' : eval S'.fact? e = .false := by
      rcases eval_mono hR.facts e with hu | heq
      · rw [hfalse] at hu; cases hu
      · rw [← heq, hfalse]
    rw [hfalse']
    simp [blocking]

theorem actualRecipients_refines {Γ : Registry} {S S' : Snapshot} (hR : S.Refines S') :
    actualRecipients Γ S' = actualRecipients Γ S := by
  simp only [actualRecipients, hR.environment]

/-- Every blocker of `S` has a counterpart in `S'`. -/
theorem blockers_stable {Γ : Registry} {S S' : Snapshot} {rule : String} (hR : S.Refines S')
    (h : blockersOf (premiseFindings Γ S rule) ≠ []) :
    blockersOf (premiseFindings Γ S' rule) ≠ [] := by
  have hex : ∀ fs : List Findings, blockersOf fs ≠ [] ↔ ∃ f ∈ fs, f.blockers ≠ [] := by
    intro fs
    simp only [blockersOf, ne_eq, List.flatten_eq_nil_iff, List.mem_map, forall_exists_index,
      and_imp, forall_apply_eq_imp_iff₂]
    constructor
    · intro h
      exact Classical.byContradiction fun hc =>
        h fun a ha => Classical.byContradiction fun hb => hc ⟨a, ha, hb⟩
    · rintro ⟨a, ha, hb⟩ h
      exact hb (h a ha)
  rw [hex] at h ⊢
  obtain ⟨f, hf, hb⟩ := h
  have hq : quarantineFindings S' = quarantineFindings S := by
    simp only [quarantineFindings, hR.classification]
  have hw : workspaceFindings S' = workspaceFindings S := by
    simp only [workspaceFindings, hR.valid]
  have hli : labelInclusionFindings S' (checkedLabel rule S') =
      labelInclusionFindings S (checkedLabel rule S) := by
    simp only [labelInclusionFindings, hR.labels, hR.checked]
  have hlp : labelPreservationFindings S' (checkedLabel rule S') =
      labelPreservationFindings S (checkedLabel rule S) := by
    simp only [labelPreservationFindings, hR.bindings, hR.checked]
  have hrec : recipientFindings Γ (actualRecipients Γ S') (checkedLabel rule S') =
      recipientFindings Γ (actualRecipients Γ S) (checkedLabel rule S) := by
    rw [actualRecipients_refines hR, hR.checked]
  have henv : (envFindings S).blockers = [] := by
    unfold envFindings; split <;> rfl
  unfold premiseFindings at hf ⊢
  dsimp only at hf ⊢
  rw [hli, hlp, hrec]
  have hcond : ∀ b ∈ checkedLabel rule S, (conditionFindings Γ S rule b).blockers ≠ [] →
      ∃ f' ∈ (checkedLabel rule S').map (conditionFindings Γ S' rule), f'.blockers ≠ [] :=
    fun b hbm hbb => ⟨_, List.mem_map.2 ⟨b, hR.checked rule ▸ hbm, rfl⟩, blocks_condition hR hbb⟩
  have hc : ∀ b ∈ checkedLabel rule S, (conditionFindings Γ S rule b).blockers ≠ [] →
      ∃ a, a ∈ checkedLabel rule S' ∧ (conditionFindings Γ S' rule a).blockers ≠ [] :=
    fun b hbm hbb => ⟨b, by rw [hR.checked]; exact hbm, blocks_condition hR hbb⟩
  by_cases ha : (rule == "admit") = true
  · simp only [ha, ite_true, List.mem_append, List.mem_cons, List.not_mem_nil, or_false,
      List.mem_map] at hf ⊢
    rcases hf with (rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl) | ⟨b, hbm, rfl⟩
    · exact ⟨_, by simp, hq ▸ hb⟩
    · exact ⟨_, by simp, hw ▸ hb⟩
    · exact ⟨_, by simp, blocks_basis hR hb⟩
    · exact ⟨_, by simp, blocks_basis hR hb⟩
    · exact ⟨_, by simp, blocks_basis hR hb⟩
    · exact absurd henv hb
    · exact ⟨_, by simp, hb⟩
    · exact ⟨_, by simp, hb⟩
    · obtain ⟨a, ham, hab⟩ := hc b hbm hb
      exact ⟨_, Or.inr ⟨a, ham, rfl⟩, hab⟩
  simp only [ha, Bool.false_eq_true, ite_false] at hf ⊢
  by_cases he : (rule == "emit") = true
  · simp only [he, ite_true, List.mem_append, List.mem_cons, List.not_mem_nil, or_false,
      List.mem_map] at hf ⊢
    rcases hf with (rfl | rfl | rfl | rfl | rfl) | ⟨b, hbm, rfl⟩
    · exact ⟨_, by simp, hw ▸ hb⟩
    · exact ⟨_, by simp, blocks_basis hR hb⟩
    · exact ⟨_, by simp, blocks_basis hR hb⟩
    · exact absurd henv hb
    · exact ⟨_, by simp, hb⟩
    · obtain ⟨a, ham, hab⟩ := hc b hbm hb
      exact ⟨_, Or.inr ⟨a, ham, rfl⟩, hab⟩
  simp only [he, Bool.false_eq_true, ite_false, List.mem_append, List.mem_cons,
    List.not_mem_nil, or_false, List.mem_map] at hf ⊢
  rcases hf with (rfl | rfl | rfl | rfl | rfl | rfl) | ⟨b, hbm, rfl⟩
  · exact ⟨_, by simp, hw ▸ hb⟩
  · exact ⟨_, by simp, blocks_basis hR hb⟩
  · exact ⟨_, by simp, blocks_basis hR hb⟩
  · exact absurd henv hb
  · exact ⟨_, by simp, hb⟩
  · exact ⟨_, by simp, hb⟩
  · obtain ⟨a, ham, hab⟩ := hc b hbm hb
    exact ⟨_, Or.inr ⟨a, ham, rfl⟩, hab⟩

/-- A `deny` stays a `deny` when more facts are known: every known-false
premise stays known false (§ 4.4, R.5.2). -/
theorem derive_deny_stable {Γ : Registry} {S S' : Snapshot} {I : Intent} {bs : List Blocker}
    (hR : S.Refines S') (h : derive Γ S I = .decision (.deny bs)) :
    ∃ bs', derive Γ S' I = .decision (.deny bs') := by
  obtain ⟨hr, henv, hout, hd⟩ := derive_decision h
  have hb : blockersOf (premiseFindings Γ S I.operation) ≠ [] := by
    intro hnil
    unfold decideRule at hd
    simp [hnil] at hd
    split at hd <;> cases hd
  have hb' := blockers_stable (Γ := Γ) hR hb
  refine ⟨blockersOf (premiseFindings Γ S' I.operation), ?_⟩
  have hdig : (outputOperations.contains I.operation &&
      (S'.facts.lookup "output_content_digest").isNone) = false := by
    by_cases ha : I.operation = "admit"
    · rw [ha]; rfl
    · obtain ⟨v, hv⟩ := Option.isSome_iff_exists.1 (hout ha).1
      have hv' := hR.facts _ _ hv
      simp only [Snapshot.fact?] at hv'
      simp [hv']
  have hcls : (outputOperations.contains I.operation && S'.classification != "classified") =
      false := by
    by_cases ha : I.operation = "admit"
    · rw [ha]; rfl
    · simp [hR.classification, (hout ha).2]
  have henv' : (Γ.environment? S'.environment).isNone = false := by
    rw [hR.environment]; simpa using henv
  unfold derive decideRule
  simp only [hr, henv', hdig, hcls, Bool.not_true, Bool.false_eq_true, ite_false]
  simp [hb']

end KomkiSpec
