import KomkiSpec.CatalogAgree

/-!
# The catalog of a denied release promises nothing either (CONTRACT.md § 2.8)

`catalog_aktion_effective` and `catalog_offenlegung_effective` cover the
denials of the normal branch. These cover the release branch: when a
release is denied, the catalog offers a fresh GO for the exact call
(§ 2.8, Aktionsfreigabe-Zweig); a release built from that offer, with a
fresh nonce, a window around the stand's time and a fitting authority, is
permitted.
-/

namespace KomkiSpec

/-- What `deriveWithRelease` checked before it decided. -/
theorem release_decision {Γ : Registry} {S : Snapshot} {I : Intent} {R : Release} {St : Stand}
    {c : String} {d : ReleaseDecision} (h : deriveWithRelease Γ S I R St c = .decision d) :
    (Γ.environment? S.environment).isSome = true ∧ outputOperations.contains I.operation = true ∧
    (R.kind = "aktionsfreigabe" ∨ (R.kind = "offenlegungsfreigabe" ∧ I.operation = "store")) ∧
    (S.facts.lookup "output_content_digest").isSome = true ∧ S.classification = "classified" ∧
    (∀ bs, d = .deny bs → bs = releaseBlockers Γ S I.operation R St c) := by
  unfold deriveWithRelease at h
  split at h; · cases h
  next h1 =>
  split at h; · cases h
  next h2 =>
  split at h; · cases h
  next h3 =>
  split at h; · cases h
  next h4 =>
  split at h; · cases h
  next h5 =>
  refine ⟨by simpa [Option.isSome_iff_ne_none] using h1, by simpa using h2, ?_, by simpa using h4,
    by simpa using h5, ?_⟩
  · by_cases hk : R.kind = "aktionsfreigabe"
    · exact Or.inl hk
    · right
      simp_all
  · intro bs hd
    subst hd
    split at h
    · cases h
    · next hb => cases h; rfl

