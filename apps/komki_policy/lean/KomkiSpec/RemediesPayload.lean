import KomkiSpec.CatalogAgree

/-!
# What the payloads of the other continuations promise (CONTRACT.md § 2.8)

`fakt_nachreichen` after a `missing_fact` names a fact the snapshot lacks,
after a `binding_condition_false` a field of that binding's condition;
`registrierte_transformation` offers only registered transformations with
`input_labels ⊆ λ(x)` and `output_labels ⊆ B_W`; `neuer_raum.required_bindings`
is necessary: a room that admits x has every one of them; so is
`required_recipients` for a room in the same environment.
-/

namespace KomkiSpec

theorem allVerdict_unknown {vs : List Verdict} (h : allVerdict vs = .unknown) :
    Verdict.unknown ∈ vs := by
  unfold allVerdict at h
  split at h; · cases h
  split at h; · cases h
  split at h
  · assumption
  · cases h

theorem anyVerdict_unknown {vs : List Verdict} (h : anyVerdict vs = .unknown) :
    Verdict.unknown ∈ vs := by
  unfold anyVerdict at h
  split at h; · cases h
  split at h; · cases h
  split at h
  · assumption
  · cases h

theorem onFact_unknown {facts : Facts} {f : String} {k : JVal → Verdict}
    (hk : ∀ v, k v ≠ .unknown) (h : onFact facts f k = .unknown) : facts f = none := by
  unfold onFact at h
  split at h
  · assumption
  · exact absurd h (hk _)

theorem ofBool_ne_unknown (b : Bool) : ofBool b ≠ .unknown := by cases b <;> simp [ofBool]

mutual
/-- The field `locate` names for an `unknown` verdict is missing. -/
theorem locate_missing {facts : Facts} : ∀ (e : Expr) {f : String},
    eval facts e = .unknown → locate facts .unknown e = some f → facts f = none
  | .tt, _, h, _ => by simp [eval] at h
  | .ff, _, h, _ => by simp [eval] at h
  | .eq _ _, _, h, hl => by
    simp only [locate, Option.some.injEq] at hl; subst hl
    simp only [eval] at h
    exact onFact_unknown (fun _ => ofBool_ne_unknown _) h
  | .member _ _, _, h, hl => by
    simp only [locate, Option.some.injEq] at hl; subst hl
    simp only [eval] at h
    exact onFact_unknown (fun _ => ofBool_ne_unknown _) h
  | .subset _ _, _, h, hl => by
    simp only [locate, Option.some.injEq] at hl; subst hl
    simp only [eval] at h
    exact onFact_unknown (fun v => by cases v <;> simp [ofBool_ne_unknown]) h
  | .atMost _ _, _, h, hl => by
    simp only [locate, Option.some.injEq] at hl; subst hl
    simp only [eval] at h
    exact onFact_unknown (fun v => by cases v <;> simp [ofBool_ne_unknown]) h
  | .all cs, _, _, hl => by simp only [locate] at hl; exact locateFirst_missing cs hl
  | .any cs, _, _, hl => by simp only [locate] at hl; exact locateFirst_missing cs hl

theorem locateFirst_missing {facts : Facts} : ∀ (cs : List Expr) {f : String},
    locateFirst facts .unknown cs = some f → facts f = none
  | [], _, h => by simp [locateFirst] at h
  | c :: cs, _, h => by
    simp only [locateFirst] at h
    split at h
    · next hc =>
      cases hl : locate facts .unknown c with
      | none => rw [hl] at h; exact locateFirst_missing cs (by simpa using h)
      | some g =>
        rw [hl] at h
        simp only [Option.orElse, Option.some.injEq] at h
        subst h
        exact locate_missing c (by simpa using hc) hl
    · exact locateFirst_missing cs h
end

