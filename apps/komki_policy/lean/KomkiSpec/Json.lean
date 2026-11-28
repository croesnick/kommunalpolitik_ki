import KomkiSpec.JVal

/-!
# The strict JSON parser and the canonical encoder (CONTRACT.md § 6)

Mirrors `KomkiPolicy.JSON`. `parse` accepts RFC 8259 with the repository's
rules: no duplicate keys, no trailing commas, no `NaN`/`Infinity`, no leading
`+`, well-formed UTF-8, surrogates only in pairs, finite floats only. It
reports the error code Elixir reports. `canonical` is the byte-stable
encoding the call hash (§ 2.6) is taken over: keys sorted, two-space
indent, one final newline, nesting up to 128. Both are executable
specifications the differential test holds against Elixir; floats are
parsed but not printed (`Float.to_string/1` is not modelled).
-/

namespace KomkiSpec.Json

def at? (s : ByteArray) (pos : Nat) : Option UInt8 :=
  if h : pos < s.size then some s[pos] else none

def isWs (b : UInt8) : Bool := b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
def inRange (b lo hi : UInt8) : Bool := lo ≤ b && b ≤ hi
def isDigit (b : UInt8) : Bool := inRange b 0x30 0x39
def isAlnum (b : UInt8) : Bool := isDigit b || inRange b 0x41 0x5A || inRange b 0x61 0x7A
def isHex (b : UInt8) : Bool := isDigit b || inRange b 0x41 0x46 || inRange b 0x61 0x66

def hexValue (b : UInt8) : Nat :=
  if isDigit b then (b - 0x30).toNat
  else if b ≤ 0x46 then (b - 0x41).toNat + 10
  else (b - 0x61).toNat + 10

def skipWs (s : ByteArray) (pos : Nat) : Nat :=
  if h : pos < s.size then
    if isWs s[pos] then skipWs s (pos + 1) else pos
  else pos
termination_by s.size - pos

/-- `true`, `false`, `null`: the literal, not followed by a letter or digit. -/
def keyword (s : ByteArray) (pos : Nat) (kw : String) (v : JVal) : Except String (JVal × Nat) :=
  let bytes := kw.toUTF8
  let n := bytes.size
  if pos + n ≤ s.size && (List.range n).all fun i => s.get! (pos + i) == bytes.get! i then
    match at? s (pos + n) with
    | some b => if isAlnum b then .error "unterminated_literal" else .ok (v, pos + n)
    | none => .ok (v, pos + n)
  else .error "unterminated_literal"

/-- `utf8_seq/2`: the length of a well-formed multi-byte sequence (RFC 3629). -/
def utf8Len (s : ByteArray) (pos : Nat) (lead : UInt8) : Option Nat :=
  let cont := fun i lo hi => match at? s (pos + i) with
    | some b => inRange b lo hi
    | none => false
  if inRange lead 0xC2 0xDF && cont 1 0x80 0xBF then some 2
  else if (inRange lead 0xE1 0xEC || inRange lead 0xEE 0xEF) && cont 1 0x80 0xBF &&
      cont 2 0x80 0xBF then some 3
  else if lead == 0xE0 && cont 1 0xA0 0xBF && cont 2 0x80 0xBF then some 3
  else if lead == 0xED && cont 1 0x80 0x9F && cont 2 0x80 0xBF then some 3
  else if lead == 0xF0 && cont 1 0x90 0xBF && cont 2 0x80 0xBF && cont 3 0x80 0xBF then some 4
  else if inRange lead 0xF1 0xF3 && cont 1 0x80 0xBF && cont 2 0x80 0xBF && cont 3 0x80 0xBF then
    some 4
  else if lead == 0xF4 && cont 1 0x80 0x8F && cont 2 0x80 0xBF && cont 3 0x80 0xBF then some 4
  else none

def utf8 (cp : Nat) : Array UInt8 :=
  if cp < 0x80 then #[cp.toUInt8]
  else if cp < 0x800 then #[(0xC0 + cp / 64).toUInt8, (0x80 + cp % 64).toUInt8]
  else if cp < 0x10000 then
    #[(0xE0 + cp / 4096).toUInt8, (0x80 + cp / 64 % 64).toUInt8, (0x80 + cp % 64).toUInt8]
  else
    #[(0xF0 + cp / 262144).toUInt8, (0x80 + cp / 4096 % 64).toUInt8,
      (0x80 + cp / 64 % 64).toUInt8, (0x80 + cp % 64).toUInt8]

