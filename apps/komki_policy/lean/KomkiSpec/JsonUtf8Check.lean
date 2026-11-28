import KomkiSpec.JsonUtf8

/-!
# `invalid_utf8` comes from a byte only

`readString` checks raw multi-byte sequences with `utf8Len` (the table of
`utf8_seq/2`) and at the closing quote once more with `String.fromUTF8?`,
which `json.ex` does not have. `parse_invalid_utf8`: that second check never
decides; `parse` answers `invalid_utf8` only because some byte fails
`utf8Len` (`BadByte`). The proof carries the invariant that the accumulator
is valid UTF-8 (`Valid`): every `\u` escape appends a scalar value
(`utf8_char`, `hex4?_lt`), every raw sequence the encoding of a `Char`
(`utf8Len_wf`). `surrogate_answers` pins the surrogate escapes and their
error code by computation.
-/

namespace KomkiSpec.Json

/-- `utf8` writes the encoding of the `Char` with that code point. -/
theorem utf8_char {c : Char} {cp : Nat} (hc : c.val.toNat = cp) :
    (utf8 cp).toList = String.utf8EncodeChar c := by
  have hv : cp < 0xD800 ∨ (0xDFFF < cp ∧ cp < 0x110000) := by
    have := c.valid; simp only [UInt32.isValidChar, Nat.isValidChar] at this; omega
  unfold utf8
  by_cases h1 : cp < 0x80
  · simp only [h1, ↓reduceIte, String.utf8EncodeChar, hc, show cp ≤ 0x7f by omega]
  by_cases h2 : cp < 0x800
  · simp only [h1, h2, ↓reduceIte]
    rw [enc2 hc (by omega) (by omega)]
    simp only [List.cons.injEq, and_true]
    constructor <;> rw [← UInt8.toNat_inj] <;> simp [Nat.toUInt8] <;> omega
  by_cases h3 : cp < 0x10000
  · simp only [h1, h2, h3, ↓reduceIte]
    rw [enc3 hc (by omega) (by omega)]
    simp only [List.cons.injEq, and_true]
    refine ⟨?_, ?_, ?_⟩ <;> rw [← UInt8.toNat_inj] <;> simp [Nat.toUInt8] <;> omega
  · simp only [h1, h2, h3, ↓reduceIte]
    rw [enc4 hc (by omega)]
    simp only [List.cons.injEq, and_true]
    refine ⟨?_, ?_, ?_, ?_⟩ <;> rw [← UInt8.toNat_inj] <;> simp [Nat.toUInt8] <;> omega

theorem hexValue_lt_fin : ∀ b : Fin 256, isHex (UInt8.ofFin b) = true →
    hexValue (UInt8.ofFin b) < 16 := by
  decide +kernel

theorem hexValue_lt {b : UInt8} (h : isHex b = true) : hexValue b < 16 :=
  hexValue_lt_fin b.toFin h

theorem hex4?_lt {s : ByteArray} {pos h : Nat} (hh : hex4? s pos = some (some h)) :
    h < 0x10000 := by
  unfold hex4? at hh
  split at hh
  · cases hh
  · simp only [Option.some.injEq] at hh
    split at hh
    · next hall =>
      cases hh
      simp only [show List.range 4 = [0, 1, 2, 3] by decide, List.map_cons, List.map_nil,
        List.all_cons, List.all_nil, Bool.and_true, Bool.and_eq_true] at hall ⊢
      simp only [List.foldl_cons, List.foldl_nil]
      have := hexValue_lt hall.1
      have := hexValue_lt hall.2.1
      have := hexValue_lt hall.2.2.1
      have := hexValue_lt hall.2.2.2
      omega
    · cases hh

/-- `readString`'s accumulator is valid UTF-8. -/
def Valid (acc : Array UInt8) : Prop := (ByteArray.mk acc).IsValidUTF8