mutual
/-- An `unknown` verdict always has a field to name. -/
theorem locate_some {facts : Facts} : ∀ (e : Expr),
    eval facts e = .unknown → (locate facts .unknown e).isSome
  | .tt, h => by simp [eval] at h
  | .ff, h => by simp [eval] at h
  | .eq _ _, _ | .member _ _, _ | .subset _ _, _ | .atMost _ _, _ => by simp [locate]
  | .all cs, h => by
    simp only [eval] at h
    obtain ⟨c, hc, hu⟩ := List.mem_map.1 (allVerdict_unknown h)
    simp only [locate]
    exact locateFirst_some cs ⟨c, hc, hu⟩
  | .any cs, h => by
    simp only [eval] at h
    obtain ⟨c, hc, hu⟩ := List.mem_map.1 (anyVerdict_unknown h)
    simp only [locate]
    exact locateFirst_some cs ⟨c, hc, hu⟩

theorem locateFirst_some {facts : Facts} : ∀ (cs : List Expr),
    (∃ c ∈ cs, eval facts c = .unknown) → (locateFirst facts .unknown cs).isSome
  | [], ⟨_, hc, _⟩ => absurd hc List.not_mem_nil
  | c :: cs, ⟨d, hd, hu⟩ => by
    simp only [locateFirst]
    split
    · next hc =>
      have hs := locate_some c (by simpa using hc)
      cases hl : locate facts .unknown c with
      | none => rw [hl] at hs; cases hs
      | some _ => simp
    · next hc =>
      rcases List.mem_cons.1 hd with rfl | hd'
      · exact absurd (by simp [hu]) hc
      · exact locateFirst_some cs ⟨d, hd', hu⟩
end

theorem factState_unknown {S : Snapshot} {n : String} (h : factState S n = .unknown) :
    S.fact? n = none := by
  unfold factState at h
  split at h
  · assumption
  all_goals cases h

/-- Every `missing_fact` among the premises names a fact the snapshot lacks,
so its `fakt_nachreichen` asks for exactly that fact. -/
theorem missing_fact_named (Γ : Registry) (S : Snapshot) (rule : String) :
    ∀ e ∈ evidenceOf (premiseFindings Γ S rule), e.code = "missing_fact" →
      ∃ f, e.fact = some f ∧ S.fact? f = none := by
  intro e he hcode
  simp only [evidenceOf, List.mem_flatten, List.mem_map] at he
  obtain ⟨_, ⟨g, hg, rfl⟩, he⟩ := he
  have basis : ∀ n, e ∈ (basisFindings S n).evidence → ∃ f, e.fact = some f ∧ S.fact? f = none := by
    intro n hn
    cases hfs : factState S n
    · simp [basisFindings, hfs, holds] at hn
    · simp only [basisFindings, hfs] at hn
      split at hn <;> simp [blocking] at hn
    · simp only [basisFindings, hfs, lacking, List.mem_singleton] at hn
      subst hn
      exact ⟨n, rfl, factState_unknown hfs⟩
  have cond : ∀ b, e ∈ (conditionFindings Γ S rule b).evidence →
      ∃ f, e.fact = some f ∧ S.fact? f = none := by
    intro b hb
    unfold conditionFindings at hb
    split at hb
    · simp [blocking] at hb
    · next ex _ =>
      cases hv : eval S.fact? ex <;> rw [hv] at hb <;> simp [holds, blocking, lacking] at hb
      subst hb
      cases hl : locate S.fact? .unknown ex with
      | none => have := locate_some ex hv; rw [hl] at this; cases this
      | some f => exact ⟨f, rfl, locate_missing ex hv hl⟩
  have env : e ∈ (envFindings S).evidence → ∃ f, e.fact = some f ∧ S.fact? f = none := by
    intro hn
    unfold envFindings at hn
    split at hn
    · simp [holds] at hn
    · simp only [lacking, List.mem_singleton] at hn
      subst hn
      simp at hcode
  have none : ∀ g : Findings, g.evidence = [] → e ∈ g.evidence →
      ∃ f, e.fact = some f ∧ S.fact? f = none := by
    intro g hg he
    rw [hg] at he
    cases he
  have hq : (quarantineFindings S).evidence = [] := by unfold quarantineFindings; split <;> rfl
  have hw : (workspaceFindings S).evidence = [] := by unfold workspaceFindings; split <;> rfl
  have hi : ∀ l, (labelInclusionFindings S l).evidence = [] := by
    intro l; unfold labelInclusionFindings; split <;> rfl
  have hp : ∀ l, (labelPreservationFindings S l).evidence = [] := by
    intro l; unfold labelPreservationFindings; split <;> rfl
  have hr : ∀ rho l, (recipientFindings Γ rho l).evidence = [] := by
    intro rho l; unfold recipientFindings; dsimp only; split <;> rfl
  unfold premiseFindings at hg
  dsimp only at hg
  split at hg
  · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
    rcases hg with (rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl) | ⟨b, _, rfl⟩
    · exact none _ hq he
    · exact none _ hw he
    · exact basis _ he
    · exact basis _ he
    · exact basis _ he
    · exact env he
    · exact none _ (hi _) he
    · exact none _ (hr _ _) he
    · exact cond _ he
  · split at hg
    · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
      rcases hg with (rfl | rfl | rfl | rfl | rfl) | ⟨b, _, rfl⟩
      · exact none _ hw he
      · exact basis _ he
      · exact basis _ he
      · exact env he
      · exact none _ (hr _ _) he
      · exact cond _ he
    · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
      rcases hg with (rfl | rfl | rfl | rfl | rfl | rfl) | ⟨b, _, rfl⟩
      · exact none _ hw he
      · exact basis _ he
      · exact basis _ he
      · exact env he
      · exact none _ (hp _) he
      · exact none _ (hr _ _) he
      · exact cond _ he