/-- Four hex digits at `pos`, if there are four. -/
def hex4? (s : ByteArray) (pos : Nat) : Option (Option Nat) :=
  if pos + 4 > s.size then none
  else
    let ds := (List.range 4).map fun i => s.get! (pos + i)
    some (if ds.all isHex then some (ds.foldl (fun n b => 16 * n + hexValue b) 0) else none)

def simpleEscape (b : UInt8) : Option UInt8 :=
  if b == 0x22 || b == 0x5C || b == 0x2F then some b
  else if b == 0x6E then some 0x0A
  else if b == 0x72 then some 0x0D
  else if b == 0x74 then some 0x09
  else if b == 0x62 then some 0x08
  else if b == 0x66 then some 0x0C
  else none

/-- The rest of a string after its opening quote. -/
def readString : Nat → ByteArray → Nat → Array UInt8 → Except String (String × Nat)
  | 0, _, _, _ => .error "fuel"
  | fuel + 1, s, pos, acc =>
    match at? s pos with
    | none => .error "unterminated_literal"
    | some b =>
      if b == 0x22 then
        match String.fromUTF8? (ByteArray.mk acc) with
        | some str => .ok (str, pos + 1)
        | none => .error "invalid_utf8"
      else if b == 0x5C then
        match at? s (pos + 1) with
        | none => .error "unterminated_literal"
        | some e =>
          if e == 0x75 then
            match hex4? s (pos + 2) with
            | none => .error "unterminated_literal"
            | some none => .error "invalid_string"
            | some (some high) =>
              let next := pos + 6
              if 0xD800 ≤ high && high ≤ 0xDBFF then
                let low := if next + 1 < s.size && s.get! next == 0x5C && s.get! (next + 1) == 0x75
                  then (hex4? s (next + 2)).join else none
                match low with
                | some low =>
                  if 0xDC00 ≤ low && low ≤ 0xDFFF then
                    readString fuel s (next + 6)
                      (acc ++ utf8 (0x10000 + (high - 0xD800) * 0x400 + (low - 0xDC00)))
                  else .error "invalid_string"
                | none => .error "invalid_string"
              else if 0xDC00 ≤ high && high ≤ 0xDFFF then .error "invalid_string"
              else readString fuel s next (acc ++ utf8 high)
          else match simpleEscape e with
            | some c => readString fuel s (pos + 2) (acc.push c)
            | none => .error "invalid_string"
      else if b < 0x20 then .error "invalid_string"
      else if b < 0x80 then readString fuel s (pos + 1) (acc.push b)
      else match utf8Len s pos b with
        | some n => readString fuel s (pos + n) (acc ++ (s.extract pos (pos + n)).data)
        | none => .error "invalid_utf8"

def isNumberByte (b : UInt8) : Bool :=
  isDigit b || b == 0x2D || b == 0x2B || b == 0x2E || b == 0x65 || b == 0x45

def numberEnd (s : ByteArray) (pos : Nat) : Nat :=
  if h : pos < s.size then
    if isNumberByte s[pos] then numberEnd s (pos + 1) else pos
  else pos
termination_by s.size - pos

/-- A number token split as `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`:
sign, integer digits, fraction digits, exponent; `none` outside the grammar. -/
structure NumberToken where
  negative : Bool
  digits : List UInt8
  fraction : Option (List UInt8)
  exponent : Option (Bool × List UInt8)

def splitNumber (bs : List UInt8) : Option NumberToken :=
  let (negative, bs) := match bs with
    | 0x2D :: rest => (true, rest)
    | rest => (false, rest)
  let digits := bs.takeWhile isDigit
  let bs := bs.drop digits.length
  if digits.isEmpty || (digits.head! == 0x30 && digits.length > 1) then none else
  let (fraction, bs) := match bs with
    | 0x2E :: rest =>
      let fs := rest.takeWhile isDigit
      (some fs, rest.drop fs.length)
    | rest => (none, rest)
  if fraction == some [] then none else
  let (exponent, bs) := match bs with
    | e :: rest =>
      if e == 0x65 || e == 0x45 then
        let (neg, rest) := match rest with
          | 0x2D :: r => (true, r)
          | 0x2B :: r => (false, r)
          | r => (false, r)
        let es := rest.takeWhile isDigit
        (some (neg, es), rest.drop es.length)
      else (none, e :: rest)
    | [] => (none, [])
  if (exponent.map (·.2.isEmpty)).getD false || !bs.isEmpty then none
  else some { negative, digits, fraction, exponent }

