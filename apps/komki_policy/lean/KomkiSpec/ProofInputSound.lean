import KomkiSpec.Bridge

/-!
# What the proof validation guarantees the model

`Model.lean` describes the proof as `verify.ex` sees it after
`validate_proof/1`. `proofError_decodes` makes that precise: every proof
the validation accepts decodes into the model, and each premise has one of
the four kinds of § 2.5. So no accepted proof falls outside the domain the
theorems about `verify` speak about.
-/

namespace KomkiSpec

theorem field_ok {j v : JVal} {k : String} (h : j.get? k = some v) : field j k = .ok v := by
  simp [field, h]; rfl

theorem strAt_ok {j : JVal} {k s : String} (h : j.get? k = some (.str s)) :
    strAt j k = .ok s := by
  simp [strAt, field_ok h]; rfl

theorem premiseError_none {path : String} {p : JVal} (h : premiseError path p = none) :
    ∃ q, decodePremise p = .ok q ∧ q.kind ∈ premiseKinds := by
  unfold premiseError at h
  split at h
  · next kvs =>
    simp only at h
    cases hk : (JVal.obj kvs).get? "kind" with
    | none => simp [hk] at h
    | some vk =>
      cases vk with
      | str kind =>
        simp only [hk] at h
        by_cases hkind : premiseKinds.contains kind = true
        · simp only [hkind, Bool.not_true, Bool.false_eq_true, ite_false] at h
          cases hn : (JVal.obj kvs).get? "name" with
          | none => simp [hn] at h
          | some vn =>
            cases vn with
            | str name =>
              simp only [hn] at h
              rcases hv : (JVal.obj kvs).get? "value" with _ | ⟨_ | b | _ | _ | _ | _ | _⟩ <;>
                first
                | refine ⟨⟨name, kind, b, kvs⟩, ?_, List.contains_iff_mem.1 hkind⟩
                  simp [decodePremise, strAt_ok hn, strAt_ok hk, field_ok hv, asBool, asObj]
                  rfl
                | simp only [hv] at h
                  repeat' split at h
                  all_goals simp_all
            | _ => simp [hn] at h
        · have : kind ∉ premiseKinds := fun hm => hkind (List.contains_iff_mem.2 hm)
          simp [this] at h
      | _ => simp [hk] at h
  · simp at h

theorem mapM_ok {α β : Type} {f : α → Decode β} {P : β → Prop} {xs : List α}
    (h : ∀ x ∈ xs, ∃ y, f x = .ok y ∧ P y) : ∃ ys, xs.mapM f = .ok ys ∧ ∀ y ∈ ys, P y := by
  induction xs with
  | nil => exact ⟨[], rfl, by simp⟩
  | cons x xs ih =>
    obtain ⟨y, hy, hp⟩ := h x List.mem_cons_self
    obtain ⟨ys, hys, hps⟩ := ih fun x hx => h x (List.mem_cons_of_mem _ hx)
    refine ⟨y :: ys, ?_, ?_⟩
    · simp [List.mapM_cons, hy, hys]; rfl
    · simp only [List.mem_cons, forall_eq_or_imp]; exact ⟨hp, hps⟩

theorem premisesError_none {i : Nat} {ps : List JVal} (h : premisesError i ps = none) :
    ∀ p ∈ ps, ∃ q, decodePremise p = .ok q ∧ q.kind ∈ premiseKinds := by
  induction ps generalizing i with
  | nil => simp
  | cons p ps ih =>
    simp only [premisesError, Option.or_eq_none_iff] at h
    intro x hx
    rcases List.mem_cons.1 hx with rfl | hx
    · exact premiseError_none h.1
    · exact ih h.2 x hx

theorem isStr_some {o : Option JVal} (h : isStr o = true) : ∃ s, o = some (.str s) := by
  match o, h with
  | some (.str s), _ => exact ⟨s, rfl⟩

theorem isStrList_some {o : Option JVal} (h : isStrList o = true) :
    ∃ xs, o = some (.arr xs) ∧ ∃ ss, xs.mapM asStr = .ok ss := by
  match o, h with
  | some (.arr xs), h =>
    simp only [isStrList, List.all_eq_true] at h
    obtain ⟨ss, hss, _⟩ := mapM_ok (f := asStr) (P := fun _ => True) (xs := xs) fun x hx => by
      match x, h x hx with
      | .str s, _ => exact ⟨s, rfl, trivial⟩
    exact ⟨xs, rfl, ss, hss⟩

/-- Main theorem: every proof `validate_proof/1` accepts decodes into the
model, each premise with a kind of § 2.5. -/
theorem proofError_decodes {j : JVal} (h : proofError j = none) :
    ∃ P, decodeProof j = .ok P ∧ ∀ p ∈ P.premises, p.kind ∈ premiseKinds := by
  unfold proofError at h
  split at h <;> try (simp at h; done)
  rename_i kvs
  simp only at h
  repeat' (split at h <;> try (simp at h; done))
  rename_i hfind hcl _ ps hps
  rw [List.find?_eq_none] at hfind
  have str : ∀ k ∈ ["rule", "conclusion", "registry_ref", "snapshot_ref", "intent_ref"],
      ∃ s, (JVal.obj kvs).get? k = some (.str s) :=
    fun k hk => isStr_some (by simpa using hfind k hk)
  obtain ⟨r, hr⟩ := str "rule" (by simp)
  obtain ⟨c, hc⟩ := str "conclusion" (by simp)
  obtain ⟨rr, hrr⟩ := str "registry_ref" (by simp)
  obtain ⟨sr, hsr⟩ := str "snapshot_ref" (by simp)
  obtain ⟨ir, hir⟩ := str "intent_ref" (by simp)
  obtain ⟨xs, hxs, ss, hss⟩ := isStrList_some (by simpa using hcl)
  obtain ⟨qs, hqs, hks⟩ := mapM_ok (premisesError_none h)
  refine ⟨⟨r, c, rr, sr, ir, ss, qs⟩, ?_, hks⟩
  simp only [decodeProof, strAt_ok hr, strAt_ok hc, strAt_ok hrr, strAt_ok hsr, strAt_ok hir,
    asStrs, field_ok hxs, field_ok hps, asArr, bind, Except.bind, pure, Except.pure, hss, hqs]

end KomkiSpec
