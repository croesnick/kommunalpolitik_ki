import KomkiSpec.JsonCanonical

/-!
# What the parser returns is canonical

`Json.parse` hands every object back with its entries sorted by key
(`sortEntries`), so every value it returns satisfies `JVal.Canon`
(`parse_canon`). With `canonical_injective`: two documents that parse to
different values never share a canonical form (`parse_canonical_injective`).
-/

namespace KomkiSpec

theorem canonList_iff : ∀ {xs : List JVal}, JVal.CanonList xs ↔ ∀ x ∈ xs, x.Canon
  | [] => by simp [JVal.CanonList]
  | x :: xs => by simp [JVal.CanonList, canonList_iff (xs := xs)]

theorem canonObj_iff : ∀ {kvs : List (String × JVal)}, JVal.CanonObj kvs ↔ ∀ kv ∈ kvs, kv.2.Canon
  | [] => by simp [JVal.CanonObj]
  | (k, v) :: kvs => by simp [JVal.CanonObj, canonObj_iff (kvs := kvs)]

/-- Neither array nor object. -/
def JVal.scalar : JVal → Bool
  | .arr _ | .obj _ => false
  | _ => true

theorem canon_of_scalar : ∀ {v : JVal}, v.scalar = true → v.Canon
  | .null, _ | .bool _, _ | .int _, _ | .float _ _, _ | .str _, _ => trivial
  | .arr _, h | .obj _, h => by simp [JVal.scalar] at h

end KomkiSpec

namespace KomkiSpec.Json

theorem sortEntries_canon {acc : List (String × JVal)} (h : ∀ kv ∈ acc, kv.2.Canon) :
    (JVal.obj (sortEntries acc)).Canon := by
  show ((sortEntries acc).map (·.1)).Pairwise (fun a b => ¬ b < a) ∧ JVal.CanonObj (sortEntries acc)
  refine ⟨?_, canonObj_iff.2 fun kv hkv => h kv (List.mem_mergeSort.1 hkv)⟩
  have hs := List.pairwise_mergeSort (le := fun a b : String × JVal => !decide (b.1 < a.1))
    (fun a b c hab hbc => by
      simp only [Bool.not_eq_true', decide_eq_false_iff_not, String.not_lt] at hab hbc ⊢
      exact String.le_trans hab hbc)
    (fun a b => by
      simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_false_iff_not, String.not_lt]
      exact String.le_total b.1 a.1 |>.symm)
    acc
  rw [List.pairwise_map]
  exact hs.imp fun h => by simpa using h

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
    (h : r.map (fun (str, q) => (JVal.str str, q)) = .ok (v, p)) : v.Canon := by
  cases r with
  | error _ => cases h
  | ok r => cases h; trivial

mutual
theorem readValue_canon : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readValue fuel s pos = .ok (v, p) → v.Canon
  | 0, _, _, _, _, h => by simp [readValue] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readValue] at h
    split at h
    · cases h
    · repeat' (first
        | exact readObject_canon fuel s _ h
        | exact readArray_canon fuel s _ h
        | exact map_str h
        | (rw [keyword_ok h]; trivial)
        | exact canon_of_scalar (readNumber_scalar h)
        | cases h
        | split at h)

theorem readObject_canon : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readObject fuel s pos = .ok (v, p) → v.Canon
  | 0, _, _, _, _, h => by simp [readObject] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readObject] at h
    repeat' (first
      | exact readEntries_canon fuel s _ [] (by simp) h
      | (cases h; exact ⟨List.Pairwise.nil, trivial⟩)
      | cases h
      | split at h)

theorem readEntries_canon : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat)
    (acc : List (String × JVal)), (∀ kv ∈ acc, kv.2.Canon) → ∀ {v : JVal} {p : Nat},
    readEntries fuel s pos acc = .ok (v, p) → v.Canon
  | 0, _, _, _, _, _, _, h => by simp [readEntries] at h
  | fuel + 1, s, pos, acc, hacc, v, p, h => by
    simp only [readEntries, bind, Except.bind] at h
    cases hk : readString fuel s (pos + 1) #[] with
    | error _ => simp [hk] at h
    | ok k =>
      simp only [hk] at h
      cases hr : readValue fuel s (skipWs s (skipWs s k.2 + 1)) with
      | error _ => simp [hr] at h; repeat' (first | cases h | split at h)
      | ok r =>
        simp only [hr] at h
        have hc := readValue_canon fuel s _ hr
        have hacc' : ∀ kv ∈ acc ++ [(k.1, r.1)], kv.2.Canon := by
          intro kv hkv
          simp only [List.mem_append, List.mem_singleton] at hkv
          rcases hkv with hkv | rfl
          · exact hacc kv hkv
          · exact hc
        repeat' (first
          | (cases h; exact sortEntries_canon hacc')
          | exact readEntries_canon fuel s _ _ hacc' h
          | cases h
          | split at h)

theorem readArray_canon : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readArray fuel s pos = .ok (v, p) → v.Canon
  | 0, _, _, _, _, h => by simp [readArray] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readArray] at h
    repeat' (first
      | exact readItems_canon fuel s _ [] (by simp) h
      | (cases h; trivial)
      | cases h
      | split at h)

theorem readItems_canon : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) (acc : List JVal),
    (∀ x ∈ acc, x.Canon) → ∀ {v : JVal} {p : Nat},
    readItems fuel s pos acc = .ok (v, p) → v.Canon
  | 0, _, _, _, _, _, _, h => by simp [readItems] at h
  | fuel + 1, s, pos, acc, hacc, v, p, h => by
    simp only [readItems, bind, Except.bind] at h
    cases hr : readValue fuel s pos with
    | error _ => simp [hr] at h
    | ok r =>
      simp only [hr] at h
      have hc := readValue_canon fuel s pos hr
      have hacc' : ∀ x ∈ acc ++ [r.1], x.Canon := by
        intro x hx
        simp only [List.mem_append, List.mem_singleton] at hx
        rcases hx with hx | rfl
        · exact hacc x hx
        · exact hc
      repeat' (first
        | (cases h; exact canonList_iff.2 hacc')
        | exact readItems_canon fuel s _ _ hacc' h
        | cases h
        | split at h)
end

/-- Every value `Json.parse` returns lists its object keys in sorted order. -/
theorem parse_canon {s : ByteArray} {v : JVal} (h : parse s = .ok v) : v.Canon := by
  unfold parse at h
  simp only [bind, Except.bind] at h
  repeat' (first | cases h | split at h)
  rename_i r hr _
  exact readValue_canon _ s _ hr

/-- Two documents that parse to different values have different canonical
forms. -/
theorem parse_canonical_injective {s s' : ByteArray} {v w : JVal} {t : String}
    (h : parse s = .ok v) (h' : parse s' = .ok w)
    (hc : canonical v = .ok t) (hc' : canonical w = .ok t) : v = w :=
  canonical_injective (parse_canon h) (parse_canon h') hc hc'

end KomkiSpec.Json
