import KomkiSpec.Release
import KomkiSpec.DeriveSound

/-!
# What a release permit means, and that it is used up

`aktion_permit` and `offenlegung_permit`: what no GO bridges still holds
when a release branch permits (§ 4.6, § 4.9, R.5.7). `release_single_use`:
once `advance` has committed the planned consumption, the same release
never permits again, at that stand or any later one (B.8, PACE nonce).
`advance_cas`: of two proposals for the same stand at most one commits.
-/

namespace KomkiSpec

/-- The release checks of § 4.6 step 3 hold. -/
def ReleaseValid (Γ : Registry) (R : Release) (St : Stand) (callHash : String) : Prop :=
  R.callHash = callHash ∧ R.validFrom ≤ St.asOf ∧ St.asOf ≤ R.validUntil ∧
  St.consumed.lookup R.nonce = none ∧ R.scope = St.scope ∧ R.authority ∈ Γ.observers

theorem window_nil_iff {a f u : Int} {x y : Blocker} :
    (if a < f then [x] else if a > u then [y] else []) = [] ↔ f ≤ a ∧ a ≤ u := by
  by_cases h1 : a < f
  · simp only [h1, ite_true, List.cons_ne_nil, false_iff]; omega
  · by_cases h2 : a > u
    · simp only [h1, h2, ite_false, ite_true, List.cons_ne_nil, false_iff]; omega
    · simp only [h1, h2, ite_false, true_iff]; omega

theorem releaseChecks_nil {Γ : Registry} {R : Release} {St : Stand} {c : String} :
    releaseChecks Γ R St c = [] ↔ ReleaseValid Γ R St c := by
  unfold releaseChecks ReleaseValid
  simp only [List.append_eq_nil_iff, window_nil_iff, beq_iff_eq, List.contains_iff_mem]
  cases St.consumed.lookup R.nonce <;> simp [and_assoc]

