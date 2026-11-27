import KomkiSpec.JsonCanonical

/-!
# What the parser returns is canonical

`Json.parse` rejects a repeated key (`duplicate_json_key`) and hands every
object back with its entries sorted by key (`sortEntries`), so every value
it returns has strictly sorted keys (`parse_strict`), hence `JVal.Canon`
(`parse_canon`). A strictly sorted entry list is the unique representation
of an Elixir map, so list equality in Lean matches `===` on the maps
`JSON.parse/1` returns. With `canonical_injective`: two documents that
parse to different encodable values never share a canonical form
(`parse_canonical_injective`), the Lean side of the test method in
CONTRACT.md § 6. No other theorem relies on these yet.
-/

namespace KomkiSpec

mutual
/-- Every object's keys strictly sorted: sorted and free of duplicates. -/
def JVal.Strict : JVal → Prop
  | .arr xs => JVal.StrictList xs
  | .obj kvs => (kvs.map (·.1)).Pairwise (· < ·) ∧ JVal.StrictObj kvs
  | _ => True

def JVal.StrictList : List JVal → Prop
  | [] => True
  | x :: xs => x.Strict ∧ JVal.StrictList xs

def JVal.StrictObj : List (String × JVal) → Prop
  | [] => True
  | (_, v) :: kvs => v.Strict ∧ JVal.StrictObj kvs
end

theorem strictList_iff : ∀ {xs : List JVal}, JVal.StrictList xs ↔ ∀ x ∈ xs, x.Strict
  | [] => by simp [JVal.StrictList]
  | x :: xs => by simp [JVal.StrictList, strictList_iff (xs := xs)]

theorem strictObj_iff : ∀ {kvs : List (String × JVal)},
    JVal.StrictObj kvs ↔ ∀ kv ∈ kvs, kv.2.Strict
  | [] => by simp [JVal.StrictObj]
  | (k, v) :: kvs => by simp [JVal.StrictObj, strictObj_iff (kvs := kvs)]

mutual
theorem strict_canon : ∀ {v : JVal}, v.Strict → v.Canon
  | .arr xs, h => strictList_canon (xs := xs) h
  | .obj kvs, h => ⟨h.1.imp String.lt_asymm, strictObj_canon (kvs := kvs) h.2⟩
  | .null, _ | .bool _, _ | .int _, _ | .float _ _, _ | .str _, _ => trivial

theorem strictList_canon : ∀ {xs : List JVal}, JVal.StrictList xs → JVal.CanonList xs
  | [], _ => trivial
  | _ :: _, h => ⟨strict_canon h.1, strictList_canon h.2⟩

theorem strictObj_canon : ∀ {kvs : List (String × JVal)}, JVal.StrictObj kvs → JVal.CanonObj kvs
  | [], _ => trivial
  | (_, _) :: _, h => ⟨strict_canon h.1, strictObj_canon h.2⟩
end

/-- Neither array nor object. -/
def JVal.scalar : JVal → Bool
  | .arr _ | .obj _ => false
  | _ => true

theorem strict_of_scalar : ∀ {v : JVal}, v.scalar = true → v.Strict
  | .null, _ | .bool _, _ | .int _, _ | .float _ _, _ | .str _, _ => trivial
  | .arr _, h | .obj _, h => by simp [JVal.scalar] at h

end KomkiSpec

namespace KomkiSpec.Json

/-- Sorting by key with the order `sortEntries` uses leaves the keys sorted. -/
theorem mergeSort_keys_sorted {α : Type} (l : List (String × α)) :
    ((l.mergeSort fun a b => !decide (b.1 < a.1)).map (·.1)).Pairwise (fun a b => ¬ b < a) := by
  have hs := List.pairwise_mergeSort (le := fun a b : String × α => !decide (b.1 < a.1))
    (fun a b c hab hbc => by
      simp only [Bool.not_eq_true', decide_eq_false_iff_not, String.not_lt] at hab hbc ⊢
      exact String.le_trans hab hbc)
    (fun a b => by
      simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not, String.not_lt]
      exact String.le_total b.1 a.1 |>.symm)
    l
  exact List.pairwise_map.2 (hs.imp fun h => by simpa using h)

theorem sortEntries_strict {acc : List (String × JVal)} (h : ∀ kv ∈ acc, kv.2.Strict)
    (hnd : (acc.map (·.1)).Nodup) : (JVal.obj (sortEntries acc)).Strict := by
  show ((sortEntries acc).map (·.1)).Pairwise (· < ·) ∧ JVal.StrictObj (sortEntries acc)
  refine ⟨?_, strictObj_iff.2 fun kv hkv => h kv (List.mem_mergeSort.1 hkv)⟩
  have hnd' : ((sortEntries acc).map (·.1)).Nodup :=
    ((List.mergeSort_perm acc _).map _).nodup_iff.2 hnd
  have hle : ((sortEntries acc).map (·.1)).Pairwise (fun a b => ¬ b < a) :=
    mergeSort_keys_sorted acc
  exact (hle.and hnd').imp fun h => Std.lt_of_le_of_ne h.1 h.2

theorem keyword_ok {s : ByteArray} {pos : Nat} {kw : String} {v w : JVal} {p : Nat}
    (h : keyword s pos kw v = .ok (w, p)) : w = v := by
  unfold keyword at h
  dsimp only at h
  split at h
  · split at h
    · split at h
      · cases h
      · cases h; rfl
    · cases h; rfl
  · cases h

theorem readNumber_scalar {s : ByteArray} {pos : Nat} {w : JVal} {p : Nat}
    (h : readNumber s pos = .ok (w, p)) : w.scalar = true := by
  unfold readNumber at h
  dsimp only at h
  split at h
  · cases h
  · split at h
    · cases h; rfl
    · repeat (first | (split at h) | (cases h; rfl) | cases h)

theorem map_str {r : Except String (String × Nat)} {v : JVal} {p : Nat}
    (h : r.map (fun (str, q) => (JVal.str str, q)) = .ok (v, p)) : v.Strict := by
  cases r with
  | error _ => cases h
  | ok r => cases h; trivial

mutual
theorem readValue_strict : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readValue fuel s pos = .ok (v, p) → v.Strict
  | 0, _, _, _, _, h => by simp [readValue] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readValue] at h
    split at h
    · cases h
    · repeat' (first
        | exact readObject_strict fuel s _ h
        | exact readArray_strict fuel s _ h
        | exact map_str h
        | (rw [keyword_ok h]; trivial)
        | exact strict_of_scalar (readNumber_scalar h)
        | cases h
        | split at h)

