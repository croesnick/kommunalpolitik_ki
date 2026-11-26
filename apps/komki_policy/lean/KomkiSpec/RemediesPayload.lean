import KomkiSpec.CatalogAgree

/-!
# What the payloads of the other continuations promise (CONTRACT.md § 2.8)

`fakt_nachreichen` asks for the field its finding names (`entry_fakt`), and
that field is what § 2.8 says: the missing fact, the observer flag that is
not `true`, the base fact that is `false`, or a field of the false binding
condition, absent only when that condition is false whatever the facts
(`BlockerNamed`, `EvidenceNamed`). `registrierte_transformation` lists
exactly the registered transformations with `input_labels ⊆ λ(x)` and
`output_labels ⊆ B_W`, in the registry's order. `neuer_raum.required_bindings`
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

/-- The premises `premiseFindings` lists, by kind. -/
theorem premise_cases {Γ : Registry} {S : Snapshot} {rule : String} {g : Findings}
    (hg : g ∈ premiseFindings Γ S rule) :
    g = quarantineFindings S ∨ g = workspaceFindings S ∨ (∃ n ∈ baseFacts rule, g = basisFindings S n) ∨
      g = envFindings S ∨ (∃ l, g = labelInclusionFindings S l) ∨
      (∃ l, g = labelPreservationFindings S l) ∨ (∃ rho l, g = recipientFindings Γ rho l) ∨
      ∃ b, g = conditionFindings Γ S rule b := by
  unfold premiseFindings at hg
  dsimp only at hg
  split at hg
  · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
    rcases hg with (rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl) | ⟨b, _, rfl⟩
    all_goals first
      | exact Or.inl rfl
      | exact Or.inr (Or.inl rfl)
      | exact Or.inr (Or.inr (Or.inl ⟨_, by simp_all [baseFacts, admitBaseFacts], rfl⟩))
      | exact Or.inr (Or.inr (Or.inr (Or.inl rfl)))
      | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, rfl⟩))))
      | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, rfl⟩)))))
      | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, _, rfl⟩))))))
      | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr ⟨_, rfl⟩))))))
  · split at hg
    · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
      rcases hg with (rfl | rfl | rfl | rfl | rfl) | ⟨b, _, rfl⟩
      all_goals first
        | exact Or.inl rfl
        | exact Or.inr (Or.inl rfl)
        | exact Or.inr (Or.inr (Or.inl ⟨_, by simp_all [baseFacts, outputBaseFacts], rfl⟩))
        | exact Or.inr (Or.inr (Or.inr (Or.inl rfl)))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, rfl⟩))))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, rfl⟩)))))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, _, rfl⟩))))))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr ⟨_, rfl⟩))))))
    · simp only [List.mem_append, List.mem_cons, List.mem_map, List.not_mem_nil, or_false] at hg
      rcases hg with (rfl | rfl | rfl | rfl | rfl | rfl) | ⟨b, _, rfl⟩
      all_goals first
        | exact Or.inl rfl
        | exact Or.inr (Or.inl rfl)
        | exact Or.inr (Or.inr (Or.inl ⟨_, by simp_all [baseFacts, outputBaseFacts], rfl⟩))
        | exact Or.inr (Or.inr (Or.inr (Or.inl rfl)))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, rfl⟩))))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, rfl⟩)))))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inl ⟨_, _, rfl⟩))))))
        | exact Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr (Or.inr ⟨_, rfl⟩))))))

/-- What a piece of missing evidence names: a `missing_fact` a fact the
snapshot lacks, `recipients_unproven` the observer flag that is not `true`. -/
def EvidenceNamed (S : Snapshot) (e : Evidence) : Prop :=
  (e.code = "missing_fact" → ∃ f, e.fact = some f ∧ S.fact? f = none) ∧
  (e.code = "recipients_unproven" → e.fact = some "environment_observers_complete" ∧
    factState S "environment_observers_complete" ≠ .true)

