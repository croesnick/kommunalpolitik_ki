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

end KomkiSpec.Json
