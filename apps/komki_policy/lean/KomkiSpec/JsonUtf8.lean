import KomkiSpec.JsonRoundtrip

/-!
# The parser accepts well-formed UTF-8 only

`parse_validUTF8`: every input `parse` accepts is valid UTF-8 as a whole,
in the sense of Lean's own `ByteArray.IsValidUTF8` (the bytes are the
encoding of some list of `Char`s). That rules out overlong forms, encoded
surrogates, code points above U+10FFFF, cut-off sequences and stray
continuation bytes, inside strings and outside.

The proof follows the readers: each one, on success, has consumed bytes that
encode some characters (`Wf`). Outside strings and in escapes those are
ASCII (`skipWs_wf`, `numberEnd_wf`, `keyword_wf`, `hex4?_wf`); a multi-byte
sequence passes `utf8Len` only if it is the encoding of a `Char`
(`utf8Len_wf`, via `String.utf8EncodeChar`). The specification is the
library's, not `utf8Len` itself. Error codes and the pairing of surrogates
in `\u` escapes stay with the differential test.

The proof does not use the `String.fromUTF8?` check at the end of
`readString`; `utf8Len_wf` is the step that carries over to `utf8_seq/2`.
-/

namespace KomkiSpec.Json

/-- The bytes from `a` up to `b` are the UTF-8 encoding of some characters. -/
def Wf (s : ByteArray) (a b : Nat) : Prop :=
  ∃ cs : List Char, At s a (cs.flatMap String.utf8EncodeChar) ∧
    a + (cs.flatMap String.utf8EncodeChar).length = b

theorem Wf.refl (s : ByteArray) (a : Nat) : Wf s a a := ⟨[], by simp [At]⟩

theorem Wf.trans {s : ByteArray} {a b c : Nat} (h1 : Wf s a b) (h2 : Wf s b c) : Wf s a c := by
  obtain ⟨xs, hx, rfl⟩ := h1
  obtain ⟨ys, hy, rfl⟩ := h2
  exact ⟨xs ++ ys, by simp only [List.flatMap_append, At_append]; exact ⟨hx, hy⟩,
    by simp [Nat.add_assoc]⟩

theorem Wf.char {s : ByteArray} {a : Nat} (c : Char) (h : At s a (String.utf8EncodeChar c)) :
    Wf s a (a + (String.utf8EncodeChar c).length) :=
  ⟨[c], by simpa using h, by simp⟩

theorem char_of (v : Nat) (h : v < 0xD800 ∨ (0xDFFF < v ∧ v < 0x110000)) :
    ∃ c : Char, c.val.toNat = v := by
  have hv : v.isValidChar := h
  exact ⟨Char.ofNat v, by simp [Char.ofNat, hv, Char.ofNatAux, UInt32.toNat_ofNatLT]⟩

theorem Wf.ascii {s : ByteArray} {a : Nat} {b : UInt8} (h : at? s a = some b) (hb : b < 0x80) :
    Wf s a (a + 1) := by
  have hb' : b.toNat < 0x80 := hb
  obtain ⟨c, hc⟩ := char_of b.toNat (by omega)
  have e := utf8EncodeChar_ascii (c := c) (by simp only [Char.toNat]; omega)
  have := Wf.char c (s := s) (a := a) (by
    rw [e]; refine ⟨?_, trivial⟩
    rw [h]; congr 1; simp only [Char.toNat, hc]; exact (UInt8.ofNat_toNat).symm)
  simpa [e] using this

/-- `utf8Len`'s check of the byte at `k + i`. -/
def cont (s : ByteArray) (k i : Nat) (lo hi : UInt8) : Bool :=
  match at? s (k + i) with
  | some b => inRange b lo hi
  | none => false