theorem Valid.chars {acc : Array UInt8} (h : Valid acc) (cs : List Char) :
    Valid (acc ++ (cs.flatMap String.utf8EncodeChar).toArray) := by
  obtain ⟨m, hm⟩ := h
  have hd := congrArg ByteArray.data hm
  simp only [List.utf8Encode, List.data_toByteArray] at hd
  exact .intro (m ++ cs) (ByteArray.ext (by simp [List.utf8Encode, hd]))

theorem Valid.char {acc : Array UInt8} (h : Valid acc) (c : Char) :
    Valid (acc ++ (String.utf8EncodeChar c).toArray) := by
  simpa using h.chars [c]

theorem Valid.push {acc : Array UInt8} (h : Valid acc) {b : UInt8} (hb : b < 0x80) :
    Valid (acc.push b) := by
  have hb' : b.toNat < 0x80 := hb
  obtain ⟨c, hc⟩ := char_of b.toNat (by omega)
  have e := utf8EncodeChar_ascii (c := c) (by simp only [Char.toNat]; omega)
  have := h.char c
  rw [e, show UInt8.ofNat c.toNat = b by simp only [Char.toNat, hc]; exact UInt8.ofNat_toNat]
    at this
  simpa using this

theorem Valid.utf8 {acc : Array UInt8} (h : Valid acc) {cp : Nat}
    (hv : cp < 0xD800 ∨ (0xDFFF < cp ∧ cp < 0x110000)) : Valid (acc ++ utf8 cp) := by
  obtain ⟨c, hc⟩ := char_of cp hv
  have := h.char c
  rwa [← utf8_char hc, Array.toArray_toList] at this

theorem Valid.extract {acc : Array UInt8} (h : Valid acc) {s : ByteArray} {pos n : Nat}
    (hw : Wf s pos (pos + n)) : Valid (acc ++ (s.extract pos (pos + n)).data) := by
  obtain ⟨cs, hat, hlen⟩ := hw
  have he := At_extract hat
  rw [show pos + (cs.flatMap String.utf8EncodeChar).length = pos + n by omega] at he
  rw [he]
  exact h.chars cs

theorem simpleEscape_out {e c : UInt8} (h : simpleEscape e = some c) : c < 0x80 := by
  unfold simpleEscape at h
  repeat' split at h
  all_goals cases h
  all_goals first
    | decide
    | (rename_i hc
       simp only [Bool.or_eq_true, beq_iff_eq, ← UInt8.toNat_inj, UInt8.lt_iff_toNat_lt,
         UInt8.reduceToNat] at hc ⊢
       omega)

/-- `readString` answers `invalid_utf8` only at a byte `utf8Len` rejects,
never from the closing `String.fromUTF8?` check. -/
theorem readString_invalid_utf8 : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : Array UInt8),
    Valid acc → readString f s pos acc = .error "invalid_utf8" →
      ∃ p b, pos ≤ p ∧ at? s p = some b ∧ 0x80 ≤ b.toNat ∧ utf8Len s p b = none
  | 0, _, _, _, _, h => by simp [readString] at h
  | f + 1, s, pos, acc, hv, h => by
    rw [readString] at h
    split at h
    · simp at h
    · next b hb =>
      split at h
      · have hs : String.fromUTF8? (ByteArray.mk acc) = some (String.fromUTF8 _ hv) := by
          simp [String.fromUTF8?, show (ByteArray.mk acc).IsValidUTF8 from hv]
        rw [hs] at h
        simp at h
      split at h
      · split at h
        · simp at h
        · split at h
          · split at h
            · simp at h
            · simp at h
            · next high hh =>
              dsimp only at h
              split at h
              · next hhi =>
                split at h
                · next low hl =>
                  split at h
                  · next hlo =>
                    simp only [Bool.and_eq_true, decide_eq_true_eq] at hhi hlo
                    obtain ⟨p, b', hp, hrest⟩ := readString_invalid_utf8 f s _ _
                      (hv.utf8 (by omega)) h
                    exact ⟨p, b', by omega, hrest⟩
                  · simp at h
                · simp at h
              · split at h
                · simp at h
                · next hhi hlo =>
                  simp only [Bool.and_eq_true, decide_eq_true_eq, not_and] at hhi hlo
                  have := hex4?_lt hh
                  obtain ⟨p, b', hp, hrest⟩ := readString_invalid_utf8 f s _ _
                    (hv.utf8 (by omega)) h
                  exact ⟨p, b', by omega, hrest⟩
          · split at h
            · next c hc =>
              obtain ⟨p, b', hp, hrest⟩ := readString_invalid_utf8 f s _ _
                (hv.push (simpleEscape_out hc)) h
              exact ⟨p, b', by omega, hrest⟩
            · simp at h
      split at h
      · simp at h
      split at h
      · next hlt =>
        obtain ⟨p, b', hp, hrest⟩ := readString_invalid_utf8 f s _ _ (hv.push hlt) h
        exact ⟨p, b', by omega, hrest⟩
      · next hnlt =>
        split at h
        · next n hn =>
          obtain ⟨p, b', hp, hrest⟩ := readString_invalid_utf8 f s _ _
            (hv.extract (utf8Len_wf hb hn)) h
          exact ⟨p, b', by omega, hrest⟩
        · next hn =>
          have : ¬ b.toNat < 0x80 := hnlt
          exact ⟨pos, b, Nat.le_refl _, hb, by omega, hn⟩