theorem readObject_strict : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readObject fuel s pos = .ok (v, p) → v.Strict
  | 0, _, _, _, _, h => by simp [readObject] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readObject] at h
    repeat' (first
      | exact readEntries_strict fuel s _ [] (by simp) List.nodup_nil h
      | (cases h; exact ⟨List.Pairwise.nil, trivial⟩)
      | cases h
      | split at h)

theorem readEntries_strict : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat)
    (acc : List (String × JVal)), (∀ kv ∈ acc, kv.2.Strict) → (acc.map (·.1)).Nodup →
    ∀ {v : JVal} {p : Nat}, readEntries fuel s pos acc = .ok (v, p) → v.Strict
  | 0, _, _, _, _, _, _, _, h => by simp [readEntries] at h
  | fuel + 1, s, pos, acc, hacc, hnd, v, p, h => by
    simp only [readEntries, bind, Except.bind] at h
    cases hk : readString fuel s (pos + 1) #[] with
    | error _ => simp [hk] at h
    | ok k =>
      simp only [hk] at h
      cases hr : readValue fuel s (skipWs s (skipWs s k.2 + 1)) with
      | error _ => simp [hr] at h; repeat' (first | cases h | split at h)
      | ok r =>
        simp only [hr] at h
        have hc := readValue_strict fuel s _ hr
        have hacc' : ∀ kv ∈ acc ++ [(k.1, r.1)], kv.2.Strict := by
          intro kv hkv
          simp only [List.mem_append, List.mem_singleton] at hkv
          rcases hkv with hkv | rfl
          · exact hacc kv hkv
          · exact hc
        cases hd : acc.any (·.1 == k.1) with
        | true => simp only [hd] at h; repeat' (first | cases h | split at h)
        | false =>
          have hnd' : ((acc ++ [(k.1, r.1)]).map (·.1)).Nodup := by
            rw [List.map_append, List.nodup_append]
            refine ⟨hnd, by simp, fun a ha b hb => ?_⟩
            simp only [List.map_cons, List.map_nil, List.mem_singleton] at hb
            subst hb
            rintro rfl
            obtain ⟨kv, hkv, heq⟩ := List.mem_map.1 ha
            exact List.any_eq_false.1 hd kv hkv (by simp [heq])
          simp only [hd] at h
          repeat' (first
            | (cases h; exact sortEntries_strict hacc' hnd')
            | exact readEntries_strict fuel s _ _ hacc' hnd' h
            | cases h
            | split at h)

theorem readArray_strict : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readArray fuel s pos = .ok (v, p) → v.Strict
  | 0, _, _, _, _, h => by simp [readArray] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readArray] at h
    repeat' (first
      | exact readItems_strict fuel s _ [] (by simp) h
      | (cases h; trivial)
      | cases h
      | split at h)

theorem readItems_strict : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) (acc : List JVal),
    (∀ x ∈ acc, x.Strict) → ∀ {v : JVal} {p : Nat},
    readItems fuel s pos acc = .ok (v, p) → v.Strict
  | 0, _, _, _, _, _, _, h => by simp [readItems] at h
  | fuel + 1, s, pos, acc, hacc, v, p, h => by
    simp only [readItems, bind, Except.bind] at h
    cases hr : readValue fuel s pos with
    | error _ => simp [hr] at h
    | ok r =>
      simp only [hr] at h
      have hc := readValue_strict fuel s pos hr
      have hacc' : ∀ x ∈ acc ++ [r.1], x.Strict := by
        intro x hx
        simp only [List.mem_append, List.mem_singleton] at hx
        rcases hx with hx | rfl
        · exact hacc x hx
        · exact hc
      repeat' (first
        | (cases h; exact strictList_iff.2 hacc')
        | exact readItems_strict fuel s _ _ hacc' h
        | cases h
        | split at h)
end

/-- Every value `Json.parse` returns lists its object keys strictly sorted:
in order and without duplicates. -/
theorem parse_strict {s : ByteArray} {v : JVal} (h : parse s = .ok v) : v.Strict := by
  unfold parse at h
  simp only [bind, Except.bind] at h
  repeat' (first | cases h | split at h)
  rename_i r hr _
  exact readValue_strict _ s _ hr

/-- Every value `Json.parse` returns lists its object keys in sorted order. -/
theorem parse_canon {s : ByteArray} {v : JVal} (h : parse s = .ok v) : v.Canon :=
  strict_canon (parse_strict h)

/-- Two documents that parse to different values have different canonical
forms, as long as both values encode (no float, depth ≤ 128). -/
theorem parse_canonical_injective {s s' : ByteArray} {v w : JVal} {t : String}
    (h : parse s = .ok v) (h' : parse s' = .ok w)
    (hc : canonical v = .ok t) (hc' : canonical w = .ok t) : v = w :=
  canonical_injective (parse_canon h) (parse_canon h') hc hc'

end KomkiSpec.Json
