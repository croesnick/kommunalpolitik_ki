import KomkiSpec.JsonParseCanon

/-!
# The parser reads back what the encoder writes

The encoder writes text, the parser reads bytes. This file works on the
UTF-8 bytes of the canonical text (`bytes`) at a position of the input
(`At`) and shows, piece by piece, that the parser reads each piece back.

Strings: `readString_body` reads every escaped body (`escapeChar`) up to its
closing quote and returns the string, for every `Char`: the two-byte
escapes, `\u00XX` for the other control characters, one byte for the rest
of ASCII, and two to four bytes otherwise, which pass the parser's check of
well-formed UTF-8 (`utf8Len_char`, RFC 3629).

Numbers and keywords: `readNumber_int` reads back `toString i` for every
integer, `keyword_At` the literals `true`, `false` and `null`, each followed
by a byte that ends the token (`EndsAt`).

Structure: `readValue_enc`, `readItems_enc` and `readEntries_enc` read back
every encoded value, array body and object body, the layout of
`arr_bytes` and `obj_bytes`, as long as the fuel exceeds the bytes left.
The main theorem `parse_canonical`: for every value with strictly sorted
keys (`JVal.Strict`), `parse` reads its canonical text back to it. With
`parse_strict` the two are inverse on the values the parser returns.
-/

namespace KomkiSpec.Json

/-- The UTF-8 bytes of a string. -/
def bytes (s : String) : List UInt8 := s.toByteArray.data.toList

theorem bytes_append (a b : String) : bytes (a ++ b) = bytes a ++ bytes b := by
  simp [bytes, String.toByteArray_append]

theorem bytes_char (c : Char) : bytes c.toString = String.utf8EncodeChar c := by
  simp [bytes, Char.toString, List.utf8Encode_singleton]

def hexByte (n : Nat) : UInt8 := UInt8.ofNat (hexUpper n).toNat

theorem control_hex : ∀ n : Fin 32,
    bytes (String.ofList [hexUpper (n.val / 16), hexUpper n.val]) =
        [hexByte (n.val / 16), hexByte n.val] ∧
      ([0x30, 0x30, hexByte (n.val / 16), hexByte n.val] : List UInt8).all isHex = true ∧
      ([0x30, 0x30, hexByte (n.val / 16), hexByte n.val] : List UInt8).foldl
        (fun n b => 16 * n + hexValue b) 0 = n.val := by
  decide

def At (s : ByteArray) (pos : Nat) : List UInt8 → Prop
  | [] => True
  | b :: bs => at? s pos = some b ∧ At s (pos + 1) bs

theorem at?_lt {s : ByteArray} {k : Nat} {b : UInt8} (h : at? s k = some b) : k < s.size := by
  unfold at? at h; split at h <;> simp_all

theorem get!_of_at? {s : ByteArray} {k : Nat} {b : UInt8} (h : at? s k = some b) : s.get! k = b := by
  unfold at? at h
  split at h
  · cases h; next hk => simp [ByteArray.get!, hk]; rfl
  · cases h

theorem At_append {s : ByteArray} {pos : Nat} {a b : List UInt8} :
    At s pos (a ++ b) ↔ At s pos a ∧ At s (pos + a.length) b := by
  induction a generalizing pos with
  | nil => simp [At]
  | cons x a ih => simp [At, ih, Nat.add_assoc, Nat.add_comm 1, and_assoc]

theorem At_get {s : ByteArray} {pos : Nat} {bs : List UInt8} (h : At s pos bs) :
    ∀ i (hi : i < bs.length), at? s (pos + i) = some bs[i] := by
  induction bs generalizing pos with
  | nil => intro i hi; simp at hi
  | cons x bs ih =>
    intro i hi
    cases i with
    | zero => exact h.1
    | succ i =>
      have := ih h.2 i (by simpa using hi)
      simpa [Nat.add_assoc, Nat.add_comm 1] using this

theorem At_extract {s : ByteArray} {pos : Nat} {bs : List UInt8} (h : At s pos bs) :
    (s.extract pos (pos + bs.length)).data = bs.toArray := by
  have hg := At_get h
  rw [ByteArray.data_extract]
  cases bs with
  | nil => simp; omega
  | cons x bs =>
    have hsize : pos + (x :: bs).length ≤ s.size := by
      have := at?_lt (hg bs.length (by simp))
      simp at this ⊢; omega
    apply Array.ext
    · simp only [Array.size_extract, ByteArray.size_data, List.size_toArray, List.length_cons] at hsize ⊢
      omega
    · intro i h1 h2
      simp only [Array.getElem_extract, List.getElem_toArray]
      have := hg i (by simpa using h2)
      unfold at? at this
      split at this
      · exact Option.some.inj this
      · cases this


theorem inRange_toNat (b lo hi : UInt8) :
    inRange b lo hi = (decide (lo.toNat ≤ b.toNat) && decide (b.toNat ≤ hi.toNat)) := by
  simp only [inRange, UInt8.le_iff_toNat_le]