mutual
/-- `locate` names a field of the expression. -/
theorem locate_field {facts : Facts} {k : Verdict} : ∀ (e : Expr) {f : String},
    locate facts k e = some f → f ∈ e.fields
  | .tt, _, h | .ff, _, h => by simp [locate] at h
  | .eq _ _, _, h | .member _ _, _, h | .subset _ _, _, h | .atMost _ _, _, h => by
    simp only [locate, Option.some.injEq] at h
    simp [Expr.fields, h]
  | .all cs, _, h | .any cs, _, h => by
    simp only [locate] at h
    obtain ⟨c, hc, hf⟩ := locateFirst_field cs h
    simp only [Expr.fields, List.mem_flatten, List.mem_map]
    exact ⟨_, ⟨c, hc, rfl⟩, hf⟩

theorem locateFirst_field {facts : Facts} {k : Verdict} : ∀ (cs : List Expr) {f : String},
    locateFirst facts k cs = some f → ∃ c ∈ cs, f ∈ c.fields
  | [], _, h => by simp [locateFirst] at h
  | c :: cs, _, h => by
    simp only [locateFirst] at h
    split at h
    · cases hl : locate facts k c with
      | none =>
        rw [hl] at h
        obtain ⟨d, hd, hf⟩ := locateFirst_field cs (by simpa using h)
        exact ⟨d, List.mem_cons_of_mem _ hd, hf⟩
      | some g =>
        rw [hl] at h
        simp only [Option.orElse, Option.some.injEq] at h
        subst h
        exact ⟨c, List.mem_cons_self, locate_field c hl⟩
    · obtain ⟨d, hd, hf⟩ := locateFirst_field cs h
      exact ⟨d, List.mem_cons_of_mem _ hd, hf⟩
end

