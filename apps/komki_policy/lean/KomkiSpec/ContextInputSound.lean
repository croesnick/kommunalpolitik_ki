import KomkiSpec.ProofInputSound
import KomkiSpec.ContextInput

/-!
# What `Context`'s input validation guarantees the model

`snapshotError_validated`: every snapshot `validate_snapshot/2` accepts
decodes into the model and lies in the domain the theorems assume
(`Snapshot.validated`, hence `Snapshot.WellFormed` by
`Snapshot.validated_sound`). With the differential test holding
`snapshotError` to `context.ex`, the domain is no longer only checked case
by case.
-/

namespace KomkiSpec

theorem strings_mapM {xs : List JVal} {ss : List String} (h : strings? xs = some ss) :
    xs.mapM asStr = .ok ss := by
  induction xs generalizing ss with
  | nil => simp [strings?] at h; subst h; rfl
  | cons x xs ih =>
    cases x <;> simp [strings?, List.mapM_cons] at h
    obtain ⟨rs, hrs, h⟩ := Option.bind_eq_some_iff.1 h
    cases h
    simp only [List.mapM_cons, asStr, ih hrs]
    rfl

theorem lookup_isSome {β : Type} {l : List (String × β)} {x : String}
    (h : x ∈ l.map (·.1)) : (l.lookup x).isSome := by
  induction l with
  | nil => simp at h
  | cons p l ih =>
    obtain ⟨k, v⟩ := p
    by_cases hk : x = k
    · subst hk; simp [List.lookup]
    · simp only [List.map_cons, List.mem_cons, hk, false_or] at h
      have : (x == k) = false := by simpa using hk
      simp [List.lookup, this, ih h]

theorem refsError_none {o : Option JVal} {against : List String} {path code : String}
    (h : refsError o against path code = none) :
    ∃ xs ss, o = some (.arr xs) ∧ xs.mapM asStr = .ok ss ∧ sortStrings ss = ss ∧
      sortDedup ss = ss ∧ ss.all against.contains = true := by
  unfold refsError at h
  split at h
  · next xs =>
    split at h
    · next ss hss =>
      split at h
      · simp at h
      · next hsort =>
        split at h
        · simp at h
        · next hall =>
          have hs : sortStrings ss = ss ∧ sortDedup ss = ss := by simpa using hsort
          have ha : ss.all against.contains = true := by simpa using hall
          exact ⟨xs, ss, rfl, strings_mapM hss, hs.1, hs.2, ha⟩
    · simp at h
  · simp at h

theorem kebabJ_some {o : Option JVal} (h : kebabJ o = true) : ∃ s, o = some (.str s) := by
  match o, h with
  | some (.str s), _ => exact ⟨s, rfl⟩

theorem strIn_some {xs : List String} {o : Option JVal} (h : strIn xs o = true) :
    ∃ s, o = some (.str s) ∧ s ∈ xs := by
  match o, h with
  | some (.str s), h => exact ⟨s, rfl, by simpa [strIn] using h⟩

theorem workspaceError_none {Γ : Registry} {o : Option JVal} (h : workspaceError Γ o = none) :
    ∃ w, o = some w ∧ (∃ id, w.get? "workspace_id" = some (.str id)) ∧
      (∃ b, w.get? "valid" = some (.bool b)) ∧
      (∃ xs ss, w.get? "bindings" = some (.arr xs) ∧ xs.mapM asStr = .ok ss ∧
        sortStrings ss = ss ∧ sortDedup ss = ss ∧ ss.all (bindingIds Γ).contains = true) ∧
      ∃ e, w.get? "environment" = some (.str e) ∧ e ∈ Γ.environments.map (·.1) := by
  unfold workspaceError at h
  split at h <;> try (simp at h; done)
  rename_i kvs
  simp only at h
  repeat' (split at h <;> try (simp at h; done))
  rename_i hid _ b hv _ henv
  obtain ⟨id, hid⟩ := kebabJ_some (by simpa using hid)
  obtain ⟨e, he, hem⟩ := strIn_some (by simpa using henv)
  obtain ⟨xs, ss, hxs, hss, h1, h2, h3⟩ := refsError_none (by simpa using h)
  exact ⟨_, rfl, ⟨id, hid⟩, ⟨b, hv⟩, ⟨xs, ss, hxs, hss, h1, h2, h3⟩, e, he, hem⟩

theorem objectError_none {Γ : Registry} {o : Option JVal} (h : objectError Γ o = none) :
    ∃ ob, o = some ob ∧ (∃ id, ob.get? "object_id" = some (.str id)) ∧
      (∃ v, ob.get? "version" = some (.str v)) ∧
      (∃ c, ob.get? "classification" = some (.str c) ∧ c ∈ ["classified", "quarantine"]) ∧
      ∃ xs ss, ob.get? "labels" = some (.arr xs) ∧ xs.mapM asStr = .ok ss ∧
        sortStrings ss = ss ∧ sortDedup ss = ss ∧ ss.all (bindingIds Γ).contains = true := by
  unfold objectError at h
  split at h <;> try (simp at h; done)
  rename_i kvs
  simp only at h
  repeat' (split at h <;> try (simp at h; done))
  rename_i hid hv hc
  obtain ⟨id, hid⟩ := kebabJ_some (by simpa using hid)
  obtain ⟨v, hv⟩ := kebabJ_some (by simpa using hv)
  obtain ⟨c, hc, hcm⟩ := strIn_some (by simpa using hc)
  exact ⟨_, rfl, ⟨id, hid⟩, ⟨v, hv⟩, ⟨c, hc, hcm⟩, refsError_none h⟩

