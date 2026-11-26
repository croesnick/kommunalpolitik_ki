import KomkiSpec.ReleaseSound

/-!
# The catalog promises nothing the release branch refuses

`catalog_aktion_effective` and `catalog_offenlegung_effective`: when a
denial's catalog offers a GO for the exact call (§ 2.8), a release built
from that offer, with a fresh nonce, a window around the stand's time and a
fitting authority, is permitted by the release branch (§ 4.6, § 4.9). The
counterexample #631 broke exactly this statement for the
Offenlegungsfreigabe.
-/

namespace KomkiSpec

/-! ## Which code a premise's blocker carries -/

def codesOf (bs : List Blocker) : List String := bs.map (·.code)

theorem code_mem {fs : List Findings} {f : Findings} (hf : f ∈ fs) {b : Blocker}
    (hb : b ∈ f.blockers) : b.code ∈ codesOf (blockersOf fs) := by
  simp only [codesOf, blockersOf, List.mem_map, List.mem_flatten]
  exact ⟨b, ⟨f.blockers, ⟨f, hf, rfl⟩, hb⟩, rfl⟩

theorem workspace_code {S : Snapshot} (h : (workspaceFindings S).blockers ≠ []) :
    ∃ b ∈ (workspaceFindings S).blockers, b.code = "workspace_invalid" := by
  unfold workspaceFindings at h ⊢
  cases hv : S.workspaceValid <;> simp_all [blocking, holds]

theorem preservation_code {S : Snapshot} {checked : List String}
    (h : (labelPreservationFindings S checked).blockers ≠ []) :
    ∃ b ∈ (labelPreservationFindings S checked).blockers, b.code = "label_not_preserved" := by
  unfold labelPreservationFindings at h ⊢
  split <;> simp_all [blocking, holds]

theorem recipient_code {Γ : Registry} {rho checked : List String}
    (h : (recipientFindings Γ rho checked).blockers ≠ []) :
    ∃ b ∈ (recipientFindings Γ rho checked).blockers, b.code = "recipient_not_allowed" := by
  have : (recipientFindings Γ rho checked).blockers = [] ∨
      ∃ b ∈ (recipientFindings Γ rho checked).blockers, b.code = "recipient_not_allowed" := by
    unfold recipientFindings
    dsimp only
    split
    · exact Or.inl rfl
    · exact Or.inr ⟨_, List.mem_singleton_self _, rfl⟩
  exact this.resolve_left h

theorem workspace_mem {Γ : Registry} {S : Snapshot} {rule : String}
    (hr : proofRules.contains rule = true) : workspaceFindings S ∈ premiseFindings Γ S rule := by
  rcases rule_cases hr with rfl | rfl | rfl | rfl <;> simp [premiseFindings]

theorem recipient_mem {Γ : Registry} {S : Snapshot} {rule : String}
    (hr : proofRules.contains rule = true) :
    recipientFindings Γ (actualRecipients Γ S) (checkedLabel rule S) ∈
      premiseFindings Γ S rule := by
  rcases rule_cases hr with rfl | rfl | rfl | rfl <;> simp [premiseFindings]

theorem preservation_mem {Γ : Registry} {S : Snapshot} {rule : String}
    (hh : handoverOperations.contains rule = true) :
    labelPreservationFindings S (checkedLabel rule S) ∈ premiseFindings Γ S rule := by
  have : rule = "transfer" ∨ rule = "store" := by simpa [handoverOperations] using hh
  rcases this with rfl | rfl <;> simp [premiseFindings]

/-- A blocker of a premise in the list puts its code among the denial's codes. -/
theorem code_of {fs : List Findings} {f : Findings} (hf : f ∈ fs) {code : String}
    (h : ∃ b ∈ f.blockers, b.code = code) : code ∈ codesOf (blockersOf fs) := by
  obtain ⟨b, hb, rfl⟩ := h
  exact code_mem hf hb

/-! ## What an offer tells -/