/-- Every `binding_condition_false` names, if anything, a field of that
binding's condition, so its `fakt_nachreichen` asks for a fact the rule reads. -/
theorem condition_field_named (Γ : Registry) (S : Snapshot) (rule : String) :
    ∀ b ∈ blockersOf (premiseFindings Γ S rule), b.code = "binding_condition_false" →
      ∀ f, b.condition = some f → ∃ bd j e, b.binding = some bd ∧ Γ.ruleExpr? bd rule = some j ∧
        Expr.ofJVal j = some e ∧ f ∈ e.fields := by
  intro b hb hcode f hf
  simp only [blockersOf, List.mem_flatten, List.mem_map] at hb
  obtain ⟨_, ⟨g, hg, rfl⟩, hb⟩ := hb
  have other : ∀ g : Findings, (∀ x ∈ g.blockers, x.code ≠ "binding_condition_false") →
      b ∈ g.blockers → ∃ bd j e, b.binding = some bd ∧ Γ.ruleExpr? bd rule = some j ∧
        Expr.ofJVal j = some e ∧ f ∈ e.fields :=
    fun g hg hb => absurd hcode (hg b hb)
  have cond : ∀ bd, b ∈ (conditionFindings Γ S rule bd).blockers → ∃ bd j e, b.binding = some bd ∧
      Γ.ruleExpr? bd rule = some j ∧ Expr.ofJVal j = some e ∧ f ∈ e.fields := by
    intro bd hbd
    unfold conditionFindings at hbd
    split at hbd
    · simp only [blocking, List.mem_singleton] at hbd
      subst hbd
      simp at hcode
    · next ex hex =>
      obtain ⟨j, hj, hjx⟩ := Option.bind_eq_some_iff.1 hex
      cases hv : eval S.fact? ex <;> rw [hv] at hbd <;> simp [holds, blocking, lacking] at hbd
      subst hbd
      exact ⟨bd, j, ex, rfl, hj, hjx, locate_field ex hf⟩
  have hq : ∀ x ∈ (quarantineFindings S).blockers, x.code ≠ "binding_condition_false" := by
    unfold quarantineFindings; split <;> simp [blocking, holds]
  have hw : ∀ x ∈ (workspaceFindings S).blockers, x.code ≠ "binding_condition_false" := by
    unfold workspaceFindings; split <;> simp [blocking, holds]
  have hbas : ∀ n, ∀ x ∈ (basisFindings S n).blockers, x.code ≠ "binding_condition_false" := by
    intro n
    unfold basisFindings
    split
    · simp [holds]
    · split <;> simp [blocking]
    · simp [lacking]
  have henv : ∀ x ∈ (envFindings S).blockers, x.code ≠ "binding_condition_false" := by
    unfold envFindings; split <;> simp [lacking, holds]
  have hi : ∀ l, ∀ x ∈ (labelInclusionFindings S l).blockers, x.code ≠ "binding_condition_false" := by
    intro l; unfold labelInclusionFindings; split <;> simp [blocking, holds]
  have hp : ∀ l, ∀ x ∈ (labelPreservationFindings S l).blockers,
      x.code ≠ "binding_condition_false" := by
    intro l; unfold labelPreservationFindings; split <;> simp [blocking, holds]
  have hr : ∀ rho l, ∀ x ∈ (recipientFindings Γ rho l).blockers,
      x.code ≠ "binding_condition_false" := by
    intro rho l; unfold recipientFindings; dsimp only; split <;> simp [blocking, holds]
  unfold premiseFindings at hg
  dsimp only at hg
  split at hg
  · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
    rcases hg with (rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl) | ⟨bd, _, rfl⟩
    · exact other _ hq hb
    · exact other _ hw hb
    · exact other _ (hbas _) hb
    · exact other _ (hbas _) hb
    · exact other _ (hbas _) hb
    · exact other _ henv hb
    · exact other _ (hi _) hb
    · exact other _ (hr _ _) hb
    · exact cond _ hb
  · split at hg
    · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
      rcases hg with (rfl | rfl | rfl | rfl | rfl) | ⟨bd, _, rfl⟩
      · exact other _ hw hb
      · exact other _ (hbas _) hb
      · exact other _ (hbas _) hb
      · exact other _ henv hb
      · exact other _ (hr _ _) hb
      · exact cond _ hb
    · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
      rcases hg with (rfl | rfl | rfl | rfl | rfl | rfl) | ⟨bd, _, rfl⟩
      · exact other _ hw hb
      · exact other _ (hbas _) hb
      · exact other _ (hbas _) hb
      · exact other _ henv hb
      · exact other _ (hp _) hb
      · exact other _ (hr _ _) hb
      · exact cond _ hb

/-- `condition_field_named` for every `deny` of `derive`. -/
theorem derive_condition_named {Γ : Registry} {S : Snapshot} {I : Intent} {bs : List Blocker}
    (hd : derive Γ S I = .decision (.deny bs)) :
    ∀ b ∈ bs, b.code = "binding_condition_false" →
      ∀ f, b.condition = some f → ∃ bd j e, b.binding = some bd ∧
        Γ.ruleExpr? bd I.operation = some j ∧ Expr.ofJVal j = some e ∧ f ∈ e.fields := by
  obtain ⟨_, _, _, hdr⟩ := derive_decision hd
  rw [decideRule_deny hdr]
  exact condition_field_named Γ S I.operation

