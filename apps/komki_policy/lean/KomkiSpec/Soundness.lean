import KomkiSpec.Verify

/-!
# Soundness of `verify` for `admit` (RFC 0003 A.7)

`verify_sound`: whatever tree is presented, `valid` implies that admit is
derivable under CONTRACT.md § 4.3 from the registry and the snapshot alone.
`verify_sound_rfc` carries that over to the Aufnahme rule of R.5.4. The
forged trees of the audit (#477, #479, #480) were counterexamples to exactly
this statement for the Elixir `verify`.
-/

namespace KomkiSpec

/-- Admit is derivable (CONTRACT.md § 4.3), stated without `verify`: every
premise is recomputed from registry and snapshot, nothing from the tree. -/
def AdmitDerivable (Γ : Registry) (S : Snapshot) : Prop :=
  S.classification = "classified" ∧
  S.workspaceValid = true ∧
  (∀ n ∈ admitBaseFacts, S.fact? n = some (.bool true)) ∧
  (∀ l ∈ S.objectLabels, l ∈ S.workspaceBindings) ∧
  (∃ env, Γ.environment? S.environment = some env ∧
    ∀ o ∈ env, recipients Γ.rules (· ∈ S.workspaceBindings) o) ∧
  (∀ b ∈ S.workspaceBindings, ∃ j e, Γ.ruleExpr? b "admit" = some j ∧
    Expr.ofJVal j = some e ∧ eval S.fact? e = .true)

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
theorem fixed_slot {Γ : Registry} {S : Snapshot} {ps : List Premise} {n k : String}
    (hreq : requiredSetOk S.workspaceBindings ps = true)
    (hall : ps.all (premiseOk Γ S) = true)
    (hn : n ∈ admitFixed) (hk : kindTable.lookup n = some k) :
    ∃ p ∈ ps, p.name = n ∧ p.kind = k ∧ fitsSlot S.workspaceBindings p = true ∧
      premiseOk Γ S p = true := by
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
theorem fact_of_fit {B : List String} {p : Premise} (hf : fitsSlot B p = true)
    (hk : p.kind = "fact") : p.strField? "fact" = some p.name := by
  simp only [fitsSlot, Bool.and_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq] at hf
  rcases hf.1.2 with h | h
  · exact absurd hk h
  · exact h

theorem base_fact {Γ : Registry} {S : Snapshot} {ps : List Premise} {n : String}
    (hreq : requiredSetOk S.workspaceBindings ps = true)
    (hall : ps.all (premiseOk Γ S) = true) (hn : n ∈ admitBaseFacts) :
    S.fact? n = some (.bool true) := by
  have hfixed : n ∈ admitFixed := by
    simp only [admitFixed, List.mem_append]; exact Or.inl (Or.inr hn)
  have hk : kindTable.lookup n = some "fact" := by
    simp only [admitBaseFacts, List.mem_cons, List.not_mem_nil, or_false] at hn
    rcases hn with rfl | rfl | rfl | rfl <;> rfl
  have hne : n ≠ "workspace_contract_valid" := by
    simp only [admitBaseFacts, List.mem_cons, List.not_mem_nil, or_false] at hn
    rcases hn with rfl | rfl | rfl | rfl <;> decide
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

/-- Main theorem: `verify` accepts only trees whose decision is derivable. -/
theorem verify_sound {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof}
    (wf : Γ.WellFormed) (h : verify Γ S I P = .valid) :
    I.operation = "admit" ∧ P.rule = "admit" ∧ P.conclusion = "permit" ∧
    P.registryRef = Γ.registryId ∧ P.snapshotRef = S.snapshotId ∧
    P.intentRef = I.intentId ∧ AdmitDerivable Γ S := by
  unfold verify at h
  by_cases hr : referencesOk Γ S I P = true
  case neg => simp [hr] at h
  by_cases hrule : P.rule = "admit"
  case neg => simp [hr, hrule] at h
  by_cases hlab : sortStrings P.checkedLabel = S.workspaceBindings
  case neg => simp [hr, hrule, hlab] at h
  by_cases hreq : requiredSetOk S.workspaceBindings P.premises = true
  case neg => simp [hr, hrule, hlab, hreq] at h
  simp only [hr, hrule, hlab, hreq, Bool.not_true, bne_self_eq_false, Bool.false_eq_true,
    ite_false] at h
  have hfinal : P.premises.all (premiseOk Γ S) = true ∧ P.conclusion = "permit" := by
    split at h
    · next hc => simpa only [Bool.and_eq_true, beq_iff_eq] using hc
    · cases h
  obtain ⟨hall, hconcl⟩ := hfinal
  simp only [referencesOk, Bool.and_eq_true, beq_iff_eq] at hr
  obtain ⟨⟨⟨⟨hsnap, hreg⟩, hint⟩, _⟩, hop⟩ := hr
  refine ⟨hop ▸ hrule, hrule, hconcl, hreg, hsnap, hint, ?_⟩
  -- not_quarantine
  obtain ⟨pq, _, _, hkq, _, hokq⟩ := fixed_slot (n := "not_quarantine") (k := "object_check")
    hreq hall (by decide) rfl
  have hq : quarantineOk S pq = true := by simpa [premiseOk, hkq] using hokq
  simp only [quarantineOk, Bool.and_eq_true, beq_iff_eq] at hq
  -- workspace_contract_valid
  obtain ⟨pw, _, hnw, hkw, hfw, hokw⟩ := fixed_slot (n := "workspace_contract_valid") (k := "fact")
    hreq hall (by decide) rfl
  have hfactw := fact_of_fit hfw hkw
  rw [hnw] at hfactw
  have hw : factPremiseOk S pw = true := by simpa [premiseOk, hkw] using hokw
  simp only [factPremiseOk, hfactw, beq_self_eq_true, ite_true, Bool.and_eq_true] at hw
  -- label_inclusion
  obtain ⟨pl, _, hnl, hkl, _, hokl⟩ := fixed_slot (n := "label_inclusion") (k := "computed")
    hreq hall (by decide) rfl
  have hl : labelInclusionOk S pl = true := by simpa [premiseOk, hkl, hnl] using hokl
  simp only [labelInclusionOk, Bool.and_eq_true] at hl
  -- recipient_inclusion
  obtain ⟨pr, _, hnr, hkr, _, hokr⟩ := fixed_slot (n := "recipient_inclusion") (k := "computed")
    hreq hall (by decide) rfl
  have hrc : recipientInclusionOk Γ S pr = true := by simpa [premiseOk, hkr, hnr] using hokr
  refine ⟨hq.1, hw.2, fun n hn => base_fact hreq hall hn,
    fun l hlm => List.contains_iff_mem.1 (List.all_eq_true.1 hl.1.1.1 l hlm), ?_, ?_⟩
  · unfold recipientInclusionOk at hrc
    split at hrc
    · cases hrc
    · next env henv =>
      simp only [Bool.and_eq_true] at hrc
      refine ⟨env, henv, fun o ho => ?_⟩
      have hin := List.all_eq_true.1 hrc.1.1.1 o (mem_sortStrings.2 ho)
      exact allowedRecipients_sound Γ wf _ o (List.contains_iff_mem.1 hin)
  · intro b hb
    have hcb : b ∈ conditionBindings P.premises := by
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
    have hc : conditionOk Γ S p = true := by
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

/-- The Verarbeitungssituation Aufnahme(x, W) of R.5.4, read from the snapshot.
The base requires a known environment: unknown recipients are missing
evidence, not ∅ (R.5.1). -/
def admitSituation (Γ : Registry) (S : Snapshot) : Situation String String where
  base := S.classification = "classified" ∧ S.workspaceValid = true ∧
    (∀ n ∈ admitBaseFacts, S.fact? n = some (.bool true)) ∧
    ∃ env, Γ.environment? S.environment = some env
  observers o := ∃ env, Γ.environment? S.environment = some env ∧ o ∈ env
  condition b := ∃ j e, Γ.ruleExpr? b "admit" = some j ∧ Expr.ofJVal j = some e ∧
    eval S.fact? e = .true

/-- The § 4.3 premises are the Aufnahme rule of R.5.4:
λ(x) ⊆ B_W ∧ Erlaubt_Γ(Aufnahme(x, W), B_W). -/
theorem admitDerivable_permitted {Γ : Registry} {S : Snapshot} (h : AdmitDerivable Γ S) :
    Sub (· ∈ S.objectLabels) (· ∈ S.workspaceBindings) ∧
    Permitted Γ.rules (admitSituation Γ S) (· ∈ S.workspaceBindings) := by
  obtain ⟨hc, hv, hbase, hlab, ⟨env, henv, hrec⟩, hcond⟩ := h
  refine ⟨hlab, ⟨hc, hv, hbase, env, henv⟩, fun o ⟨env', henv', ho⟩ => ?_, hcond⟩
  rw [henv] at henv'
  cases henv'
  exact hrec o ho

/-- A.7 for `admit`: a tree `verify` accepts proves the Aufnahme rule. -/
theorem verify_sound_rfc {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof}
    (wf : Γ.WellFormed) (h : verify Γ S I P = .valid) :
    Sub (· ∈ S.objectLabels) (· ∈ S.workspaceBindings) ∧
    Permitted Γ.rules (admitSituation Γ S) (· ∈ S.workspaceBindings) :=
  admitDerivable_permitted (verify_sound wf h).2.2.2.2.2.2

end KomkiSpec