theorem catalog_aktion_mem {Γ : Registry} {c : CatalogCtx} {codes : List String} {h : String}
    (hrule : c.rule ≠ "release") (hm : Go.aktion h ∈ (catalogGos Γ c codes).flatten) :
    (∀ code ∈ codes, unbridgeableFor c.rule code = false) ∧ observersUnproven c = false ∧
    c.callHash = some h ∧ outputOperations.contains c.rule = true := by
  simp only [catalogGos, List.mem_flatten, List.mem_map] at hm
  obtain ⟨l, ⟨code, hcode, rfl⟩, hm⟩ := hm
  rw [List.mem_append] at hm
  rcases hm with hm | hm
  · rw [List.mem_filter] at hm
    obtain ⟨hreg, hkeep⟩ := hm
    simp only [Bool.not_eq_true', Bool.or_eq_false_iff, List.any_eq_false] at hkeep
    obtain ⟨⟨hany, hobs⟩, _⟩ := hkeep
    have hrel : (c.rule == "release") = false := by simpa using hrule
    unfold regularGos at hreg
    simp only [hrel, Bool.false_eq_true, ite_false] at hreg
    split at hreg
    · simp at hreg
    · split at hreg
      · next hout =>
        split at hreg
        · next h' hcall =>
          simp only [List.mem_singleton, Go.aktion.injEq] at hreg
          subst hreg
          simp only [Bool.and_eq_true] at hout
          exact ⟨fun k hk => by simpa using hany k hk, hobs, hcall, hout.1⟩
        · simp at hreg
      · simp at hreg
  · split at hm <;> simp_all

theorem decideRule_deny {Γ : Registry} {S : Snapshot} {I : Intent} {bs : List Blocker}
    (h : decideRule Γ S I = .deny bs) : bs = blockersOf (premiseFindings Γ S I.operation) := by
  unfold decideRule at h
  dsimp only at h
  split at h
  · cases h; rfl
  · split at h <;> cases h

/-- The release a person grants for an Aktionsfreigabe offer. -/
def aktionRelease (callHash authority nonce : String) (St : Stand) : Release :=
  { releaseId := "go", kind := "aktionsfreigabe", callHash, scope := St.scope, authority,
    validFrom := St.asOf, validUntil := St.asOf, nonce }

/-- No empty promise (§ 2.8): an Aktionsfreigabe the catalog offers on a
denial of the normal branch is permitted by the release branch, at any
stand, with a fresh nonce and any observer as the granting authority. -/
theorem catalog_aktion_effective {Γ : Registry} {S : Snapshot} {I : Intent} {bs : List Blocker}
    {c h : String} {St : Stand} {nonce auth : String}
    (hd : derive Γ S I = .decision (.deny bs))
    (hm : Go.aktion h ∈ (catalogGos Γ (normalCatalogCtx Γ S I.operation c) (codesOf bs)).flatten)
    (hn : St.consumed.lookup nonce = none) (ha : auth ∈ Γ.observers) :
    deriveWithRelease Γ S I (aktionRelease h auth nonce St) St c =
      .decision (.permit (proposalOf (aktionRelease h auth nonce St) St c)) := by
  obtain ⟨hr, henv, hout, hdr⟩ := derive_decision hd
  have hbs := decideRule_deny hdr
  have hrel : (normalCatalogCtx Γ S I.operation c).rule ≠ "release" := by
    intro he
    simp only [normalCatalogCtx] at he
    rw [he] at hr
    exact absurd hr (by decide)
  obtain ⟨hany, hobs, hcall, houtop⟩ := catalog_aktion_mem hrel hm
  simp only [normalCatalogCtx] at hany hobs hcall houtop
  have hh : h = c := by rw [houtop] at hcall; simp at hcall; exact hcall.symm
  have hna : I.operation ≠ "admit" := by
    intro he; rw [he] at houtop; exact absurd houtop (by decide)
  obtain ⟨hdig, hcls⟩ := hout hna
  have hblocked : ∀ f ∈ premiseFindings Γ S I.operation, ∀ code,
      (∃ b ∈ f.blockers, b.code = code) → unbridgeableFor I.operation code = false :=
    fun f hf code hc => hany code (hbs ▸ code_of hf hc)
  have hw : (workspaceFindings S).blockers = [] := by
    apply Classical.byContradiction; intro hne
    have := hblocked _ (workspace_mem hr) _ (workspace_code hne)
    simp [unbridgeableFor, unbridgeableCodes] at this
  have hobs' : envObserverBlockers S I.operation = [] := by
    unfold envObserverBlockers
    unfold observersUnproven at hobs
    split
    · next hc =>
      simp only [Bool.and_eq_true, bne_iff_ne, ne_eq] at hc
      have hs : I.operation = "store" := by simpa [unbridgeableOps] using hc.1
      simp [hs, hc.2] at hobs
    · rfl
  have hpres : (if handoverOperations.contains I.operation then
      (labelPreservationFindings S (checkedLabel I.operation S)).blockers else []) = [] := by
    split
    · next hho =>
      apply Classical.byContradiction; intro hne
      have := hblocked _ (preservation_mem hho) _ (preservation_code hne)
      simp [unbridgeableFor, unbridgeableCodes] at this
    · rfl
  have hrec : (if unbridgeableOps.contains I.operation then
      (recipientFindings Γ (actualRecipients Γ S) (checkedLabel I.operation S)).blockers
      else []) = [] := by
    split
    · next hst =>
      apply Classical.byContradiction; intro hne
      have := hblocked _ (recipient_mem hr) _ (recipient_code hne)
      simp [unbridgeableFor] at this
      exact this.2 (List.contains_iff_mem.1 hst)
    · rfl
  have hchecks : releaseChecks Γ (aktionRelease h auth nonce St) St c = [] :=
    releaseChecks_nil.2 ⟨hh, Int.le_refl _, Int.le_refl _, hn, rfl, ha⟩
  have hblock : releaseBlockers Γ S I.operation (aktionRelease h auth nonce St) St c = [] := by
    simp only [releaseBlockers, aktionRelease, aktionBlockers]
    simp only [aktionRelease] at hchecks
    have hpres' : I.operation ∈ handoverOperations →
        (labelPreservationFindings S (checkedLabel I.operation S)).blockers = [] := by
      simpa using hpres
    have hrec' : I.operation ∈ unbridgeableOps →
        (recipientFindings Γ (actualRecipients Γ S) (checkedLabel I.operation S)).blockers = [] := by
      simpa using hrec
    simp only [(by decide : ("aktionsfreigabe" == "offenlegungsfreigabe") = false),
      Bool.false_eq_true, ite_false, hw, hobs', hchecks, List.nil_append, List.append_nil,
      List.append_eq_nil_iff]
    exact ⟨by split <;> simp_all, by split <;> simp_all⟩
  have henv' : Γ.environment? S.environment ≠ none := by
    simpa [Option.isSome_iff_ne_none] using henv
  have hmem : I.operation ∈ outputOperations := List.contains_iff_mem.1 houtop
  have hdig' : (S.facts.lookup "output_content_digest").isNone = false := by
    simpa [Snapshot.fact?] using hdig
  unfold deriveWithRelease
  rw [hblock]
  simp [henv', hmem, hdig', hcls, aktionRelease]

theorem befugteFor_mem {Γ : Registry} {art b a : String} (h : a ∈ befugteFor Γ art b) :
    befugnis Γ b a art = true := by
  unfold befugteFor at h
  unfold befugnis
  split at h
  · simp at h
  · next bd _ =>
    simp only [List.mem_filterMap, Prod.exists] at h
    obtain ⟨a', r, o, hm, hc⟩ := h
    by_cases hro : r = "readers" ∧ o = art
    · have : a' = a := by simpa [hro.1, hro.2] using hc
      subst this
      exact List.any_eq_true.2 ⟨(a', r, o), hm, by simp [hro.1, hro.2]⟩
    · exfalso
      have : ¬((r == "readers" && o == art) = true) := by simpa using hro
      simp [this] at hc

theorem befugteFor_known {Γ : Registry} (hak : Γ.AuthoritiesKnown) {art b a : String}
    (h : a ∈ befugteFor Γ art b) : a ∈ Γ.observers := by
  unfold befugteFor at h
  split at h
  · simp at h
  · next bd hbd =>
    simp only [List.mem_filterMap, Prod.exists] at h
    obtain ⟨a', r, o, hm, hc⟩ := h
    have ha' : a' = a := by
      by_cases hro : (r == "readers" && o == art) = true
      · simpa [hro] using hc
      · simp [hro] at hc
    subst ha'
    exact hak b bd hbd (a', r, o) hm

/-- An authority among the lockerungsbefugte is an observer. -/
theorem lockerungsbefugte_known {Γ : Registry} (hak : Γ.AuthoritiesKnown)
    {checked rho : List String} {art a : String} (h : a ∈ lockerungsbefugte Γ checked rho art) :
    a ∈ Γ.observers := by
  unfold lockerungsbefugte at h
  split at h
  · simp at h
  · simp only [sortDedup, List.mem_eraseDups, mem_sortStrings, List.mem_filter] at h
    exact befugteFor_known hak h.1

/-- An authority among the lockerungsbefugte holds the Befugnis on every
lockerungsbedürftige binding. -/
theorem mem_lockerungsbefugte {Γ : Registry} {checked rho : List String} {art a : String}
    (h : a ∈ lockerungsbefugte Γ checked rho art) :
    ∀ b ∈ lockerungsbeduerftig Γ checked rho, befugnis Γ b a art = true := by
  unfold lockerungsbefugte at h
  split at h
  · simp at h
  · next b bs hlb =>
    rw [hlb]
    simp only [sortDedup, List.mem_eraseDups, mem_sortStrings, List.mem_filter, List.all_eq_true,
      List.contains_iff_mem] at h
    obtain ⟨ha, hall⟩ := h
    intro x hx
    rcases List.mem_cons.1 hx with rfl | hx
    · exact befugteFor_mem ha
    · exact befugteFor_mem (hall x hx)

theorem catalog_offenlegung_mem {Γ : Registry} {c : CatalogCtx} {codes : List String}
    {h art : String} {zl : List String} (hrule : c.rule ≠ "release")
    (hm : Go.offenlegung h art zl ∈ (catalogGos Γ c codes).flatten) :
    c.rule = "store" ∧ offenlegungOfferable Γ c = true ∧
    (∀ code ∈ codes, unbridgeableCodes.contains code = false) ∧ observersUnproven c = false ∧
    h = c.callHash.getD "" ∧ art = c.ausgabeart.getD "" ∧ zl = c.ziellabel := by
  simp only [catalogGos, List.mem_flatten, List.mem_map] at hm
  obtain ⟨l, ⟨code, _, rfl⟩, hm⟩ := hm
  rw [List.mem_append] at hm
  have hrel : (c.rule == "release") = false := by simpa using hrule
  rcases hm with hm | hm
  · rw [List.mem_filter] at hm
    have hreg := hm.1
    unfold regularGos at hreg
    simp only [hrel, Bool.false_eq_true, ite_false] at hreg
    split at hreg
    · simp at hreg
    · split at hreg
      · split at hreg <;> simp at hreg
      · simp at hreg
  · split at hm
    · next hinst =>
      simp only [List.mem_singleton, Go.offenlegung.injEq] at hm
      obtain ⟨rfl, rfl, rfl⟩ := hm
      simp only [Bool.and_eq_true, beq_iff_eq, bne_iff_ne, ne_eq, Bool.not_eq_true',
        Bool.or_eq_false_iff, List.any_eq_false] at hinst
      obtain ⟨⟨⟨⟨hstore, _⟩, _⟩, hoff⟩, ⟨hcodes, _⟩, hobs⟩ := hinst.1
      refine ⟨hstore, hoff, fun k hk => ?_, hobs, rfl, rfl, rfl⟩
      have := hcodes k hk
      simp only [Bool.or_eq_true, not_or] at this
      simpa using this.1
    · simp at hm

/-- The release a person grants for an Offenlegungsfreigabe offer. -/
def offenlegungRelease (callHash art : String) (ziellabel : List String)
    (authority nonce : String) (St : Stand) : Release :=
  { releaseId := "go", kind := "offenlegungsfreigabe", callHash, scope := St.scope, authority,
    validFrom := St.asOf, validUntil := St.asOf, nonce, ausgabeart := some art, ziellabel }

/-- No empty promise for the Offenlegungsfreigabe (§ 2.8, § 4.9, #631): an
offer on a store denial of the normal branch is permitted, with a fresh
nonce and an authority holding every needed Befugnis. -/
theorem catalog_offenlegung_effective {Γ : Registry} {S : Snapshot} {I : Intent}
    {bs : List Blocker} {c h art : String} {zl : List String} {St : Stand} {nonce auth : String}
    (hd : derive Γ S I = .decision (.deny bs))
    (hm : Go.offenlegung h art zl ∈
      (catalogGos Γ (normalCatalogCtx Γ S I.operation c) (codesOf bs)).flatten)
    (hn : St.consumed.lookup nonce = none) (hak : Γ.AuthoritiesKnown)
    (hb : auth ∈ lockerungsbefugte Γ (checkedLabel I.operation S) (actualRecipients Γ S) art) :
    deriveWithRelease Γ S I (offenlegungRelease h art zl auth nonce St) St c =
      .decision (.permit (proposalOf (offenlegungRelease h art zl auth nonce St) St c)) := by
  obtain ⟨hr, henv, hout, hdr⟩ := derive_decision hd
  have hbs := decideRule_deny hdr
  have hrel : (normalCatalogCtx Γ S I.operation c).rule ≠ "release" := by
    intro he
    simp only [normalCatalogCtx] at he
    rw [he] at hr
    exact absurd hr (by decide)
  obtain ⟨hstore, hoff, hcodes, hobs, hh, hart, hzl⟩ := catalog_offenlegung_mem hrel hm
  simp only [normalCatalogCtx] at hstore hoff hobs hh hart hzl hb
  obtain ⟨hdig, hcls⟩ := hout (by rw [hstore]; decide)
  have ha : auth ∈ Γ.observers := lockerungsbefugte_known hak hb
  have hop : outputOperations.contains I.operation = true := by rw [hstore]; decide
  rw [hop] at hh
  simp only [ite_true, Option.getD_some] at hh
  cases hza : zielAusgabeart S.environment with
  | none => simp [offenlegungOfferable, hza] at hoff
  | some art0 =>
  simp only [hza, Option.getD_some, Option.bind_some] at hart hzl
  subst hart hh
  simp only [offenlegungOfferable, hza, hop, ite_true, Option.bind_some, Bool.and_eq_true,
    Bool.not_eq_true', List.isEmpty_eq_false_iff] at hoff
  obtain ⟨⟨⟨hne, hreg⟩, hcover⟩, _⟩ := hoff
  have hziel : ausgabeartZiellabel art = some zl := by
    cases hz : ausgabeartZiellabel art with
    | none => simp [hz] at hne
    | some zl' => simp [hz] at hzl; rw [hzl]
  rw [← hzl] at hreg hcover
  have hck : checkedLabel "store" S = checkedLabel I.operation S := by rw [hstore]
  have hblocked : ∀ f ∈ premiseFindings Γ S I.operation, ∀ code,
      (∃ b ∈ f.blockers, b.code = code) → unbridgeableCodes.contains code = false :=
    fun f hf code hc => hcodes code (hbs ▸ code_of hf hc)
  have hw : (workspaceFindings S).blockers = [] := by
    apply Classical.byContradiction; intro hne
    have := hblocked _ (workspace_mem hr) _ (workspace_code hne)
    simp [unbridgeableCodes] at this
  have hpres : (labelPreservationFindings S (checkedLabel "store" S)).blockers = [] := by
    apply Classical.byContradiction; intro hne
    have hho : handoverOperations.contains I.operation = true := by rw [hstore]; decide
    rw [hck] at hne
    have := hblocked _ (preservation_mem hho) _ (preservation_code hne)
    simp [unbridgeableCodes] at this
  have hchecks : releaseChecks Γ (offenlegungRelease h art zl auth nonce St) St h = [] :=
    releaseChecks_nil.2 ⟨rfl, Int.le_refl _, Int.le_refl _, hn, rfl, ha⟩
  have hfs : factState S "environment_observers_complete" = .true := by
    unfold observersUnproven at hobs
    simp only [hstore] at hobs
    cases hf : factState S "environment_observers_complete" <;> simp_all
  have hobs' : envObserverBlockers S "store" = [] := by simp [envObserverBlockers, hfs]
  have hzb : ziellabelBlockers Γ S (offenlegungRelease h art zl auth nonce St) = [] := by
    have hany : (zl.any fun b => (Γ.binding? b).isNone) = false := by
      simp only [List.any_eq_false, Option.isNone_iff_eq_none]
      intro b hb hnone
      have := List.all_eq_true.1 hreg b hb
      simp [hnone] at this
    simp [ziellabelBlockers, offenlegungRelease, hza, hany, hziel]
  have hbef : befugnisBlockers Γ S (offenlegungRelease h art zl auth nonce St) = [] := by
    unfold befugnisBlockers
    rw [List.filterMap_eq_nil_iff]
    intro b hx
    rw [hck] at hx
    simp [offenlegungRelease, mem_lockerungsbefugte hb b hx]
  have hzr : ziellabelRecipientBlockers Γ S (offenlegungRelease h art zl auth nonce St) = [] := by
    unfold ziellabelRecipientBlockers
    simp only [offenlegungRelease, hreg, ite_true]
    unfold recipientFindings
    dsimp only
    rw [List.isEmpty_iff.1 hcover]
    rfl
  have henv' : Γ.environment? S.environment ≠ none := by
    simpa [Option.isSome_iff_ne_none] using henv
  have hmem : I.operation ∈ outputOperations := List.contains_iff_mem.1 hop
  have hdig' : (S.facts.lookup "output_content_digest").isNone = false := by
    simpa [Snapshot.fact?] using hdig
  have hblock : releaseBlockers Γ S I.operation (offenlegungRelease h art zl auth nonce St) St h =
      [] := by
    simp only [releaseBlockers, offenlegungRelease, beq_self_eq_true, ite_true,
      offenlegungBlockers]
    simp only [offenlegungRelease] at hchecks hzb hbef hzr
    simp [hw, hpres, hchecks, hobs', hzb, hbef, hzr]
  unfold deriveWithRelease
  rw [hblock]
  simp [henv', hdig', hcls, offenlegungRelease, hstore, (by decide : "store" ∈ outputOperations)]

end KomkiSpec
