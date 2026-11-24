import KomkiSpec.Verify

/-!
# Soundness of `verify` (RFC 0003 A.7)

`verify_sound`: whatever tree is presented, `valid` implies that the tree's
rule is derivable under CONTRACT.md § 4.3, § 4.5, § 4.7 or § 4.8 from the
registry and the snapshot alone. `verify_sound_rfc` carries that over to the
rules of R.5.4–R.5.6, `handover_within_admitted` to A.3 at the engine. The
forged trees of the audit (#477, #479, #480) and the output trees on a
quarantined object or without digest (#628) were counterexamples to exactly
this statement for the Elixir `verify`.
-/

namespace KomkiSpec

/-- The label duty of a rule: λ(x) ⊆ B_W for Aufnahme (R.5.4); none for
Erzeugen, whose λ(y) := B_W the mediator assigns (R.5.5); B_W ⊆ λ(y) for
Speicherung and Übergabe (R.5.6). -/
def LabelDuty (rule : String) (S : Snapshot) : Prop :=
  if rule = "admit" then Sub (· ∈ S.objectLabels) (· ∈ S.workspaceBindings)
  else if rule = "emit" then True
  else Sub (· ∈ S.workspaceBindings) (· ∈ S.objectLabels)

/-- `rule` is derivable (CONTRACT.md § 4.3, § 4.5, § 4.7, § 4.8), stated
without `verify`: every premise is recomputed from registry and snapshot,
nothing from the tree. -/
structure Derivable (Γ : Registry) (S : Snapshot) (rule : String) : Prop where
  classified : S.classification = "classified"
  digest : rule ≠ "admit" → (S.fact? "output_content_digest").isSome = true
  valid : S.workspaceValid = true
  facts : ∀ n ∈ baseFacts rule, S.fact? n = some (.bool true)
  labels : LabelDuty rule S
  recipients : ∃ env, Γ.environment? S.environment = some env ∧
    ∀ o ∈ env, recipients Γ.rules (· ∈ checkedLabel rule S) o
  conditions : ∀ b ∈ checkedLabel rule S, ∃ j e, Γ.ruleExpr? b rule = some j ∧
    Expr.ofJVal j = some e ∧ eval S.fact? e = .true

/-! ## The tables, checked once by evaluation -/

theorem rule_cases {r : String} (h : proofRules.contains r = true) :
    r = "admit" ∨ r = "emit" ∨ r = "transfer" ∨ r = "store" := by
  simpa [proofRules] using h

theorem shared_slots : ∀ r ∈ proofRules,
    "workspace_contract_valid" ∈ fixedPremises r ∧ "recipient_inclusion" ∈ fixedPremises r := by
  decide

theorem base_slots : ∀ r ∈ proofRules, ∀ n ∈ baseFacts r,
    n ∈ fixedPremises r ∧ kindTable.lookup n = some "fact" ∧ n ≠ "workspace_contract_valid" := by
  decide

theorem output_rules : ∀ r ∈ proofRules, r ≠ "admit" → outputOperations.contains r = true := by
  decide

theorem handover_rules : ∀ r ∈ handoverOperations,
    r ∈ proofRules ∧ r ≠ "admit" ∧ r ≠ "emit" ∧ "label_preservation" ∈ fixedPremises r := by
  decide

/-! ## Lemmas -/

theorem mem_sortStrings {xs : List String} {a : String} : a ∈ sortStrings xs ↔ a ∈ xs := by
  unfold sortStrings; exact List.mem_mergeSort

/-- The computed list lies inside R_Γ(L); 𝒪 needs the registry invariant. -/
theorem allowedRecipients_sound (Γ : Registry) (wf : Γ.WellFormed) (L : List String) (o : String)
    (h : o ∈ allowedRecipients Γ L) : recipients Γ.rules (· ∈ L) o := by
  cases L with
  | nil => exact ⟨h, fun _ hb => absurd hb List.not_mem_nil⟩
  | cons b bs =>
    simp only [allowedRecipients, mem_sortStrings, List.mem_filter, List.all_eq_true,
      List.contains_iff_mem] at h
    obtain ⟨hb, hbs⟩ := h
    refine ⟨wf b o hb, fun b' hb' => ?_⟩
    rcases List.mem_cons.1 hb' with rfl | hb'
    · exact hb
    · exact hbs b' hb'

/-- Every fixed slot is filled by a premise that fits it and passes its check. -/
theorem fixed_slot {Γ : Registry} {S : Snapshot} {rule : String} {B : List String}
    {ps : List Premise} {n k : String}
    (hreq : requiredSetOk rule B ps = true)
    (hall : ps.all (premiseOk Γ S rule) = true)
    (hn : n ∈ fixedPremises rule) (hk : kindTable.lookup n = some k) :
    ∃ p ∈ ps, p.name = n ∧ p.kind = k ∧ fitsSlot rule B p = true ∧
      premiseOk Γ S rule p = true := by
  simp only [requiredSetOk, Bool.and_eq_true, List.all_eq_true, List.any_eq_true,
    beq_iff_eq] at hreq
  obtain ⟨⟨hfixed, _⟩, hfit⟩ := hreq
  obtain ⟨p, hp, hname⟩ := hfixed n hn
  have hf := hfit p hp
  have hkind : p.kind = k := by
    simp only [fitsSlot, Bool.and_eq_true, beq_iff_eq] at hf
    rw [hname, hk] at hf
    exact (Option.some.inj hf.1.1.2).symm
  exact ⟨p, hp, hname, hkind, hf, List.all_eq_true.1 hall p hp⟩

/-- A fitting fact premise names the fact its slot names (#479). -/
theorem fact_of_fit {rule : String} {B : List String} {p : Premise}
    (hf : fitsSlot rule B p = true) (hk : p.kind = "fact") :
    p.strField? "fact" = some p.name := by
  simp only [fitsSlot, Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq] at hf
  rcases hf.1.2 with h | h
  · exact absurd hk h
  · exact h

theorem base_fact {Γ : Registry} {S : Snapshot} {rule : String} {B : List String}
    {ps : List Premise} {n : String}
    (hreq : requiredSetOk rule B ps = true)
    (hall : ps.all (premiseOk Γ S rule) = true)
    (hslot : n ∈ fixedPremises rule ∧ kindTable.lookup n = some "fact" ∧
      n ≠ "workspace_contract_valid") :
    S.fact? n = some (.bool true) := by
  obtain ⟨hfixed, hk, hne⟩ := hslot
  obtain ⟨p, _, hname, hkind, hfit, hok⟩ := fixed_slot hreq hall hfixed hk
  have hfact := fact_of_fit hfit hkind
  rw [hname] at hfact
  simp only [premiseOk, hkind, factPremiseOk, hfact] at hok
  simp only [beq_self_eq_true, ite_true, beq_iff_eq, hne, ite_false] at hok
  split at hok
  · next b hb =>
    simp only [Bool.and_eq_true, beq_iff_eq] at hok
    rw [hb, hok.2]
  · simp at hok

/-- The condition of every binding of the checked label holds. -/
theorem conditions_hold {Γ : Registry} {S : Snapshot} {rule : String} {ps : List Premise}
    (hreq : requiredSetOk rule (checkedLabel rule S) ps = true)
    (hall : ps.all (premiseOk Γ S rule) = true) :
    ∀ b ∈ checkedLabel rule S, ∃ j e, Γ.ruleExpr? b rule = some j ∧
      Expr.ofJVal j = some e ∧ eval S.fact? e = .true := by
  intro b hb
  have hcb : b ∈ conditionBindings ps := by
    simp only [requiredSetOk, Bool.and_eq_true, List.all_eq_true] at hreq
    exact List.contains_iff_mem.1 (hreq.1.2 b hb)
  simp only [conditionBindings, List.mem_filterMap] at hcb
  obtain ⟨p, hp, hsel⟩ := hcb
  have hkc : p.kind = "condition" := by
    by_cases hne : p.kind = "condition"
    · exact hne
    · simp [hne] at hsel
  have hbind : p.strField? "binding" = some b := by
    have hsel' : p.name = "binding_condition" ∧ p.strField? "binding" = some b := by
      simpa [hkc] using hsel
    exact hsel'.2
  have hc : conditionOk Γ S rule p = true := by
    simpa [premiseOk, hkc] using List.all_eq_true.1 hall p hp
  unfold conditionOk at hc
  rw [hbind] at hc
  dsimp only at hc
  split at hc
  · cases hc
  · next j hj =>
    split at hc
    · cases hc
    · next e he =>
      simp only [Bool.and_eq_true, beq_iff_eq] at hc
      exact ⟨j, e, hj, he, hc.1.2⟩

/-- The recipient slot: the environment's observers lie inside R_Γ(checked label). -/
theorem recipients_hold {Γ : Registry} {S : Snapshot} {rule : String} {ps : List Premise}
    (wf : Γ.WellFormed) (hr : proofRules.contains rule = true)
    (hreq : requiredSetOk rule (checkedLabel rule S) ps = true)
    (hall : ps.all (premiseOk Γ S rule) = true) :
    ∃ env, Γ.environment? S.environment = some env ∧
      ∀ o ∈ env, recipients Γ.rules (· ∈ checkedLabel rule S) o := by
  obtain ⟨p, _, hn, hk, _, hok⟩ := fixed_slot (n := "recipient_inclusion") (k := "computed")
    hreq hall (shared_slots rule (List.contains_iff_mem.1 hr)).2 rfl
  have hrc : recipientInclusionOk Γ S (checkedLabel rule S) p = true := by
    simpa [premiseOk, hk, hn] using hok
  unfold recipientInclusionOk at hrc
  split at hrc
  · cases hrc
  · next env henv =>
    simp only [Bool.and_eq_true] at hrc
    refine ⟨env, henv, fun o ho => ?_⟩
    have hin := List.all_eq_true.1 hrc.1.1.1 o (mem_sortStrings.2 ho)
    exact allowedRecipients_sound Γ wf _ o (List.contains_iff_mem.1 hin)

/-! ## Main theorems -/

/-- Main theorem: `verify` accepts only trees whose decision is derivable. -/
theorem verify_sound {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof}
    (wf : Γ.WellFormed) (h : verify Γ S I P = .valid) :
    I.operation = P.rule ∧ P.conclusion = "permit" ∧ P.registryRef = Γ.registryId ∧
    P.snapshotRef = S.snapshotId ∧ P.intentRef = I.intentId ∧ Derivable Γ S P.rule := by
  unfold verify at h
  cases hin : (outputOperations.contains I.operation && !outputInputOk S)
  case true => simp only [hin, ite_true] at h; cases h
  simp only [hin, Bool.false_eq_true, ite_false] at h
  cases hr : referencesOk Γ S I P
  case false => simp only [hr, Bool.not_false, ite_true] at h; cases h
  simp only [hr, Bool.not_true, Bool.false_eq_true, ite_false] at h
  by_cases hlab : sortStrings P.checkedLabel = checkedLabel P.rule S
  case neg => simp [hlab] at h
  cases hreq : requiredSetOk P.rule (checkedLabel P.rule S) P.premises
  case false => simp [hlab, hreq] at h
  simp only [hlab, hreq, bne_self_eq_false, Bool.not_true, Bool.false_eq_true, ite_false] at h
  have hfinal : P.premises.all (premiseOk Γ S P.rule) = true ∧ P.conclusion = "permit" := by
    split at h
    · next hc => simpa only [Bool.and_eq_true, beq_iff_eq] using hc
    · cases h
  obtain ⟨hall, hconcl⟩ := hfinal
  simp only [referencesOk, Bool.and_eq_true, beq_iff_eq] at hr
  obtain ⟨⟨⟨⟨hsnap, hreg⟩, hint⟩, hrule⟩, hop⟩ := hr
  have hmem := List.contains_iff_mem.1 hrule
  -- The output rules: digest and classification come from the prerequisite (#628).
  have hout : P.rule ≠ "admit" →
      (S.fact? "output_content_digest").isSome = true ∧ S.classification = "classified" := by
    intro hne
    have hc := output_rules P.rule hmem hne
    rw [hop] at hc
    have hok : outputInputOk S = true := by
      cases h' : outputInputOk S
      · rw [hc, h'] at hin; exact absurd hin (by decide)
      · rfl
    simpa only [outputInputOk, Snapshot.fact?, Bool.and_eq_true, beq_iff_eq] using hok
  -- workspace_contract_valid
  obtain ⟨pw, _, hnw, hkw, hfw, hokw⟩ := fixed_slot (n := "workspace_contract_valid") (k := "fact")
    hreq hall (shared_slots P.rule hmem).1 rfl
  have hfactw := fact_of_fit hfw hkw
  rw [hnw] at hfactw
  have hw : factPremiseOk S pw = true := by simpa [premiseOk, hkw] using hokw
  simp only [factPremiseOk, hfactw, beq_self_eq_true, ite_true, Bool.and_eq_true] at hw
  refine ⟨hop.symm, hconcl, hreg, hsnap, hint, ?_⟩
  -- The rule-specific premises: Aufnahme, Erzeugen, Speicherung and Übergabe.
  have hlabels : S.classification = "classified" ∧ LabelDuty P.rule S := by
    by_cases ha : P.rule = "admit"
    · obtain ⟨pq, _, _, hkq, _, hokq⟩ := fixed_slot (n := "not_quarantine") (k := "object_check")
        hreq hall (by rw [ha]; decide) rfl
      have hq : quarantineOk S pq = true := by simpa [premiseOk, hkq] using hokq
      simp only [quarantineOk, Bool.and_eq_true, beq_iff_eq] at hq
      obtain ⟨pl, _, hnl, hkl, _, hokl⟩ := fixed_slot (n := "label_inclusion") (k := "computed")
        hreq hall (by rw [ha]; decide) rfl
      have hl : labelInclusionOk S pl = true := by simpa [premiseOk, hkl, hnl] using hokl
      simp only [labelInclusionOk, Bool.and_eq_true] at hl
      refine ⟨hq.1, ?_⟩
      simp only [LabelDuty, ha, ite_true]
      exact fun l hlm => List.contains_iff_mem.1 (List.all_eq_true.1 hl.1.1.1 l hlm)
    · refine ⟨(hout ha).2, ?_⟩
      by_cases he : P.rule = "emit"
      · simp [LabelDuty, he]
      · have hho : handoverOperations.contains P.rule = true := by
          rcases rule_cases hrule with h' | h' | h' | h' <;> simp_all [handoverOperations]
        obtain ⟨pp, _, hnp, hkp, _, hokp⟩ := fixed_slot (n := "label_preservation")
          (k := "computed") hreq hall (handover_rules P.rule (List.contains_iff_mem.1 hho)).2.2.2 rfl
        have hpres : labelPreservationOk S P.rule pp = true := by
          simpa [premiseOk, hkp, hnp] using hokp
        simp only [labelPreservationOk, checkedLabel, hho, ite_true, Bool.and_eq_true] at hpres
        simp only [LabelDuty, ha, he, ite_false]
        exact fun b hb => List.contains_iff_mem.1 (List.all_eq_true.1 hpres.1.1.1.2 b hb)
  exact {
    classified := hlabels.1
    digest := fun hne => (hout hne).1
    valid := hw.2
    facts := fun n hn => base_fact hreq hall (base_slots P.rule hmem n hn)
    labels := hlabels.2
    recipients := recipients_hold wf hrule hreq hall
    conditions := conditions_hold hreq hall }

/-- The Verarbeitungssituation of the rule (Aufnahme R.5.4, Erzeugen R.5.5,
Speicherung and Übergabe R.5.6), read from the snapshot. The base requires a
known environment: unknown recipients are missing evidence, not ∅ (R.5.1). -/
def situation (Γ : Registry) (S : Snapshot) (rule : String) : Situation String String where
  base := S.classification = "classified" ∧
    (rule ≠ "admit" → (S.fact? "output_content_digest").isSome = true) ∧
    S.workspaceValid = true ∧ (∀ n ∈ baseFacts rule, S.fact? n = some (.bool true)) ∧
    ∃ env, Γ.environment? S.environment = some env
  observers o := ∃ env, Γ.environment? S.environment = some env ∧ o ∈ env
  condition b := ∃ j e, Γ.ruleExpr? b rule = some j ∧ Expr.ofJVal j = some e ∧
    eval S.fact? e = .true

/-- The contract's premises are the rules of R.5.4–R.5.6: the label duty and
Erlaubt_Γ(c, checked label). -/
theorem derivable_permitted {Γ : Registry} {S : Snapshot} {rule : String}
    (h : Derivable Γ S rule) :
    LabelDuty rule S ∧ Permitted Γ.rules (situation Γ S rule) (· ∈ checkedLabel rule S) := by
  obtain ⟨hc, hd, hv, hbase, hlab, ⟨env, henv, hrec⟩, hcond⟩ := h
  refine ⟨hlab, ⟨hc, hd, hv, hbase, env, henv⟩, fun o ⟨env', henv', ho⟩ => ?_, hcond⟩
  rw [henv] at henv'
  cases henv'
  exact hrec o ho

/-- A.7: a tree `verify` accepts proves the rule of its operation. -/
theorem verify_sound_rfc {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof}
    (wf : Γ.WellFormed) (h : verify Γ S I P = .valid) :
    LabelDuty P.rule S ∧ Permitted Γ.rules (situation Γ S P.rule) (· ∈ checkedLabel P.rule S) :=
  derivable_permitted (verify_sound wf h).2.2.2.2.2

/-- A.3 at the engine: an object x admitted into a room reaches, through a
verified store or transfer out of the same room, only observers in
R_Γ(λ(x)). The two verified trees form one regular step of the calculus.
Both snapshots name the same B_W because B_W is fixed (RFC 4.1); keeping it
fixed is the mediator's duty, not the engine's. -/
theorem handover_within_admitted {Γ : Registry} {S₁ S₂ : Snapshot} {I₁ I₂ : Intent}
    {P₁ P₂ : Proof} (wf : Γ.WellFormed)
    (hA : verify Γ S₁ I₁ P₁ = .valid) (hAr : P₁.rule = "admit")
    (hH : verify Γ S₂ I₂ P₂ = .valid) (hHr : handoverOperations.contains P₂.rule = true)
    (hW : S₂.workspaceBindings = S₁.workspaceBindings)
    {env : List String} (henv : Γ.environment? S₂.environment = some env)
    {o : String} (ho : o ∈ env) :
    recipients Γ.rules (· ∈ S₁.objectLabels) o := by
  have ⟨hdutyA, _⟩ := verify_sound_rfc wf hA
  have ⟨hdutyH, _, hrec, _⟩ := verify_sound_rfc wf hH
  obtain ⟨_, hna, hne, _⟩ := handover_rules P₂.rule (List.contains_iff_mem.1 hHr)
  simp only [LabelDuty, hAr, ite_true] at hdutyA
  simp only [LabelDuty, hna, hne, ite_false] at hdutyH
  simp only [checkedLabel, hHr, ite_true] at hrec
  have hstep : Step (· ∈ S₁.objectLabels) (· ∈ S₂.objectLabels) :=
    Step.admitEmit (bw := (· ∈ S₂.workspaceBindings)) (fun l hl => hW ▸ hdutyA l hl) hdutyH
  exact recipients_antitone Γ.rules (preservation (Path.cons hstep Path.refl)) o
    (hrec o ⟨env, henv, ho⟩)

end KomkiSpec