/-- `utf8Len` with its local check lifted out to `cont`; must match `Json.lean`
line for line (`rfl`). -/
theorem utf8Len_eq (s : ByteArray) (k : Nat) (b : UInt8) : utf8Len s k b =
    if inRange b 0xC2 0xDF && cont s k 1 0x80 0xBF then some 2
    else if (inRange b 0xE1 0xEC || inRange b 0xEE 0xEF) && cont s k 1 0x80 0xBF &&
        cont s k 2 0x80 0xBF then some 3
    else if b == 0xE0 && cont s k 1 0xA0 0xBF && cont s k 2 0x80 0xBF then some 3
    else if b == 0xED && cont s k 1 0x80 0x9F && cont s k 2 0x80 0xBF then some 3
    else if b == 0xF0 && cont s k 1 0x90 0xBF && cont s k 2 0x80 0xBF &&
        cont s k 3 0x80 0xBF then some 4
    else if inRange b 0xF1 0xF3 && cont s k 1 0x80 0xBF && cont s k 2 0x80 0xBF &&
        cont s k 3 0x80 0xBF then some 4
    else if b == 0xF4 && cont s k 1 0x80 0x8F && cont s k 2 0x80 0xBF &&
        cont s k 3 0x80 0xBF then some 4
    else none := rfl