def digitsValue (ds : List UInt8) : Nat := ds.foldl (fun n d => 10 * n + (d - 0x30).toNat) 0

/-- The smallest magnitude that rounds to infinity: halfway between the
largest double and 2^1024. That `binary_to_float/1` fails from there on is
held by the differential test (`@overflow_cases`), not proven. -/
def overflowBound : Nat := 2 ^ 1024 - 2 ^ 970

def digitCount (n : Nat) : Nat := (toString n).length

/-- Whether `m · 10^e` rounds to a finite double. -/
def finiteDouble (m : Nat) (e : Int) : Bool :=
  if m == 0 then true
  else
    let size := (digitCount m : Int) + e
    if size ≥ 310 then false
    else if size ≤ 308 then true
    else if e ≥ 0 then m * 10 ^ e.toNat < overflowBound
    else m < overflowBound * 10 ^ (-e).toNat

def readNumber (s : ByteArray) (pos : Nat) : Except String (JVal × Nat) :=
  let stop := numberEnd s pos
  match splitNumber (s.extract pos stop).data.toList with
  | none => .error "invalid_number"
  | some t =>
    let sign : Int := if t.negative then -1 else 1
    if t.fraction.isNone && t.exponent.isNone then
      .ok (.int (sign * digitsValue t.digits), stop)
    else
      let frac := t.fraction.getD []
      let m := digitsValue (t.digits ++ frac)
      let exp : Int := match t.exponent with
        | some (neg, es) => (if neg then -1 else 1) * digitsValue es
        | none => 0
      let e := exp - frac.length
      if !finiteDouble m e then .error "invalid_number"
      else if m == 0 then .ok (.float 0 0, stop)
      else if e ≥ 0 then .ok (.float (sign * m * 10 ^ e.toNat) 0, stop)
      else .ok (.float (sign * m) (-e).toNat, stop)

def sortEntries (kvs : List (String × JVal)) : List (String × JVal) :=
  kvs.mergeSort fun a b => !decide (b.1 < a.1)

