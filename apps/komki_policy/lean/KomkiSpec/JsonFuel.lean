import KomkiSpec.Json

/-!
# The parser's fuel always suffices

`Json.parse` recurses with fuel `4 * size + 4`; `JSON.parse/1` has none. If
the fuel ran out, the model would answer `fuel` where Elixir answers with
the grammar. `parse_noFuel`: that never happens, on any bytes. Each reader
needs at most a linear amount in the bytes left (`readValue_good`:
`3 n + 1`, `readArray_good` and `readObject_good`: `3 n + 3`,
`readItems_good` and `readEntries_good`: `3 n + 2`, `readString_noFuel`:
`n + 1`), and each succeeds only past its start (`Good`). The factor 3 is
needed (`[` repeated `k` times needs `3 k - 1`); the proof carries down to
`3 * size + 1`.
-/

namespace KomkiSpec.Json

/-- An answer that is not the fuel error. -/
def NoFuel {α : Type} (r : Except String α) : Prop := r ≠ .error "fuel"

theorem at?_lt_size {s : ByteArray} {k : Nat} {b : UInt8} (h : at? s k = some b) : k < s.size := by
  unfold at? at h; split at h <;> simp_all

theorem at?_none {s : ByteArray} {pos : Nat} (h : s.size ≤ pos) : at? s pos = none := by
  unfold at?; simp; omega

theorem ite_some_ge {p : Prop} [Decidable p] {a n : Nat} {r : Option Nat} (ha : 2 ≤ a)
    (hr : r = some n → 2 ≤ n) : (if p then some a else r) = some n → 2 ≤ n := by
  split
  · intro h; cases h; exact ha
  · exact hr

theorem utf8Len_ge {s : ByteArray} {pos : Nat} {b : UInt8} {n : Nat}
    (h : utf8Len s pos b = some n) : 2 ≤ n := by
  unfold utf8Len at h
  dsimp only at h
  revert h
  repeat' (first | apply ite_some_ge (by decide) | (intro h; cases h))

theorem readString_noFuel : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : Array UInt8),
    s.size - pos < f → NoFuel (readString f s pos acc)
  | 0, s, pos, acc, h => by omega
  | f + 1, s, pos, acc, h => by
    unfold NoFuel
    by_cases hp : pos < s.size
    · rw [readString]
      repeat' (first
        | exact readString_noFuel f s _ _ (by omega)
        | exact readString_noFuel f s _ _ (by have := utf8Len_ge ‹_›; omega)
        | (intro e; simp at e; done)
        | split
        | dsimp only)
    · rw [readString, at?_none (by omega)]
      intro e; simp at e

theorem skipWs_ge (s : ByteArray) (pos : Nat) : pos ≤ skipWs s pos := by
  rw [skipWs]
  split
  · split
    · have := skipWs_ge s (pos + 1); omega
    · omega
  · omega
termination_by s.size - pos

theorem numberEnd_ge (s : ByteArray) (pos : Nat) : pos ≤ numberEnd s pos := by
  rw [numberEnd]
  split
  · split
    · have := numberEnd_ge s (pos + 1); omega
    · omega
  · omega
termination_by s.size - pos

theorem readString_mono : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : Array UInt8)
    {str : String} {q : Nat}, readString f s pos acc = .ok (str, q) → pos < q
  | 0, _, _, _, _, _, h => by simp [readString] at h
  | f + 1, s, pos, acc, str, q, h => by
    rw [readString] at h
    repeat' (first
      | (cases h; omega)
      | (have := readString_mono f s _ _ h; omega)
      | (have := readString_mono f s _ _ h; have := utf8Len_ge ‹_›; omega)
      | (cases h; done)
      | split at h
      | dsimp only at h)

theorem readNumber_mono {s : ByteArray} {pos : Nat} {v : JVal} {q : Nat}
    (h : readNumber s pos = .ok (v, q)) : pos < q := by
  unfold readNumber at h
  dsimp only at h
  have hge := numberEnd_ge s pos
  by_cases he : numberEnd s pos = pos
  · rw [he] at h
    simp [splitNumber] at h
  · split at h
    · cases h
    · repeat' (first | (cases h; omega) | (cases h; done) | split at h)

