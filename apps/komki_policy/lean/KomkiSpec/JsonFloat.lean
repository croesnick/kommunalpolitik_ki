import KomkiSpec.JsonParseCanon
set_option exponentiation.threshold 1100

/-!
# The parser's floats are finite

`readNumber` rejects a float whose value rounds to infinity as a double, the
way `binary_to_float/1` fails. It decides that through a shortcut on the
number of decimal digits (`finiteDouble`). `finiteDouble_iff`: the shortcut
is exactly the comparison of `m · 10^e` with `overflowBound`, the boundaries
at 308 and 310 digits included. `parse_floatsOk`: every float `parse`
returns passes it. That the representation equals Elixir's float, rounding
included, stays with the differential test.
-/

namespace KomkiSpec.Json

theorem digitCount_eq (m : Nat) : digitCount m = (Nat.toDigits 10 m).length := by
  simp [digitCount, Nat.repr_eq_ofList_toDigits, String.length_ofList]

theorem digitCount_lt (m : Nat) : m < 10 ^ digitCount m := by
  rw [digitCount_eq]
  exact (Nat.length_toDigits_le_iff (by decide) Nat.length_toDigits_pos).1 (Nat.le_refl _)

theorem digitCount_ge {m : Nat} (h : 0 < m) : 10 ^ (digitCount m - 1) ≤ m := by
  rw [digitCount_eq]
  have hp := Nat.length_toDigits_pos (b := 10) (n := m)
  by_cases h1 : (Nat.toDigits 10 m).length = 1
  · rw [h1]; simp; omega
  · have hiff := Nat.length_toDigits_le_iff (b := 10) (n := m)
      (k := (Nat.toDigits 10 m).length - 1) (by decide) (by omega)
    have : ¬ m < 10 ^ ((Nat.toDigits 10 m).length - 1) := fun hlt => absurd (hiff.2 hlt) (by omega)
    omega

theorem bound_lo : 10 ^ 308 < overflowBound := by
  unfold overflowBound; decide +kernel
theorem bound_hi : overflowBound < 10 ^ 309 := by
  unfold overflowBound; decide +kernel

/-- `finiteDouble` is exactly the overflow bound of `binary_to_float/1`:
the digit-count shortcuts at 308 and 310 agree with comparing `m · 10^e`
against `overflowBound`. -/
theorem finiteDouble_iff (m : Nat) (e : Int) :
    finiteDouble m e = true ↔
      (if 0 ≤ e then m * 10 ^ e.toNat < overflowBound
       else m < overflowBound * 10 ^ (-e).toNat) := by
  have lo := bound_lo
  have hi := bound_hi
  by_cases hm : m = 0
  · subst hm
    have hb : 0 < overflowBound := by omega
    have hp : 0 < overflowBound * 10 ^ (-e).toNat := Nat.mul_pos hb (Nat.pow_pos (by decide))
    split <;> simp [finiteDouble, hb, hp]
  have hlt := digitCount_lt m
  have hge := digitCount_ge (Nat.pos_of_ne_zero hm)
  have hd : 1 ≤ digitCount m := by
    rcases Nat.eq_zero_or_pos (digitCount m) with h | h
    · rw [h] at hlt; simp at hlt; omega
    · exact h
  unfold finiteDouble
  simp only [beq_iff_eq, hm, ite_false]
  generalize digitCount m = d at hlt hge hd ⊢
  have p10 : ∀ a b : Nat, a ≤ b → 10 ^ a ≤ 10 ^ b := fun a b h => Nat.pow_le_pow_right (by decide) h
  cases e with
  | ofNat n =>
    simp only [Int.ofNat_eq_natCast, Int.toNat_natCast, Int.natCast_nonneg, ite_true, ge_iff_le]
    by_cases h1 : (310 : Int) ≤ d + n
    · simp only [h1, ite_true, Bool.false_eq_true, false_iff, Nat.not_lt]
      calc overflowBound ≤ 10 ^ 309 := Nat.le_of_lt hi
        _ ≤ 10 ^ (d - 1 + n) := p10 _ _ (by omega)
        _ = 10 ^ (d - 1) * 10 ^ n := Nat.pow_add _ _ _
        _ ≤ m * 10 ^ n := Nat.mul_le_mul_right _ hge
    · by_cases h2 : (d : Int) + n ≤ 308
      · simp only [h1, h2, ite_true, ite_false, true_iff]
        calc m * 10 ^ n < 10 ^ d * 10 ^ n := Nat.mul_lt_mul_of_pos_right hlt (Nat.pow_pos (by decide))
          _ = 10 ^ (d + n) := (Nat.pow_add _ _ _).symm
          _ ≤ 10 ^ 308 := p10 _ _ (by omega)
          _ < overflowBound := lo
      · simp [h1, h2]
  | negSucc k =>
    have he : (-Int.negSucc k).toNat = k + 1 := by simp [Int.neg_negSucc]
    have hn : ¬ (0 : Int) ≤ Int.negSucc k := by simp
    simp only [hn, ite_false, he]
    have hsz : (d : Int) + Int.negSucc k = (d : Int) - (k + 1) := by simp [Int.negSucc_eq]; omega
    rw [hsz]
    by_cases h1 : (310 : Int) ≤ (d : Int) - (k + 1)
    · simp only [ge_iff_le, h1, ite_true, Bool.false_eq_true, false_iff, Nat.not_lt]
      calc overflowBound * 10 ^ (k + 1) ≤ 10 ^ 309 * 10 ^ (k + 1) :=
            Nat.mul_le_mul_right _ (Nat.le_of_lt hi)
        _ = 10 ^ (309 + (k + 1)) := (Nat.pow_add _ _ _).symm
        _ ≤ 10 ^ (d - 1) := p10 _ _ (by omega)
        _ ≤ m := hge
    · by_cases h2 : (d : Int) - (k + 1) ≤ 308
      · simp only [ge_iff_le, h1, h2, ite_true, ite_false, true_iff]
        calc m < 10 ^ d := hlt
          _ ≤ 10 ^ (308 + (k + 1)) := p10 _ _ (by omega)
          _ = 10 ^ 308 * 10 ^ (k + 1) := Nat.pow_add _ _ _
          _ < overflowBound * 10 ^ (k + 1) :=
            Nat.mul_lt_mul_of_pos_right lo (Nat.pow_pos (by decide))
      · simp [h1, h2]