theorem evidence_named (Γ : Registry) (S : Snapshot) (rule : String) :
    ∀ e ∈ evidenceOf (premiseFindings Γ S rule), EvidenceNamed S e := by
  intro e he
  simp only [evidenceOf, List.mem_flatten, List.mem_map] at he
  obtain ⟨_, ⟨g, hg, rfl⟩, he⟩ := he
  have none : ∀ g : Findings, g.evidence = [] → e ∈ g.evidence → EvidenceNamed S e := by
    intro g hg he
    rw [hg] at he
    cases he
  rcases premise_cases hg with rfl | rfl | ⟨n, _, rfl⟩ | rfl | ⟨l, rfl⟩ | ⟨l, rfl⟩ | ⟨rho, l, rfl⟩ |
    ⟨b, rfl⟩
  · exact none _ (by unfold quarantineFindings; split <;> rfl) he
  · exact none _ (by unfold workspaceFindings; split <;> rfl) he
  · cases hfs : factState S n
    · simp [basisFindings, hfs, holds] at he
    · simp only [basisFindings, hfs] at he
      split at he <;> simp [blocking] at he
    · simp only [basisFindings, hfs, lacking, List.mem_singleton] at he
      subst he
      exact ⟨fun _ => ⟨n, rfl, factState_unknown hfs⟩, fun h => by simp at h⟩
  · unfold envFindings at he
    split at he
    · simp [holds] at he
    · next hne =>
      simp only [lacking, List.mem_singleton] at he
      subst he
      exact ⟨fun h => by simp at h, fun _ => ⟨rfl, by simpa using hne⟩⟩
  · exact none _ (by unfold labelInclusionFindings; split <;> rfl) he
  · exact none _ (by unfold labelPreservationFindings; split <;> rfl) he
  · exact none _ (by unfold recipientFindings; dsimp only; split <;> rfl) he
  · unfold conditionFindings at he
    split at he
    · simp [blocking] at he
    · next ex _ =>
      cases hv : eval S.fact? ex <;> rw [hv] at he <;> simp [holds, blocking, lacking] at he
      subst he
      refine ⟨fun _ => ?_, fun h => by simp at h⟩
      cases hl : locate S.fact? .unknown ex with
      | none => have := locate_some ex hv; rw [hl] at this; cases this
      | some f => exact ⟨f, rfl, locate_missing ex hv hl⟩

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

theorem allVerdict_false {vs : List Verdict} (h : allVerdict vs = .false) : Verdict.false ∈ vs := by
  unfold allVerdict at h
  split at h; · cases h
  split at h
  · assumption
  · split at h <;> cases h

theorem anyVerdict_false {vs : List Verdict} (h : anyVerdict vs = .false) :
    ∀ v ∈ vs, v = .false := by
  unfold anyVerdict at h
  intro v hv
  split at h
  · next hn => rw [hn] at hv; cases hv
  split at h; · cases h
  split at h; · cases h
  next ht hu =>
  cases v
  · exact absurd hv ht
  · rfl
  · exact absurd hv hu

theorem locateFirst_none {facts : Facts} {k : Verdict} :
    ∀ {cs : List Expr}, locateFirst facts k cs = none →
      ∀ c ∈ cs, eval facts c = k → locate facts k c = none
  | [], _, _, hc, _ => absurd hc List.not_mem_nil
  | c :: cs, h, d, hd, hk => by
    simp only [locateFirst] at h
    split at h
    · cases hl : locate facts k c with
      | some _ => rw [hl] at h; simp [Option.orElse] at h
      | none =>
        rw [hl] at h
        simp only [Option.orElse] at h
        rcases List.mem_cons.1 hd with rfl | hd'
        · exact hl
        · exact locateFirst_none h d hd' hk
    · next hc =>
      rcases List.mem_cons.1 hd with rfl | hd'
      · exact absurd (by simp [hk]) hc
      · exact locateFirst_none h d hd' hk