/-- An Aktionsfreigabe offer of a release catalog: the release was one, no
code of the denial is beyond any GO, and the offer names the call. -/
theorem release_catalog_aktion_mem {Γ : Registry} {c : CatalogCtx} {codes : List String}
    {h : String} (hrule : c.rule = "release") (hm : Go.aktion h ∈ (catalogGos Γ c codes).flatten) :
    (∀ code ∈ codes, unbridgeableFor "release" code = false) ∧
    c.releaseKind ≠ some "offenlegungsfreigabe" ∧ h = c.callHash.getD "" := by
  simp only [catalogGos, List.mem_flatten, List.mem_map] at hm
  obtain ⟨l, ⟨code, _, rfl⟩, hm⟩ := hm
  rw [List.mem_append] at hm
  rcases hm with hm | hm
  · rw [List.mem_filter] at hm
    obtain ⟨hreg, hkeep⟩ := hm
    simp only [hrule, Bool.not_eq_true', Bool.or_eq_false_iff, List.any_eq_false] at hkeep
    obtain ⟨⟨hany, _⟩, _⟩ := hkeep
    unfold regularGos at hreg
    simp only [hrule, beq_self_eq_true, ite_true] at hreg
    split at hreg
    · split at hreg <;> simp at hreg
    · next hk =>
      split at hreg
      · simp at hreg
      · simp only [List.mem_singleton, Go.aktion.injEq] at hreg
        exact ⟨fun k hk' => by simpa using hany k hk', by simpa using hk, hreg⟩
  · simp [hrule] at hm

/-- No empty promise after a denied Aktionsfreigabe (§ 2.8): the fresh GO
the catalog offers is permitted, at any stand, with a fresh nonce and any
observer as the granting authority. -/
theorem release_catalog_aktion_effective {Γ : Registry} {S : Snapshot} {I : Intent}
    {R : Release} {St : Stand} {bs : List Blocker} {c h nonce auth : String}
    (hd : deriveWithRelease Γ S I R St c = .decision (.deny bs))
    (hm : Go.aktion h ∈
      (catalogGos Γ (releaseCatalogCtx Γ S I.operation R c) (codesOf bs)).flatten)
    (hn : St.consumed.lookup nonce = none) (ha : auth ∈ Γ.observers) :
    deriveWithRelease Γ S I (aktionRelease h auth nonce St) St c =
      .decision (.permit (proposalOf (aktionRelease h auth nonce St) St c)) := by
  obtain ⟨henv, hop, _, hdig, hcls, hbs⟩ := release_decision hd
  obtain ⟨hany, hkind, hh⟩ := release_catalog_aktion_mem rfl hm
  simp only [releaseCatalogCtx, Option.getD_some, ne_eq, Option.some.injEq] at hkind hh
  have hbs' : bs = aktionBlockers Γ S I.operation R St c := by
    rw [hbs bs rfl]
    simp only [releaseBlockers, hkind, beq_iff_eq, ite_false]
  have hcode : ∀ b ∈ aktionBlockers Γ S I.operation R St c, unbridgeableFor "release" b.code = false :=
    fun b hb => hany b.code (by rw [hbs']; exact List.mem_map_of_mem hb)
  have hpart : ∀ part : List Blocker, (∀ b ∈ part, b ∈ aktionBlockers Γ S I.operation R St c) →
      (∀ b ∈ part, unbridgeableFor "release" b.code = true) → part = [] := by
    intro part hsub hbad
    cases part with
    | nil => rfl
    | cons b _ =>
      have := hcode b (hsub b List.mem_cons_self)
      rw [hbad b List.mem_cons_self] at this
      cases this
  have hin : ∀ b, b ∈ (workspaceFindings S).blockers ∨ b ∈ envObserverBlockers S I.operation ∨
      b ∈ (if handoverOperations.contains I.operation then
        (labelPreservationFindings S (checkedLabel I.operation S)).blockers else []) ∨
      b ∈ (if unbridgeableOps.contains I.operation then
        (recipientFindings Γ (actualRecipients Γ S) (checkedLabel I.operation S)).blockers
        else []) → b ∈ aktionBlockers Γ S I.operation R St c := by
    intro b hb
    unfold aktionBlockers
    dsimp only
    simp only [List.mem_append]
    rcases hb with hb | hb | hb | hb
    · exact Or.inl (Or.inl (Or.inl (Or.inl hb)))
    · exact Or.inl (Or.inl (Or.inl (Or.inr hb)))
    · exact Or.inl (Or.inl (Or.inr hb))
    · exact Or.inl (Or.inr hb)
  have hw : (workspaceFindings S).blockers = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inl hb)
    · intro b hb
      unfold workspaceFindings at hb
      split at hb
      · simp [holds] at hb
      · simp only [blocking, List.mem_singleton] at hb
        subst hb
        simp [unbridgeableFor, unbridgeableCodes]
  have hobs : envObserverBlockers S I.operation = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inr (Or.inl hb))
    · intro b hb
      unfold envObserverBlockers at hb
      split at hb
      · simp only [List.mem_singleton] at hb
        subst hb
        simp [unbridgeableFor]
      · cases hb
  have hpres : (if handoverOperations.contains I.operation then
      (labelPreservationFindings S (checkedLabel I.operation S)).blockers else []) = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inr (Or.inr (Or.inl hb)))
    · intro b hb
      split at hb
      · unfold labelPreservationFindings at hb
        split at hb
        · simp [holds] at hb
        · simp only [blocking, List.mem_singleton] at hb
          subst hb
          simp [unbridgeableFor, unbridgeableCodes]
      · cases hb
  have hrec : (if unbridgeableOps.contains I.operation then
      (recipientFindings Γ (actualRecipients Γ S) (checkedLabel I.operation S)).blockers
      else []) = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inr (Or.inr (Or.inr hb)))
    · intro b hb
      split at hb
      · unfold recipientFindings at hb
        dsimp only at hb
        split at hb
        · cases hb
        · simp only [blocking, List.mem_singleton] at hb
          subst hb
          simp [unbridgeableFor]
      · cases hb
  have hchecks : releaseChecks Γ (aktionRelease h auth nonce St) St c = [] :=
    releaseChecks_nil.2 ⟨hh, Int.le_refl _, Int.le_refl _, hn, rfl, ha⟩
  have hblock : releaseBlockers Γ S I.operation (aktionRelease h auth nonce St) St c = [] := by
    simp only [releaseBlockers, aktionRelease, aktionBlockers]
    simp only [aktionRelease] at hchecks
    simp only [(by decide : ("aktionsfreigabe" == "offenlegungsfreigabe") = false),
      Bool.false_eq_true, ite_false, hw, hobs, hpres, hrec, hchecks, List.nil_append]
  have henv' : Γ.environment? S.environment ≠ none := by
    simpa [Option.isSome_iff_ne_none] using henv
  have hmem : I.operation ∈ outputOperations := List.contains_iff_mem.1 hop
  have hdig' : (S.facts.lookup "output_content_digest").isNone = false := by simpa using hdig
  unfold deriveWithRelease
  rw [hblock]
  simp [henv', hmem, hdig', hcls, aktionRelease]