/-- No fuel error, and on success the reader has moved past `p`. -/
def Good {α : Type} (p : Nat) (r : Except String (α × Nat)) : Prop :=
  r ≠ .error "fuel" ∧ ∀ a q, r = .ok (a, q) → p < q

theorem good_error {α : Type} {p : Nat} {e : String} (h : e ≠ "fuel") :
    Good p (.error e : Except String (α × Nat)) :=
  ⟨fun x => h (by cases x; rfl), fun _ _ x => by cases x⟩

theorem keyword_good {s : ByteArray} {pos : Nat} {kw : String} {v : JVal}
    (hk : 0 < kw.toUTF8.size) : Good pos (keyword s pos kw v) := by
  unfold keyword
  dsimp only
  split
  · split
    · split
      · exact good_error (by decide)
      · exact ⟨fun x => (by cases x), fun _ _ x => (by cases x; omega)⟩
    · exact ⟨fun x => (by cases x), fun _ _ x => (by cases x; omega)⟩
  · exact good_error (by decide)

theorem readNumber_good {s : ByteArray} {pos : Nat} : Good pos (readNumber s pos) := by
  refine ⟨?_, fun _ _ h => readNumber_mono h⟩
  unfold readNumber
  dsimp only
  repeat' (first | (intro x; cases x; done) | (intro x; simp at x; done) | split)

theorem readValue_lt {f : Nat} {s : ByteArray} {pos : Nat} {v : JVal} {q : Nat}
    (h : readValue f s pos = .ok (v, q)) : pos < s.size := by
  cases f with
  | zero => simp [readValue] at h
  | succ f =>
    rw [readValue] at h
    split at h
    · cases h
    · next hs => exact at?_lt_size hs