/-- A byte at which `utf8Len` fails, the cause of `invalid_utf8`. -/
def BadByte (s : ByteArray) : Prop :=
  ∃ p b, at? s p = some b ∧ 0x80 ≤ b.toNat ∧ utf8Len s p b = none

/-- `r` answers `invalid_utf8` only because of a `BadByte`. -/
def ByByte {α : Type} (s : ByteArray) (r : Except String α) : Prop :=
  r = .error "invalid_utf8" → BadByte s

theorem byByte_error {α : Type} {s : ByteArray} {e : String} (h : e ≠ "invalid_utf8") :
    ByByte s (.error e : Except String α) :=
  fun x => absurd (by cases x; rfl) h

theorem byByte_ok {α : Type} {s : ByteArray} {a : α} : ByByte s (.ok a : Except String α) :=
  fun x => by cases x

theorem readString_byByte {f : Nat} {s : ByteArray} {pos : Nat} :
    ByByte s (readString f s pos #[]) := fun h => by
  obtain ⟨p, b, -, hrest⟩ := readString_invalid_utf8 f s pos #[] (.intro [] rfl) h
  exact ⟨p, b, hrest⟩

theorem keyword_byByte {s : ByteArray} {pos : Nat} {kw : String} {v : JVal} :
    ByByte s (keyword s pos kw v) := by
  unfold keyword
  dsimp only
  repeat' split
  all_goals first | exact byByte_ok | exact byByte_error (by decide)

theorem readNumber_byByte {s : ByteArray} {pos : Nat} : ByByte s (readNumber s pos) := by
  unfold readNumber
  dsimp only
  repeat' split
  all_goals first | exact byByte_ok | exact byByte_error (by decide)

theorem byByte_bind {α β : Type} {s : ByteArray} {r : Except String α}
    {k : α → Except String β} (hr : ByByte s r) (hk : ∀ a, r = .ok a → ByByte s (k a)) :
    ByByte s (r >>= k) := by
  cases h : r with
  | error e => intro x; exact hr (by rw [h]; simpa [bind, Except.bind] using x)
  | ok a => simpa [bind, Except.bind] using hk a h

mutual
theorem readValue_byByte : ∀ (f : Nat) (s : ByteArray) (pos : Nat), ByByte s (readValue f s pos)
  | 0, _, _ => by rw [readValue]; exact byByte_error (by decide)
  | f + 1, s, pos => by
    rw [readValue]
    split
    · exact byByte_error (by decide)
    split
    · exact readObject_byByte f s _
    split
    · exact readArray_byByte f s _
    split
    · intro x
      cases hr : readString f s (pos + 1) #[] with
      | error e => rw [hr] at x; exact readString_byByte (by rw [hr]; simpa [Except.map] using x)
      | ok r => rw [hr] at x; simp [Except.map] at x
    split
    · exact keyword_byByte
    split
    · exact keyword_byByte
    split
    · exact keyword_byByte
    split
    · exact readNumber_byByte
    split
    · exact byByte_error (by decide)
    · exact byByte_error (by decide)

theorem readObject_byByte : ∀ (f : Nat) (s : ByteArray) (pos : Nat), ByByte s (readObject f s pos)
  | 0, _, _ => by rw [readObject]; exact byByte_error (by decide)
  | f + 1, s, pos => by
    rw [readObject]
    repeat' split
    all_goals first
      | exact byByte_ok
      | exact byByte_error (by decide)
      | exact readEntries_byByte f s _ _

theorem readEntries_byByte : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : List (String × JVal)),
    ByByte s (readEntries f s pos acc)
  | 0, _, _, _ => by rw [readEntries]; exact byByte_error (by decide)
  | f + 1, s, pos, acc => by
    rw [readEntries]
    refine byByte_bind readString_byByte fun _ _ => ?_
    dsimp only
    split
    · exact byByte_error (by decide)
    split
    · exact byByte_error (by decide)
    refine byByte_bind (readValue_byByte f s _) fun _ _ => ?_
    repeat' split
    all_goals first
      | exact byByte_ok
      | exact byByte_error (by decide)
      | exact readEntries_byByte f s _ _