/-- What `Snapshot.validated` asks of one fact. -/
def factTyped (Γ : Registry) (n : String) (v : JVal) : Bool :=
  if admitBaseFacts.contains n then valueFits "boolean" v
  else match Γ.factFields.lookup n with
    | some ty => valueFits ty v
    | none => false

theorem factError_none {Γ : Registry} {n : String} {e : JVal} (h : factError Γ n e = none) :
    (∃ v, e.get? "value" = some v ∧ factTyped Γ n v = true) ∧
      (∃ s, e.get? "source" = some (.str s)) ∧ ∃ k, e.get? "source_kind" = some (.str k) := by
  unfold factError at h
  split at h <;> try (simp at h; done)
  rename_i kvs
  simp only at h
  repeat' (split at h <;> try (simp at h; done))
  rename_i hknown hsrc hkind _ v hv hfit
  obtain ⟨s, hs⟩ := isStr_some (by simpa using hsrc)
  obtain ⟨k, hk, -⟩ := strIn_some (by simpa using hkind)
  refine ⟨⟨v, hv, ?_⟩, ⟨s, hs⟩, k, hk⟩
  have hfit : valueFits (factType Γ n) v = true := by simpa using hfit
  unfold factTyped
  unfold factType at hfit
  by_cases hb : n ∈ admitBaseFacts
  · simpa [hb] using hfit
  · cases hl : Γ.factFields.lookup n with
    | none => simp [hb, hl] at hknown
    | some ty => simpa [hb, hl] using hfit

theorem factsError_none {Γ : Registry} {o : Option JVal} (h : factsError Γ o = none) :
    ∃ kvs, o = some (.obj kvs) ∧ ∀ p ∈ kvs, factError Γ p.1 p.2 = none := by
  unfold factsError at h
  split at h
  · next kvs =>
    refine ⟨kvs, rfl, fun p hp => ?_⟩
    rw [List.findSome?_eq_none_iff] at h
    exact h p (List.mem_mergeSort.2 hp)
  · simp at h

/-- Main theorem: every snapshot `validate_snapshot/2` accepts decodes into
the model and lies in the domain the theorems assume. -/
theorem snapshotError_validated {Γ : Registry} {j : JVal} (h : snapshotError Γ j = none) :
    ∃ S, decodeSnapshot j = .ok S ∧ S.validated Γ = true := by
  unfold snapshotError at h
  split at h <;> try (simp at h; done)
  rename_i kvs
  simp only at h
  repeat' (split at h <;> try (simp at h; done))
  rename_i hsid _ _
  obtain ⟨sid, hsid⟩ := kebabJ_some (by simpa using hsid)
  simp only [Option.or_eq_none_iff] at h
  obtain ⟨hw, ho, hf⟩ := h
  obtain ⟨w, hw', ⟨wid, hwid⟩, ⟨valid, hvalid⟩, ⟨bxs, bss, hbxs, hbss, hb1, hb2, hb3⟩, env, henv,
    henvm⟩ := workspaceError_none hw
  obtain ⟨ob, ho', ⟨oid, hoid⟩, ⟨ver, hver⟩, ⟨cls, hcls, hclsm⟩, lxs, lss, hlxs, hlss, hl1, hl2,
    hl3⟩ := objectError_none ho
  obtain ⟨fkvs, hf', hfe⟩ := factsError_none hf
  obtain ⟨facts, hfacts, hfP⟩ := mapM_ok (f := decodeFact)
    (P := fun q => factTyped Γ q.1 q.2 = true) (xs := fkvs) fun p hp => by
      obtain ⟨⟨v, hv, ht⟩, _, _⟩ := factError_none (hfe p hp)
      exact ⟨(p.1, v), by simp [decodeFact, field_ok hv]; rfl, ht⟩
  obtain ⟨sources, hsources, -⟩ := mapM_ok (f := decodeFactSource) (P := fun _ => True)
    (xs := fkvs) fun p hp => by
      obtain ⟨_, ⟨s, hs⟩, ⟨k, hk⟩⟩ := factError_none (hfe p hp)
      exact ⟨(p.1, s, k), by simp [decodeFactSource, strAt_ok hs, strAt_ok hk]; rfl, trivial⟩
  refine ⟨⟨sid, bss, valid, env, cls, lss, facts, oid ++ "@" ++ ver, wid, sources⟩, ?_, ?_⟩
  · simp only [decodeSnapshot, field_ok hw', field_ok ho', field_ok hf', asObj, hfacts, hsources,
      strAt_ok hsid, asStrs, field_ok hbxs, asArr, hbss, field_ok hvalid, asBool, strAt_ok henv,
      strAt_ok hcls, field_ok hlxs, hlss, strAt_ok hoid, strAt_ok hver, strAt_ok hwid, bind,
      Except.bind, pure, Except.pure]
  · simp only [Snapshot.validated, Snapshot.wellFormed, Bool.and_eq_true]
    refine ⟨⟨⟨⟨⟨⟨⟨⟨⟨?_, ?_⟩, by simp [hb1]⟩, by simp [hb2]⟩, by simp [hl1]⟩, by simp [hl2]⟩,
      lookup_isSome henvm⟩, hb3⟩, hl3⟩, ?_⟩
    · simp only [List.mem_cons, List.not_mem_nil, or_false] at hclsm
      rcases hclsm with rfl | rfl <;> rfl
    · rw [List.all_eq_true]
      intro n hn
      simp only [Snapshot.fact?]
      cases hlk : facts.lookup n with
      | none => rfl
      | some v =>
        have ht := hfP _ (mem_of_lookup hlk)
        have hv : valueFits "boolean" v = true := by simpa [factTyped, hn] using ht
        cases v <;> simp [valueFits] at hv ⊢
    · rw [List.all_eq_true]
      intro ⟨n, v⟩ hy
      exact hfP (n, v) hy

end KomkiSpec