theorem good_mono {α : Type} {p p' : Nat} {r : Except String (α × Nat)} (h : Good p' r)
    (hp : p ≤ p') : Good p r :=
  ⟨h.1, fun a q e => by have := h.2 a q e; omega⟩

theorem good_of_error {α β : Type} {p : Nat} {r : Except String (α × Nat)} {e : String}
    (hr : r = .error e) (h : r ≠ .error "fuel") : Good p (.error e : Except String (β × Nat)) :=
  good_error (fun x => h (by rw [hr, x]))

theorem good_string {f : Nat} {s : ByteArray} {p : Nat} (h : s.size - (p + 1) < f) :
    Good p ((readString f s (p + 1) #[]).map fun (str, q) => (JVal.str str, q)) := by
  cases hr : readString f s (p + 1) #[] with
  | error e => exact good_of_error rfl (by rw [← hr]; exact readString_noFuel f s _ _ h)
  | ok r =>
    refine ⟨fun x => by simp [Except.map] at x, fun a q x => ?_⟩
    simp only [Except.map, Except.ok.injEq, Prod.mk.injEq] at x
    have := readString_mono f s _ _ (str := r.1) (q := r.2) (by rw [hr])
    omega

mutual
theorem readValue_good : ∀ (f : Nat) (s : ByteArray) (pos : Nat),
    3 * (s.size - pos) + 1 ≤ f → Good pos (readValue f s pos)
  | 0, _, _, h => by omega
  | f + 1, s, pos, h => by
    rw [readValue]
    split
    · exact good_error (by decide)
    · next b hb =>
      have hp := at?_lt_size hb
      split
      · exact good_mono (readObject_good f s (pos + 1) (by omega)) (by omega)
      split
      · exact good_mono (readArray_good f s (pos + 1) (by omega)) (by omega)
      split
      · exact good_string (by omega)
      split
      · exact keyword_good (by decide)
      split
      · exact keyword_good (by decide)
      split
      · exact keyword_good (by decide)
      split
      · exact readNumber_good
      split
      · exact good_error (by decide)
      · exact good_error (by decide)

theorem readObject_good : ∀ (f : Nat) (s : ByteArray) (pos : Nat),
    3 * (s.size - pos) + 3 ≤ f → Good pos (readObject f s pos)
  | 0, _, _, h => by omega
  | f + 1, s, pos, h => by
    rw [readObject]
    have hw := skipWs_ge s pos
    split
    · exact good_error (by decide)
    · split
      · exact ⟨fun x => (by cases x), fun _ _ x => (by cases x; omega)⟩
      split
      · exact good_mono (readEntries_good f s _ [] (by omega)) hw
      · exact good_error (by decide)

theorem readEntries_good : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : List (String × JVal)),
    3 * (s.size - pos) + 2 ≤ f → Good pos (readEntries f s pos acc)
  | 0, _, _, _, h => by omega
  | f + 1, s, pos, acc, h => by
    simp only [readEntries, bind, Except.bind]
    cases hk : readString f s (pos + 1) #[] with
    | error e => exact good_of_error hk (readString_noFuel f s _ _ (by omega))
    | ok kr =>
      obtain ⟨key, kpos⟩ := kr
      have hkm := readString_mono f s _ _ hk
      dsimp only
      split
      · exact good_error (by decide)
      · split
        · exact good_error (by decide)
        · have hc := skipWs_ge s kpos
          have hs := skipWs_ge s (skipWs s kpos + 1)
          have hg := readValue_good f s (skipWs s (skipWs s kpos + 1)) (by omega)
          cases hv : readValue f s (skipWs s (skipWs s kpos + 1)) with
          | error e => exact good_of_error hv hg.1
          | ok r =>
            obtain ⟨v, vpos⟩ := r
            have hvm := hg.2 _ _ hv
            have hlt := readValue_lt hv
            have hw := skipWs_ge s vpos
            have hk2 := skipWs_ge s (skipWs s vpos + 1)
            dsimp only
            split
            · exact good_error (by decide)
            · split
              · exact good_error (by decide)
              · split
                · exact ⟨fun x => (by cases x), fun _ _ x => (by cases x; omega)⟩
                split
                · split
                  · exact good_error (by decide)
                  · split
                    · exact good_error (by decide)
                    split
                    · exact good_mono (readEntries_good f s _ _ (by omega)) (by omega)
                    · exact good_error (by decide)
                · exact good_error (by decide)

theorem readArray_good : ∀ (f : Nat) (s : ByteArray) (pos : Nat),
    3 * (s.size - pos) + 3 ≤ f → Good pos (readArray f s pos)
  | 0, _, _, h => by omega
  | f + 1, s, pos, h => by
    rw [readArray]
    have hw := skipWs_ge s pos
    split
    · exact good_error (by decide)
    · split
      · exact ⟨fun x => (by cases x), fun _ _ x => (by cases x; omega)⟩
      split
      · exact good_error (by decide)
      · exact good_mono (readItems_good f s _ [] (by omega)) hw

theorem readItems_good : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : List JVal),
    3 * (s.size - pos) + 2 ≤ f → Good pos (readItems f s pos acc)
  | 0, _, _, _, h => by omega
  | f + 1, s, pos, acc, h => by
    have hg := readValue_good f s pos (by omega)
    simp only [readItems, bind, Except.bind]
    cases hv : readValue f s pos with
    | error e => exact good_of_error hv hg.1
    | ok r =>
      obtain ⟨v, vpos⟩ := r
      have hvm := hg.2 _ _ hv
      have hlt := readValue_lt hv
      have hw := skipWs_ge s vpos
      have hk := skipWs_ge s (skipWs s vpos + 1)
      dsimp only
      split
      · exact good_error (by decide)
      · split
        · exact ⟨fun x => (by cases x), fun _ _ x => (by cases x; omega)⟩
        split
        · split
          · exact good_error (by decide)
          · split
            · exact good_error (by decide)
            · exact good_mono (readItems_good f s _ _ (by omega)) (by omega)
        · exact good_error (by decide)
end

/-- Main theorem: on every input the parser's fuel suffices, so `parse`
never answers `fuel`; every answer is the strict JSON grammar's. -/
theorem parse_noFuel (s : ByteArray) : parse s ≠ .error "fuel" := by
  unfold parse
  simp only [bind, Except.bind]
  split
  · intro x; simp at x
  · have hg := readValue_good (4 * s.size + 4) s (skipWs s 0) (by omega)
    cases hv : readValue (4 * s.size + 4) s (skipWs s 0) with
    | error e => intro x; exact hg.1 (by rw [hv]; simp at x ⊢; exact x)
    | ok r =>
      obtain ⟨v, q⟩ := r
      dsimp only
      split <;> (intro x; simp at x)

end KomkiSpec.Json