theorem cont_at {s : ByteArray} {k i : Nat} {lo hi : UInt8} (h : cont s k i lo hi = true) :
    ∃ x, at? s (k + i) = some x ∧ lo.toNat ≤ x.toNat ∧ x.toNat ≤ hi.toNat := by
  unfold cont at h
  split at h
  · next x hx =>
    simp only [inRange_toNat, Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨x, hx, h⟩
  · cases h

theorem ofNat_eq {b : UInt8} {n : Nat} (h : n % 256 = b.toNat) : UInt8.ofNat n = b := by
  rw [← UInt8.toNat_inj, UInt8.toNat_ofNat']; exact h

theorem enc2 {c : Char} {v : Nat} (hc : c.val.toNat = v) (h1 : 0x7f < v) (h2 : v ≤ 0x7ff) :
    String.utf8EncodeChar c = [UInt8.ofNat (v / 64 % 32 + 0xc0), UInt8.ofNat (v % 64 + 0x80)] := by
  simp only [String.utf8EncodeChar, hc, show ¬ v ≤ 0x7f by omega, show v ≤ 0x7ff by omega,
    ite_true, ite_false]

theorem enc3 {c : Char} {v : Nat} (hc : c.val.toNat = v) (h1 : 0x7ff < v) (h2 : v ≤ 0xffff) :
    String.utf8EncodeChar c = [UInt8.ofNat (v / 4096 % 16 + 0xe0),
      UInt8.ofNat (v / 64 % 64 + 0x80), UInt8.ofNat (v % 64 + 0x80)] := by
  simp only [String.utf8EncodeChar, hc, show ¬ v ≤ 0x7f by omega, show ¬ v ≤ 0x7ff by omega,
    show v ≤ 0xffff by omega, ite_true, ite_false]

theorem enc4 {c : Char} {v : Nat} (hc : c.val.toNat = v) (h1 : 0xffff < v) :
    String.utf8EncodeChar c = [UInt8.ofNat (v / 262144 % 8 + 0xf0),
      UInt8.ofNat (v / 4096 % 64 + 0x80), UInt8.ofNat (v / 64 % 64 + 0x80),
      UInt8.ofNat (v % 64 + 0x80)] := by
  simp only [String.utf8EncodeChar, hc, show ¬ v ≤ 0x7f by omega, show ¬ v ≤ 0x7ff by omega,
    show ¬ v ≤ 0xffff by omega, ite_false]

/-- Two bytes `C2–DF 80–BF`: U+0080 to U+07FF. -/
theorem wf2 {s : ByteArray} {k : Nat} {b x : UInt8} (hb : at? s k = some b)
    (hx : at? s (k + 1) = some x) (b1 : 0xC2 ≤ b.toNat) (b2 : b.toNat ≤ 0xDF)
    (x1 : 0x80 ≤ x.toNat) (x2 : x.toNat ≤ 0xBF) : Wf s k (k + 2) := by
  obtain ⟨c, hc⟩ := char_of ((b.toNat - 0xC0) * 64 + (x.toNat - 0x80)) (by omega)
  have he := enc2 hc (by omega) (by omega)
  have := Wf.char c (s := s) (a := k) (by
    rw [he, ofNat_eq (b := b) (by omega), ofNat_eq (b := x) (by omega)]
    exact ⟨hb, hx, trivial⟩)
  rwa [he] at this

/-- Three bytes `E0–EF` and two continuation bytes whose value is a scalar
of three bytes: U+0800 to U+FFFF without the surrogates. -/
theorem wf3 {s : ByteArray} {k : Nat} {b x y : UInt8} (hb : at? s k = some b)
    (hx : at? s (k + 1) = some x) (hy : at? s (k + 2) = some y)
    (b1 : 0xE0 ≤ b.toNat) (b2 : b.toNat ≤ 0xEF) (x1 : 0x80 ≤ x.toNat) (x2 : x.toNat ≤ 0xBF)
    (y1 : 0x80 ≤ y.toNat) (y2 : y.toNat ≤ 0xBF)
    (hv : let v := (b.toNat - 0xE0) * 4096 + (x.toNat - 0x80) * 64 + (y.toNat - 0x80)
      0x800 ≤ v ∧ (v < 0xD800 ∨ 0xDFFF < v)) : Wf s k (k + 3) := by
  dsimp only at hv
  obtain ⟨c, hc⟩ := char_of ((b.toNat - 0xE0) * 4096 + (x.toNat - 0x80) * 64 +
    (y.toNat - 0x80)) (by omega)
  have he := enc3 hc (by omega) (by omega)
  have := Wf.char c (s := s) (a := k) (by
    rw [he, ofNat_eq (b := b) (by omega), ofNat_eq (b := x) (by omega),
      ofNat_eq (b := y) (by omega)]
    exact ⟨hb, hx, hy, trivial⟩)
  rwa [he] at this

/-- Four bytes `F0–F4` and three continuation bytes whose value is a scalar
of four bytes: U+10000 to U+10FFFF. -/
theorem wf4 {s : ByteArray} {k : Nat} {b x y z : UInt8} (hb : at? s k = some b)
    (hx : at? s (k + 1) = some x) (hy : at? s (k + 2) = some y) (hz : at? s (k + 3) = some z)
    (b1 : 0xF0 ≤ b.toNat) (b2 : b.toNat ≤ 0xF4) (x1 : 0x80 ≤ x.toNat) (x2 : x.toNat ≤ 0xBF)
    (y1 : 0x80 ≤ y.toNat) (y2 : y.toNat ≤ 0xBF) (z1 : 0x80 ≤ z.toNat) (z2 : z.toNat ≤ 0xBF)
    (hv : let v := (b.toNat - 0xF0) * 262144 + (x.toNat - 0x80) * 4096 +
        (y.toNat - 0x80) * 64 + (z.toNat - 0x80)
      0x10000 ≤ v ∧ v < 0x110000) : Wf s k (k + 4) := by
  dsimp only at hv
  obtain ⟨c, hc⟩ := char_of ((b.toNat - 0xF0) * 262144 + (x.toNat - 0x80) * 4096 +
    (y.toNat - 0x80) * 64 + (z.toNat - 0x80)) (by omega)
  have he := enc4 hc (by omega)
  have := Wf.char c (s := s) (a := k) (by
    rw [he, ofNat_eq (b := b) (by omega), ofNat_eq (b := x) (by omega),
      ofNat_eq (b := y) (by omega), ofNat_eq (b := z) (by omega)]
    exact ⟨hb, hx, hy, hz, trivial⟩)
  rwa [he] at this

/-- A sequence `utf8Len` accepts is the encoding of one `Char`. -/
theorem utf8Len_wf {s : ByteArray} {k : Nat} {b : UInt8} {n : Nat}
    (hb : at? s k = some b) (h : utf8Len s k b = some n) : Wf s k (k + n) := by
  rw [utf8Len_eq] at h
  have hb' := b.toNat_lt
  repeat' split at h
  all_goals cases h
  all_goals
    rename_i hc
    simp only [Bool.and_eq_true, Bool.or_eq_true, inRange_toNat, decide_eq_true_eq, beq_iff_eq,
      ← UInt8.toNat_inj, UInt8.reduceToNat] at hc
  · obtain ⟨⟨b1, b2⟩, h1⟩ := hc
    obtain ⟨x, hx, x1, x2⟩ := cont_at h1
    simp only [UInt8.reduceToNat] at *
    exact wf2 hb hx b1 b2 x1 x2
  all_goals first
    | (obtain ⟨⟨hl, h1⟩, h2⟩ := hc
       obtain ⟨x, hx, x1, x2⟩ := cont_at h1
       obtain ⟨y, hy, y1, y2⟩ := cont_at h2
       simp only [UInt8.reduceToNat] at *
       exact wf3 hb hx hy (by omega) (by omega) (by omega) (by omega) y1 y2
         (by dsimp only; omega))
    | (obtain ⟨⟨⟨hl, h1⟩, h2⟩, h3⟩ := hc
       obtain ⟨x, hx, x1, x2⟩ := cont_at h1
       obtain ⟨y, hy, y1, y2⟩ := cont_at h2
       obtain ⟨z, hz, z1, z2⟩ := cont_at h3
       simp only [UInt8.reduceToNat] at *
       exact wf4 hb hx hy hz (by omega) (by omega) (by omega) (by omega) y1 y2 z1 z2
         (by dsimp only; omega))

theorem at?_get! {s : ByteArray} {k : Nat} (h : k < s.size) : at? s k = some (s.get! k) := by
  unfold at?; simp [h, ByteArray.get!]; rfl

/-- A run of ASCII bytes is well-formed. -/
theorem Wf.ascii_run {s : ByteArray} : ∀ (n a : Nat),
    (∀ i, i < n → ∃ x, at? s (a + i) = some x ∧ x < 0x80) → Wf s a (a + n)
  | 0, a, _ => Wf.refl s a
  | n + 1, a, h => by
    obtain ⟨x, hx, hl⟩ := h 0 (by omega)
    have := Wf.ascii_run n (a + 1) (fun i hi => by
      obtain ⟨y, hy, hl'⟩ := h (i + 1) (by omega)
      exact ⟨y, by rw [Nat.add_assoc, Nat.add_comm 1]; exact hy, hl'⟩)
    exact (Wf.ascii hx hl).trans (by rw [Nat.add_assoc, Nat.add_comm 1] at this; exact this)

theorem skipWs_wf (s : ByteArray) (pos : Nat) : Wf s pos (skipWs s pos) := by
  rw [skipWs]
  split
  · next hp =>
    split
    · next hw =>
      refine (Wf.ascii (b := s[pos]) (by simp [at?, hp]) ?_).trans (skipWs_wf s (pos + 1))
      simp only [isWs, Bool.or_eq_true, beq_iff_eq] at hw
      rcases hw with ((h | h) | h) | h <;> rw [h] <;> decide
    · exact Wf.refl s pos
  · exact Wf.refl s pos
termination_by s.size - pos

theorem numberEnd_wf (s : ByteArray) (pos : Nat) : Wf s pos (numberEnd s pos) := by
  rw [numberEnd]
  split
  · next hp =>
    split
    · next hw =>
      refine (Wf.ascii (b := s[pos]) (by simp [at?, hp]) ?_).trans (numberEnd_wf s (pos + 1))
      simp only [isNumberByte, isDigit, inRange, Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true,
        decide_eq_true_eq] at hw
      simp only [UInt8.lt_iff_toNat_lt, UInt8.le_iff_toNat_le] at hw ⊢
      rcases hw with ((((h | h) | h) | h) | h) | h
      · simp only [UInt8.reduceToNat] at h ⊢; omega
      all_goals rw [h]; decide
    · exact Wf.refl s pos
  · exact Wf.refl s pos
termination_by s.size - pos

theorem keyword_wf {s : ByteArray} {pos : Nat} {kw : String} {v w : JVal} {q : Nat}
    (hk : ∀ i, i < kw.toUTF8.size → kw.toUTF8.get! i < 0x80)
    (h : keyword s pos kw v = .ok (w, q)) : Wf s pos q := by
  unfold keyword at h
  dsimp only at h
  split at h
  · next hc =>
    simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true, List.mem_range,
      beq_iff_eq] at hc
    have hq : q = pos + kw.toUTF8.size := by
      repeat' split at h
      all_goals first | (cases h; rfl) | cases h
    rw [hq]
    refine Wf.ascii_run _ _ (fun i hi => ⟨s.get! (pos + i), at?_get! (by omega), ?_⟩)
    rw [hc.2 i hi]; exact hk i hi
  · cases h

theorem kw_ascii : ∀ kw ∈ ["null", "true", "false"],
    ∀ i, i < kw.toUTF8.size → kw.toUTF8.get! i < 0x80 := by
  decide +kernel

theorem isHex_ascii {b : UInt8} (h : isHex b = true) : b < 0x80 := by
  simp only [isHex, isDigit, inRange, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq,
    UInt8.le_iff_toNat_le, UInt8.lt_iff_toNat_lt, UInt8.reduceToNat] at h ⊢
  omega

theorem hex4?_wf {s : ByteArray} {pos h : Nat} (hh : hex4? s pos = some (some h)) :
    Wf s pos (pos + 4) := by
  unfold hex4? at hh
  split at hh
  · cases hh
  · next hs =>
    simp only [Option.some.injEq] at hh
    split at hh
    · next hall =>
      simp only [List.all_eq_true, List.mem_map, List.mem_range, forall_exists_index, and_imp,
        forall_apply_eq_imp_iff₂] at hall
      exact Wf.ascii_run 4 pos (fun i hi =>
        ⟨s.get! (pos + i), at?_get! (by omega), isHex_ascii (hall i hi)⟩)
    · cases hh

theorem simpleEscape_ascii {e c : UInt8} (h : simpleEscape e = some c) : e < 0x80 := by
  unfold simpleEscape at h
  repeat' split at h
  all_goals cases h
  all_goals
    rename_i hc
    simp only [Bool.or_eq_true, beq_iff_eq, ← UInt8.toNat_inj, UInt8.lt_iff_toNat_lt,
      UInt8.reduceToNat] at hc ⊢
    omega

theorem Wf.byte {s : ByteArray} {k : Nat} {b c : UInt8} (h : at? s k = some b)
    (hb : (b == c) = true) (hc : c < 0x80) : Wf s k (k + 1) :=
  Wf.ascii h (by rw [beq_iff_eq.1 hb]; exact hc)

theorem readString_wf : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : Array UInt8)
    {str : String} {q : Nat}, readString f s pos acc = .ok (str, q) → Wf s pos q
  | 0, _, _, _, _, _, h => by simp [readString] at h
  | f + 1, s, pos, acc, str, q, h => by
    rw [readString] at h
    split at h
    · cases h
    · next b hb =>
      split at h
      · next hq =>
        split at h
        · cases h; exact Wf.byte hb hq (by decide)
        · cases h
      split at h
      · next hbs =>
        have w0 := Wf.byte hb hbs (by decide)
        split at h
        · cases h
        · next e he =>
          split at h
          · next hu =>
            have w1 := w0.trans (Wf.byte he hu (by decide))
            split at h
            · cases h
            · cases h
            · next high hh =>
              have w6 : Wf s pos (pos + 6) := w1.trans (hex4?_wf hh)
              dsimp only at h
              split at h
              · split at h
                · next low hl =>
                  split at h
                  · split at hl
                    · next hc =>
                      simp only [Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at hc
                      obtain ⟨⟨hn, h5c⟩, h75⟩ := hc
                      have hx : hex4? s (pos + 6 + 2) = some (some low) := by
                        simpa [Option.join_eq_some_iff] using hl
                      have w7 : Wf s (pos + 6) (pos + 6 + 1) :=
                        Wf.ascii (at?_get! (by omega)) (by rw [h5c]; decide)
                      have w8 : Wf s (pos + 6 + 1) (pos + 6 + 2) :=
                        Wf.ascii (at?_get! (by omega)) (by rw [h75]; decide)
                      have w12 := (w6.trans (w7.trans (w8.trans (hex4?_wf hx))))
                      exact w12.trans (by simpa [Nat.add_assoc] using readString_wf f s _ _ h)
                    · cases hl
                  · cases h
                · cases h
              · split at h
                · cases h
                · exact w6.trans (readString_wf f s _ _ h)
          · split at h
            · next c hc =>
              exact (w0.trans (Wf.ascii he (simpleEscape_ascii hc))).trans
                (readString_wf f s _ _ h)
            · cases h
      split at h
      · cases h
      split at h
      · next hlt => exact (Wf.ascii hb hlt).trans (readString_wf f s _ _ h)
      split at h
      · next n hn => exact (utf8Len_wf hb hn).trans (readString_wf f s _ _ h)
      · cases h

theorem readNumber_wf {s : ByteArray} {pos : Nat} {v : JVal} {q : Nat}
    (h : readNumber s pos = .ok (v, q)) : Wf s pos q := by
  have hq : q = numberEnd s pos := by
    unfold readNumber at h
    dsimp only at h
    repeat' split at h
    all_goals first | (cases h; rfl) | cases h
  rw [hq]; exact numberEnd_wf s pos

mutual
theorem readValue_wf : ∀ (f : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {q : Nat},
    readValue f s pos = .ok (v, q) → Wf s pos q
  | 0, _, _, _, _, h => by simp [readValue] at h
  | f + 1, s, pos, v, q, h => by
    rw [readValue] at h
    split at h
    · cases h
    · next b hb =>
      split at h
      · next hc => exact (Wf.byte hb hc (by decide)).trans (readObject_wf f s _ h)
      split at h
      · next hc => exact (Wf.byte hb hc (by decide)).trans (readArray_wf f s _ h)
      split at h
      · next hc =>
        cases hr : readString f s (pos + 1) #[] with
        | error e => rw [hr] at h; cases h
        | ok r =>
          rw [hr] at h
          simp only [Except.map, Except.ok.injEq, Prod.mk.injEq] at h
          obtain ⟨_, rfl⟩ := h
          exact (Wf.byte hb hc (by decide)).trans (readString_wf f s _ _ hr)
      split at h
      · exact keyword_wf (kw_ascii _ (by simp)) h
      split at h
      · exact keyword_wf (kw_ascii _ (by simp)) h
      split at h
      · exact keyword_wf (kw_ascii _ (by simp)) h
      split at h
      · exact readNumber_wf h
      split at h
      · cases h
      · cases h

theorem readObject_wf : ∀ (f : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {q : Nat},
    readObject f s pos = .ok (v, q) → Wf s pos q
  | 0, _, _, _, _, h => by simp [readObject] at h
  | f + 1, s, pos, v, q, h => by
    rw [readObject] at h
    have ww := skipWs_wf s pos
    split at h
    · cases h
    · next b hb =>
      split at h
      · next hc => cases h; exact ww.trans (Wf.byte hb hc (by decide))
      split at h
      · next hc => exact ww.trans (readEntries_wf f s _ [] (Wf.byte hb hc (by decide)) h)
      · cases h

theorem readEntries_wf : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : List (String × JVal))
    {v : JVal} {q : Nat}, Wf s pos (pos + 1) → readEntries f s pos acc = .ok (v, q) → Wf s pos q
  | 0, _, _, _, _, _, _, h => by simp [readEntries] at h
  | f + 1, s, pos, acc, v, q, h0, h => by
    simp only [readEntries, bind, Except.bind] at h
    cases hk : readString f s (pos + 1) #[] with
    | error e => rw [hk] at h; cases h
    | ok kr =>
      obtain ⟨key, kpos⟩ := kr
      rw [hk] at h
      have wk := h0.trans (readString_wf f s _ _ hk)
      dsimp only at h
      have wc := wk.trans (skipWs_wf s kpos)
      split at h
      · cases h
      · next c hc =>
        split at h
        · cases h
        · next hcol =>
          have wc1 := wc.trans (Wf.ascii hc (by simp at hcol; rw [hcol]; decide))
          have wv := wc1.trans (skipWs_wf s (skipWs s kpos + 1))
          cases hv : readValue f s (skipWs s (skipWs s kpos + 1)) with
          | error e => rw [hv] at h; cases h
          | ok r =>
            obtain ⟨v', vpos⟩ := r
            rw [hv] at h
            have wvp := wv.trans (readValue_wf f s _ hv)
            have ww := wvp.trans (skipWs_wf s vpos)
            dsimp only at h
            split at h
            · cases h
            · split at h
              · cases h
              · next b hb =>
                split at h
                · next hc' => cases h; exact ww.trans (Wf.byte hb hc' (by decide))
                split at h
                · next hc' =>
                  have wk2 := (ww.trans (Wf.byte hb hc' (by decide))).trans
                    (skipWs_wf s (skipWs s vpos + 1))
                  split at h
                  · cases h
                  · next n hn =>
                    split at h
                    · cases h
                    split at h
                    · next hq =>
                      exact wk2.trans (readEntries_wf f s _ _ (Wf.byte hn hq (by decide)) h)
                    · cases h
                · cases h

theorem readArray_wf : ∀ (f : Nat) (s : ByteArray) (pos : Nat) {v : JVal} {q : Nat},
    readArray f s pos = .ok (v, q) → Wf s pos q
  | 0, _, _, _, _, h => by simp [readArray] at h
  | f + 1, s, pos, v, q, h => by
    rw [readArray] at h
    have ww := skipWs_wf s pos
    split at h
    · cases h
    · next b hb =>
      split at h
      · next hc => cases h; exact ww.trans (Wf.byte hb hc (by decide))
      split at h
      · cases h
      · exact ww.trans (readItems_wf f s _ [] h)

theorem readItems_wf : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : List JVal)
    {v : JVal} {q : Nat}, readItems f s pos acc = .ok (v, q) → Wf s pos q
  | 0, _, _, _, _, _, h => by simp [readItems] at h
  | f + 1, s, pos, acc, v, q, h => by
    simp only [readItems, bind, Except.bind] at h
    cases hv : readValue f s pos with
    | error e => rw [hv] at h; cases h
    | ok r =>
      obtain ⟨v', vpos⟩ := r
      rw [hv] at h
      have ww := (readValue_wf f s _ hv).trans (skipWs_wf s vpos)
      dsimp only at h
      split at h
      · cases h
      · next b hb =>
        split at h
        · next hc => cases h; exact ww.trans (Wf.byte hb hc (by decide))
        split at h
        · next hc =>
          have wk := (ww.trans (Wf.byte hb hc (by decide))).trans
            (skipWs_wf s (skipWs s vpos + 1))
          split at h
          · cases h
          · split at h
            · cases h
            · exact wk.trans (readItems_wf f s _ _ h)
        · cases h
end

theorem Wf.le_size {s : ByteArray} {a b : Nat} (h : Wf s a b) (hab : a < b) : b ≤ s.size := by
  obtain ⟨cs, hat, rfl⟩ := h
  have := at?_lt (At_get hat ((cs.flatMap String.utf8EncodeChar).length - 1) (by omega))
  omega

/-- Well-formed from the first byte to the last: the input is valid UTF-8 in
the sense of Lean's `ByteArray.IsValidUTF8`. -/
theorem Wf.valid {s : ByteArray} (h : Wf s 0 s.size) : s.IsValidUTF8 := by
  obtain ⟨cs, hat, hlen⟩ := h
  have he := At_extract hat
  rw [Nat.zero_add] at hlen
  rw [hlen, Nat.zero_add, ByteArray.extract_zero_size] at he
  exact .intro cs (ByteArray.ext (by simp [List.utf8Encode, he]))

/-- Main theorem: `parse` accepts only input that is valid UTF-8 as a
whole (RFC 3629): no overlong form, no surrogate, nothing above U+10FFFF, no
cut-off sequence, no stray continuation byte, inside strings or outside. -/
theorem parse_validUTF8 {s : ByteArray} {v : JVal} (h : parse s = .ok v) : s.IsValidUTF8 := by
  unfold parse at h
  simp only [bind, Except.bind] at h
  split at h
  · cases h
  · next hne =>
    cases hv : readValue (4 * s.size + 4) s (skipWs s 0) with
    | error e => rw [hv] at h; cases h
    | ok r =>
      obtain ⟨v', pos⟩ := r
      rw [hv] at h
      dsimp only at h
      split at h
      · cases h
      · next hend =>
        have w := ((skipWs_wf s 0).trans (readValue_wf _ s _ hv)).trans (skipWs_wf s pos)
        have := w.le_size (by omega)
        exact Wf.valid (by rwa [show skipWs s pos = s.size by omega] at w)

end KomkiSpec.Json