theorem readArray_byByte : ∀ (f : Nat) (s : ByteArray) (pos : Nat), ByByte s (readArray f s pos)
  | 0, _, _ => by rw [readArray]; exact byByte_error (by decide)
  | f + 1, s, pos => by
    rw [readArray]
    repeat' split
    all_goals first
      | exact byByte_ok
      | exact byByte_error (by decide)
      | exact readItems_byByte f s _ _

theorem readItems_byByte : ∀ (f : Nat) (s : ByteArray) (pos : Nat) (acc : List JVal),
    ByByte s (readItems f s pos acc)
  | 0, _, _, _ => by rw [readItems]; exact byByte_error (by decide)
  | f + 1, s, pos, acc => by
    rw [readItems]
    refine byByte_bind (readValue_byByte f s _) fun _ _ => ?_
    dsimp only
    repeat' split
    all_goals first
      | exact byByte_ok
      | exact byByte_error (by decide)
      | exact readItems_byByte f s _ _
end

/-- Main theorem: `parse` answers `invalid_utf8` only because some byte of a
string fails `utf8Len`, the table of `utf8_seq/2`; never because of the
`String.fromUTF8?` check Elixir does not have. -/
theorem parse_invalid_utf8 {s : ByteArray} (h : parse s = .error "invalid_utf8") : BadByte s := by
  unfold parse at h
  simp only at h
  split at h
  · simp at h
  · refine byByte_bind (readValue_byByte _ s _) (fun _ _ => ?_) h
    split
    · exact byByte_error (by decide)
    · exact byByte_ok

/-- A parse answer as text: the string read, or the error code. -/
def answer (s : String) : String :=
  match parse s.toUTF8 with
  | .ok (.str t) => "ok " ++ t
  | .ok _ => "ok"
  | .error e => e

/-- Surrogate escapes: only a high one followed by a low one reads, as the
scalar both encode; every other combination is `invalid_string`, the code
`json.ex` reports (`require_low_surrogate/5`). The kernel computes it. -/
theorem surrogate_answers :
    answer "\"\\ud800\"" = "invalid_string" ∧
    answer "\"\\udc00\"" = "invalid_string" ∧
    answer "\"\\ud800\\u0041\"" = "invalid_string" ∧
    answer "\"\\ud800\\ud800\"" = "invalid_string" ∧
    answer "\"\\ud800\\udc00\"" = "ok " ++ (Char.ofNat 0x10000).toString ∧
    answer "\"\\udbff\\udfff\"" = "ok " ++ (Char.ofNat 0x10FFFF).toString := by
  decide +kernel

end KomkiSpec.Json