/-- The codes no Offenlegungsfreigabe offer survives (`release_transitions/2`). -/
def offenlegungBeyond (code : String) : Bool :=
  unbridgeableCodes.contains code || offenlegungUnbridgeableCodes.contains code ||
    code == "recipient_not_allowed"

/-- An Offenlegungsfreigabe offer of a release catalog: the release was one,
no code of the denial is beyond it, and the offer repeats call, Ausgabeart
and Ziellabel. -/
theorem release_catalog_offenlegung_mem {Γ : Registry} {c : CatalogCtx} {codes : List String}
    {h art : String} {zl : List String} (hrule : c.rule = "release")
    (hm : Go.offenlegung h art zl ∈ (catalogGos Γ c codes).flatten) :
    c.releaseKind = some "offenlegungsfreigabe" ∧ (∀ code ∈ codes, offenlegungBeyond code = false) ∧
    h = c.callHash.getD "" ∧ art = c.ausgabeart.getD "" ∧ zl = c.ziellabel := by
  simp only [catalogGos, List.mem_flatten, List.mem_map] at hm
  obtain ⟨l, ⟨code, _, rfl⟩, hm⟩ := hm
  rw [List.mem_append] at hm
  rcases hm with hm | hm
  · rw [List.mem_filter] at hm
    obtain ⟨hreg, hkeep⟩ := hm
    simp only [hrule, beq_self_eq_true, Bool.true_and, Bool.not_eq_true', Bool.or_eq_false_iff,
      List.any_eq_false] at hkeep
    obtain ⟨⟨hany, hrna⟩, _⟩ := hkeep
    unfold regularGos at hreg
    simp only [hrule, beq_self_eq_true, ite_true] at hreg
    split at hreg
    · next hk =>
      split at hreg
      · simp at hreg
      · simp only [List.mem_singleton, Go.offenlegung.injEq] at hreg
        obtain ⟨h1, h2, h3⟩ := hreg
        refine ⟨by simpa using hk, fun k hk' => ?_, h1, h2, h3⟩
        have := hany k hk'
        simp only [offenlegungBeyond, Bool.or_eq_false_iff, beq_eq_false_iff_ne, ne_eq]
        refine ⟨by simpa using this, fun he => ?_⟩
        subst he
        simp [hk'] at hrna
    · split at hreg <;> simp at hreg
  · simp [hrule] at hm

/-- No empty promise after a denied Offenlegungsfreigabe (§ 2.8, § 4.9):
the fresh GO the catalog offers is permitted, with a fresh nonce and an
authority holding every needed Befugnis. -/
theorem release_catalog_offenlegung_effective {Γ : Registry} {S : Snapshot} {I : Intent}
    {R : Release} {St : Stand} {bs : List Blocker} {c h art nonce auth : String}
    {zl : List String}
    (hd : deriveWithRelease Γ S I R St c = .decision (.deny bs))
    (hm : Go.offenlegung h art zl ∈
      (catalogGos Γ (releaseCatalogCtx Γ S I.operation R c) (codesOf bs)).flatten)
    (hn : St.consumed.lookup nonce = none) (hak : Γ.AuthoritiesKnown)
    (hb : auth ∈ lockerungsbefugte Γ (checkedLabel "store" S) (actualRecipients Γ S) art) :
    deriveWithRelease Γ S I (offenlegungRelease h art zl auth nonce St) St c =
      .decision (.permit (proposalOf (offenlegungRelease h art zl auth nonce St) St c)) := by
  obtain ⟨henv, _, hkop, hdig, hcls, hbs⟩ := release_decision hd
  obtain ⟨hkind, hany, hh, hart, hzl⟩ := release_catalog_offenlegung_mem rfl hm
  simp only [releaseCatalogCtx, Option.getD_some, Option.some.injEq] at hkind hh hart hzl
  have hstore : I.operation = "store" := by
    rcases hkop with hk | ⟨_, hs⟩
    · exact absurd (hkind.symm.trans hk) (by decide)
    · exact hs
  have hbs' : bs = offenlegungBlockers Γ S R St c := by
    rw [hbs bs rfl]
    simp [releaseBlockers, hkind]
  have hcode : ∀ b ∈ offenlegungBlockers Γ S R St c, offenlegungBeyond b.code = false :=
    fun b hb => hany b.code (by rw [hbs']; exact List.mem_map_of_mem hb)
  have hpart : ∀ part : List Blocker, (∀ b ∈ part, b ∈ offenlegungBlockers Γ S R St c) →
      (∀ b ∈ part, offenlegungBeyond b.code = true) → part = [] := by
    intro part hsub hbad
    cases part with
    | nil => rfl
    | cons b _ =>
      have := hcode b (hsub b List.mem_cons_self)
      rw [hbad b List.mem_cons_self] at this
      cases this
  have hin : ∀ b, b ∈ (workspaceFindings S).blockers ∨
      b ∈ (labelPreservationFindings S (checkedLabel "store" S)).blockers ∨
      b ∈ envObserverBlockers S "store" ∨ b ∈ ziellabelBlockers Γ S R ∨
      b ∈ ziellabelRecipientBlockers Γ S R → b ∈ offenlegungBlockers Γ S R St c := by
    intro b hb
    unfold offenlegungBlockers
    simp only [List.mem_append]
    rcases hb with hb | hb | hb | hb | hb
    · exact Or.inl (Or.inl (Or.inl (Or.inl (Or.inl (Or.inl hb)))))
    · exact Or.inl (Or.inl (Or.inl (Or.inl (Or.inl (Or.inr hb)))))
    · exact Or.inl (Or.inl (Or.inl (Or.inr hb)))
    · exact Or.inl (Or.inl (Or.inr hb))
    · exact Or.inr hb
  have hw : (workspaceFindings S).blockers = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inl hb)
    · intro b hb
      unfold workspaceFindings at hb
      split at hb
      · simp [holds] at hb
      · simp only [blocking, List.mem_singleton] at hb
        subst hb
        simp [offenlegungBeyond, unbridgeableCodes]
  have hpres : (labelPreservationFindings S (checkedLabel "store" S)).blockers = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inr (Or.inl hb))
    · intro b hb
      unfold labelPreservationFindings at hb
      split at hb
      · simp [holds] at hb
      · simp only [blocking, List.mem_singleton] at hb
        subst hb
        simp [offenlegungBeyond, unbridgeableCodes]
  have hobs : envObserverBlockers S "store" = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inr (Or.inr (Or.inl hb)))
    · intro b hb
      unfold envObserverBlockers at hb
      split at hb
      · simp only [List.mem_singleton] at hb
        subst hb
        simp [offenlegungBeyond, offenlegungUnbridgeableCodes]
      · cases hb
  have hzb : ziellabelBlockers Γ S R = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inr (Or.inr (Or.inr (Or.inl hb))))
    · intro b hb
      unfold ziellabelBlockers at hb
      split at hb
      · simp only [List.mem_singleton] at hb; subst hb
        simp [offenlegungBeyond, offenlegungUnbridgeableCodes]
      · split at hb
        · simp only [List.mem_singleton] at hb; subst hb
          simp [offenlegungBeyond, offenlegungUnbridgeableCodes]
        · split at hb
          · simp only [List.mem_singleton] at hb; subst hb
            simp [offenlegungBeyond, offenlegungUnbridgeableCodes]
          · cases hb
  have hzr : ziellabelRecipientBlockers Γ S R = [] := by
    apply hpart
    · intro b hb; exact hin b (Or.inr (Or.inr (Or.inr (Or.inr hb))))
    · intro b hb
      unfold ziellabelRecipientBlockers at hb
      split at hb
      · unfold recipientFindings at hb
        dsimp only at hb
        split at hb
        · cases hb
        · simp only [blocking, List.mem_singleton] at hb
          subst hb
          simp [offenlegungBeyond]
      · cases hb
  -- The offer repeats the presented release's Ausgabeart and Ziellabel.
  have hausg : R.ausgabeart = some art := by
    cases ha : R.ausgabeart with
    | none =>
      simp only [ziellabelBlockers, ha, Option.bind_none] at hzb
      split at hzb
      · cases hzb
      · split at hzb
        · cases hzb
        · simp at hzb
    | some a => simp [ha] at hart; rw [hart]
  have hfresh : ∀ (f : Release → List Blocker), (∀ R₁ R₂ : Release, R₁.ausgabeart = R₂.ausgabeart →
      R₁.ziellabel = R₂.ziellabel → f R₁ = f R₂) →
      f (offenlegungRelease h art zl auth nonce St) = f R :=
    fun f hf => hf _ _ (by simp [offenlegungRelease, hausg]) (by simp [offenlegungRelease, hzl])
  have hzb' : ziellabelBlockers Γ S (offenlegungRelease h art zl auth nonce St) = [] := by
    rw [hfresh (ziellabelBlockers Γ S) (fun R₁ R₂ ha hz => by simp [ziellabelBlockers, ha, hz]),
      hzb]
  have hzr' : ziellabelRecipientBlockers Γ S (offenlegungRelease h art zl auth nonce St) = [] := by
    rw [hfresh (ziellabelRecipientBlockers Γ S)
      (fun R₁ R₂ _ hz => by simp [ziellabelRecipientBlockers, hz]), hzr]
  have ha : auth ∈ Γ.observers := lockerungsbefugte_known hak hb
  have hchecks : releaseChecks Γ (offenlegungRelease h art zl auth nonce St) St c = [] :=
    releaseChecks_nil.2 ⟨hh, Int.le_refl _, Int.le_refl _, hn, rfl, ha⟩
  have hbef : befugnisBlockers Γ S (offenlegungRelease h art zl auth nonce St) = [] := by
    unfold befugnisBlockers
    rw [List.filterMap_eq_nil_iff]
    intro b hx
    simp [offenlegungRelease, mem_lockerungsbefugte hb b hx]
  have hblock : releaseBlockers Γ S I.operation (offenlegungRelease h art zl auth nonce St) St c =
      [] := by
    simp only [releaseBlockers, offenlegungRelease, beq_self_eq_true, ite_true,
      offenlegungBlockers]
    simp only [offenlegungRelease] at hchecks hzb' hbef hzr'
    simp [hw, hpres, hchecks, hobs, hzb', hbef, hzr']
  have henv' : Γ.environment? S.environment ≠ none := by
    simpa [Option.isSome_iff_ne_none] using henv
  have hdig' : (S.facts.lookup "output_content_digest").isNone = false := by simpa using hdig
  unfold deriveWithRelease
  rw [hblock]
  simp [henv', hdig', hcls, offenlegungRelease, hstore, (by decide : "store" ∈ outputOperations)]

