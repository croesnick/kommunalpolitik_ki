import KomkiSpec.ReleaseSound
import KomkiSpec.JsonParseCanon
import KomkiSpec.Bridge

/-!
# The consumed ledger is a map

`stand.ex` keeps `consumed` as a `Map` from nonce to release id; the model
keeps a list (`Stand.consumed`) and reads it with `List.lookup`. The two
agree only while no nonce appears twice (`Stand.Ledger`).
`decodeStand_ledger`: a stand decoded from a strictly parsed file has that
property, its keys are strictly sorted. `advance_ledger`,
`advances_ledger`: `advance` keeps it, since it refuses a consumed nonce.
`ledger_lookup`: on such a list `lookup` finds exactly the consumed pairs,
whatever their order. `advances_ledger_parsed` puts the three together.
-/

namespace KomkiSpec

/-- Every nonce appears at most once in `consumed`. -/
def Stand.Ledger (St : Stand) : Prop := (St.consumed.map (·.1)).Nodup

theorem lookup_none {l : List (String × String)} {n : String} (h : l.lookup n = none) :
    n ∉ l.map (·.1) := by
  induction l with
  | nil => simp
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    simp only [List.lookup] at h
    split at h
    · cases h
    · next hne =>
      simp only [List.map_cons, List.mem_cons, not_or]
      exact ⟨fun e => by simp [e] at hne, ih h⟩

theorem advance_ledger {St St' : Stand} {P : Proposal} (hl : St.Ledger)
    (h : advance St P = .ok St') : St'.Ledger := by
  obtain ⟨_, _, hfresh, _, hc⟩ := advance_ok h
  unfold Stand.Ledger at hl ⊢
  rw [hc, List.map_cons, List.nodup_cons]
  exact ⟨lookup_none hfresh, hl⟩

theorem advances_ledger {St St' : Stand} (h : Advances St St') (hl : St.Ledger) : St'.Ledger := by
  induction h with
  | refl => exact hl
  | step ha _ ih => exact ih (advance_ledger hl ha)

theorem get?_strict {j v : JVal} {k : String} (hj : j.Strict) (h : j.get? k = some v) :
    v.Strict := by
  cases j with
  | obj kvs =>
    simp only [JVal.get?] at h
    exact strictObj_iff.1 hj.2 (k, v) (mem_of_lookup h)
  | _ => simp [JVal.get?] at h

/-- A decoder that keeps each key keeps the list of keys. -/
theorem mapM_keys {f : String × JVal → Decode (String × String)}
    (hf : ∀ p q, f p = .ok q → q.1 = p.1) :
    ∀ {kvs : List (String × JVal)} {l : List (String × String)},
      kvs.mapM f = .ok l → l.map (·.1) = kvs.map (·.1)
  | [], l, h => by simp [pure, Except.pure] at h; subst h; rfl
  | p :: kvs, l, h => by
    rw [List.mapM_cons] at h
    simp only [bind, Except.bind, pure, Except.pure] at h
    cases hp : f p with
    | error e => simp [hp] at h
    | ok q =>
      cases hk : kvs.mapM f with
      | error e => simp [hp, hk] at h
      | ok l' =>
        simp only [hp, hk, Except.ok.injEq] at h
        subst h
        simp [hf p q hp, mapM_keys hf hk]

/-- A stand the bridge decodes from a strictly parsed file (`Json.parse_strict`)
satisfies the ledger invariant: its keys are strictly sorted. -/
theorem decodeStand_ledger {j : JVal} {St : Stand} (hj : j.Strict) (h : decodeStand j = .ok St) :
    St.Ledger := by
  unfold decodeStand field at h
  cases hc : j.get? "consumed" with
  | none => simp [hc, bind, Except.bind, throw, throwThe, MonadExceptOf.throw] at h
  | some c =>
    cases c with
    | obj kvs =>
      have hs := get?_strict hj hc
      simp only [hc, bind, Except.bind, pure, Except.pure, asObj] at h
      split at h
      · cases h
      · next l hm =>
        have hk := mapM_keys (fun p q e => by
          obtain ⟨n, r⟩ := p
          split at e
          · cases e
          · cases e; rfl) hm
        repeat' split at h
        all_goals (try (cases h; done))
        all_goals
          cases h
          unfold Stand.Ledger
          dsimp only
          rw [hk]
          exact hs.1.imp fun {a b} (hlt : a < b) (he : a = b) => String.lt_irrefl a (by
            rw [he] at hlt ⊢; exact hlt)
    | _ => simp [hc, bind, Except.bind, pure, Except.pure, asObj] at h

/-- On a ledger, `lookup` is a map lookup: it finds a nonce's release exactly
when the pair is consumed, independent of the order of the list. -/
theorem ledger_lookup {St : Stand} (hl : St.Ledger) {n r : String} :
    St.consumed.lookup n = some r ↔ (n, r) ∈ St.consumed := by
  unfold Stand.Ledger at hl
  generalize St.consumed = l at hl ⊢
  induction l with
  | nil => simp
  | cons p l ih =>
    obtain ⟨a, b⟩ := p
    simp only [List.map_cons, List.nodup_cons] at hl
    simp only [List.lookup, List.mem_cons, Prod.mk.injEq]
    split
    · next he =>
      have ha : n = a := by simpa using he
      subst ha
      constructor
      · intro h; cases h; exact .inl ⟨rfl, rfl⟩
      · rintro (⟨-, rfl⟩ | hm)
        · rfl
        · exact absurd (List.mem_map_of_mem (f := (·.1)) hm) hl.1
    · next he =>
      have ha : n ≠ a := by simpa using he
      rw [ih hl.2]
      constructor
      · exact .inr
      · rintro (⟨rfl, -⟩ | hm)
        · exact absurd rfl ha
        · exact hm

/-- Main theorem: every stand reachable by committed `advance` steps from a
stand the bridge decodes from a parsed file keeps every nonce at most once,
so `consumed` behaves like the `Map` that `stand.ex` keeps. -/
theorem advances_ledger_parsed {s : ByteArray} {j : JVal} {St St' : Stand}
    (hp : Json.parse s = .ok j) (hd : decodeStand j = .ok St) (ha : Advances St St') :
    St'.Ledger ∧ ∀ n r, St'.consumed.lookup n = some r ↔ (n, r) ∈ St'.consumed :=
  have hl := advances_ledger ha (decodeStand_ledger (Json.parse_strict hp) hd)
  ⟨hl, fun _ _ => ledger_lookup hl⟩

end KomkiSpec