/-- `missing_fact_named` for every `indeterminate` of `derive`. -/
theorem derive_missing_named {Γ : Registry} {S : Snapshot} {I : Intent} {es : List Evidence}
    (hd : derive Γ S I = .decision (.indeterminate es)) :
    ∀ e ∈ es, e.code = "missing_fact" → ∃ f, e.fact = some f ∧ S.fact? f = none := by
  obtain ⟨_, _, _, hdr⟩ := derive_decision hd
  rw [decideRule_indeterminate hdr]
  exact missing_fact_named Γ S I.operation

theorem mem_of_mem_ordered {t : Transition} {ts : List Transition} (h : t ∈ ordered ts) : t ∈ ts := by
  unfold ordered at h
  obtain ⟨h, _⟩ := List.mem_filter.1 h
  obtain ⟨_, _, h⟩ := List.mem_flatMap.1 h
  exact (List.mem_filter.1 h).1

theorem mem_ite {α : Type} {t : α} {p : Prop} [Decidable p] {a b : List α}
    (h : t ∈ (if p then a else b)) : t ∈ a ∨ t ∈ b := by
  split at h
  · exact Or.inl h
  · exact Or.inr h

/-- Where a continuation of a catalog entry comes from: the transitions of
one finding, a filled-up `neuer_raum`, or an added GO. -/
theorem catalog_mem {Γ : Registry} {c : CatalogCtx} {fs : List Finding} {e : List Transition}
    {t : Transition} (he : e ∈ catalog Γ c fs) (ht : t ∈ e) :
    t = neuerRaum c ∨ (∃ g, t = .go g) ∨ ∃ f ∈ fs,
      t ∈ (if c.rule == "release" then releaseTransitions c f else regularTransitions Γ c f) := by
  unfold catalog at he
  dsimp only at he
  rcases mem_ite he with he | he
  · simp only [List.mem_map, Prod.exists] at he
    obtain ⟨_, ts, ⟨f, hf, hfe⟩, rfl⟩ := he
    simp only [Prod.mk.injEq] at hfe
    obtain ⟨rfl, rfl⟩ := hfe
    exact Or.inr (Or.inr ⟨f, hf, mem_of_mem_ordered ht⟩)
  · simp only [List.mem_map, Prod.exists] at he
    obtain ⟨_, ts, ⟨f, hf, hfe⟩, rfl⟩ := he
    simp only [Prod.mk.injEq] at hfe
    obtain ⟨rfl, rfl⟩ := hfe
    rcases mem_ite ht with ht | ht
    · exact Or.inl (List.mem_singleton.1 ht)
    · rcases List.mem_append.1 ht with hk | hadd
      · exact Or.inr (Or.inr ⟨f, hf, mem_of_mem_ordered (List.mem_filter.1 hk).1⟩)
      · rcases mem_ite hadd with hadd | hadd
        · exact Or.inr (Or.inl ⟨_, List.mem_singleton.1 hadd⟩)
        · cases hadd

theorem mem_callGo {c : CatalogCtx} {t : Transition} (h : t ∈ callGo c) : ∃ g, t = .go g := by
  unfold callGo at h
  split at h
  · split at h
    · exact ⟨_, List.mem_singleton.1 h⟩
    · cases h
  · cases h