/-- When `locate` finds no field for a `false` verdict, the expression is
`false` whatever the facts: no field is to blame (§ 2.8, `condition: null`). -/
theorem locate_none_false {facts : Facts} : ∀ (e : Expr),
    eval facts e = .false → locate facts .false e = none → ∀ g, eval g e = .false
  | .tt, h, _ => by simp [eval] at h
  | .ff, _, _ => fun _ => by simp [eval]
  | .eq _ _, _, hl | .member _ _, _, hl | .subset _ _, _, hl | .atMost _ _, _, hl => by
    simp [locate] at hl
  | .all cs, h, hl => by
    simp only [eval] at h
    simp only [locate] at hl
    obtain ⟨c, hc, hf⟩ := List.mem_map.1 (allVerdict_false h)
    intro g
    have hcg := locate_none_false c hf (locateFirst_none hl c hc hf) g
    simp only [eval]
    unfold allVerdict
    have hne : cs.map (eval g) ≠ [] := by simpa using List.ne_nil_of_mem hc
    have hmem : Verdict.false ∈ cs.map (eval g) := List.mem_map.2 ⟨c, hc, hcg⟩
    simp [hne, hmem]
  | .any cs, h, hl => by
    simp only [eval] at h
    simp only [locate] at hl
    have hall := anyVerdict_false h
    intro g
    have hcg : ∀ c ∈ cs, eval g c = .false := fun c hc =>
      have hf := hall _ (List.mem_map.2 ⟨c, hc, rfl⟩)
      locate_none_false c hf (locateFirst_none hl c hc hf) g
    simp only [eval]
    unfold anyVerdict
    split; · rfl
    split
    · next ht =>
      obtain ⟨c, hc, hv⟩ := List.mem_map.1 ht
      rw [hcg c hc] at hv; cases hv
    split
    · next hu =>
      obtain ⟨c, hc, hv⟩ := List.mem_map.1 hu
      rw [hcg c hc] at hv; cases hv
    · rfl

/-- What a blocker names: `basis_right_false` a base fact of the rule that is
`false`, `audit_path_not_ready` exactly `audit_path_ready`; `binding_condition_false` a field of the
binding's condition, or nothing when that condition is `false` whatever the
facts. `fakt_nachreichen` asks for exactly this (§ 2.8). -/
def BlockerNamed (Γ : Registry) (S : Snapshot) (rule : String) (b : Blocker) : Prop :=
  (b.code = "basis_right_false" → ∃ n, b.condition = some n ∧ n ∈ baseFacts rule ∧
    n ≠ "audit_path_ready" ∧ factState S n = .false) ∧
  (b.code = "audit_path_not_ready" → b.condition = some "audit_path_ready" ∧
    factState S "audit_path_ready" = .false) ∧
  (b.code = "binding_condition_false" → ∃ bd j e, b.binding = some bd ∧
    Γ.ruleExpr? bd rule = some j ∧ Expr.ofJVal j = some e ∧ eval S.fact? e = .false ∧
    match b.condition with
    | some f => f ∈ e.fields
    | none => ∀ g, eval g e = .false)

theorem blocker_named (Γ : Registry) (S : Snapshot) (rule : String) :
    ∀ b ∈ blockersOf (premiseFindings Γ S rule), BlockerNamed Γ S rule b := by
  intro b hb
  simp only [blockersOf, List.mem_flatten, List.mem_map] at hb
  obtain ⟨_, ⟨g, hg, rfl⟩, hb⟩ := hb
  have other : ∀ g : Findings, (∀ x ∈ g.blockers, x.code ≠ "basis_right_false" ∧
      x.code ≠ "audit_path_not_ready" ∧ x.code ≠ "binding_condition_false") →
      b ∈ g.blockers → BlockerNamed Γ S rule b := by
    intro g hg hb
    obtain ⟨h1, h2, h3⟩ := hg b hb
    exact ⟨fun h => (h1 h).elim, fun h => (h2 h).elim, fun h => (h3 h).elim⟩
  rcases premise_cases hg with rfl | rfl | ⟨n, hn, rfl⟩ | rfl | ⟨l, rfl⟩ | ⟨l, rfl⟩ |
    ⟨rho, l, rfl⟩ | ⟨bd, rfl⟩
  · exact other _ (by unfold quarantineFindings; split <;> simp [blocking, holds]) hb
  · exact other _ (by unfold workspaceFindings; split <;> simp [blocking, holds]) hb
  · cases hfs : factState S n
    · simp [basisFindings, hfs, holds] at hb
    · simp only [basisFindings, hfs] at hb
      split at hb
      · next ha =>
        simp only [blocking, List.mem_singleton] at hb
        subst hb
        have : n = "audit_path_ready" := by simpa using ha
        subst this
        exact ⟨fun h => by simp at h, fun _ => ⟨rfl, hfs⟩, fun h => by simp at h⟩
      · next ha =>
        simp only [blocking, List.mem_singleton] at hb
        subst hb
        exact ⟨fun _ => ⟨n, rfl, hn, by simpa using ha, hfs⟩, fun h => by simp at h,
          fun h => by simp at h⟩
    · simp [basisFindings, hfs, lacking] at hb
  · exact other _ (by unfold envFindings; split <;> simp [lacking, holds]) hb
  · exact other _ (by unfold labelInclusionFindings; split <;> simp [blocking, holds]) hb
  · exact other _ (by unfold labelPreservationFindings; split <;> simp [blocking, holds]) hb
  · exact other _ (by unfold recipientFindings; dsimp only; split <;> simp [blocking, holds]) hb
  · unfold conditionFindings at hb
    split at hb
    · simp only [blocking, List.mem_singleton] at hb
      subst hb
      exact ⟨fun h => by simp at h, fun h => by simp at h, fun h => by simp at h⟩
    · next ex hex =>
      obtain ⟨j, hj, hjx⟩ := Option.bind_eq_some_iff.1 hex
      cases hv : eval S.fact? ex <;> rw [hv] at hb <;> simp [holds, blocking, lacking] at hb
      subst hb
      refine ⟨fun h => by simp at h, fun h => by simp at h, fun _ => ⟨bd, j, ex, rfl, hj, hjx, hv, ?_⟩⟩
      dsimp only
      cases hl : locate S.fact? .false ex with
      | some f => exact locate_field ex hl
      | none => exact locate_none_false ex hv hl

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