/-- A float the parser may hand back: its magnitude `|m| / 10^s` rounds to a
finite double. -/
def floatOk : JVal → Bool
  | .float m s => finiteDouble m.natAbs (-(s : Int))
  | _ => true

theorem floatOk_pos {σ : Int} (hσ : σ.natAbs = 1) {m : Nat} {e : Int}
    (hf : finiteDouble m e = true) (he : e ≥ 0) :
    floatOk (.float (σ * m * 10 ^ e.toNat) 0) = true := by
  have ha : (σ * m * 10 ^ e.toNat).natAbs = m * 10 ^ e.toNat := by
    simp [Int.natAbs_mul, hσ, Int.natAbs_pow]
  simp only [floatOk, ha, Int.natCast_zero, Int.neg_zero]
  rw [finiteDouble_iff] at hf ⊢
  simp only [show (0 : Int) ≤ e from he, ite_true] at hf
  simpa using hf

theorem floatOk_neg {σ : Int} (hσ : σ.natAbs = 1) {m : Nat} {e : Int}
    (hf : finiteDouble m e = true) (he : ¬ e ≥ 0) :
    floatOk (.float (σ * m) (-e).toNat) = true := by
  have ha : (σ * m).natAbs = m := by simp [Int.natAbs_mul, hσ]
  have hs : -(((-e).toNat : Nat) : Int) = e := by omega
  simp only [floatOk, ha, hs, hf]

theorem floatOk_pos' {σ : Int} (hσ : σ.natAbs = 1) {m : Nat} {e : Int}
    (hf : ¬(!finiteDouble m e) = true) (he : e ≥ 0) :
    floatOk (.float (σ * m * 10 ^ e.toNat) 0) = true :=
  floatOk_pos hσ (by simpa using hf) he

theorem floatOk_neg' {σ : Int} (hσ : σ.natAbs = 1) {m : Nat} {e : Int}
    (hf : ¬(!finiteDouble m e) = true) (he : ¬ e ≥ 0) :
    floatOk (.float (σ * m) (-e).toNat) = true :=
  floatOk_neg hσ (by simpa using hf) he