/-- The permit of a release branch: no blocker at all. -/
theorem releaseBlockers_nil {Γ : Registry} {S : Snapshot} {I : Intent} {R : Release}
    {St : Stand} {c : String} {P : Proposal}
    (h : deriveWithRelease Γ S I R St c = .decision (.permit P)) :
    releaseBlockers Γ S I.operation R St c = [] ∧ P = proposalOf R St c ∧
    outputOperations.contains I.operation = true ∧ (Γ.environment? S.environment).isSome = true := by
  unfold deriveWithRelease at h
  split at h; · cases h
  next henv =>
  split at h; · cases h
  next hop =>
  split at h; · cases h
  split at h; · cases h
  split at h; · cases h
  split at h
  · next hb =>
    cases h
    simp only [Option.isNone_iff_eq_none, ← ne_eq,
      Option.ne_none_iff_isSome] at henv
    simp only [Bool.not_eq_true', Bool.not_eq_false] at hop
    exact ⟨hb, rfl, hop, henv⟩
  · cases h

theorem workspace_blockers_nil {S : Snapshot} (h : (workspaceFindings S).blockers = []) :
    S.workspaceValid = true := by
  unfold workspaceFindings at h
  cases hv : S.workspaceValid <;> simp_all [blocking]

theorem preservation_blockers_nil {S : Snapshot} {checked : List String}
    (h : (labelPreservationFindings S checked).blockers = []) :
    ∀ b ∈ S.workspaceBindings, b ∈ checked :=
  clean_labelPreservation.1 ⟨h, by unfold labelPreservationFindings; split <;> rfl⟩

theorem recipient_blockers_nil {Γ : Registry} {rho checked : List String}
    (h : (recipientFindings Γ rho checked).blockers = []) :
    ∀ o ∈ rho, o ∈ allowedRecipients Γ checked :=
  clean_recipient.1 ⟨h, by unfold recipientFindings; dsimp only; split <;> rfl⟩

theorem env_blockers_nil {S : Snapshot} (h : envObserverBlockers S "store" = []) :
    factState S "environment_observers_complete" = .true := by
  unfold envObserverBlockers at h
  by_cases hf : factState S "environment_observers_complete" = .true
  · exact hf
  · simp [unbridgeableOps, hf] at h

/-- The recipients a store permit leaves to the observers of the store. -/
theorem recipients_of {Γ : Registry} (wf : Γ.WellFormed) {S : Snapshot} {L : List String}
    {env : List String} (henv : Γ.environment? S.environment = some env)
    (h : ∀ o ∈ actualRecipients Γ S, o ∈ allowedRecipients Γ L) :
    ∀ o ∈ env, recipients Γ.rules (· ∈ L) o := by
  intro o ho
  have : o ∈ actualRecipients Γ S := by simpa [actualRecipients, henv, mem_sortStrings] using ho
  exact allowedRecipients_sound Γ wf L o (h o this)

/-- § 4.6: an Aktionsfreigabe bridges neither an invalid contract nor a
dropped binding; for `store` neither the recipient test (#417) nor an
unproven observer list (#432). -/
theorem aktion_permit {Γ : Registry} {S : Snapshot} {I : Intent} {R : Release} {St : Stand}
    {c : String} {P : Proposal} (wf : Γ.WellFormed)
    (h : deriveWithRelease Γ S I R St c = .decision (.permit P))
    (hk : R.kind = "aktionsfreigabe") :
    S.workspaceValid = true ∧ ReleaseValid Γ R St c ∧
    (handoverOperations.contains I.operation = true →
      ∀ b ∈ S.workspaceBindings, b ∈ S.objectLabels) ∧
    (I.operation = "store" →
      factState S "environment_observers_complete" = .true ∧
      ∃ env, Γ.environment? S.environment = some env ∧
        ∀ o ∈ env, recipients Γ.rules (· ∈ S.objectLabels) o) := by
  obtain ⟨hb, _, _, henv⟩ := releaseBlockers_nil h
  obtain ⟨env, henv⟩ := Option.isSome_iff_exists.1 henv
  have hko : (R.kind == "offenlegungsfreigabe") = false := by rw [hk]; decide
  simp only [releaseBlockers, hko, Bool.false_eq_true, ite_false, aktionBlockers,
    List.append_eq_nil_iff] at hb
  obtain ⟨⟨⟨⟨hw, hobs⟩, hpres⟩, hrec⟩, hchecks⟩ := hb
  refine ⟨workspace_blockers_nil hw, releaseChecks_nil.1 hchecks, fun hh => ?_, fun hs => ?_⟩
  · rw [hh] at hpres
    have hck : checkedLabel I.operation S = S.objectLabels := by
      unfold checkedLabel; rw [hh]; rfl
    have := preservation_blockers_nil (by simpa using hpres)
    rwa [hck] at this
  · rw [hs] at hobs hrec
    have hck : checkedLabel "store" S = S.objectLabels := by
      simp [checkedLabel, handoverOperations]
    refine ⟨env_blockers_nil hobs, env, henv, recipients_of wf henv ?_⟩
    have := recipient_blockers_nil (by simpa [unbridgeableOps] using hrec)
    rwa [hck] at this

/-- Which release branch exists (`require_supportable/2`). -/
theorem release_supportable {Γ : Registry} {S : Snapshot} {I : Intent} {R : Release}
    {St : Stand} {c : String} {d : ReleaseDecision}
    (h : deriveWithRelease Γ S I R St c = .decision d) :
    R.kind = "aktionsfreigabe" ∨ (R.kind = "offenlegungsfreigabe" ∧ I.operation = "store") := by
  unfold deriveWithRelease at h
  split at h; · cases h
  split at h; · cases h
  split at h; · cases h
  next hs =>
  simp only [Bool.not_eq_true', Bool.not_eq_false, Bool.or_eq_true, Bool.and_eq_true,
    beq_iff_eq] at hs
  exact hs

/-- BerechtigtZurLockerung (R.5.7): every binding of λ(y) whose readers miss
an observer of the store carries the Befugnis of the release's authority. -/
def BerechtigtZurLockerung (Γ : Registry) (S : Snapshot) (R : Release) (art : String) : Prop :=
  ∀ b ∈ lockerungsbeduerftig Γ S.objectLabels (actualRecipients Γ S),
    befugnis Γ b R.authority art = true

/-- § 4.9, R.5.7: an Offenlegungsfreigabe permits only a store, with a valid
contract, no dropped binding, a proven observer list, the closed Ausgabeart
and Ziellabel, the Befugnis for every relaxed binding and a Ziellabel whose
readers cover the store. -/
theorem offenlegung_permit {Γ : Registry} {S : Snapshot} {I : Intent} {R : Release}
    {St : Stand} {c : String} {P : Proposal} (wf : Γ.WellFormed)
    (h : deriveWithRelease Γ S I R St c = .decision (.permit P))
    (hk : R.kind = "offenlegungsfreigabe") :
    I.operation = "store" ∧ S.workspaceValid = true ∧
    (∀ b ∈ S.workspaceBindings, b ∈ S.objectLabels) ∧ ReleaseValid Γ R St c ∧
    factState S "environment_observers_complete" = .true ∧
    ∃ art, R.ausgabeart = some art ∧ zielAusgabeart S.environment = some art ∧
      ausgabeartZiellabel art = some R.ziellabel ∧
      (∀ b ∈ R.ziellabel, (Γ.binding? b).isSome) ∧ BerechtigtZurLockerung Γ S R art ∧
      ∃ env, Γ.environment? S.environment = some env ∧
        ∀ o ∈ env, recipients Γ.rules (· ∈ R.ziellabel) o := by
  have hop : I.operation = "store" := by
    rcases release_supportable h with h' | h'
    · exact absurd (hk.symm.trans h') (by decide)
    · exact h'.2
  obtain ⟨hb, _, _, henv⟩ := releaseBlockers_nil h
  obtain ⟨env, henv⟩ := Option.isSome_iff_exists.1 henv
  simp only [releaseBlockers, hk, beq_self_eq_true, ite_true, offenlegungBlockers,
    List.append_eq_nil_iff] at hb
  obtain ⟨⟨⟨⟨⟨⟨hw, hpres⟩, hchecks⟩, hobs⟩, hziel⟩, hbef⟩, hrec⟩ := hb
  have hck : checkedLabel "store" S = S.objectLabels := by simp [checkedLabel, handoverOperations]
  rw [hck] at hpres
  unfold ziellabelBlockers at hziel
  split at hziel; · cases hziel
  next hart =>
  split at hziel; · cases hziel
  next hknown =>
  split at hziel; · cases hziel
  next hzl =>
  simp only [bne_iff_ne, ne_eq, Decidable.not_not] at hart hzl
  obtain ⟨art, hra, hza⟩ := Option.bind_eq_some_iff.1 hzl
  have hreg : ∀ b ∈ R.ziellabel, (Γ.binding? b).isSome := by
    intro b hb
    cases hbb : Γ.binding? b with
    | some _ => rfl
    | none => exact absurd (List.any_eq_true.2 ⟨b, hb, by simp [hbb]⟩) hknown
  refine ⟨hop, workspace_blockers_nil hw, preservation_blockers_nil hpres,
    releaseChecks_nil.1 hchecks, env_blockers_nil hobs, art, hra, hart.trans hra, hza, hreg,
    ?_, env, henv, recipients_of wf henv ?_⟩
  · intro b hb
    unfold befugnisBlockers at hbef
    rw [hck, List.filterMap_eq_nil_iff] at hbef
    have := hbef b hb
    rw [hra] at this
    simpa using this
  · unfold ziellabelRecipientBlockers at hrec
    have hall : (R.ziellabel.all fun b => (Γ.binding? b).isSome) = true :=
      List.all_eq_true.2 hreg
    exact recipient_blockers_nil (by simpa [hall] using hrec)

/-! ## Single use (§ 2.7, B.8) -/

theorem advance_ok {St St' : Stand} {P : Proposal} (h : advance St P = .ok St') :
    P.standRef = St.ref ∧ P.standVersionAfter = St.version + 1 ∧
    St.consumed.lookup P.nonce = none ∧ St'.version = St.version + 1 ∧
    St'.consumed = (P.nonce, P.releaseId) :: St.consumed := by
  unfold advance at h
  split at h
  · next hc =>
    split at h
    · cases h
    · next hn =>
      cases h
      simp only [Bool.and_eq_true, beq_iff_eq] at hc
      simp only [Option.isSome_iff_ne_none, ne_eq, Decidable.not_not] at hn
      exact ⟨hc.1, hc.2, hn, rfl, rfl⟩
  · cases h

/-- What one stand has consumed, every stand after it has consumed too. -/
theorem advance_keeps {St St' : Stand} {P : Proposal} (h : advance St P = .ok St')
    {n r : String} (hn : St.consumed.lookup n = some r) : St'.consumed.lookup n = some r := by
  obtain ⟨_, _, hfresh, _, hc⟩ := advance_ok h
  rw [hc]
  by_cases he : n = P.nonce
  · subst he; rw [hfresh] at hn; cases hn
  · have hne : (n == P.nonce) = false := by simpa using he
    simp [List.lookup, hne, hn]

/-- Stands reachable by committed transitions. -/
inductive Advances : Stand → Stand → Prop
  | refl {St : Stand} : Advances St St
  | step {St St' St'' : Stand} {P : Proposal} : advance St P = .ok St' → Advances St' St'' →
      Advances St St''

theorem advances_keep {St St' : Stand} (h : Advances St St') {n r : String}
    (hn : St.consumed.lookup n = some r) : ∃ r', St'.consumed.lookup n = some r' := by
  induction h with
  | refl => exact ⟨r, hn⟩
  | step ha _ ih => exact ih (advance_keeps ha hn)

theorem consumed_blocks {Γ : Registry} {S : Snapshot} {op : String} {R : Release} {St : Stand}
    {c r : String} (hn : St.consumed.lookup R.nonce = some r) :
    releaseBlockers Γ S op R St c ≠ [] := by
  have : releaseChecks Γ R St c ≠ [] := by
    intro hnil
    have := (releaseChecks_nil.1 hnil).2.2.2.1
    rw [hn] at this; cases this
  unfold releaseBlockers offenlegungBlockers aktionBlockers
  split <;> simp_all [List.append_eq_nil_iff]

/-- B.8: once the planned consumption is committed, the same release never
permits again, at the next stand or at any stand after it. -/
theorem release_single_use {Γ : Registry} {S : Snapshot} {I : Intent} {R : Release}
    {St St' St'' : Stand} {c : String} {P : Proposal}
    (h : deriveWithRelease Γ S I R St c = .decision (.permit P))
    (ha : advance St P = .ok St') (hlater : Advances St' St'')
    (S₂ : Snapshot) (I₂ : Intent) (c₂ : String) (P₂ : Proposal) :
    deriveWithRelease Γ S₂ I₂ R St'' c₂ ≠ .decision (.permit P₂) := by
  intro h₂
  obtain ⟨_, hP, _, _⟩ := releaseBlockers_nil h
  have hnonce : St'.consumed.lookup R.nonce = some R.releaseId := by
    obtain ⟨_, _, _, _, hc⟩ := advance_ok ha
    rw [hc, hP]
    simp [proposalOf, List.lookup]
  obtain ⟨r, hr⟩ := advances_keep hlater hnonce
  exact consumed_blocks (Γ := Γ) (S := S₂) (op := I₂.operation) (c := c₂) hr
    (releaseBlockers_nil h₂).1

/-- Compare-and-swap (§ 2.7): of two proposals for the same stand, at most
one commits; the second finds the version already moved on. -/
theorem advance_cas {St St₁ : Stand} {P₁ P₂ : Proposal}
    (h₁ : advance St P₁ = .ok St₁) (h₂ : P₂.standVersionAfter = St.version + 1) :
    advance St₁ P₂ = .refused "stand_version_conflict" := by
  obtain ⟨_, _, _, hv, _⟩ := advance_ok h₁
  unfold advance
  have : (P₂.standVersionAfter == St₁.version + 1) = false := by
    rw [h₂, hv]; simp
  simp [this]

end KomkiSpec