theorem mem_ite_cond {α : Type} {t : α} {p : Prop} [Decidable p] {a b : List α}
    (h : t ∈ (if p then a else b)) : (p ∧ t ∈ a) ∨ (¬p ∧ t ∈ b) := by
  split at h
  · next hp => exact Or.inl ⟨hp, h⟩
  · next hp => exact Or.inr ⟨hp, h⟩

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

/-- Every `neuer_raum` carries the payload of § 2.8: `required_bindings`
from `required_bindings_for/1`, ρ_Γ(c) as `required_recipients`. -/
theorem catalog_neuerRaum {Γ : Registry} {c : CatalogCtx} {fs : List Finding}
    {e : List Transition} {rb rr : List String}
    (he : e ∈ catalog Γ c fs) (ht : Transition.neuerRaum rb rr ∈ e) :
    rb = requiredBindingsFor c ∧ rr = c.rho := by
  rcases catalog_mem he ht with h | ⟨_, h⟩ | ⟨f, _, hf⟩
  · simp only [neuerRaum, Transition.neuerRaum.injEq] at h
    exact h
  · cases h
  rcases mem_ite_cond hf with ⟨hrel, hf⟩ | ⟨_, hf⟩
  · rcases release_shape hf with h | ⟨_, h⟩
    · simp only [Transition.neuerRaum.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      refine ⟨?_, rfl⟩
      have ha : (c.rule == "admit") = false := by
        simp only [beq_iff_eq] at hrel
        simp [hrel]
      simp [requiredBindingsFor, ha]
    · cases h
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
  obtain ⟨hrb, _⟩ := catalog_neuerRaum he ht
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
  obtain ⟨_, hrr⟩ := catalog_neuerRaum he ht
  obtain ⟨env, hgot, hrec⟩ := (derive_sound wf hS' hp).1.recipients
  intro o ho
  rw [hrr] at ho
  simp only [normalCatalogCtx, actualRecipients, ← henv, hgot, Option.getD_some] at ho
  exact hrec o (mem_sortStrings.1 ho)

/-! ## The entry of one finding -/

/-- The catalog entry of finding `f`, as `catalog` builds it for `fs`. -/
def catalogEntry (Γ : Registry) (c : CatalogCtx) (fs : List Finding) (f : Finding) :
    List Transition :=
  let codes := fs.map (·.code)
  let stripAktion0 := codes.any (unbridgeableFor c.rule) || observersUnproven c
  let stripOff := codes.any (fun k => unbridgeableCodes.contains k ||
      offenlegungUnbridgeableCodes.contains k) ||
    (c.rule == "release" && codes.contains "recipient_not_allowed") || observersUnproven c
  let instead := c.rule == "store" && codes.contains "recipient_not_allowed" &&
    c.rule != "release" && offenlegungOfferable Γ c && !stripOff
  let ts := ordered (if c.rule == "release" then releaseTransitions c f else regularTransitions Γ c f)
  if !(stripAktion0 || stripOff || instead) then ts
  else
    let kept := ts.filter fun
      | .go (.aktion _) => !(stripAktion0 || instead)
      | .go (.offenlegung _ _ _) => !stripOff
      | _ => true
    let added := kept ++ (if instead && callGoCodes.contains f.code then
      [.go (.offenlegung (c.callHash.getD "") (c.ausgabeart.getD "") c.ziellabel)] else [])
    if added.isEmpty then [neuerRaum c] else added

/-- `catalog` is the entry of each finding, in the findings' order. -/
theorem catalog_eq_map (Γ : Registry) (c : CatalogCtx) (fs : List Finding) :
    catalog Γ c fs = fs.map (catalogEntry Γ c fs) := by
  unfold catalog catalogEntry
  dsimp only
  split <;>
  · simp only [List.map_map]
    apply List.map_congr_left
    intro f _
    rfl

theorem entry_mem {Γ : Registry} {c : CatalogCtx} {fs : List Finding} {f : Finding}
    {t : Transition} (h : t ∈ catalogEntry Γ c fs f) :
    t = neuerRaum c ∨ (∃ g, t = .go g) ∨
      t ∈ ordered (if c.rule == "release" then releaseTransitions c f else regularTransitions Γ c f) := by
  unfold catalogEntry at h
  dsimp only at h
  rcases mem_ite h with h | h
  · exact Or.inr (Or.inr h)
  rcases mem_ite h with h | h
  · exact Or.inl (List.mem_singleton.1 h)
  rcases List.mem_append.1 h with hk | hadd
  · exact Or.inr (Or.inr (List.mem_filter.1 hk).1)
  rcases mem_ite hadd with h | h
  · exact Or.inr (Or.inl ⟨_, List.mem_singleton.1 h⟩)
  · cases h

theorem fakt_ordered_ne {xs : List String} {ts : List Transition}
    (h : Transition.fakt xs ∈ ordered ts) : xs ≠ [] := by
  unfold ordered at h
  have hk := (List.mem_filter.1 h).2
  intro hx
  subst hx
  simp at hk

theorem fakt_of_transitions {Γ : Registry} {c : CatalogCtx} {f : Finding} {xs : List String}
    (h : Transition.fakt xs ∈
      (if c.rule == "release" then releaseTransitions c f else regularTransitions Γ c f)) :
    xs = (if f.evidence then f.fact else f.condition).toList := by
  rcases mem_ite h with h | h
  · rcases release_shape h with h | ⟨_, h⟩ <;> cases h
  unfold regularTransitions at h
  rcases mem_ite_cond h with ⟨_, h⟩ | ⟨_, h⟩
  · cases List.mem_singleton.1 h
  rcases mem_ite_cond h with ⟨_, h⟩ | ⟨_, h⟩
  · cases List.mem_singleton.1 h
  rcases mem_ite_cond h with ⟨hc, h⟩ | ⟨_, h⟩
  · rcases List.mem_append.1 h with h | h
    · simp only [List.mem_cons, Transition.fakt.injEq, List.not_mem_nil, or_false] at h
      rcases h with rfl | h
      · simp only [Bool.and_eq_true, Bool.not_eq_true'] at hc
        simp [hc.1]
      · cases h
    · obtain ⟨_, h⟩ := mem_callGo h; cases h
  rcases mem_ite_cond h with ⟨_, h⟩ | ⟨_, h⟩
  · rcases List.mem_append.1 h with h | h
    · unfold matchingTransformations at h
      obtain ⟨⟨_, _, _⟩, _, h⟩ := List.mem_map.1 h
      cases h
    · cases List.mem_singleton.1 h
  rcases mem_ite_cond h with ⟨_, h⟩ | ⟨_, h⟩
  · rcases List.mem_append.1 h with h | h
    · cases List.mem_singleton.1 h
    · obtain ⟨_, h⟩ := mem_callGo h; cases h
  rcases mem_ite_cond h with ⟨hc, h⟩ | ⟨_, h⟩
  · simp only [List.mem_cons, Transition.fakt.injEq, List.not_mem_nil, or_false] at h
    rcases h with rfl | h
    · simp only [Bool.and_eq_true] at hc
      simp [hc.1]
    · cases h
  · cases h

/-- `fakt_nachreichen` asks for the finding's own field: its `condition` for
a blocker, its `fact` for missing evidence, and never for nothing. -/
theorem entry_fakt {Γ : Registry} {c : CatalogCtx} {fs : List Finding} {f : Finding}
    {xs : List String} (h : Transition.fakt xs ∈ catalogEntry Γ c fs f) :
    ∃ n, xs = [n] ∧ (if f.evidence then f.fact else f.condition) = some n := by
  rcases entry_mem h with h | ⟨_, h⟩ | h
  · cases h
  · cases h
  have hne := fakt_ordered_ne h
  have hxs := fakt_of_transitions (mem_of_mem_ordered h)
  revert hne hxs
  cases (if f.evidence then f.fact else f.condition) with
  | none => intro hne hxs; exact absurd hxs (by simpa using hne)
  | some n => intro _ hxs; exact ⟨n, by simpa using hxs, rfl⟩

/-- Every blocker of a `deny` names what its `fakt_nachreichen` asks for (`BlockerNamed`). -/
theorem derive_blockers_named {Γ : Registry} {S : Snapshot} {I : Intent} {bs : List Blocker}
    (hd : derive Γ S I = .decision (.deny bs)) : ∀ b ∈ bs, BlockerNamed Γ S I.operation b := by
  obtain ⟨_, _, _, hdr⟩ := derive_decision hd
  rw [decideRule_deny hdr]
  exact blocker_named Γ S I.operation

/-- Every piece of missing evidence of an `indeterminate` names what its
`fakt_nachreichen` asks for (`EvidenceNamed`). -/
theorem derive_evidence_named {Γ : Registry} {S : Snapshot} {I : Intent} {es : List Evidence}
    (hd : derive Γ S I = .decision (.indeterminate es)) : ∀ e ∈ es, EvidenceNamed S e := by
  obtain ⟨_, _, _, hdr⟩ := derive_decision hd
  rw [decideRule_indeterminate hdr]
  exact evidence_named Γ S I.operation

/-- The `fakt_nachreichen` of a blocker asks for exactly the field it names. -/
theorem derive_fakt_deny {Γ : Registry} {S : Snapshot} {I : Intent} {bs : List Blocker}
    {h : String} {b : Blocker} {xs : List String} (hd : derive Γ S I = .decision (.deny bs))
    (hb : b ∈ bs) (hx : Transition.fakt xs ∈
      catalogEntry Γ (normalCatalogCtx Γ S I.operation h) (bs.map Blocker.finding) b.finding) :
    ∃ n, xs = [n] ∧ b.condition = some n ∧ BlockerNamed Γ S I.operation b := by
  obtain ⟨n, hn, hc⟩ := entry_fakt hx
  exact ⟨n, hn, by simpa [Blocker.finding] using hc, derive_blockers_named hd b hb⟩

/-- The `fakt_nachreichen` of missing evidence asks for exactly the fact it names. -/
theorem derive_fakt_indeterminate {Γ : Registry} {S : Snapshot} {I : Intent} {es : List Evidence}
    {h : String} {e : Evidence} {xs : List String}
    (hd : derive Γ S I = .decision (.indeterminate es)) (he : e ∈ es)
    (hx : Transition.fakt xs ∈
      catalogEntry Γ (normalCatalogCtx Γ S I.operation h) (es.map Evidence.finding) e.finding) :
    ∃ n, xs = [n] ∧ e.fact = some n ∧ EvidenceNamed S e := by
  obtain ⟨n, hn, hc⟩ := entry_fakt hx
  exact ⟨n, hn, by simpa [Evidence.finding] using hc, derive_evidence_named hd e he⟩

theorem matching_rank {Γ : Registry} {c : CatalogCtx} :
    ∀ t ∈ matchingTransformations Γ c, t.rank = 1 := by
  intro t ht
  unfold matchingTransformations at ht
  obtain ⟨⟨_, _, _⟩, _, rfl⟩ := List.mem_map.1 ht
  rfl

theorem ordered_transformations (Γ : Registry) (c : CatalogCtx) :
    ordered (matchingTransformations Γ c ++ [neuerRaum c]) =
      matchingTransformations Γ c ++ [neuerRaum c] := by
  have hm := @matching_rank Γ c
  have nil : ∀ r, r ≠ 1 → (matchingTransformations Γ c).filter (·.rank == r) = [] := by
    intro r hr
    apply List.filter_eq_nil_iff.2
    intro t ht
    simp [hm t ht, Ne.symm hr]
  have self : (matchingTransformations Γ c).filter (·.rank == 1) = matchingTransformations Γ c :=
    List.filter_eq_self.2 fun t ht => by simp [hm t ht]
  unfold ordered
  simp only [List.filter_append, List.flatMap_cons, List.flatMap_nil, nil 0 (by decide),
    nil 2 (by decide), nil 3 (by decide), nil 4 (by decide), self]
  simp only [neuerRaum, Transition.rank, List.filter_cons, List.filter_nil]
  simp only [beq_iff_eq, List.nil_append, List.append_nil]
  simp only [reduceCtorEq, ite_false, ite_true, List.filter_nil, List.nil_append,
    List.filter_cons, List.append_assoc]
  simp
  intro t ht
  unfold matchingTransformations at ht
  obtain ⟨⟨_, _, _⟩, _, rfl⟩ := List.mem_map.1 ht
  rfl

/-- `registrierte_transformation` lists every matching registered
transformation, in the registry's order (sorted by id), and nothing else:
the entry's transformations are exactly `matchingTransformations`. -/
theorem entry_transformations {Γ : Registry} {c : CatalogCtx} {fs : List Finding} {f : Finding}
    (hcode : f.code = "label_not_included") (hrel : c.rule ≠ "release") :
    (catalogEntry Γ c fs f).filter (·.rank == 1) = matchingTransformations Γ c := by
  have hreg : regularTransitions Γ c f = matchingTransformations Γ c ++ [neuerRaum c] := by
    unfold regularTransitions
    simp [hcode, unbridgeableCodes]
  have hr : (c.rule == "release") = false := by simpa using hrel
  have hm := @matching_rank Γ c
  have hrank : (matchingTransformations Γ c ++ [neuerRaum c]).filter (·.rank == 1) =
      matchingTransformations Γ c := by
    rw [List.filter_append, List.filter_eq_self.2 fun t ht => by simp [hm t ht]]
    simp [neuerRaum, Transition.rank]
  unfold catalogEntry
  dsimp only
  rw [hr]
  simp only [Bool.false_eq_true, ite_false, hreg, ordered_transformations]
  split
  · exact hrank
  · have hkeep : ∀ p : Transition → Bool, (∀ t, (∀ g, t ≠ .go g) → p t = true) →
        (matchingTransformations Γ c ++ [neuerRaum c]).filter p =
          matchingTransformations Γ c ++ [neuerRaum c] := by
      intro p hp
      apply List.filter_eq_self.2
      intro t ht
      apply hp
      intro g hg
      subst hg
      rcases List.mem_append.1 ht with ht | ht
      · unfold matchingTransformations at ht
        obtain ⟨⟨_, _, _⟩, _, h⟩ := List.mem_map.1 ht
        cases h
      · cases List.mem_singleton.1 ht
    rw [hkeep _ (fun t ht => by cases t with | go g => exact absurd rfl (ht g) | _ => rfl)]
    have hnc : callGoCodes.contains f.code = false := by simp [hcode, callGoCodes]
    simp only [hnc, Bool.and_false, Bool.false_eq_true, ite_false, List.append_nil]
    split
    · next he => simp at he
    · exact hrank

/-- For a `deny` of `derive`: the entry of `label_not_included` offers every
registered transformation with `input_labels ⊆ λ(x)` and `output_labels ⊆ B_W`. -/
theorem derive_transformations_listed {Γ : Registry} {S : Snapshot} {I : Intent}
    {bs : List Blocker} {h : String} {b : Blocker} (hd : derive Γ S I = .decision (.deny bs))
    (hcode : b.code = "label_not_included") :
    (catalogEntry Γ (normalCatalogCtx Γ S I.operation h) (bs.map Blocker.finding) b.finding).filter
      (·.rank == 1) = matchingTransformations Γ (normalCatalogCtx Γ S I.operation h) := by
  obtain ⟨hr, _, _, _⟩ := derive_decision hd
  exact entry_transformations (by simpa [Blocker.finding] using hcode)
    (by simpa [normalCatalogCtx] using rule_not_release hr)

end KomkiSpec
