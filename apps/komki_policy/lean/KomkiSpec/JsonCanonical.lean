import KomkiSpec.Json

/-!
# The canonical encoder is injective (CONTRACT.md § 2.6)

`Release.call_hash/4` hashes the canonical JSON of the call; two different
calls must not share that text. A reader for the canonical form (`decV`)
inverts `encode` on every value whose objects list their keys in the order
the encoder sorts them (`JVal.Canon`), so the encoder is injective there
(`encode_injective`, `canonical_injective`). The reader exists only for the
proof; the bridge parses with `Json.parse`.
-/

namespace KomkiSpec

mutual
/-- Every object's keys in the order the encoder sorts them. -/
def JVal.Canon : JVal → Prop
  | .arr xs => JVal.CanonList xs
  | .obj kvs => (kvs.map (·.1)).Pairwise (fun a b => ¬ b < a) ∧ JVal.CanonObj kvs
  | _ => True

def JVal.CanonList : List JVal → Prop
  | [] => True
  | x :: xs => x.Canon ∧ JVal.CanonList xs

def JVal.CanonObj : List (String × JVal) → Prop
  | [] => True
  | (_, v) :: kvs => v.Canon ∧ JVal.CanonObj kvs
end

end KomkiSpec

namespace KomkiSpec.Json

def hexVal (c : Char) : Nat := "0123456789ABCDEF".toList.idxOf c

def unescape (e : Char) : Char :=
  if e == 'b' then Char.ofNat 0x08
  else if e == 't' then '\t'
  else if e == 'n' then '\n'
  else if e == 'f' then Char.ofNat 0x0C
  else if e == 'r' then '\r'
  else e