/-- What `regularTransitions` contains: `neuer_raum` with the context's
payload, a GO, a `fakt_nachreichen`, or a matching transformation. -/
theorem regular_shape {Γ : Registry} {c : CatalogCtx} {f : Finding} {t : Transition}
    (h : t ∈ regularTransitions Γ c f) :
    t = neuerRaum c ∨ (∃ g, t = .go g) ∨ (∃ fs, t = .fakt fs) ∨ t ∈ matchingTransformations Γ c := by
  unfold regularTransitions at h
  rcases mem_ite h with h | h
  · exact Or.inr (Or.inl ⟨_, List.mem_singleton.1 h⟩)
  rcases mem_ite h with h | h
  · exact Or.inl (List.mem_singleton.1 h)
  rcases mem_ite h with h | h
  · rcases List.mem_append.1 h with h | h
    · simp only [List.mem_cons, List.not_mem_nil, or_false] at h
      rcases h with rfl | rfl
      · exact Or.inr (Or.inr (Or.inl ⟨_, rfl⟩))
      · exact Or.inl rfl
    · exact Or.inr (Or.inl (mem_callGo h))
  rcases mem_ite h with h | h
  · rcases List.mem_append.1 h with h | h
    · exact Or.inr (Or.inr (Or.inr h))
    · exact Or.inl (List.mem_singleton.1 h)
  rcases mem_ite h with h | h
  · rcases List.mem_append.1 h with h | h
    · exact Or.inl (List.mem_singleton.1 h)
    · exact Or.inr (Or.inl (mem_callGo h))
  rcases mem_ite h with h | h
  · simp only [List.mem_cons, List.not_mem_nil, or_false] at h
    rcases h with rfl | rfl
    · exact Or.inr (Or.inr (Or.inl ⟨_, rfl⟩))
    · exact Or.inl rfl
  · cases h

theorem release_shape {c : CatalogCtx} {f : Finding} {t : Transition}
    (h : t ∈ releaseTransitions c f) : t = .neuerRaum [] c.rho ∨ ∃ g, t = .go g := by
  unfold releaseTransitions at h
  rcases mem_ite h with h | h <;> rcases mem_ite h with h | h
  all_goals first
    | exact Or.inl (List.mem_singleton.1 h)
    | exact Or.inr ⟨_, List.mem_singleton.1 h⟩

/-- `registrierte_transformation` offers registered transformations only,
with `input_labels ⊆ λ(x)` and `output_labels` within the checked label. -/
theorem catalog_transformation {Γ : Registry} {c : CatalogCtx} {fs : List Finding}
    {e : List Transition} {id : String} {out : List String}
    (he : e ∈ catalog Γ c fs) (ht : Transition.transformation id out ∈ e) :
    ∃ input, (id, input, out) ∈ Γ.transformations ∧ (∀ l ∈ input, l ∈ c.objectLabels) ∧
      ∀ l ∈ out, l ∈ c.checked := by
  rcases catalog_mem he ht with h | ⟨_, h⟩ | ⟨f, _, hf⟩
  · cases h
  · cases h
  have hm : Transition.transformation id out ∈ matchingTransformations Γ c := by
    rcases mem_ite hf with hf | hf
    · rcases release_shape hf with h | ⟨_, h⟩ <;> cases h
    · rcases regular_shape hf with h | ⟨_, h⟩ | ⟨_, h⟩ | h
      · cases h
      · cases h
      · cases h
      · exact h
  unfold matchingTransformations at hm
  obtain ⟨⟨id', input, out'⟩, hfil, heq⟩ := List.mem_map.1 hm
  cases heq
  obtain ⟨hreg, hok⟩ := List.mem_filter.1 hfil
  simp only [Bool.and_eq_true, List.all_eq_true, List.contains_iff_mem] at hok
  exact ⟨input, hreg, hok.1, hok.2⟩

/-- `catalog_transformation` for a decision of `derive`: inputs within λ(x),
outputs within the checked label, so an object carrying the output labels
passes label inclusion against that label (§ 4.3). -/
theorem remedies_transformation {Γ : Registry} {S : Snapshot} {rule h : String}
    {fs : List Finding} {e : List Transition} {id : String} {out : List String}
    (he : e ∈ catalog Γ (normalCatalogCtx Γ S rule h) fs)
    (ht : Transition.transformation id out ∈ e) :
    (∃ input, (id, input, out) ∈ Γ.transformations ∧ ∀ l ∈ input, l ∈ S.objectLabels) ∧
      labelInclusionFindings { S with objectLabels := out } (checkedLabel rule S) = holds := by
  obtain ⟨input, hreg, hin, hout⟩ := catalog_transformation he ht
  refine ⟨⟨input, hreg, fun l hl => ?_⟩, ?_⟩
  · have := hin l hl
    simp only [normalCatalogCtx] at this
    split at this
    · exact this
    · cases this
  · have hsub : subsetOf out (checkedLabel rule S) = true := by
      simp only [subsetOf, List.all_eq_true, List.contains_iff_mem]
      exact hout
    simp [labelInclusionFindings, hsub]