/-- `release_catalog_aktion_effective` for the whole catalog of a denied release. -/
theorem release_remedies_aktion_effective {Γ : Registry} {S : Snapshot} {I : Intent}
    {R : Release} {St : Stand} {bs : List Blocker} {c h nonce auth : String}
    (hd : deriveWithRelease Γ S I R St c = .decision (.deny bs))
    (hm : Transition.go (.aktion h) ∈
      (catalog Γ (releaseCatalogCtx Γ S I.operation R c) (bs.map Blocker.finding)).flatten)
    (hn : St.consumed.lookup nonce = none) (ha : auth ∈ Γ.observers) :
    deriveWithRelease Γ S I (aktionRelease h auth nonce St) St c =
      .decision (.permit (proposalOf (aktionRelease h auth nonce St) St c)) :=
  release_catalog_aktion_effective hd (deny_go_mem hm) hn ha

/-- `release_catalog_offenlegung_effective` for the whole catalog of a denied release. -/
theorem release_remedies_offenlegung_effective {Γ : Registry} {S : Snapshot} {I : Intent}
    {R : Release} {St : Stand} {bs : List Blocker} {c h art nonce auth : String}
    {zl : List String}
    (hd : deriveWithRelease Γ S I R St c = .decision (.deny bs))
    (hm : Transition.go (.offenlegung h art zl) ∈
      (catalog Γ (releaseCatalogCtx Γ S I.operation R c) (bs.map Blocker.finding)).flatten)
    (hn : St.consumed.lookup nonce = none) (hak : Γ.AuthoritiesKnown)
    (hb : auth ∈ lockerungsbefugte Γ (checkedLabel "store" S) (actualRecipients Γ S) art) :
    deriveWithRelease Γ S I (offenlegungRelease h art zl auth nonce St) St c =
      .decision (.permit (proposalOf (offenlegungRelease h art zl auth nonce St) St c)) :=
  release_catalog_offenlegung_effective hd (deny_go_mem hm) hn hak hb

end KomkiSpec