/-- An escaped string body up to its closing quote, and the rest. -/
def readStr : List Char → Option (List Char × List Char)
  | [] => none
  | c :: r =>
    if c == '"' then some ([], r)
    else if c == '\\' then
      match r with
      | e :: r' =>
        if e == 'u' then
          match r' with
          | _ :: _ :: a :: b :: r'' =>
            (readStr r'').map fun (s, t) => (Char.ofNat (16 * hexVal a + hexVal b) :: s, t)
          | _ => none
        else (readStr r').map fun (s, t) => (unescape e :: s, t)
      | [] => none
    else (readStr r).map fun (s, t) => (c :: s, t)

theorem hexUpper_inv : ∀ n < 32, 16 * hexVal (hexUpper (n / 16)) + hexVal (hexUpper n) = n := by
  decide

theorem char_of_toNat {c : Char} {n : Nat} (h : c.toNat = n) : Char.ofNat n = c := by
  rw [← h, Char.ofNat_toNat]

theorem readStr_escapeChar (c : Char) (r : List Char) :
    readStr ((escapeChar c).toList ++ r) = (readStr r).map fun (s, t) => (c :: s, t) := by
  unfold escapeChar
  by_cases h1 : c = '"'
  · subst h1; rw [readStr.eq_def]; simp [unescape]
  by_cases h2 : c = '\\'
  · subst h2; rw [readStr.eq_def]; simp [unescape]
  by_cases h3 : c.toNat = 0x08
  · simp [h1, h2, h3]; rw [readStr.eq_def]; simp [unescape]; rw [char_of_toNat h3]
  by_cases h4 : c = '\t'
  · subst h4; rw [readStr.eq_def]; simp [unescape]
  by_cases h5 : c = '\n'
  · subst h5; rw [readStr.eq_def]; simp [unescape]
  by_cases h6 : c.toNat = 0x0C
  · simp [h1, h2, h4, h5, h6]; rw [readStr.eq_def]; simp [unescape]; rw [char_of_toNat h6]
  by_cases h7 : c = '\r'
  · subst h7; rw [readStr.eq_def]; simp [unescape]
  by_cases h8 : c.toNat < 0x20
  · simp [h1, h2, h3, h4, h5, h6, h7, h8]
    rw [readStr.eq_def]; simp
    rw [readStr.eq_def]; simp
    rw [hexUpper_inv _ h8, Char.ofNat_toNat]
  · simp [h1, h2, h3, h4, h5, h6, h7, h8]
    rw [readStr.eq_def]; simp [h1, h2]

theorem readStr_escaped (cs r : List Char) :
    readStr ((cs.flatMap fun c => (escapeChar c).toList) ++ '"' :: r) = some (cs, r) := by
  induction cs with
  | nil => rw [readStr.eq_def]; simp
  | cons c cs ih =>
    rw [List.flatMap_cons, List.append_assoc, readStr_escapeChar, ih]; rfl

theorem encodeString_toList (s : String) :
    (encodeString s).toList = '"' :: (s.toList.flatMap fun c => (escapeChar c).toList) ++ ['"'] := by
  simp [encodeString, String.toList_join, List.flatMap_map]

/-- A digit run, read as a natural number. -/
def readNat (cs : List Char) : Option (Nat × List Char) :=
  let ds := cs.takeWhile Char.isDigit
  if ds.isEmpty then none else some (Nat.ofDigitChars 10 ds 0, cs.dropWhile Char.isDigit)

def readInt : List Char → Option (Int × List Char)
  | [] => none
  | c :: r =>
    if c == '-' then (readNat r).map fun (n, t) => (-(n : Int), t)
    else (readNat (c :: r)).map fun (n, t) => ((n : Int), t)

/-- What may follow a number: no further digit. -/
def NoDigit (r : List Char) : Prop := ∀ c, r.head? = some c → c.isDigit = false

theorem readNat_toDigits (n : Nat) {r : List Char} (hr : NoDigit r) :
    readNat (Nat.toDigits 10 n ++ r) = some (n, r) := by
  have hd : ∀ c ∈ Nat.toDigits 10 n, c.isDigit = true := fun c h =>
    Nat.isDigit_of_mem_toDigits (by decide) (by decide) h
  have ht : r.takeWhile Char.isDigit = [] := by
    cases r with
    | nil => rfl
    | cons c r => simp [List.takeWhile, hr c rfl]
  have hdrop : r.dropWhile Char.isDigit = r := by
    cases r with
    | nil => rfl
    | cons c r => simp [List.dropWhile, hr c rfl]
  simp [readNat, List.takeWhile_append_of_pos hd, List.dropWhile_append_of_pos hd, ht, hdrop,
    Nat.toDigits_ne_nil, Nat.ofDigitChars_ten_toDigits]

theorem readInt_toString (i : Int) {r : List Char} (hr : NoDigit r) :
    readInt ((toString i).toList ++ r) = some (i, r) := by
  cases i with
  | ofNat m =>
    obtain ⟨c, ds, hc⟩ : ∃ c ds, Nat.toDigits 10 m = c :: ds := by
      cases h : Nat.toDigits 10 m with
      | nil => exact absurd h Nat.toDigits_ne_nil
      | cons c ds => exact ⟨c, ds, rfl⟩
    have hdig : c.isDigit = true :=
      Nat.isDigit_of_mem_toDigits (by decide) (by decide) (hc ▸ List.mem_cons_self)
    have hneg : (c == '-') = false := by
      cases h : c == '-' with
      | false => rfl
      | true => simp at h; subst h; simp at hdig
    have := readNat_toDigits m hr
    rw [hc, List.cons_append] at this
    simp [Int.toString_eq_repr, Int.repr, Nat.repr_eq_ofList_toDigits, hc, readInt, hneg]
    exact ⟨m, this, rfl⟩
  | negSucc m =>
    simp [Int.toString_eq_repr, Int.repr, Nat.repr_eq_ofList_toDigits, readInt,
      readNat_toDigits _ hr]
    omega

def blank (c : Char) : Bool := c == ' ' || c == '\n'

def skipBlank (cs : List Char) : List Char := cs.dropWhile blank

mutual
/-- A canonical value at the head of `cs`, and the rest. -/
def decV : Nat → List Char → Option (JVal × List Char)
  | 0, _ => none
  | _ + 1, [] => none
  | n + 1, c :: r =>
    if c == '-' || c.isDigit then (readInt (c :: r)).map fun (i, t) => (.int i, t)
    else if c == 'n' then if r.take 3 == ['u', 'l', 'l'] then some (.null, r.drop 3) else none
    else if c == 't' then if r.take 3 == ['r', 'u', 'e'] then some (.bool true, r.drop 3) else none
    else if c == 'f' then
      if r.take 4 == ['a', 'l', 's', 'e'] then some (.bool false, r.drop 4) else none
    else if c == '"' then (readStr r).map fun (s, t) => (.str (String.ofList s), t)
    else if c == '[' then
      if (skipBlank r).head? == some ']' then some (.arr [], (skipBlank r).drop 1)
      else (decItems n (skipBlank r)).map fun (xs, t) => (.arr xs, t)
    else if c == '{' then
      if (skipBlank r).head? == some '}' then some (.obj [], (skipBlank r).drop 1)
      else (decEntries n (skipBlank r)).map fun (kvs, t) => (.obj kvs, t)
    else none

def decItems : Nat → List Char → Option (List JVal × List Char)
  | 0, _ => none
  | n + 1, cs =>
    match decV n cs with
    | none => none
    | some (v, r) =>
      match skipBlank r with
      | c :: t =>
        if c == ',' then (decItems n (skipBlank t)).map fun (vs, u) => (v :: vs, u)
        else if c == ']' then some ([v], t) else none
      | [] => none

def decEntries : Nat → List Char → Option (List (String × JVal) × List Char)
  | 0, _ => none
  | _ + 1, [] => none
  | n + 1, c :: cs =>
    if c != '"' then none else
    match readStr cs with
    | none => none
    | some (k, r) =>
      if r.take 2 != [':', ' '] then none else
      match decV n (r.drop 2) with
      | none => none
      | some (v, r') =>
        match skipBlank r' with
        | c :: t =>
          if c == ',' then
            (decEntries n (skipBlank t)).map fun (kvs, u) => ((String.ofList k, v) :: kvs, u)
          else if c == '}' then some ([(String.ofList k, v)], t) else none
        | [] => none
end

theorem pad_blank (d : Nat) : ∀ c ∈ (pad d).toList, blank c = true := by
  intro c h
  simp [pad, String.toList_join] at h
  obtain ⟨a, ⟨_, rfl⟩, h⟩ := h
  simp at h; subst h; rfl

theorem skipBlank_pad (d : Nat) (r : List Char) :
    skipBlank ((pad d).toList ++ r) = skipBlank r := by
  simp [skipBlank, List.dropWhile_append_of_pos (pad_blank d)]

theorem skipBlank_nl (r : List Char) : skipBlank ('\n' :: r) = skipBlank r := by
  simp [skipBlank, List.dropWhile, blank]

theorem skipBlank_of {c : Char} (h : blank c = false) (r : List Char) :
    skipBlank (c :: r) = c :: r := by
  simp [skipBlank, List.dropWhile, h]

/-- The first character of an encoded value: never blank or a closing bracket. -/
def Lead (c : Char) : Prop := blank c = false ∧ c ≠ ']' ∧ c ≠ '}'

theorem lead_digit {c : Char} (h : c.isDigit = true) : Lead c := by
  refine ⟨?_, ?_, ?_⟩
  · cases hb : blank c with
    | false => rfl
    | true =>
      simp [blank] at hb
      rcases hb with hb | hb <;> subst hb <;> simp at h
  · intro hc; subst hc; simp at h
  · intro hc; subst hc; simp at h

theorem toString_int_lead (i : Int) : ∃ c t, (toString i).toList = c :: t ∧ Lead c := by
  cases i with
  | ofNat m =>
    cases h : Nat.toDigits 10 m with
    | nil => exact absurd h Nat.toDigits_ne_nil
    | cons c ds =>
      refine ⟨c, ds, ?_, lead_digit (Nat.isDigit_of_mem_toDigits (by decide) (by decide)
        (h ▸ List.mem_cons_self))⟩
      simp [Int.toString_eq_repr, Int.repr, Nat.repr_eq_ofList_toDigits, h]
  | negSucc m =>
    refine ⟨'-', (Nat.repr (m + 1)).toList, ?_, rfl, by decide, by decide⟩
    simp [Int.toString_eq_repr, Int.repr]


/-- An array's text after `[`, its newline and the first indent. -/
def arrBody (d e : Nat) : List String → List Char → List Char
  | [], r => r
  | [i], r => i.toList ++ '\n' :: ((pad e).toList ++ ']' :: r)
  | i :: is, r => i.toList ++ ',' :: '\n' :: ((pad d).toList ++ arrBody d e is r)

def entryText (k v : String) : List Char := (encodeString k).toList ++ ':' :: ' ' :: v.toList

/-- An object's text after `{`, its newline and the first indent. -/
def objBody (d e : Nat) : List (String × String) → List Char → List Char
  | [], r => r
  | [(k, v)], r => entryText k v ++ '\n' :: ((pad e).toList ++ '}' :: r)
  | (k, v) :: es, r => entryText k v ++ ',' :: '\n' :: ((pad d).toList ++ objBody d e es r)

theorem arr_text (d e : Nat) (i : String) (is : List String) (r : List Char) :
    (",\n".intercalate ((i :: is).map (pad d ++ ·)) ++ "\n" ++ pad e ++ "]").toList ++ r =
      (pad d).toList ++ arrBody d e (i :: is) r := by
  induction is generalizing i with
  | nil => simp [String.intercalate_singleton, arrBody]
  | cons j js ih =>
    rw [List.map_cons, List.map_cons, String.intercalate_cons_cons]
    rw [← List.map_cons] 
    simp only [String.toList_append, List.append_assoc] at ih ⊢
    rw [ih]; simp [arrBody]

theorem obj_text (d e : Nat) (k v : String) (es : List (String × String)) (r : List Char) :
    (",\n".intercalate (((k, v) :: es).map fun (k, v) => pad d ++ encodeString k ++ ": " ++ v) ++
      "\n" ++ pad e ++ "}").toList ++ r = (pad d).toList ++ objBody d e ((k, v) :: es) r := by
  induction es generalizing k v with
  | nil => simp [String.intercalate_singleton, objBody, entryText]
  | cons kv es ih =>
    obtain ⟨k', v'⟩ := kv
    have ih' := ih k' v'
    simp only [List.map_cons, String.intercalate_cons_cons, String.toList_append,
      List.append_assoc] at ih' ⊢
    rw [ih']; simp [objBody, entryText]

theorem noDigit_cons {c : Char} (h : c.isDigit = false) (r : List Char) : NoDigit (c :: r) := by
  intro c' h'; simp at h'; subst h'; exact h

theorem encode_lead : ∀ {d : Nat} {v : JVal} {s : String}, encode d v = .ok s →
    ∃ c t, s.toList = c :: t ∧ Lead c := by
  intro d v s h
  unfold encode at h
  split at h
  · cases h
  · split at h
    · cases h; exact ⟨'n', _, rfl, rfl, by decide, by decide⟩
    · rename_i b; cases h; cases b
      · exact ⟨'f', _, rfl, rfl, by decide, by decide⟩
      · exact ⟨'t', _, rfl, rfl, by decide, by decide⟩
    · cases h; exact toString_int_lead _
    · cases h
    · cases h; exact ⟨'"', _, by simp [encodeString_toList]; rfl, rfl, by decide, by decide⟩
    · cases h; exact ⟨'[', _, rfl, rfl, by decide, by decide⟩
    · simp only [bind, Except.bind] at h
      split at h
      · cases h
      · cases h; exact ⟨'[', _, by simp; rfl, rfl, by decide, by decide⟩
    · cases h; exact ⟨'{', _, rfl, rfl, by decide, by decide⟩
    · simp only [bind, Except.bind] at h
      split at h
      · cases h
      · cases h; exact ⟨'{', _, by simp; rfl, rfl, by decide, by decide⟩

theorem toString_int_head (i : Int) :
    ∃ c t, (toString i).toList = c :: t ∧ (c == '-' || c.isDigit) = true := by
  cases i with
  | ofNat m =>
    cases h : Nat.toDigits 10 m with
    | nil => exact absurd h Nat.toDigits_ne_nil
    | cons c ds =>
      refine ⟨c, ds, ?_, ?_⟩
      · simp [Int.toString_eq_repr, Int.repr, Nat.repr_eq_ofList_toDigits, h]
      · simp [Nat.isDigit_of_mem_toDigits (by decide) (by decide) (h ▸ List.mem_cons_self)]
  | negSucc m => exact ⟨'-', (Nat.repr (m + 1)).toList, by simp [Int.toString_eq_repr, Int.repr], rfl⟩

theorem encode_arr {d : Nat} {x : JVal} {xs : List JVal} {s : String}
    (h : encode d (.arr (x :: xs)) = .ok s) : ∃ is, encodeItems (d + 1) (x :: xs) = .ok is ∧
      s = "[\n" ++ ",\n".intercalate (is.map (pad (d + 1) ++ ·)) ++ "\n" ++ pad d ++ "]" := by
  unfold encode at h
  split at h
  · cases h
  · simp only [bind, Except.bind] at h
    split at h
    · cases h
    · rename_i is hi; cases h; exact ⟨is, hi, rfl⟩

theorem encode_obj {d : Nat} {kv : String × JVal} {kvs : List (String × JVal)} {s : String}
    (h : encode d (.obj (kv :: kvs)) = .ok s) : ∃ es, encodeEntries (d + 1) (kv :: kvs) = .ok es ∧
      s = "{\n" ++ ",\n".intercalate
        ((es.mergeSort fun a b => !decide (b.1 < a.1)).map fun (k, v) =>
          pad (d + 1) ++ encodeString k ++ ": " ++ v) ++ "\n" ++ pad d ++ "}" := by
  unfold encode at h
  split at h
  · cases h
  · simp only [bind, Except.bind] at h
    split at h
    · cases h
    · rename_i es he; cases h; exact ⟨es, he, rfl⟩

theorem encodeItems_cons {d : Nat} {x : JVal} {xs : List JVal} {is : List String}
    (h : encodeItems d (x :: xs) = .ok is) :
    ∃ i is', encode d x = .ok i ∧ encodeItems d xs = .ok is' ∧ is = i :: is' := by
  simp only [encodeItems, bind, Except.bind] at h
  split at h
  · cases h
  · split at h
    · cases h
    · rename_i i hi _ is' hs; cases h; exact ⟨i, is', hi, hs, rfl⟩

theorem encodeEntries_cons {d : Nat} {k : String} {v : JVal} {kvs : List (String × JVal)}
    {es : List (String × String)} (h : encodeEntries d ((k, v) :: kvs) = .ok es) :
    ∃ sv es', encode d v = .ok sv ∧ encodeEntries d kvs = .ok es' ∧ es = (k, sv) :: es' := by
  simp only [encodeEntries, bind, Except.bind] at h
  split at h
  · cases h
  · split at h
    · cases h
    · rename_i sv hv _ es' hs; cases h; exact ⟨sv, es', hv, hs, rfl⟩

theorem encodeEntries_keys : ∀ {d : Nat} {kvs : List (String × JVal)} {es : List (String × String)},
    encodeEntries d kvs = .ok es → es.map (·.1) = kvs.map (·.1)
  | _, [], es, h => by simp [encodeEntries] at h; cases h; rfl
  | _, (k, v) :: kvs, es, h => by
    obtain ⟨sv, es', _, hs, rfl⟩ := encodeEntries_cons h
    simp [encodeEntries_keys hs]

theorem decV_str (s0 : String) (n : Nat) (r : List Char) :
    decV (n + 1) ((encodeString s0).toList ++ r) = some (.str s0, r) := by
  rw [encodeString_toList, List.cons_append]
  simp only [decV]
  simp [List.append_assoc, readStr_escaped]

theorem decV_null (n : Nat) (r : List Char) : decV (n + 1) ("null".toList ++ r) = some (.null, r) := by
  simp only [decV]; simp

theorem decV_bool (b : Bool) (n : Nat) (r : List Char) :
    decV (n + 1) ((if b then "true" else "false").toList ++ r) = some (.bool b, r) := by
  cases b <;> simp only [decV] <;> simp

theorem decV_int (i : Int) (n : Nat) {r : List Char} (hr : NoDigit r) :
    decV (n + 1) ((toString i).toList ++ r) = some (.int i, r) := by
  obtain ⟨c, t, hs, hc⟩ := toString_int_head i
  have hi := readInt_toString i hr
  rw [hs, List.cons_append] at hi ⊢
  simp only [decV]; simp [hc, hi]

theorem decV_emptyArr (n : Nat) (r : List Char) : decV (n + 1) ("[]".toList ++ r) = some (.arr [], r) := by
  simp only [decV]; simp [skipBlank_of (c := ']') (by decide)]

theorem decV_emptyObj (n : Nat) (r : List Char) : decV (n + 1) ("{}".toList ++ r) = some (.obj [], r) := by
  simp only [decV]; simp [skipBlank_of (c := '}') (by decide)]

theorem decV_arr {n : Nat} {body r : List Char} {xs : List JVal} (d : Nat)
    (hb : skipBlank body = body) (hh : body.head? ≠ some ']') (hi : decItems n body = some (xs, r)) :
    decV (n + 1) ('[' :: '\n' :: ((pad d).toList ++ body)) = some (.arr xs, r) := by
  simp only [decV]
  simp [skipBlank_nl, skipBlank_pad, hb, hh, hi]

theorem decV_obj {n : Nat} {body r : List Char} {kvs : List (String × JVal)} (d : Nat)
    (hb : skipBlank body = body) (hh : body.head? ≠ some '}')
    (hi : decEntries n body = some (kvs, r)) :
    decV (n + 1) ('{' :: '\n' :: ((pad d).toList ++ body)) = some (.obj kvs, r) := by
  simp only [decV]
  simp [skipBlank_nl, skipBlank_pad, hb, hh, hi]

theorem decItems_last {n : Nat} {cs r : List Char} {x : JVal} (e : Nat)
    (hv : decV n cs = some (x, '\n' :: ((pad e).toList ++ ']' :: r))) :
    decItems (n + 1) cs = some ([x], r) := by
  simp only [decItems, hv]
  simp [skipBlank_nl, skipBlank_pad, skipBlank_of (c := ']') (by decide)]

theorem decItems_more {n : Nat} {cs body r : List Char} {x : JVal} {xs : List JVal} (d : Nat)
    (hv : decV n cs = some (x, ',' :: '\n' :: ((pad d).toList ++ body)))
    (hb : skipBlank body = body) (hi : decItems n body = some (xs, r)) :
    decItems (n + 1) cs = some (x :: xs, r) := by
  simp only [decItems, hv]
  simp [skipBlank_of (c := ',') (by decide), skipBlank_nl, skipBlank_pad, hb, hi]

theorem decEntries_last {n : Nat} {k sv : String} {r : List Char} {v : JVal} (e : Nat)
    (hv : decV n (sv.toList ++ '\n' :: ((pad e).toList ++ '}' :: r)) =
      some (v, '\n' :: ((pad e).toList ++ '}' :: r))) :
    decEntries (n + 1) (entryText k sv ++ '\n' :: ((pad e).toList ++ '}' :: r)) =
      some ([(k, v)], r) := by
  simp only [entryText, encodeString_toList, List.cons_append, List.append_assoc]
  simp only [decEntries]
  simp [readStr_escaped, hv, skipBlank_nl, skipBlank_pad, skipBlank_of (c := '}') (by decide)]

theorem decEntries_more {n : Nat} {k sv : String} {body r : List Char} {v : JVal}
    {kvs : List (String × JVal)} (d : Nat)
    (hv : decV n (sv.toList ++ ',' :: '\n' :: ((pad d).toList ++ body)) =
      some (v, ',' :: '\n' :: ((pad d).toList ++ body)))
    (hb : skipBlank body = body) (hi : decEntries n body = some (kvs, r)) :
    decEntries (n + 1) (entryText k sv ++ ',' :: '\n' :: ((pad d).toList ++ body)) =
      some ((k, v) :: kvs, r) := by
  simp only [entryText, encodeString_toList, List.cons_append, List.append_assoc]
  simp only [decEntries]
  simp [readStr_escaped, hv, skipBlank_of (c := ',') (by decide), skipBlank_nl, skipBlank_pad,
    hb, hi]

theorem arrBody_head (d e : Nat) (i : String) (is : List String) (r : List Char) :
    ∃ t, arrBody d e (i :: is) r = i.toList ++ t := by
  cases is <;> exact ⟨_, rfl⟩

theorem objBody_head (d e : Nat) (k v : String) (es : List (String × String)) (r : List Char) :
    ∃ t, objBody d e ((k, v) :: es) r = '"' :: t := by
  cases es <;> simp [objBody, entryText, encodeString_toList]

/-- From fuel `N` on. -/
abbrev Eventually (p : Nat → Prop) : Prop := ∃ N, ∀ n, N ≤ n → p n

mutual
theorem decV_encode : ∀ (v : JVal) {d : Nat} {s : String}, v.Canon → encode d v = .ok s →
    ∀ {r : List Char}, NoDigit r → Eventually fun n => decV n (s.toList ++ r) = some (v, r)
  | .null, _, _, _, h, _, _ => by
    unfold encode at h; split at h; · cases h
    cases h
    exact ⟨1, fun n hn => by cases n with | zero => omega | succ n => exact decV_null n _⟩
  | .bool b, _, _, _, h, _, _ => by
    unfold encode at h; split at h; · cases h
    cases h
    exact ⟨1, fun n hn => by cases n with | zero => omega | succ n => exact decV_bool b n _⟩
  | .int i, _, _, _, h, _, hr => by
    unfold encode at h; split at h; · cases h
    cases h
    exact ⟨1, fun n hn => by cases n with | zero => omega | succ n => exact decV_int i n hr⟩
  | .float _ _, _, _, _, h, _, _ => by
    unfold encode at h; split at h <;> cases h
  | .str s0, _, _, _, h, _, _ => by
    unfold encode at h; split at h; · cases h
    cases h
    exact ⟨1, fun n hn => by cases n with | zero => omega | succ n => exact decV_str s0 n _⟩
  | .arr [], _, _, _, h, _, _ => by
    unfold encode at h; split at h; · cases h
    cases h
    exact ⟨1, fun n hn => by cases n with | zero => omega | succ n => exact decV_emptyArr n _⟩
  | .arr (x :: xs), d, s, hc, h, r, _ => by
    obtain ⟨is, hi, rfl⟩ := encode_arr h
    obtain ⟨N, hN⟩ := decItems_encode (x :: xs) (e := d) hc hi r (List.cons_ne_nil _ _)
    obtain ⟨i, is', hx, _, rfl⟩ := encodeItems_cons hi
    obtain ⟨c, t, hs, hl⟩ := encode_lead hx
    obtain ⟨u, hu⟩ := arrBody_head (d + 1) d i is' r
    have hb : skipBlank (arrBody (d + 1) d (i :: is') r) = arrBody (d + 1) d (i :: is') r := by
      rw [hu, hs]; exact skipBlank_of hl.1 _
    have hh : (arrBody (d + 1) d (i :: is') r).head? ≠ some ']' := by
      rw [hu, hs]; simp [hl.2.1]
    have ht : ("[\n" ++ ",\n".intercalate ((i :: is').map (pad (d + 1) ++ ·)) ++ "\n" ++ pad d ++
        "]").toList ++ r = '[' :: '\n' :: ((pad (d + 1)).toList ++ arrBody (d + 1) d (i :: is') r) := by
      rw [← arr_text]; simp [String.toList_append]
    refine ⟨N + 1, fun n hn => ?_⟩
    cases n with
    | zero => omega
    | succ n => rw [ht]; exact decV_arr (d + 1) hb hh (hN n (by omega))
  | .obj [], _, _, _, h, _, _ => by
    unfold encode at h; split at h; · cases h
    cases h
    exact ⟨1, fun n hn => by cases n with | zero => omega | succ n => exact decV_emptyObj n _⟩
  | .obj ((k, v) :: kvs), d, s, hc, h, r, _ => by
    obtain ⟨es, he, rfl⟩ := encode_obj h
    have hsort : (es.mergeSort fun a b => !decide (b.1 < a.1)) = es := by
      apply List.mergeSort_of_pairwise
      have hp := hc.1
      rw [← encodeEntries_keys he, List.pairwise_map] at hp
      exact hp.imp fun h => by simpa using h
    obtain ⟨N, hN⟩ := decEntries_encode ((k, v) :: kvs) (e := d) hc.2 he r (List.cons_ne_nil _ _)
    obtain ⟨sv, es', _, _, rfl⟩ := encodeEntries_cons he
    obtain ⟨t, hu⟩ := objBody_head (d + 1) d k sv es' r
    have hb : skipBlank (objBody (d + 1) d ((k, sv) :: es') r) = objBody (d + 1) d ((k, sv) :: es') r := by
      rw [hu]; exact skipBlank_of rfl _
    have hh : (objBody (d + 1) d ((k, sv) :: es') r).head? ≠ some '}' := by
      rw [hu]; simp
    have ht : ("{\n" ++ ",\n".intercalate (((k, sv) :: es').map fun (k, v) =>
        pad (d + 1) ++ encodeString k ++ ": " ++ v) ++ "\n" ++ pad d ++ "}").toList ++ r =
        '{' :: '\n' :: ((pad (d + 1)).toList ++ objBody (d + 1) d ((k, sv) :: es') r) := by
      rw [← obj_text]; simp [String.toList_append]
    refine ⟨N + 1, fun n hn => ?_⟩
    cases n with
    | zero => omega
    | succ n => rw [hsort, ht]; exact decV_obj (d + 1) hb hh (hN n (by omega))

theorem decItems_encode : ∀ (xs : List JVal) {d e : Nat} {is : List String}, JVal.CanonList xs →
    encodeItems d xs = .ok is → ∀ (r : List Char), xs ≠ [] →
    Eventually fun n => decItems n (arrBody d e is r) = some (xs, r)
  | [], _, _, _, _, _, _, h => absurd rfl h
  | [x], _, e, _, hc, h, r, _ => by
    obtain ⟨i, is', hx, hxs, rfl⟩ := encodeItems_cons h
    simp [encodeItems] at hxs; subst hxs
    obtain ⟨N, hN⟩ := decV_encode x hc.1 hx (r := '\n' :: ((pad e).toList ++ ']' :: r))
      (noDigit_cons rfl _)
    exact ⟨N + 1, fun n hn => by
      cases n with | zero => omega | succ n => exact decItems_last e (hN n (by omega))⟩
  | x :: y :: ys, d, e, _, hc, h, r, _ => by
    obtain ⟨i, is', hx, hxs, rfl⟩ := encodeItems_cons h
    obtain ⟨M, hM⟩ := decItems_encode (y :: ys) (e := e) hc.2 hxs r (List.cons_ne_nil _ _)
    obtain ⟨j, is'', hy, _, rfl⟩ := encodeItems_cons hxs
    obtain ⟨N, hN⟩ := decV_encode x hc.1 hx
      (r := ',' :: '\n' :: ((pad d).toList ++ arrBody d e (j :: is'') r)) (noDigit_cons rfl _)
    obtain ⟨c, t, hs, hl⟩ := encode_lead hy
    obtain ⟨u, hu⟩ := arrBody_head d e j is'' r
    have hb : skipBlank (arrBody d e (j :: is'') r) = arrBody d e (j :: is'') r := by
      rw [hu, hs]; exact skipBlank_of hl.1 _
    exact ⟨max N M + 1, fun n hn => by
      cases n with
      | zero => omega
      | succ n => exact decItems_more d (hN n (by omega)) hb (hM n (by omega))⟩

theorem decEntries_encode : ∀ (kvs : List (String × JVal)) {d e : Nat}
    {es : List (String × String)}, JVal.CanonObj kvs → encodeEntries d kvs = .ok es →
    ∀ (r : List Char), kvs ≠ [] → Eventually fun n => decEntries n (objBody d e es r) = some (kvs, r)
  | [], _, _, _, _, _, _, h => absurd rfl h
  | [(_, v)], _, e, _, hc, h, r, _ => by
    obtain ⟨sv, es', hv, hs, rfl⟩ := encodeEntries_cons h
    simp [encodeEntries] at hs; subst hs
    obtain ⟨N, hN⟩ := decV_encode v hc.1 hv (r := '\n' :: ((pad e).toList ++ '}' :: r))
      (noDigit_cons rfl _)
    exact ⟨N + 1, fun n hn => by
      cases n with | zero => omega | succ n => exact decEntries_last e (hN n (by omega))⟩
  | (_, v) :: (k', v') :: kvs, d, e, _, hc, h, r, _ => by
    obtain ⟨sv, es', hv, hs, rfl⟩ := encodeEntries_cons h
    obtain ⟨M, hM⟩ := decEntries_encode ((k', v') :: kvs) (e := e) hc.2 hs r (List.cons_ne_nil _ _)
    obtain ⟨sv', es'', _, _, rfl⟩ := encodeEntries_cons hs
    obtain ⟨N, hN⟩ := decV_encode v hc.1 hv
      (r := ',' :: '\n' :: ((pad d).toList ++ objBody d e ((k', sv') :: es'') r)) (noDigit_cons rfl _)
    obtain ⟨t, hu⟩ := objBody_head d e k' sv' es'' r
    have hb : skipBlank (objBody d e ((k', sv') :: es'') r) = objBody d e ((k', sv') :: es'') r := by
      rw [hu]; exact skipBlank_of rfl _
    exact ⟨max N M + 1, fun n hn => by
      cases n with
      | zero => omega
      | succ n => exact decEntries_more d (hN n (by omega)) hb (hM n (by omega))⟩
end

theorem encode_injective {d : Nat} {v w : JVal} {s : String} (hv : v.Canon) (hw : w.Canon)
    (h : encode d v = .ok s) (h' : encode d w = .ok s) : v = w := by
  have hr : NoDigit [] := fun _ h => by simp at h
  obtain ⟨N, hN⟩ := decV_encode v hv h hr
  obtain ⟨M, hM⟩ := decV_encode w hw h' hr
  have := (hN (max N M) (Nat.le_max_left _ _)).symm.trans (hM (max N M) (Nat.le_max_right _ _))
  simpa using this

theorem canonical_injective {v w : JVal} {t : String} (hv : v.Canon) (hw : w.Canon)
    (h : canonical v = .ok t) (h' : canonical w = .ok t) : v = w := by
  unfold canonical at h h'
  cases he : encode 0 v with
  | error _ => simp [he, Except.map] at h
  | ok s =>
    cases he' : encode 0 w with
    | error _ => simp [he', Except.map] at h'
    | ok s' =>
      simp [he, he', Except.map] at h h'
      have : s.toList = s'.toList := by
        have := congrArg String.toList (h.trans h'.symm)
        simpa [String.toList_append] using this
      exact encode_injective hv hw he (String.ext this ▸ he')

end KomkiSpec.Json