theorem utf8Len_char {s : ByteArray} {pos : Nat} (c : Char) (hc : 0x7F < c.val.toNat)
    (h : At s pos (String.utf8EncodeChar c)) :
    ∃ b rest, String.utf8EncodeChar c = b :: rest ∧
      utf8Len s pos b = some (String.utf8EncodeChar c).length := by
  have hv : c.val.toNat < 0xD800 ∨ (0xDFFF < c.val.toNat ∧ c.val.toNat < 0x110000) := c.valid
  unfold String.utf8EncodeChar at h ⊢
  generalize c.val.toNat = v at *
  simp only [show ¬ v ≤ 0x7f by omega, ite_false] at h ⊢
  by_cases h2 : v ≤ 0x7ff
  · simp only [h2, ite_true, At] at h ⊢
    obtain ⟨_, h1, _⟩ := h
    refine ⟨_, _, rfl, ?_⟩
    simp only [utf8Len, h1, inRange_toNat, UInt8.toNat_ofNat', UInt8.toNat_ofNat, Nat.reducePow,
      Nat.reduceMod]
    split
    · rfl
    · rename_i hn; simp only [Bool.and_eq_true, decide_eq_true_eq] at hn; omega
  by_cases h3 : v ≤ 0xffff
  · simp only [h2, h3, ite_true, ite_false, At] at h ⊢
    obtain ⟨_, h1, h2', _⟩ := h
    simp only [Nat.add_assoc, Nat.reduceAdd] at h2'
    refine ⟨_, _, rfl, ?_⟩
    simp only [utf8Len, h1, h2', inRange_toNat, UInt8.toNat_ofNat', UInt8.toNat_ofNat,
      Nat.reducePow, Nat.reduceMod]
    have e0 : v / 4096 % 16 = v / 4096 := by omega
    have e1 : (v / 4096 % 16 + 224) % 256 = v / 4096 + 224 := by omega
    have e2 : (v / 64 % 64 + 128) % 256 = v / 64 % 64 + 128 := by omega
    have e3 : (v % 64 + 128) % 256 = v % 64 + 128 := by omega
    simp only [e2, e3, e0]
    have ha : v / 4096 < 16 := by omega
    have hsplit : v = 4096 * (v / 4096) + 64 * (v / 64 % 64) + v % 64 := by omega
    have hb : v / 64 % 64 < 64 := by omega
    have hd : v % 64 < 64 := by omega
    generalize v / 4096 = a at *
    generalize v / 64 % 64 = b at *
    generalize v % 64 = d at *
    repeat' split
    all_goals (simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq,
      ← UInt8.toNat_inj, UInt8.toNat_ofNat', UInt8.toNat_ofNat, Nat.reducePow, Nat.reduceMod] at *)
    all_goals first | rfl | omega
  · simp only [h2, h3, ite_false, At] at h ⊢
    obtain ⟨_, h1, h2', h3', _⟩ := h
    simp only [Nat.add_assoc, Nat.reduceAdd] at h2' h3'
    refine ⟨_, _, rfl, ?_⟩
    simp only [utf8Len, h1, h2', h3', inRange_toNat, UInt8.toNat_ofNat', UInt8.toNat_ofNat,
      Nat.reducePow, Nat.reduceMod]
    have e0 : v / 262144 % 8 = v / 262144 := by omega
    have e1 : (v / 262144 % 8 + 240) % 256 = v / 262144 + 240 := by omega
    have e2 : (v / 4096 % 64 + 128) % 256 = v / 4096 % 64 + 128 := by omega
    have e3 : (v / 64 % 64 + 128) % 256 = v / 64 % 64 + 128 := by omega
    have e4 : (v % 64 + 128) % 256 = v % 64 + 128 := by omega
    simp only [e0, e2, e3, e4]
    have ha : v / 262144 < 5 := by omega
    have hsplit : v = 262144 * (v / 262144) + 4096 * (v / 4096 % 64) + 64 * (v / 64 % 64) +
      v % 64 := by omega
    have hb : v / 4096 % 64 < 64 := by omega
    have hc' : v / 64 % 64 < 64 := by omega
    have hd : v % 64 < 64 := by omega
    generalize v / 262144 = a at *
    generalize v / 4096 % 64 = b at *
    generalize v / 64 % 64 = c' at *
    generalize v % 64 = d at *
    repeat' split
    all_goals (simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq,
      ← UInt8.toNat_inj, UInt8.toNat_ofNat', UInt8.toNat_ofNat, Nat.reducePow, Nat.reduceMod] at *)
    all_goals first | rfl | omega

section
variable {f : Nat} {s : ByteArray} {pos : Nat} {acc : Array UInt8}

theorem readString_plain {b : UInt8} (h0 : at? s pos = some b) (hq : b ≠ 0x22)
    (hs : b ≠ 0x5C) (hl : 0x20 ≤ b) (hh : b < 0x80) :
    readString (f + 1) s pos acc = readString f s (pos + 1) (acc.push b) := by
  rw [readString, h0]
  have h1 : ¬ b < 0x20 := by
    intro h; exact absurd (UInt8.le_iff_toNat_le.1 hl) (by have := UInt8.lt_iff_toNat_lt.1 h; omega)
  simp [hq, hs, h1, hh]

theorem readString_simple {e b : UInt8} (h0 : at? s pos = some 0x5C)
    (h1 : at? s (pos + 1) = some e) (he : e ≠ 0x75) (hb : simpleEscape e = some b) :
    readString (f + 1) s pos acc = readString f s (pos + 2) (acc.push b) := by
  rw [readString, h0]
  simp [h1, he, hb]

theorem readString_u {cp : Nat} (h0 : at? s pos = some 0x5C)
    (h1 : at? s (pos + 1) = some 0x75) (hx : hex4? s (pos + 2) = some (some cp))
    (hcp : cp < 0xD800) :
    readString (f + 1) s pos acc = readString f s (pos + 6) (acc ++ utf8 cp) := by
  rw [readString, h0]
  have : ¬ 0xD800 ≤ cp := by omega
  have : ¬ 0xDC00 ≤ cp := by omega
  simp [*]

theorem readString_multi {b : UInt8} {n : Nat} (h0 : at? s pos = some b) (hb : 0x80 ≤ b)
    (hn : utf8Len s pos b = some n) :
    readString (f + 1) s pos acc =
      readString f s (pos + n) (acc ++ (s.extract pos (pos + n)).data) := by
  rw [readString, h0]
  have h2 : b ≠ 0x22 := by intro h; subst h; exact absurd hb (by decide)
  have h3 : b ≠ 0x5C := by intro h; subst h; exact absurd hb (by decide)
  have h4 : ¬ b < 0x20 := by
    intro h; have := UInt8.lt_iff_toNat_lt.1 h; have := UInt8.le_iff_toNat_le.1 hb; simp at *; omega
  have h5 : ¬ b < 0x80 := by
    intro h; have := UInt8.lt_iff_toNat_lt.1 h; have := UInt8.le_iff_toNat_le.1 hb; simp at *; omega
  simp [h2, h3, h4, h5, hn]

theorem readString_close (h0 : at? s pos = some 0x22) (hv : (ByteArray.mk acc).IsValidUTF8) :
    readString (f + 1) s pos acc = .ok (String.fromUTF8 (ByteArray.mk acc) hv, pos + 1) := by
  rw [readString, h0]
  simp [String.fromUTF8?, hv]

theorem utf8EncodeChar_ascii {c : Char} (h : c.toNat ≤ 0x7F) :
    String.utf8EncodeChar c = [UInt8.ofNat c.toNat] := by
  unfold String.utf8EncodeChar
  simp only [Char.toNat] at h ⊢
  simp only [h, ite_true]

theorem hex4?_of_At {b0 b1 b2 b3 : UInt8} (h : At s pos [b0, b1, b2, b3]) :
    hex4? s pos = some (if [b0, b1, b2, b3].all isHex then
      some ([b0, b1, b2, b3].foldl (fun n b => 16 * n + hexValue b) 0) else none) := by
  have hg := At_get h
  have h3 := at?_lt (hg 3 (by simp))
  unfold hex4?
  split
  · omega
  have e : (List.range 4).map (fun i => s.get! (pos + i)) = [b0, b1, b2, b3] := by
    simp only [List.range_succ, List.range_zero, List.nil_append, List.map_cons,
      List.map_nil, List.cons_append]
    rw [get!_of_at? (hg 0 (by simp)), get!_of_at? (hg 1 (by simp)), get!_of_at? (hg 2 (by simp)),
      get!_of_at? (hg 3 (by simp))]
    rfl
  simp only [e]

theorem utf8Len_lead {b : UInt8} {n : Nat} (h : utf8Len s pos b = some n) : 0x80 ≤ b := by
  rw [UInt8.le_iff_toNat_le]
  unfold utf8Len at h
  simp only [inRange_toNat] at h
  repeat' split at h
  all_goals (try cases h)
  all_goals (rename_i hc; simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq,
    beq_iff_eq, ← UInt8.toNat_inj] at hc; simp only [UInt8.reduceToNat] at *; omega)

/-- A two-byte escape `\e` of an ASCII character. -/
theorem step_named {c : Char} {e : UInt8} (hk : c.toNat ≤ 0x7F) (he : e ≠ 0x75)
    (hs : simpleEscape e = some (UInt8.ofNat c.toNat)) (h : At s pos [0x5C, e]) :
    readString (f + 1) s pos acc =
      readString f s (pos + 2) (acc ++ (String.utf8EncodeChar c).toArray) := by
  rw [readString_simple h.1 h.2.1 he hs, utf8EncodeChar_ascii hk]
  simp

/-- One character of an encoded string: `readString` moves past its bytes
and collects the character's UTF-8 encoding. -/
theorem readString_char (c : Char) (h : At s pos (bytes (escapeChar c))) :
    readString (f + 1) s pos acc =
      readString f s (pos + (bytes (escapeChar c)).length)
        (acc ++ (String.utf8EncodeChar c).toArray) := by
  unfold escapeChar at h ⊢
  by_cases h1 : c = '"'
  · subst h1
    simp only [beq_self_eq_true, ite_true] at h ⊢
    rw [show bytes "\\\"" = [0x5C, 0x22] by decide] at h ⊢
    exact step_named (by decide) (by decide) (by decide) h
  have b1 : (c == '"') = false := by simpa using h1
  simp only [b1, Bool.false_eq_true, ite_false] at h ⊢
  by_cases h2 : c = '\\'
  · subst h2
    simp only [beq_self_eq_true, ite_true] at h ⊢
    rw [show bytes "\\\\" = [0x5C, 0x5C] by decide] at h ⊢
    exact step_named (by decide) (by decide) (by decide) h
  have b2 : (c == '\\') = false := by simpa using h2
  simp only [b2, Bool.false_eq_true, ite_false] at h ⊢
  by_cases h3 : c.toNat = 0x08
  · simp only [h3, beq_self_eq_true, ite_true] at h ⊢
    rw [show bytes "\\b" = [0x5C, 0x62] by decide] at h ⊢
    exact step_named (by omega) (by decide) (by rw [h3]; decide) h
  have b3 : (c.toNat == 0x08) = false := by simpa using h3
  simp only [b3, Bool.false_eq_true, ite_false] at h ⊢
  by_cases h4 : c = '\t'
  · subst h4
    simp only [beq_self_eq_true, ite_true] at h ⊢
    rw [show bytes "\\t" = [0x5C, 0x74] by decide] at h ⊢
    exact step_named (by decide) (by decide) (by decide) h
  have b4 : (c == '\t') = false := by simpa using h4
  simp only [b4, Bool.false_eq_true, ite_false] at h ⊢
  by_cases h5 : c = '\n'
  · subst h5
    simp only [beq_self_eq_true, ite_true] at h ⊢
    rw [show bytes "\\n" = [0x5C, 0x6E] by decide] at h ⊢
    exact step_named (by decide) (by decide) (by decide) h
  have b5 : (c == '\n') = false := by simpa using h5
  simp only [b5, Bool.false_eq_true, ite_false] at h ⊢
  by_cases h6 : c.toNat = 0x0C
  · simp only [h6, beq_self_eq_true, ite_true] at h ⊢
    rw [show bytes "\\f" = [0x5C, 0x66] by decide] at h ⊢
    exact step_named (by omega) (by decide) (by rw [h6]; decide) h
  have b6 : (c.toNat == 0x0C) = false := by simpa using h6
  simp only [b6, Bool.false_eq_true, ite_false] at h ⊢
  by_cases h7 : c = '\r'
  · subst h7
    simp only [beq_self_eq_true, ite_true] at h ⊢
    rw [show bytes "\\r" = [0x5C, 0x72] by decide] at h ⊢
    exact step_named (by decide) (by decide) (by decide) h
  have b7 : (c == '\r') = false := by simpa using h7
  simp only [b7, Bool.false_eq_true, ite_false] at h ⊢
  by_cases h8 : c.toNat < 0x20
  · simp only [h8, ite_true] at h ⊢
    obtain ⟨hb, hx, hv⟩ := control_hex ⟨c.toNat, h8⟩
    simp only at hb hx hv
    rw [bytes_append, hb, show bytes "\\u00" = [0x5C, 0x75, 0x30, 0x30] by decide] at h ⊢
    have h' := h
    simp only [List.cons_append, List.nil_append, At] at h'
    have hsuf : At s (pos + 2) [0x30, 0x30, hexByte (c.toNat / 16), hexByte c.toNat] := by
      have := (At_append (a := [0x5C, 0x75]) (b := [0x30, 0x30, hexByte (c.toNat / 16),
        hexByte c.toNat])).1 (by simpa using h)
      simpa using this.2
    have hx4 := hex4?_of_At hsuf
    simp only [hx, ite_true, hv] at hx4
    rw [readString_u h'.1 h'.2.1 hx4 (by omega), utf8EncodeChar_ascii (by omega)]
    simp [utf8, show c.toNat < 0x80 by omega]
  simp only [h8, ite_false] at h ⊢
  rw [bytes_char] at h ⊢
  by_cases ha : c.toNat ≤ 0x7F
  · rw [utf8EncodeChar_ascii ha] at h ⊢
    have ne : ∀ k, k ≤ 0x7F → c.toNat ≠ k → UInt8.ofNat c.toNat ≠ UInt8.ofNat k := by
      intro k hk hne heq
      have := congrArg UInt8.toNat heq
      simp only [UInt8.toNat_ofNat'] at this
      omega
    have hq : c.toNat ≠ 0x22 := fun e => h1 (by rw [← char_of_toNat e])
    have hs : c.toNat ≠ 0x5C := fun e => h2 (by rw [← char_of_toNat e])
    rw [readString_plain h.1 (ne _ (by decide) hq) (ne _ (by decide) hs)
      (by rw [UInt8.le_iff_toNat_le]; simp only [UInt8.toNat_ofNat']; simp; omega)
      (by rw [UInt8.lt_iff_toNat_lt]; simp only [UInt8.toNat_ofNat']; simp; omega)]
    simp
  · obtain ⟨b, rest, he, hl⟩ := utf8Len_char c (by simp only [Char.toNat] at ha; omega) h
    have hx := At_extract h
    rw [he] at h hx hl ⊢
    rw [readString_multi h.1 (utf8Len_lead hl) hl, hx]


end

/-- The escaped characters of a string body. -/
def bodyBytes (cs : List Char) : List UInt8 := bytes (String.join (cs.map escapeChar))

theorem bodyBytes_cons (c : Char) (cs : List Char) :
    bodyBytes (c :: cs) = bytes (escapeChar c) ++ bodyBytes cs := by
  simp [bodyBytes, String.join_cons, bytes_append]

/-- `readString` reads an escaped body up to its closing quote and returns the
characters it has collected before and in it. -/
theorem readString_body {s : ByteArray} :
    ∀ (cs : List Char) (pre : List Char) (pos fuel : Nat),
    At s pos (bodyBytes cs ++ [0x22]) → cs.length < fuel →
    readString fuel s pos pre.utf8Encode.data =
      .ok (String.ofList (pre ++ cs), pos + (bodyBytes cs).length + 1)
  | [], pre, pos, fuel + 1, h, _ => by
    simp only [bodyBytes, List.map_nil, String.join_nil] at h
    have hv : (ByteArray.mk pre.utf8Encode.data).IsValidUTF8 := ByteArray.isValidUTF8_utf8Encode
    rw [readString_close h.1 hv]
    simp only [List.append_nil, Except.ok.injEq, Prod.mk.injEq]
    refine ⟨?_, by simp [bodyBytes, bytes]⟩
    rw [← String.toByteArray_inj]
    simp [String.fromUTF8]
  | c :: cs, pre, pos, fuel + 1, h, hf => by
    rw [bodyBytes_cons, List.append_assoc] at h
    have ⟨hc, hrest⟩ := At_append.1 h
    rw [readString_char c hc]
    have ih := readString_body cs (pre ++ [c]) (pos + (bytes (escapeChar c)).length) fuel hrest
      (by simp at hf; omega)
    rw [List.utf8Encode_append, List.utf8Encode_singleton] at ih
    simp only [ByteArray.data_append, List.data_toByteArray] at ih
    rw [ih, bodyBytes_cons]
    simp [Nat.add_assoc]

/-! ## Numbers and keywords -/

/-- The byte of an ASCII character. -/
def asciiByte (c : Char) : UInt8 := UInt8.ofNat c.toNat

theorem bytes_ofList_ascii : ∀ {l : List Char}, (∀ c ∈ l, c.toNat ≤ 0x7F) →
    bytes (String.ofList l) = l.map asciiByte
  | [], _ => by decide
  | c :: l, h => by
    rw [show String.ofList (c :: l) = c.toString ++ String.ofList l by
      simp]
    rw [bytes_append, bytes_char, utf8EncodeChar_ascii (h c (by simp)),
      bytes_ofList_ascii (fun c hc => h c (by simp [hc]))]
    rfl

theorem digit_toNat {c : Char} (h : c.isDigit = true) : 48 ≤ c.toNat ∧ c.toNat ≤ 57 :=
  Char.isDigit_iff_toNat.1 h

theorem digit_ascii {c : Char} (h : c.isDigit = true) : c.toNat ≤ 0x7F := by
  have := digit_toNat h; omega

theorem isDigit_asciiByte {c : Char} (h : c.isDigit = true) : isDigit (asciiByte c) = true := by
  have := digit_toNat h
  simp only [isDigit, inRange, asciiByte, UInt8.le_iff_toNat_le, UInt8.toNat_ofNat',
    Bool.and_eq_true, decide_eq_true_eq]
  simp only [UInt8.reduceToNat, Nat.reducePow]
  omega

theorem digitsValue_map {ds : List Char} (h : ∀ c ∈ ds, c.isDigit = true) :
    digitsValue (ds.map asciiByte) = Nat.ofDigitChars 10 ds 0 := by
  unfold digitsValue
  rw [Nat.ofDigitChars_eq_foldl, List.foldl_map]
  generalize 0 = init
  induction ds generalizing init with
  | nil => rfl
  | cons c ds ih =>
    simp only [List.foldl_cons]
    have hc := h c (by simp)
    rw [ih (fun c hc => h c (by simp [hc]))]
    congr 1
    have := digit_toNat hc
    have hle : (48 : UInt8) ≤ asciiByte c := by
      rw [UInt8.le_iff_toNat_le]; simp only [asciiByte, UInt8.toNat_ofNat']; simp; omega
    rw [UInt8.toNat_sub_of_le _ _ hle]
    simp only [asciiByte, UInt8.toNat_ofNat']
    simp; omega

theorem toDigits_head (n : Nat) (hn : 0 < n) : ∃ c cs, Nat.toDigits 10 n = c :: cs ∧ c ≠ '0' := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    by_cases h : n < 10
    · rw [Nat.toDigits_of_lt_base h]
      have key : ∀ k, k < 10 → 0 < k → k.digitChar ≠ '0' := by decide
      exact ⟨_, _, rfl, key n h hn⟩
    · rw [Nat.toDigits_of_base_le (by decide) (by omega)]
      obtain ⟨c, cs, hc, h0⟩ := ih (n / 10) (by omega) (by omega)
      exact ⟨c, cs ++ [Nat.digitChar (n % 10)], by simp [hc], h0⟩

theorem toDigits_digits (n : Nat) : ∀ c ∈ Nat.toDigits 10 n, c.isDigit = true :=
  fun _ h => Nat.isDigit_of_mem_toDigits (by decide) (by decide) h

/-- The digits of `n` as bytes. -/
def digitBytes (n : Nat) : List UInt8 := (Nat.toDigits 10 n).map asciiByte

theorem bytes_toString_int (i : Int) :
    bytes (toString i) = (if i < 0 then [0x2D] else []) ++ digitBytes i.natAbs := by
  cases i with
  | ofNat m =>
    simp only [Int.toString_eq_repr, Int.repr, Nat.repr_eq_ofList_toDigits]
    rw [bytes_ofList_ascii (fun c hc => digit_ascii (toDigits_digits m c hc))]
    simp [digitBytes]
  | negSucc m =>
    simp only [Int.toString_eq_repr, Int.repr, Nat.repr_eq_ofList_toDigits]
    rw [bytes_append, bytes_ofList_ascii (fun c hc => digit_ascii (toDigits_digits _ c hc))]
    simp [digitBytes]
    rw [show bytes "-" = [45] by decide]
    rfl

theorem digitBytes_digits (n : Nat) : ∀ b ∈ digitBytes n, isDigit b = true := by
  intro b hb
  obtain ⟨c, hc, rfl⟩ := List.mem_map.1 hb
  exact isDigit_asciiByte (toDigits_digits n c hc)

theorem digitBytes_shape (n : Nat) :
    ∃ d ds, digitBytes n = d :: ds ∧ isDigit d = true ∧ (d == 0x30 && ds.length > 0) = false := by
  by_cases hn : n = 0
  · subst hn; exact ⟨0x30, [], by decide, by decide, by decide⟩
  · obtain ⟨c, cs, hc, h0⟩ := toDigits_head n (by omega)
    refine ⟨asciiByte c, cs.map asciiByte, by simp [digitBytes, hc],
      digitBytes_digits n _ (by simp [digitBytes, hc]), ?_⟩
    have hd := digit_toNat (toDigits_digits n c (by simp [hc]))
    have : asciiByte c ≠ 0x30 := by
      intro e
      have := congrArg UInt8.toNat e
      simp only [asciiByte, UInt8.toNat_ofNat'] at this
      simp at this
      exact h0 (by rw [← char_of_toNat (by omega : c.toNat = 48)])
    simp [this]

theorem takeWhile_all {α : Type} {p : α → Bool} :
    ∀ {l : List α}, (∀ x ∈ l, p x = true) → l.takeWhile p = l
  | [], _ => rfl
  | x :: l, h => by
    have ih := takeWhile_all (p := p) (l := l) (fun y hy => h y (List.mem_cons_of_mem _ hy))
    simp only [List.takeWhile_cons, h x List.mem_cons_self, ite_true, ih]

theorem splitNumber_digits (neg : Bool) (n : Nat) :
    splitNumber ((if neg then [0x2D] else []) ++ digitBytes n) =
      some ⟨neg, digitBytes n, none, none⟩ := by
  obtain ⟨d, ds, hd, hdig, hz⟩ := digitBytes_shape n
  have hall := digitBytes_digits n
  have htw : (digitBytes n).takeWhile isDigit = digitBytes n :=
    takeWhile_all hall
  have hneq : d ≠ 0x2D := by intro e; subst e; exact absurd hdig (by decide)
  rw [hd] at htw ⊢
  have hz' : d = 0x30 → ds = [] := by
    intro e; subst e; cases ds with
    | nil => rfl
    | cons _ _ => simp at hz
  have hh : (d :: ds).head! = d := rfl
  cases neg <;> simp [splitNumber, htw, hneq, hh] <;> exact hz'

/-- The byte after a token, if any, is not one of `bs`'s kind. -/
def EndsAt (s : ByteArray) (k : Nat) (p : UInt8 → Bool) : Prop :=
  ∀ b, at? s k = some b → p b = false

theorem numberEnd_At {s : ByteArray} : ∀ {pos : Nat} {bs : List UInt8}, At s pos bs →
    (∀ b ∈ bs, isNumberByte b = true) → EndsAt s (pos + bs.length) isNumberByte →
    numberEnd s pos = pos + bs.length
  | pos, [], _, _, he => by
    rw [numberEnd]
    split
    · next h =>
      have := he s[pos] (by simp [at?, h])
      simp [this]
    · rfl
  | pos, b :: bs, h, hn, he => by
    rw [numberEnd]
    have hb := h.1
    unfold at? at hb
    split at hb
    · next hlt =>
      cases hb
      rw [dite_eq_left_of_eq_true (eq_true hlt)]
      simp only [hn _ List.mem_cons_self, ite_true]
      rw [numberEnd_At h.2 (fun x hx => hn x (List.mem_cons_of_mem _ hx))
        (by simpa [Nat.add_assoc, Nat.add_comm 1] using he)]
      simp [Nat.add_assoc, Nat.add_comm 1]
    · cases hb

theorem digitsValue_digitBytes (n : Nat) : digitsValue (digitBytes n) = n := by
  rw [digitBytes, digitsValue_map (toDigits_digits n), Nat.ofDigitChars_ten_toDigits]

/-- An integer the encoder wrote, followed by a byte that ends the number. -/
theorem readNumber_int {s : ByteArray} {pos : Nat} (i : Int) (h : At s pos (bytes (toString i)))
    (he : EndsAt s (pos + (bytes (toString i)).length) isNumberByte) :
    readNumber s pos = .ok (.int i, pos + (bytes (toString i)).length) := by
  have hnum : ∀ b ∈ bytes (toString i), isNumberByte b = true := by
    intro b hb
    rw [bytes_toString_int] at hb
    simp only [List.mem_append] at hb
    rcases hb with hb | hb
    · split at hb <;> simp_all [isNumberByte]
    · simp [isNumberByte, digitBytes_digits _ b hb]
  have hend := numberEnd_At h hnum he
  have hx := At_extract h
  unfold readNumber
  simp only [hend, hx, List.toList_toArray]
  have hs := splitNumber_digits (decide (i < 0)) i.natAbs
  simp only [decide_eq_true_eq] at hs
  rw [bytes_toString_int, hs]
  simp only [Option.isNone_none, Bool.and_self, ite_true, digitsValue_digitBytes]
  by_cases hi : i < 0 <;> simp [hi] <;> omega

theorem get!_bytes (kw : String) (i : Nat) (hi : i < (bytes kw).length) :
    kw.toUTF8.get! i = (bytes kw)[i] := by
  unfold bytes at hi ⊢
  simp only [String.toUTF8_eq_toByteArray, ByteArray.get!, Array.getElem!_eq_getD, Array.getD,
    Array.getElem_toList]
  simp only [Array.length_toList] at hi
  have : i < kw.utf8ByteSize := by simpa [String.size_toByteArray] using hi
  simp [this]

theorem keyword_At {s : ByteArray} {pos : Nat} {kw : String} {v : JVal}
    (hne : bytes kw ≠ []) (h : At s pos (bytes kw))
    (he : EndsAt s (pos + (bytes kw).length) isAlnum) :
    keyword s pos kw v = .ok (v, pos + (bytes kw).length) := by
  have hg := At_get h
  have hlen : kw.toUTF8.size = (bytes kw).length := by simp [bytes]
  unfold keyword
  simp only [hlen]
  have hsize : pos + (bytes kw).length ≤ s.size := by
    cases hb : bytes kw with
    | nil => exact absurd hb hne
    | cons x xs =>
      have := at?_lt (hg xs.length (by simp [hb]))
      simp only [List.length_cons]; omega
  have hall : (List.range (bytes kw).length).all
      (fun i => s.get! (pos + i) == kw.toUTF8.get! i) = true := by
    rw [List.all_eq_true]
    intro i hi
    have hi' := List.mem_range.1 hi
    rw [get!_of_at? (hg i hi'), get!_bytes kw i hi', beq_self_eq_true]
  simp only [hsize, hall, decide_true, Bool.true_and, ite_true]
  split
  · next b hb => rw [he b hb]; rfl
  · rfl

/-! ## Whitespace and the scalars at `readValue` -/

/-- The UTF-8 bytes of a character list. -/
def enc (cs : List Char) : List UInt8 := cs.flatMap String.utf8EncodeChar

theorem bytes_ofList_enc : ∀ (l : List Char), bytes (String.ofList l) = enc l
  | [] => by decide
  | c :: l => by
    rw [show String.ofList (c :: l) = c.toString ++ String.ofList l by simp, bytes_append,
      bytes_char, bytes_ofList_enc l]
    simp [enc]

theorem bytes_eq_enc (s : String) : bytes s = enc s.toList := by
  rw [← bytes_ofList_enc, String.ofList_toList]

theorem enc_append (a b : List Char) : enc (a ++ b) = enc a ++ enc b := by
  simp [enc]

theorem enc_ascii {c : Char} (h : c.toNat ≤ 0x7F) (cs : List Char) :
    enc (c :: cs) = asciiByte c :: enc cs := by
  simp [enc, utf8EncodeChar_ascii h, asciiByte]

theorem skipWs_stop {s : ByteArray} {pos : Nat} {b : UInt8} (h : at? s pos = some b)
    (hb : isWs b = false) : skipWs s pos = pos := by
  rw [skipWs]
  unfold at? at h
  split at h
  · next hlt => cases h; rw [dite_eq_left_of_eq_true (eq_true hlt)]; simp [hb]
  · cases h

theorem skipWs_ws {s : ByteArray} {pos : Nat} {b : UInt8} (h : at? s pos = some b)
    (hb : isWs b = true) : skipWs s pos = skipWs s (pos + 1) := by
  rw [skipWs]
  unfold at? at h
  split at h
  · next hlt => cases h; rw [dite_eq_left_of_eq_true (eq_true hlt)]; simp [hb]
  · cases h

/-- Whitespace bytes, then a byte that is none. -/
theorem skipWs_At {s : ByteArray} : ∀ {pos : Nat} {ws : List UInt8} {b : UInt8},
    At s pos (ws ++ [b]) → (∀ w ∈ ws, isWs w = true) → isWs b = false →
    skipWs s pos = pos + ws.length
  | pos, [], b, h, _, hb => by simpa using skipWs_stop h.1 hb
  | pos, w :: ws, b, h, hw, hb => by
    rw [skipWs_ws h.1 (hw w List.mem_cons_self),
      skipWs_At h.2 (fun x hx => hw x (List.mem_cons_of_mem _ hx)) hb]
    simp [Nat.add_assoc, Nat.add_comm 1]

/-- What follows a value in the canonical text: `,` or a newline. -/
def Follow (s : ByteArray) (k : Nat) : Prop := at? s k = some 0x2C ∨ at? s k = some 0x0A

theorem Follow.alnum {s : ByteArray} {k : Nat} (h : Follow s k) : EndsAt s k isAlnum := by
  intro b hb; rcases h with h | h <;> rw [h] at hb <;> cases hb <;> decide

theorem Follow.number {s : ByteArray} {k : Nat} (h : Follow s k) : EndsAt s k isNumberByte := by
  intro b hb; rcases h with h | h <;> rw [h] at hb <;> cases hb <;> decide

theorem readValue_keyword {s : ByteArray} {pos f : Nat} {kw : String} {v : JVal} {b : UInt8}
    (hb : bytes kw = b :: (bytes kw).tail) (hd : readValue (f + 1) s pos = keyword s pos kw v)
    (h : At s pos (bytes kw)) (hf : Follow s (pos + (bytes kw).length)) :
    readValue (f + 1) s pos = .ok (v, pos + (bytes kw).length) := by
  rw [hd, keyword_At (by rw [hb]; simp) h hf.alnum]

theorem readValue_null {s : ByteArray} {pos f : Nat} (h : At s pos (bytes "null"))
    (hf : Follow s (pos + 4)) : readValue (f + 1) s pos = .ok (.null, pos + 4) := by
  have h0 : at? s pos = some 0x6E := by
    rw [show bytes "null" = [0x6E, 0x75, 0x6C, 0x6C] by decide] at h; exact h.1
  rw [readValue_keyword (kw := "null") (v := .null) (b := 0x6E) (by decide) (by simp [readValue, h0]) h
    (by simpa [show (bytes "null").length = 4 by decide] using hf)]
  rfl

theorem readValue_bool {s : ByteArray} {pos f : Nat} (b : Bool)
    (h : At s pos (bytes (if b then "true" else "false")))
    (hf : Follow s (pos + (bytes (if b then "true" else "false")).length)) :
    readValue (f + 1) s pos = .ok (.bool b, pos + (bytes (if b then "true" else "false")).length) := by
  cases b <;> simp only [Bool.false_eq_true, ite_false, ite_true] at h hf ⊢
  · have h0 : at? s pos = some 0x66 := by
      rw [show bytes "false" = [0x66, 0x61, 0x6C, 0x73, 0x65] by decide] at h; exact h.1
    exact readValue_keyword (kw := "false") (v := .bool false) (b := 0x66) (by decide)
      (by simp [readValue, h0]) h hf
  · have h0 : at? s pos = some 0x74 := by
      rw [show bytes "true" = [0x74, 0x72, 0x75, 0x65] by decide] at h; exact h.1
    exact readValue_keyword (kw := "true") (v := .bool true) (b := 0x74) (by decide)
      (by simp [readValue, h0]) h hf

theorem readValue_int {s : ByteArray} {pos f : Nat} (i : Int) (h : At s pos (bytes (toString i)))
    (hf : Follow s (pos + (bytes (toString i)).length)) :
    readValue (f + 1) s pos = .ok (.int i, pos + (bytes (toString i)).length) := by
  have hb := bytes_toString_int i
  obtain ⟨d, ds, hd, hdig, _⟩ := digitBytes_shape i.natAbs
  obtain ⟨b, hb0, hcase⟩ : ∃ b, at? s pos = some b ∧ (b = 0x2D ∨ isDigit b = true) := by
    rw [hb] at h
    by_cases hi : i < 0
    · simp only [hi, ite_true, List.cons_append, List.nil_append] at h
      exact ⟨_, h.1, Or.inl rfl⟩
    · simp only [hi, ite_false, List.nil_append, hd] at h
      exact ⟨_, h.1, Or.inr hdig⟩
  have hdisp : readValue (f + 1) s pos = readNumber s pos := by
    simp only [readValue, hb0]
    have hnum : (isDigit b || b == 0x2D) = true := by
      rcases hcase with rfl | h
      · decide
      · simp [h]
    rcases hcase with rfl | hd'
    · simp
    · have h1 : b ≠ 0x7B := fun e => by subst e; exact absurd hd' (by decide)
      have h2 : b ≠ 0x5B := fun e => by subst e; exact absurd hd' (by decide)
      have h3 : b ≠ 0x22 := fun e => by subst e; exact absurd hd' (by decide)
      have h4 : b ≠ 0x6E := fun e => by subst e; exact absurd hd' (by decide)
      have h5 : b ≠ 0x74 := fun e => by subst e; exact absurd hd' (by decide)
      have h6 : b ≠ 0x66 := fun e => by subst e; exact absurd hd' (by decide)
      simp [h1, h2, h3, h4, h5, h6, hd']
  rw [hdisp, readNumber_int i h hf.number]

theorem escapeChar_ne_nil (c : Char) : bytes (escapeChar c) ≠ [] := by
  unfold escapeChar
  repeat' split
  all_goals first
    | decide
    | (rw [bytes_append, show bytes "\\u00" = [0x5C, 0x75, 0x30, 0x30] by decide]; simp)
    | (rw [bytes_char]; exact String.utf8EncodeChar_ne_nil)

theorem bodyBytes_length : ∀ cs : List Char, cs.length ≤ (bodyBytes cs).length
  | [] => by simp
  | c :: cs => by
    rw [bodyBytes_cons, List.length_append]
    have := bodyBytes_length cs
    have : 0 < (bytes (escapeChar c)).length := List.length_pos_iff.2 (escapeChar_ne_nil c)
    simp; omega

theorem bytes_encodeString (str : String) :
    bytes (encodeString str) = [0x22] ++ bodyBytes str.toList ++ [0x22] := by
  simp only [encodeString, bytes_append, bodyBytes]
  rw [show bytes "\"" = [0x22] by decide]

theorem readValue_str {s : ByteArray} {pos f : Nat} (str : String)
    (h : At s pos (bytes (encodeString str))) (hl : (bytes (encodeString str)).length < f + 1) :
    readValue (f + 1) s pos = .ok (.str str, pos + (bytes (encodeString str)).length) := by
  rw [bytes_encodeString] at h hl ⊢
  rw [List.append_assoc] at h
  have h0 := h.1
  have hb := readString_body str.toList [] (pos + 1) f h.2
    (by have := bodyBytes_length str.toList; simp at hl; omega)
  simp only [List.utf8Encode_nil, List.nil_append, String.ofList_toList] at hb
  rw [show ByteArray.empty.data = #[] from rfl] at hb
  simp only [readValue, h0]
  simp [hb, Except.map]
  omega

/-! ## Arrays, objects and the whole document -/

/-- The indent of depth `e` as bytes. -/
def padB (e : Nat) : List UInt8 := List.replicate (2 * e) 0x20

theorem bytes_pad : ∀ e, bytes (pad e) = padB e
  | 0 => by decide
  | e + 1 => by
    rw [show pad (e + 1) = "  " ++ pad e by simp [pad, List.replicate_succ, String.join_cons],
      bytes_append, bytes_pad e, show bytes "  " = [0x20, 0x20] by decide]
    simp only [padB, Nat.mul_succ, List.replicate_succ]
    rfl

theorem lit_open_arr : bytes "[\n" = [0x5B, 0x0A] := by decide
theorem lit_open_obj : bytes "{\n" = [0x7B, 0x0A] := by decide
theorem lit_sep : bytes ",\n" = [0x2C, 0x0A] := by decide
theorem lit_nl : bytes "\n" = [0x0A] := by decide
theorem lit_close_arr : bytes "]" = [0x5D] := by decide
theorem lit_close_obj : bytes "}" = [0x7D] := by decide
theorem lit_colon : bytes ": " = [0x3A, 0x20] := by decide

/-- An array's bytes after `[`, its newline and the first indent. -/
def arrBodyB (d e : Nat) : List String → List UInt8
  | [] => []
  | [i] => bytes i ++ [0x0A] ++ padB e ++ [0x5D]
  | i :: is => bytes i ++ [0x2C, 0x0A] ++ padB d ++ arrBodyB d e is

theorem arr_inner (d e : Nat) (i : String) (is : List String) :
    bytes (",\n".intercalate ((i :: is).map (pad d ++ ·)) ++ "\n" ++ pad e ++ "]") =
      padB d ++ arrBodyB d e (i :: is) := by
  induction is generalizing i with
  | nil =>
    simp [String.intercalate_singleton, bytes_append, bytes_pad, arrBodyB, lit_nl, lit_close_arr]
  | cons j js ih =>
    have ih' := ih j
    simp only [List.map_cons] at ih' ⊢
    rw [String.intercalate_cons_cons]
    rw [show arrBodyB d e (i :: j :: js) = bytes i ++ [0x2C, 0x0A] ++ padB d ++
      arrBodyB d e (j :: js) from rfl]
    simp only [String.append_assoc, bytes_append, bytes_pad] at ih' ⊢
    rw [ih']
    simp only [lit_sep, List.append_assoc, List.cons_append, List.nil_append]

theorem arr_bytes (d e : Nat) (i : String) (is : List String) :
    bytes ("[\n" ++ ",\n".intercalate ((i :: is).map (pad d ++ ·)) ++ "\n" ++ pad e ++ "]") =
      [0x5B, 0x0A] ++ padB d ++ arrBodyB d e (i :: is) := by
  have h := arr_inner d e i is
  simp only [String.append_assoc, bytes_append] at h ⊢
  rw [h, lit_open_arr, List.append_assoc]

/-- An object's bytes after `{`, its newline and the first indent. -/
def objBodyB (d e : Nat) : List (String × String) → List UInt8
  | [] => []
  | [(k, v)] => bytes (encodeString k) ++ [0x3A, 0x20] ++ bytes v ++ [0x0A] ++ padB e ++ [0x7D]
  | (k, v) :: es =>
    bytes (encodeString k) ++ [0x3A, 0x20] ++ bytes v ++ [0x2C, 0x0A] ++ padB d ++ objBodyB d e es

theorem obj_inner (d e : Nat) (k v : String) (es : List (String × String)) :
    bytes (",\n".intercalate (((k, v) :: es).map fun (k, v) => pad d ++ encodeString k ++ ": " ++ v) ++
      "\n" ++ pad e ++ "}") = padB d ++ objBodyB d e ((k, v) :: es) := by
  induction es generalizing k v with
  | nil =>
    simp [String.intercalate_singleton, bytes_append, bytes_pad, objBodyB, lit_nl, lit_close_obj,
      lit_colon]
  | cons kv es ih =>
    obtain ⟨k', v'⟩ := kv
    have ih' := ih k' v'
    simp only [List.map_cons] at ih' ⊢
    rw [String.intercalate_cons_cons]
    rw [show objBodyB d e ((k, v) :: (k', v') :: es) = bytes (encodeString k) ++ [0x3A, 0x20] ++
      bytes v ++ [0x2C, 0x0A] ++ padB d ++ objBodyB d e ((k', v') :: es) from rfl]
    simp only [String.append_assoc, bytes_append, bytes_pad] at ih' ⊢
    rw [ih']
    simp only [lit_sep, lit_colon, List.append_assoc, List.cons_append, List.nil_append]

theorem obj_bytes (d e : Nat) (k v : String) (es : List (String × String)) :
    bytes ("{\n" ++ ",\n".intercalate (((k, v) :: es).map fun (k, v) =>
      pad d ++ encodeString k ++ ": " ++ v) ++ "\n" ++ pad e ++ "}") =
      [0x7B, 0x0A] ++ padB d ++ objBodyB d e ((k, v) :: es) := by
  have h := obj_inner d e k v es
  simp only [String.append_assoc, bytes_append] at h ⊢
  rw [h, lit_open_obj, List.append_assoc]

/-- A byte that can start an encoded value. -/
def LeadB (b : UInt8) : Prop := isWs b = false ∧ b ≠ 0x5D ∧ b ≠ 0x2C ∧ b ≠ 0x7D

instance (b : UInt8) : Decidable (LeadB b) := by unfold LeadB; infer_instance

theorem digit_leadB {b : UInt8} (h : isDigit b = true) : LeadB b := by
  simp only [isDigit, inRange, Bool.and_eq_true, decide_eq_true_eq, UInt8.le_iff_toNat_le] at h
  simp only [UInt8.reduceToNat] at h
  simp only [LeadB, isWs, Bool.or_eq_false_iff, beq_eq_false_iff_ne, ne_eq, ← UInt8.toNat_inj,
    UInt8.reduceToNat]
  omega

theorem encode_head {d : Nat} {v : JVal} {t : String} (h : encode d v = .ok t) :
    ∃ b, (bytes t).head? = some b ∧ LeadB b := by
  unfold encode at h
  split at h
  · cases h
  split at h
  · cases h; exact ⟨0x6E, by decide, by decide⟩
  · next b' =>
    cases h
    cases b'
    · exact ⟨0x66, by decide, by decide⟩
    · exact ⟨0x74, by decide, by decide⟩
  · next i =>
    cases h
    rw [bytes_toString_int]
    obtain ⟨d', ds, hd, hdig, _⟩ := digitBytes_shape i.natAbs
    by_cases hi : i < 0
    · exact ⟨0x2D, by simp [hi], by decide⟩
    · exact ⟨d', by simp [hi, hd], digit_leadB hdig⟩
  · cases h
  · next str =>
    cases h
    exact ⟨0x22, by rw [bytes_encodeString]; simp, by decide⟩
  · cases h; exact ⟨0x5B, by decide, by decide⟩
  · next xs hne =>
    simp only [bind, Except.bind] at h
    split at h
    · cases h
    · cases h
      exact ⟨0x5B, by simp [String.append_assoc, bytes_append, lit_open_arr], by decide⟩
  · cases h; exact ⟨0x7B, by decide, by decide⟩
  · next kvs hne =>
    simp only [bind, Except.bind] at h
    split at h
    · cases h
    · cases h
      exact ⟨0x7B, by simp [String.append_assoc, bytes_append, lit_open_obj], by decide⟩

theorem At_prefix {s : ByteArray} {pos : Nat} {a b : List UInt8} (h : At s pos (a ++ b)) :
    At s pos a := (At_append.1 h).1

theorem At_suffix {s : ByteArray} {pos : Nat} {a b : List UInt8} (h : At s pos (a ++ b)) :
    At s (pos + a.length) b := (At_append.1 h).2

/-- A newline and an indent, then a byte that is no whitespace. -/
theorem skip_indent {s : ByteArray} {pos e : Nat} {b : UInt8} {rest : List UInt8}
    (h : At s pos ([0x0A] ++ padB e ++ b :: rest)) (hb : isWs b = false) :
    skipWs s pos = pos + 1 + 2 * e := by
  have h' : At s pos (([0x0A] ++ padB e) ++ [b]) := by
    have := At_prefix (a := ([0x0A] ++ padB e) ++ [b]) (b := rest) (by simpa using h)
    exact this
  rw [skipWs_At h' (by intro w hw; simp [padB] at hw; rcases hw with rfl | ⟨_, rfl⟩ <;> decide) hb]
  simp [padB]; omega

theorem sortEntries_sorted {kvs : List (String × JVal)} (h : (kvs.map (·.1)).Pairwise (· < ·)) :
    sortEntries kvs = kvs := by
  apply List.mergeSort_of_pairwise
  rw [List.pairwise_map] at h
  exact h.imp fun h' => by simpa using String.lt_asymm h'

theorem arrBodyB_head (d e : Nat) (i : String) (is : List String) :
    ∃ t, arrBodyB d e (i :: is) = bytes i ++ t := by
  cases is with
  | nil => exact ⟨[0x0A] ++ padB e ++ [0x5D], by simp [arrBodyB]⟩
  | cons j js => exact ⟨[0x2C, 0x0A] ++ padB d ++ arrBodyB d e (j :: js), by simp [arrBodyB]⟩

/-- An object key: `readString` after its opening quote returns it. -/
theorem readString_key {s : ByteArray} {pos f : Nat} {k : String} {rest : List UInt8}
    (h : At s pos (bytes (encodeString k) ++ rest)) (hl : (bytes (encodeString k)).length < f + 1) :
    readString f s (pos + 1) #[] = .ok (k, pos + (bytes (encodeString k)).length) := by
  rw [bytes_encodeString] at h hl ⊢
  have h' := At_prefix h
  rw [List.append_assoc] at h'
  have hb := readString_body k.toList [] (pos + 1) f h'.2
    (by have := bodyBytes_length k.toList; simp at hl; omega)
  simp only [List.utf8Encode_nil, List.nil_append, String.ofList_toList] at hb
  rw [show ByteArray.empty.data = #[] from rfl] at hb
  rw [hb]
  simp; omega

theorem objBodyB_head (d e : Nat) (k v : String) (es : List (String × String)) :
    ∃ t, objBodyB d e ((k, v) :: es) = bytes (encodeString k) ++ t := by
  cases es with
  | nil => exact ⟨[0x3A, 0x20] ++ bytes v ++ [0x0A] ++ padB e ++ [0x7D], by simp [objBodyB]⟩
  | cons kv es =>
    obtain ⟨k', v'⟩ := kv
    exact ⟨[0x3A, 0x20] ++ bytes v ++ [0x2C, 0x0A] ++ padB d ++ objBodyB d e ((k', v') :: es),
      by simp [objBodyB]⟩

theorem At_at {s : ByteArray} {pos : Nat} {l : List UInt8} (h : At s pos l) {k : Nat} {b : UInt8}
    (hk : l[k]? = some b) : at? s (pos + k) = some b := by
  obtain ⟨hlt, rfl⟩ := List.getElem?_eq_some_iff.1 hk
  exact At_get h k hlt

mutual
theorem readValue_enc : ∀ (v : JVal) {d : Nat} {t : String}, v.Strict → encode d v = .ok t →
    ∀ {s : ByteArray} {pos fuel : Nat}, At s pos (bytes t) → Follow s (pos + (bytes t).length) →
    (bytes t).length < fuel → readValue fuel s pos = .ok (v, pos + (bytes t).length)
  | .null, _, _, _, h, _, _, fuel, hA, hF, hl => by
    unfold encode at h; split at h; · cases h
    cases h
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by omega⟩
    have h4 : (bytes "null").length = 4 := by decide
    rw [h4] at hF ⊢
    exact readValue_null hA hF
  | .bool b, _, _, _, h, _, _, fuel, hA, hF, hl => by
    unfold encode at h; split at h; · cases h
    cases h
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by omega⟩
    exact readValue_bool b hA hF
  | .int i, _, _, _, h, _, _, fuel, hA, hF, hl => by
    unfold encode at h; split at h; · cases h
    cases h
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by omega⟩
    exact readValue_int i hA hF
  | .float _ _, _, _, _, h, _, _, _, _, _, _ => by unfold encode at h; split at h <;> cases h
  | .str str, _, _, _, h, _, _, fuel, hA, hF, hl => by
    unfold encode at h; split at h; · cases h
    cases h
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by omega⟩
    exact readValue_str str hA hl
  | .arr [], _, _, _, h, s, pos, fuel, hA, hF, hl => by
    unfold encode at h; split at h; · cases h
    cases h
    rw [show bytes "[]" = [0x5B, 0x5D] by decide] at hA hl ⊢
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 2 := ⟨fuel - 2, by simp at hl; omega⟩
    have h1 : skipWs s (pos + 1) = pos + 1 := skipWs_stop hA.2.1 (by decide)
    simp [readValue, readArray, hA.1, h1, hA.2.1]
  | .arr (x :: xs), d, t, hc, h, s, pos, fuel, hA, hF, hl => by
    obtain ⟨is, hi, rfl⟩ := encode_arr h
    obtain ⟨i, is', hx, _, rfl⟩ := encodeItems_cons hi
    rw [arr_bytes] at hA hF hl ⊢
    simp only [List.append_assoc, List.length_append, List.length_cons, List.length_nil] at hA hl
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 2 := ⟨fuel - 2, by omega⟩
    obtain ⟨b, hb, hlead⟩ := encode_head hx
    obtain ⟨t1, ht1⟩ := arrBodyB_head (d + 1) d i is'
    obtain ⟨rest, hrest⟩ : ∃ rest, arrBodyB (d + 1) d (i :: is') = b :: rest := by
      rw [ht1]
      cases hbi : bytes i with
      | nil => simp [hbi] at hb
      | cons b' bs => simp [hbi] at hb; subst hb; exact ⟨_, rfl⟩
    have hr := hA.2
    have hw := skip_indent (e := d + 1) (b := b) (rest := rest)
      (by rw [hrest] at hr; simpa using hr) hlead.1
    have hA2 : At s (pos + 1 + 1 + 2 * (d + 1)) (arrBodyB (d + 1) d (i :: is')) := by
      have := At_suffix (a := [0x0A] ++ padB (d + 1)) (b := arrBodyB (d + 1) d (i :: is'))
        (by simpa using hA.2)
      simp only [padB, List.length_append, List.length_cons, List.length_nil,
        List.length_replicate] at this
      rw [show pos + 1 + 1 + 2 * (d + 1) = pos + 1 + (0 + 1 + 2 * (d + 1)) by omega]
      exact this
    have hn : at? s (pos + 1 + 1 + 2 * (d + 1)) = some b := by
      have := hA2; rw [hrest] at this; exact this.1
    have ih := readItems_enc (x :: xs) hc hi (List.cons_ne_nil _ _) (fuel := f) (acc := [])
      hA2 (by simp [padB] at hl; omega)
    have hne1 : b ≠ 0x5D := hlead.2.1
    have hne2 : b ≠ 0x2C := hlead.2.2.1
    simp only [readValue, hA.1, readArray, hw, hn]
    simp [hne1, hne2, ih, padB]
    omega
  | .obj [], _, _, _, h, s, pos, fuel, hA, hF, hl => by
    unfold encode at h; split at h; · cases h
    cases h
    rw [show bytes "{}" = [0x7B, 0x7D] by decide] at hA hl ⊢
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 2 := ⟨fuel - 2, by simp at hl; omega⟩
    have h1 : skipWs s (pos + 1) = pos + 1 := skipWs_stop hA.2.1 (by decide)
    simp [readValue, readObject, hA.1, h1, hA.2.1]
  | .obj ((k, v) :: kvs), d, t, hc, h, s, pos, fuel, hA, hF, hl => by
    obtain ⟨es, he, rfl⟩ := encode_obj h
    have hsort : (es.mergeSort fun a b => !decide (b.1 < a.1)) = es := by
      apply List.mergeSort_of_pairwise
      have hp := hc.1
      rw [← encodeEntries_keys he, List.pairwise_map] at hp
      exact hp.imp fun h' => by simpa using String.lt_asymm h'
    obtain ⟨sv, es', hv, _, rfl⟩ := encodeEntries_cons he
    rw [hsort, obj_bytes] at hA hF hl ⊢
    simp only [List.append_assoc, List.length_append, List.length_cons, List.length_nil] at hA hl
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 2 := ⟨fuel - 2, by omega⟩
    obtain ⟨t1, ht1⟩ := objBodyB_head (d + 1) d k sv es'
    obtain ⟨rest, hrest⟩ : ∃ rest, objBodyB (d + 1) d ((k, sv) :: es') = 0x22 :: rest := by
      rw [ht1, bytes_encodeString]
      exact ⟨bodyBytes k.toList ++ [0x22] ++ t1, by simp⟩
    have hr := hA.2
    have hw := skip_indent (e := d + 1) (b := 0x22) (rest := rest)
      (by rw [hrest] at hr; simpa using hr) (by decide)
    have hA2 : At s (pos + 1 + 1 + 2 * (d + 1)) (objBodyB (d + 1) d ((k, sv) :: es')) := by
      have := At_suffix (a := [0x0A] ++ padB (d + 1)) (b := objBodyB (d + 1) d ((k, sv) :: es'))
        (by simpa using hA.2)
      simp only [padB, List.length_append, List.length_cons, List.length_nil,
        List.length_replicate] at this
      rw [show pos + 1 + 1 + 2 * (d + 1) = pos + 1 + (0 + 1 + 2 * (d + 1)) by omega]
      exact this
    have hn : at? s (pos + 1 + 1 + 2 * (d + 1)) = some 0x22 := by
      have := hA2; rw [hrest] at this; exact this.1
    have ih := readEntries_enc ((k, v) :: kvs) hc.2 he (List.cons_ne_nil _ _) (fuel := f)
      (acc := []) (by simpa using hc.1) hA2 (by simp [padB] at hl; omega)
    simp only [readValue, hA.1, readObject, hw, hn]
    simp [ih, padB]
    omega

theorem readItems_enc : ∀ (xs : List JVal) {d e : Nat} {is : List String}, JVal.StrictList xs →
    encodeItems d xs = .ok is → xs ≠ [] →
    ∀ {s : ByteArray} {pos fuel : Nat} {acc : List JVal}, At s pos (arrBodyB d e is) →
    (arrBodyB d e is).length < fuel →
    readItems fuel s pos acc = .ok (.arr (acc ++ xs), pos + (arrBodyB d e is).length)
  | [], _, _, _, _, _, hne, _, _, _, _, _, _ => absurd rfl hne
  | x :: xs, d, e, is, hc, h, _, s, pos, fuel, acc, hA, hl => by
    obtain ⟨i, is', hx, hxs, rfl⟩ := encodeItems_cons h
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by omega⟩
    cases xs with
    | nil =>
      simp only [encodeItems] at hxs
      cases hxs
      simp only [arrBodyB, List.append_assoc] at hA hl ⊢
      have hi := At_prefix hA
      have hr := At_suffix hA
      have hF : Follow s (pos + (bytes i).length) := Or.inr hr.1
      simp only [List.length_append, List.length_cons, List.length_nil] at hl
      have hv := readValue_enc x hc.1 hx (fuel := f) hi hF (by omega)
      have hw := skip_indent (e := e) (b := 0x5D) (rest := []) (by simpa using hr) (by decide)
      have hcl : at? s (pos + (bytes i).length + 1 + 2 * e) = some 0x5D := by
        have hA' : At s pos ((bytes i ++ [0x0A] ++ padB e) ++ [0x5D]) := by simpa using hA
        have := (At_suffix hA').1
        simp [padB] at this
        rw [show pos + (bytes i).length + 1 + 2 * e = pos + ((bytes i).length + (2 * e + 1)) by omega]
        exact this
      simp only [readItems, bind, Except.bind, hv, hw, hcl]
      simp [padB]
      omega
    | cons y ys =>
      obtain ⟨i2, is'', hy, hys, rfl⟩ := encodeItems_cons hxs
      rw [show arrBodyB d e (i :: i2 :: is'') = bytes i ++ [0x2C, 0x0A] ++ padB d ++
        arrBodyB d e (i2 :: is'') from rfl] at hA hl ⊢
      simp only [List.append_assoc] at hA
      have hi := At_prefix hA
      have hr := At_suffix hA
      have hcomma : at? s (pos + (bytes i).length) = some 0x2C := hr.1
      simp only [List.length_append, List.length_cons, List.length_nil] at hl
      have hv := readValue_enc x hc.1 hx (fuel := f) hi (Or.inl hcomma) (by omega)
      have hw : skipWs s (pos + (bytes i).length) = pos + (bytes i).length :=
        skipWs_stop hcomma (by decide)
      obtain ⟨b, hb, hlead⟩ := encode_head hy
      obtain ⟨t2, ht2⟩ := arrBodyB_head d e i2 is''
      obtain ⟨rest, hrest⟩ : ∃ rest, arrBodyB d e (i2 :: is'') = b :: rest := by
        rw [ht2]
        cases hbi : bytes i2 with
        | nil => simp [hbi] at hb
        | cons b' bs => simp [hbi] at hb; subst hb; exact ⟨_, rfl⟩
      have hr2 := hr.2
      rw [hrest] at hr2
      have hk := skip_indent (e := d) (b := b) (rest := rest) (by simpa using hr2) hlead.1
      have hA2 : At s (pos + (bytes i).length + 1 + 1 + 2 * d) (arrBodyB d e (i2 :: is'')) := by
        have := At_suffix (a := [0x0A] ++ padB d) (b := arrBodyB d e (i2 :: is'')) (by simpa using hr.2)
        simp only [padB, List.length_append, List.length_cons, List.length_nil,
          List.length_replicate] at this
        rw [show pos + (bytes i).length + 1 + 1 + 2 * d =
          pos + (bytes i).length + 1 + (0 + 1 + 2 * d) by omega]
        exact this
      have hn : at? s (pos + (bytes i).length + 1 + 1 + 2 * d) = some b := by
        have := hA2; rw [hrest] at this; exact this.1
      have ih := readItems_enc (y :: ys) hc.2 hxs (List.cons_ne_nil _ _) (fuel := f)
        (acc := acc ++ [x]) hA2 (by omega)
      have hne1 : b ≠ 0x5D := hlead.2.1
      simp only [readItems, bind, Except.bind, hv, hw, hcomma, hk, hn]
      simp [hne1, ih, padB]
      omega

theorem readEntries_enc : ∀ (kvs : List (String × JVal)) {d e : Nat} {es : List (String × String)},
    JVal.StrictObj kvs → encodeEntries d kvs = .ok es → kvs ≠ [] →
    ∀ {s : ByteArray} {pos fuel : Nat} {acc : List (String × JVal)},
    ((acc ++ kvs).map (·.1)).Pairwise (· < ·) → At s pos (objBodyB d e es) →
    (objBodyB d e es).length < fuel →
    readEntries fuel s pos acc = .ok (.obj (acc ++ kvs), pos + (objBodyB d e es).length)
  | [], _, _, _, _, _, hne, _, _, _, _, _, _, _ => absurd rfl hne
  | (k, v) :: kvs, d, e, es, hc, h, _, s, pos, fuel, acc, hp, hA, hl => by
    obtain ⟨sv, es', hv, hes, rfl⟩ := encodeEntries_cons h
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by omega⟩
    -- The shared prefix: key, `: `, value.
    obtain ⟨tail, htail, hsep⟩ : ∃ tail, objBodyB d e ((k, sv) :: es') =
        bytes (encodeString k) ++ [0x3A, 0x20] ++ bytes sv ++ tail ∧
        (tail.head? = some 0x0A ∨ tail.head? = some 0x2C) := by
      cases es' with
      | nil => exact ⟨[0x0A] ++ padB e ++ [0x7D], by simp [objBodyB], Or.inl rfl⟩
      | cons kv es'' =>
        obtain ⟨k', v'⟩ := kv
        exact ⟨[0x2C, 0x0A] ++ padB d ++ objBodyB d e ((k', v') :: es''),
          by simp [objBodyB, List.append_assoc], Or.inr rfl⟩
    have hA' := hA
    rw [htail] at hA' hl
    simp only [List.append_assoc] at hA'
    simp only [List.length_append, List.length_cons, List.length_nil] at hl
    have hkey := readString_key (f := f) hA' (by omega)
    obtain ⟨kpos, hkpos⟩ : ∃ kpos, kpos = pos + (bytes (encodeString k)).length := ⟨_, rfl⟩
    rw [← hkpos] at hkey
    have hr1 := At_suffix hA'
    rw [← hkpos] at hr1
    have hcolon : at? s kpos = some 0x3A := hr1.1
    have hcs : skipWs s kpos = kpos := skipWs_stop hcolon (by decide)
    obtain ⟨b, hb, hlead⟩ := encode_head hv
    obtain ⟨bs, hbs⟩ : ∃ bs, bytes sv = b :: bs := by
      cases hsv : bytes sv with
      | nil => simp [hsv] at hb
      | cons b' bs => simp [hsv] at hb; subst hb; exact ⟨bs, rfl⟩
    have hsp : skipWs s (kpos + 1) = kpos + 2 := by
      have h2 : At s (kpos + 1) ([0x20] ++ [b]) := by
        have := hr1.2; rw [hbs] at this; exact ⟨this.1, this.2.1, trivial⟩
      rw [skipWs_At h2 (by decide) hlead.1]
      simp
    have hvA : At s (kpos + 2) (bytes sv) := by
      have := At_prefix (a := bytes sv) (b := tail) hr1.2.2
      simpa [Nat.add_assoc] using this
    have hF : Follow s (kpos + 2 + (bytes sv).length) := by
      have := At_suffix (a := bytes sv) (b := tail) hr1.2.2
      rcases hsep with h1 | h1 <;> cases ht : tail with
      | nil => simp [ht] at h1
      | cons t ts =>
        simp [ht] at h1; subst h1; rw [ht] at this
        first | exact Or.inr (by simpa [Nat.add_assoc] using this.1)
              | exact Or.inl (by simpa [Nat.add_assoc] using this.1)
    have hval := readValue_enc v hc.1 hv (fuel := f) hvA hF (by omega)
    have hdup : (acc.any (·.1 == k)) = false := by
      rw [List.any_eq_false]
      intro kv hkv heq
      simp only [beq_iff_eq] at heq
      rw [List.map_append, List.pairwise_append] at hp
      have := hp.2.2 kv.1 (List.mem_map_of_mem hkv) k (by simp)
      rw [heq] at this
      exact String.lt_irrefl k this
    have hvt : At s (kpos + 2 + (bytes sv).length) tail := by
      have := At_suffix (a := bytes sv) (b := tail) hr1.2.2
      simpa [Nat.add_assoc] using this
    cases kvs with
    | nil =>
      simp only [encodeEntries] at hes
      cases hes
      have ht : tail = [0x0A] ++ padB e ++ [0x7D] := by
        have := htail; simp only [objBodyB, List.append_assoc] at this
        exact (List.append_cancel_left (List.append_cancel_left (List.append_cancel_left this))).symm
      subst ht
      have hw := skip_indent (e := e) (b := 0x7D) (rest := []) (by simpa using hvt) (by decide)
      have hcl : at? s (kpos + 2 + (bytes sv).length + 1 + 2 * e) = some 0x7D := by
        have hvt' : At s (kpos + 2 + (bytes sv).length) (([0x0A] ++ padB e) ++ [0x7D]) := by
          simpa using hvt
        have := (At_suffix hvt').1
        simp [padB] at this
        rw [show kpos + 2 + (bytes sv).length + 1 + 2 * e =
          kpos + 2 + (bytes sv).length + (2 * e + 1) by omega]
        exact this
      have hsorted := sortEntries_sorted (kvs := acc ++ [(k, v)]) (by simpa using hp)
      simp only [readEntries, bind, Except.bind, hkey, hcs, hcolon, hsp, hval, hdup, hw, hcl]
      simp [hsorted, htail, padB]
      omega
    | cons kv2 kvs' =>
      obtain ⟨k2, v2⟩ := kv2
      obtain ⟨sv2, es'', _, _, rfl⟩ := encodeEntries_cons hes
      have ht : tail = [0x2C, 0x0A] ++ padB d ++ objBodyB d e ((k2, sv2) :: es'') := by
        have := htail; simp only [objBodyB, List.append_assoc] at this
        have := List.append_cancel_left (List.append_cancel_left (List.append_cancel_left this))
        simpa using this.symm
      subst ht
      have hcomma : at? s (kpos + 2 + (bytes sv).length) = some 0x2C := hvt.1
      have hw : skipWs s (kpos + 2 + (bytes sv).length) = kpos + 2 + (bytes sv).length :=
        skipWs_stop hcomma (by decide)
      obtain ⟨t2, ht2⟩ := objBodyB_head d e k2 sv2 es''
      obtain ⟨rest, hrest⟩ : ∃ rest, objBodyB d e ((k2, sv2) :: es'') = 0x22 :: rest := by
        rw [ht2, bytes_encodeString]
        exact ⟨bodyBytes k2.toList ++ [0x22] ++ t2, by simp⟩
      have hr2 := hvt.2
      rw [hrest] at hr2
      have hk := skip_indent (e := d) (b := 0x22) (rest := rest) (by simpa using hr2) (by decide)
      have hA2 : At s (kpos + 2 + (bytes sv).length + 1 + 1 + 2 * d)
          (objBodyB d e ((k2, sv2) :: es'')) := by
        have := At_suffix (a := [0x0A] ++ padB d) (b := objBodyB d e ((k2, sv2) :: es''))
          (by simpa using hvt.2)
        simp only [padB, List.length_append, List.length_cons, List.length_nil,
          List.length_replicate] at this
        rw [show kpos + 2 + (bytes sv).length + 1 + 1 + 2 * d =
          kpos + 2 + (bytes sv).length + 1 + (0 + 1 + 2 * d) by omega]
        exact this
      have hn : at? s (kpos + 2 + (bytes sv).length + 1 + 1 + 2 * d) = some 0x22 := by
        have := hA2; rw [hrest] at this; exact this.1
      have hp' : (((acc ++ [(k, v)]) ++ (k2, v2) :: kvs').map (·.1)).Pairwise (· < ·) := by
        simpa using hp
      have ih := readEntries_enc ((k2, v2) :: kvs') hc.2 hes (List.cons_ne_nil _ _) (fuel := f)
        (acc := acc ++ [(k, v)]) hp' hA2 (by simp [padB] at hl; omega)
      simp only [readEntries, bind, Except.bind, hkey, hcs, hcolon, hsp, hval, hdup, hw, hcomma,
        hk, hn]
      simp [ih, htail, padB]
      omega
end

theorem At_drop (s : ByteArray) (k : Nat) : At s k (s.data.toList.drop k) := by
  by_cases hk : k < s.size
  · have e : s.data.toList.drop k = s[k] :: s.data.toList.drop (k + 1) := by
      rw [List.drop_eq_getElem_cons (by simpa using hk)]
      rfl
    rw [e]
    exact ⟨by unfold at?; rw [dite_eq_left_of_eq_true (eq_true hk)], At_drop s (k + 1)⟩
  · have : s.data.toList.drop k = [] := List.drop_eq_nil_of_le (by simp; omega)
    rw [this]; trivial
termination_by s.size - k

theorem skipWs_end {s : ByteArray} : skipWs s s.size = s.size := by
  rw [skipWs]; simp

/-- Main theorem: the strict parser reads back the canonical text of every
value with strictly sorted keys. -/
theorem parse_canonical {v : JVal} {t : String} (hs : v.Strict) (h : canonical v = .ok t) :
    parse t.toUTF8 = .ok v := by
  unfold canonical at h
  cases he : encode 0 v with
  | error _ => simp [he, Except.map] at h
  | ok t0 =>
    simp only [he, Except.map, Except.ok.injEq] at h
    subst h
    have hb : (t0 ++ "\n").toUTF8.data.toList = bytes t0 ++ [0x0A] := by
      have : (t0 ++ "\n").toUTF8.data.toList = bytes (t0 ++ "\n") := by simp [bytes]
      rw [this, bytes_append, lit_nl]
    have hA := At_drop (t0 ++ "\n").toUTF8 0
    simp only [List.drop_zero, hb] at hA
    have hsize : (t0 ++ "\n").toUTF8.size = (bytes t0).length + 1 := by
      have := congrArg List.length hb; simpa using this
    obtain ⟨b, hb0, hlead⟩ := encode_head he
    have h0 : at? (t0 ++ "\n").toUTF8 0 = some b := by
      cases hbt : bytes t0 with
      | nil => simp [hbt] at hb0
      | cons b' bs => rw [hbt] at hA hb0; simp at hb0; subst hb0; exact hA.1
    have hw : skipWs (t0 ++ "\n").toUTF8 0 = 0 := skipWs_stop h0 hlead.1
    have hnl : at? (t0 ++ "\n").toUTF8 (bytes t0).length = some 0x0A := by
      have := At_suffix hA; simpa using this.1
    have hv := readValue_enc v hs he (fuel := 4 * (t0 ++ "\n").toUTF8.size + 4)
      (At_prefix hA) (Or.inr (by simpa using hnl)) (by omega)
    have hend : skipWs (t0 ++ "\n").toUTF8 (0 + (bytes t0).length) =
        (t0 ++ "\n").toUTF8.size := by
      rw [Nat.zero_add, skipWs_ws hnl (by decide), ← hsize, skipWs_end]
    unfold parse
    simp only [hw, bind, Except.bind]
    split
    · omega
    rw [hv]
    simp only []
    rw [hend]
    simp

end KomkiSpec.Json
