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

end KomkiSpec.Json