theorem readNumber_floatOk {s : ByteArray} {pos : Nat} {w : JVal} {p : Nat}
    (h : readNumber s pos = .ok (w, p)) : floatOk w = true := by
  unfold readNumber at h
  dsimp only at h
  repeat' (first | (cases h; done) | split at h)
  all_goals (cases h)
  all_goals first
    | rfl
    | (simp [floatOk, finiteDouble]; done)
    | (apply floatOk_pos' (by decide) <;> assumption)
    | (apply floatOk_neg' (by decide) <;> assumption)
end KomkiSpec.Json

namespace KomkiSpec

mutual
/-- Every float in a value passes `floatOk`. -/
def JVal.FloatsOk : JVal → Prop
  | .arr xs => JVal.FloatsOkList xs
  | .obj kvs => JVal.FloatsOkObj kvs
  | v => Json.floatOk v = true

def JVal.FloatsOkList : List JVal → Prop
  | [] => True
  | x :: xs => x.FloatsOk ∧ JVal.FloatsOkList xs

def JVal.FloatsOkObj : List (String × JVal) → Prop
  | [] => True
  | (_, v) :: kvs => v.FloatsOk ∧ JVal.FloatsOkObj kvs
end

theorem floatsOkList_iff : ∀ {xs : List JVal}, JVal.FloatsOkList xs ↔ ∀ x ∈ xs, x.FloatsOk
  | [] => by simp [JVal.FloatsOkList]
  | x :: xs => by simp [JVal.FloatsOkList, floatsOkList_iff (xs := xs)]

theorem floatsOkObj_iff : ∀ {kvs : List (String × JVal)},
    JVal.FloatsOkObj kvs ↔ ∀ kv ∈ kvs, kv.2.FloatsOk
  | [] => by simp [JVal.FloatsOkObj]
  | (k, v) :: kvs => by simp [JVal.FloatsOkObj, floatsOkObj_iff (kvs := kvs)]

theorem floatsOk_of_floatOk : ∀ {v : JVal}, v.scalar = true → Json.floatOk v = true → v.FloatsOk
  | .null, _, h | .bool _, _, h | .int _, _, h | .float _ _, _, h | .str _, _, h => h
  | .arr _, hs, _ | .obj _, hs, _ => by simp [JVal.scalar] at hs

end KomkiSpec

namespace KomkiSpec.Json

theorem sortEntries_floatsOk {acc : List (String × JVal)} (h : ∀ kv ∈ acc, kv.2.FloatsOk) :
    (JVal.obj (sortEntries acc)).FloatsOk :=
  floatsOkObj_iff.2 fun kv hkv => h kv (List.mem_mergeSort.1 hkv)

theorem map_str_floats {r : Except String (String × Nat)} {v : JVal} {p : Nat}
    (h : r.map (fun (str, q) => (JVal.str str, q)) = .ok (v, p)) : v.FloatsOk := by
  cases r with
  | error _ => cases h
  | ok r => cases h; rfl

mutual
theorem readValue_floats : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readValue fuel s pos = .ok (v, p) → v.FloatsOk
  | 0, _, _, _, _, h => by simp [readValue] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readValue] at h
    split at h
    · cases h
    · repeat' (first
        | exact readObject_floats fuel s _ h
        | exact readArray_floats fuel s _ h
        | exact map_str_floats h
        | (rw [keyword_ok h]; rfl)
        | exact floatsOk_of_floatOk (readNumber_scalar h) (readNumber_floatOk h)
        | cases h
        | split at h)

theorem readObject_floats : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readObject fuel s pos = .ok (v, p) → v.FloatsOk
  | 0, _, _, _, _, h => by simp [readObject] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readObject] at h
    repeat' (first
      | exact readEntries_floats fuel s _ [] (by simp) h
      | (cases h; trivial)
      | cases h
      | split at h)

theorem readEntries_floats : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat)
    (acc : List (String × JVal)), (∀ kv ∈ acc, kv.2.FloatsOk) →
    ∀ {v : JVal} {p : Nat}, readEntries fuel s pos acc = .ok (v, p) → v.FloatsOk
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
        have hc := readValue_floats fuel s _ hr
        have hacc' : ∀ kv ∈ acc ++ [(k.1, r.1)], kv.2.FloatsOk := by
          intro kv hkv
          simp only [List.mem_append, List.mem_singleton] at hkv
          rcases hkv with hkv | rfl
          · exact hacc kv hkv
          · exact hc
        repeat' (first
          | (cases h; exact sortEntries_floatsOk hacc')
          | exact readEntries_floats fuel s _ _ hacc' h
          | cases h
          | split at h)

theorem readArray_floats : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {p : Nat},
    readArray fuel s pos = .ok (v, p) → v.FloatsOk
  | 0, _, _, _, _, h => by simp [readArray] at h
  | fuel + 1, s, pos, v, p, h => by
    simp only [readArray] at h
    repeat' (first
      | exact readItems_floats fuel s _ [] (by simp) h
      | (cases h; trivial)
      | cases h
      | split at h)

theorem readItems_floats : ∀ (fuel : Nat) (s : ByteArray) (pos : Nat) (acc : List JVal),
    (∀ x ∈ acc, x.FloatsOk) → ∀ {v : JVal} {p : Nat},
    readItems fuel s pos acc = .ok (v, p) → v.FloatsOk
  | 0, _, _, _, _, _, _, h => by simp [readItems] at h
  | fuel + 1, s, pos, acc, hacc, v, p, h => by
    simp only [readItems, bind, Except.bind] at h
    cases hr : readValue fuel s pos with
    | error _ => simp [hr] at h
    | ok r =>
      simp only [hr] at h
      have hc := readValue_floats fuel s pos hr
      have hacc' : ∀ x ∈ acc ++ [r.1], x.FloatsOk := by
        intro x hx
        simp only [List.mem_append, List.mem_singleton] at hx
        rcases hx with hx | rfl
        · exact hacc x hx
        · exact hc
      repeat' (first
        | (cases h; exact floatsOkList_iff.2 hacc')
        | exact readItems_floats fuel s _ _ hacc' h
        | cases h
        | split at h)
end

/-- Main theorem: every float `parse` returns rounds to a finite double; by
`finiteDouble_iff` its magnitude stays below `overflowBound`. -/
theorem parse_floatsOk {s : ByteArray} {v : JVal} (h : parse s = .ok v) : v.FloatsOk := by
  unfold parse at h
  simp only [bind, Except.bind] at h
  repeat' (first | cases h | split at h)
  rename_i r hr _
  exact readValue_floats _ s _ hr

end KomkiSpec.Json