/-- Outside the release branch every `neuer_raum` carries the payload of
§ 2.8: `required_bindings` from `required_bindings_for/1`, ρ_Γ(c) as
`required_recipients`. -/
theorem catalog_neuerRaum {Γ : Registry} {c : CatalogCtx} {fs : List Finding}
    {e : List Transition} {rb rr : List String} (hrel : c.rule ≠ "release")
    (he : e ∈ catalog Γ c fs) (ht : Transition.neuerRaum rb rr ∈ e) :
    rb = requiredBindingsFor c ∧ rr = c.rho := by
  rcases catalog_mem he ht with h | ⟨_, h⟩ | ⟨f, _, hf⟩
  · simp only [neuerRaum, Transition.neuerRaum.injEq] at h
    exact h
  · cases h
  have hr : (c.rule == "release") = false := by simpa using hrel
  rw [hr] at hf
  simp only [Bool.false_eq_true, ite_false] at hf
  rcases regular_shape hf with h | ⟨_, h⟩ | ⟨_, h⟩ | h
  · simp only [neuerRaum, Transition.neuerRaum.injEq] at h
    exact h
  · cases h
  · cases h
  · unfold matchingTransformations at h
    obtain ⟨⟨_, _, _⟩, _, h⟩ := List.mem_map.1 h
    cases h

/-- `neuer_raum.required_bindings` is necessary (§ 2.8, B.7): every room in
which `derive` admits x under the same Γ has all of them. -/
theorem neuer_raum_necessary {Γ : Registry} {S S' : Snapshot} {I' : Intent} {P : Proof}
    {fs : List Finding} {h : String} {e : List Transition} {rb rr : List String}
    (wf : Γ.WellFormed) (hS' : S'.WellFormed)
    (he : e ∈ catalog Γ (normalCatalogCtx Γ S "admit" h) fs) (ht : Transition.neuerRaum rb rr ∈ e)
    (hx : S'.objectLabels = S.objectLabels) (hI : I'.operation = "admit")
    (hp : derive Γ S' I' = .decision (.permit P)) : ∀ b ∈ rb, b ∈ S'.workspaceBindings := by
  obtain ⟨hrb, _⟩ := catalog_neuerRaum (by simp [normalCatalogCtx]) he ht
  intro b hb
  rw [hrb] at hb
  simp only [requiredBindingsFor, normalCatalogCtx, beq_self_eq_true, ite_true] at hb
  have hd := (derive_sound wf hS' hp).1.labels
  rw [hI] at hd
  simp only [LabelDuty, ite_true] at hd
  exact hd b (hx ▸ mem_sortStrings.1 hb)

/-- `neuer_raum.required_recipients` is necessary against the current
environment (§ 2.8): a room in the same environment in which `derive`
permits the rule admits every one of them under its checked label. -/
theorem neuer_raum_recipients_necessary {Γ : Registry} {S S' : Snapshot} {I' : Intent}
    {P : Proof} {fs : List Finding} {h : String} {e : List Transition} {rb rr : List String}
    (wf : Γ.WellFormed) (hS' : S'.WellFormed)
    (he : e ∈ catalog Γ (normalCatalogCtx Γ S I'.operation h) fs)
    (ht : Transition.neuerRaum rb rr ∈ e) (henv : S'.environment = S.environment)
    (hp : derive Γ S' I' = .decision (.permit P)) :
    ∀ o ∈ rr, recipients Γ.rules (· ∈ checkedLabel I'.operation S') o := by
  obtain ⟨hr, _, _, _⟩ := derive_decision hp
  obtain ⟨_, hrr⟩ := catalog_neuerRaum (by simpa [normalCatalogCtx] using rule_not_release hr) he ht
  obtain ⟨env, hgot, hrec⟩ := (derive_sound wf hS' hp).1.recipients
  intro o ho
  rw [hrr] at ho
  simp only [normalCatalogCtx, actualRecipients, ← henv, hgot, Option.getD_some] at ho
  exact hrec o (mem_sortStrings.1 ho)

end KomkiSpec