mutual
def readValue : Nat → ByteArray → Nat → Except String (JVal × Nat)
  | 0, _, _ => .error "fuel"
  | fuel + 1, s, pos =>
    match at? s pos with
    | none => .error "incomplete_document"
    | some b =>
      if b == 0x7B then readObject fuel s (pos + 1)
      else if b == 0x5B then readArray fuel s (pos + 1)
      else if b == 0x22 then (readString fuel s (pos + 1) #[]).map fun (str, p) => (.str str, p)
      else if b == 0x6E then keyword s pos "null" .null
      else if b == 0x74 then keyword s pos "true" (.bool true)
      else if b == 0x66 then keyword s pos "false" (.bool false)
      else if isDigit b || b == 0x2D then readNumber s pos
      else if b == 0x2B || b == 0x4E || b == 0x49 then .error "invalid_number"
      else .error "unexpected_byte"

def readObject : Nat → ByteArray → Nat → Except String (JVal × Nat)
  | 0, _, _ => .error "fuel"
  | fuel + 1, s, pos =>
    let w := skipWs s pos
    match at? s w with
    | none => .error "incomplete_document"
    | some b =>
      if b == 0x7D then .ok (.obj [], w + 1)
      else if b == 0x22 then readEntries fuel s w []
      else .error "unexpected_byte"

/-- Entries from the key's opening quote at `pos`. -/
def readEntries : Nat → ByteArray → Nat → List (String × JVal) → Except String (JVal × Nat)
  | 0, _, _, _ => .error "fuel"
  | fuel + 1, s, pos, acc => do
    let (key, kpos) ← readString fuel s (pos + 1) #[]
    let colon := skipWs s kpos
    match at? s colon with
    | none => .error "incomplete_document"
    | some c =>
      if c != 0x3A then .error "unexpected_byte" else
      let (v, vpos) ← readValue fuel s (skipWs s (colon + 1))
      if acc.any (·.1 == key) then .error "duplicate_json_key" else
      let acc := acc ++ [(key, v)]
      let w := skipWs s vpos
      match at? s w with
      | none => .error "incomplete_document"
      | some b =>
        if b == 0x7D then .ok (.obj (sortEntries acc), w + 1)
        else if b == 0x2C then
          let k := skipWs s (w + 1)
          match at? s k with
          | none => .error "incomplete_document"
          | some n =>
            if n == 0x7D then .error "trailing_comma"
            else if n == 0x22 then readEntries fuel s k acc
            else .error "unexpected_byte"
        else .error "unexpected_byte"

def readArray : Nat → ByteArray → Nat → Except String (JVal × Nat)
  | 0, _, _ => .error "fuel"
  | fuel + 1, s, pos =>
    let w := skipWs s pos
    match at? s w with
    | none => .error "incomplete_document"
    | some b =>
      if b == 0x5D then .ok (.arr [], w + 1)
      else if b == 0x2C then .error "unexpected_byte"
      else readItems fuel s w []

def readItems : Nat → ByteArray → Nat → List JVal → Except String (JVal × Nat)
  | 0, _, _, _ => .error "fuel"
  | fuel + 1, s, pos, acc => do
    let (v, vpos) ← readValue fuel s pos
    let acc := acc ++ [v]
    let w := skipWs s vpos
    match at? s w with
    | none => .error "incomplete_document"
    | some b =>
      if b == 0x5D then .ok (.arr acc, w + 1)
      else if b == 0x2C then
        let k := skipWs s (w + 1)
        match at? s k with
        | none => .error "incomplete_document"
        | some n => if n == 0x5D then .error "trailing_comma" else readItems fuel s k acc
      else .error "unexpected_byte"
end

/-- `JSON.parse/1`: the value, or the error code. -/
def parse (s : ByteArray) : Except String JVal := do
  let w := skipWs s 0
  if w ≥ s.size then .error "empty_input" else
  let (v, pos) ← readValue (4 * s.size + 4) s w
  if skipWs s pos < s.size then .error "trailing_data" else .ok v

/-! ## The canonical encoder -/

def hexUpper (n : Nat) : Char := "0123456789ABCDEF".toList[n % 16]!

def escapeChar (c : Char) : String :=
  if c == '"' then "\\\""
  else if c == '\\' then "\\\\"
  else if c.toNat == 0x08 then "\\b"
  else if c == '\t' then "\\t"
  else if c == '\n' then "\\n"
  else if c.toNat == 0x0C then "\\f"
  else if c == '\r' then "\\r"
  else if c.toNat < 0x20 then
    "\\u00" ++ String.ofList [hexUpper (c.toNat / 16), hexUpper c.toNat]
  else c.toString

def encodeString (s : String) : String := "\"" ++ String.join (s.toList.map escapeChar) ++ "\""

def pad (depth : Nat) : String := String.join (List.replicate depth "  ")

/-- The depth limit of the encoder (`@max_depth`, #473). -/
def maxDepth : Nat := 128

mutual
def encode : Nat → JVal → Except String String
  | d, v => if d > maxDepth then .error "depth_limit_exceeded" else match v with
    | .null => .ok "null"
    | .bool b => .ok (if b then "true" else "false")
    | .int i => .ok (toString i)
    | .float _ _ => .error "float_not_modelled"
    | .str s => .ok (encodeString s)
    | .arr [] => .ok "[]"
    | .arr xs => do
      let items ← encodeItems (d + 1) xs
      .ok ("[\n" ++ ",\n".intercalate (items.map (pad (d + 1) ++ ·)) ++ "\n" ++ pad d ++ "]")
    | .obj [] => .ok "{}"
    | .obj kvs => do
      let entries ← encodeEntries (d + 1) kvs
      let sorted := entries.mergeSort fun a b => !decide (b.1 < a.1)
      .ok ("{\n" ++ ",\n".intercalate (sorted.map fun (k, v) =>
        pad (d + 1) ++ encodeString k ++ ": " ++ v) ++ "\n" ++ pad d ++ "}")

def encodeItems : Nat → List JVal → Except String (List String)
  | _, [] => .ok []
  | d, x :: xs => do .ok ((← encode d x) :: (← encodeItems d xs))

def encodeEntries : Nat → List (String × JVal) → Except String (List (String × String))
  | _, [] => .ok []
  | d, (k, v) :: kvs => do .ok ((k, ← encode d v) :: (← encodeEntries d kvs))
end

/-- `JSON.canonical/1`: exactly one final newline. -/
def canonical (v : JVal) : Except String String := (encode 0 v).map (· ++ "\n")

end KomkiSpec.Json
