import KomkiSpec.ContextInput

/-!
# The schema checks of release, stand and proposal (CONTRACT.md § 2.6, § 2.7, § 4.6)

`Release.validate/1`, `Stand.validate/1` and `validate_proposal/1` in
`stand.ex` on the parsed JSON: the first error as code and path, in the
order the Elixir code checks, or none. Executable and held by the
differential test.
-/

namespace KomkiSpec

/-- `Validations.require_schema/3` with `:missing_field`. -/
def schemaError (j : JVal) (schema : String) : Option InputError :=
  match j.get? "schema" with
  | none => some ⟨"missing_field", "$.schema"⟩
  | some (.str s) => if s == schema then none else some ⟨"invalid_schema", "$.schema"⟩
  | some _ => some ⟨"invalid_schema", "$.schema"⟩

/-- `Validations.closed_fields/3` at the top level. -/
def closedError (kvs : List (String × JVal)) (allowed : List String) : Option InputError :=
  (firstUnknown kvs allowed).map fun k => ⟨"unknown_field", "$." ++ k⟩

/-- `Validations.require_kebab/2`. -/
def kebabError (j : JVal) (k : String) : Option InputError :=
  if kebabJ (j.get? k) then none else some ⟨"invalid_reference_id", "$." ++ k⟩

/-- `Validations.require_hex64/3`: 64 lowercase hex digits. -/
def hex64 : Option JVal → Bool
  | some (.str s) => s.length == 64 && s.all fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')
  | _ => false

def natJ : Option JVal → Bool
  | some (.int i) => 0 ≤ i
  | _ => false

def intJ : Option JVal → Bool
  | some (.int _) => true
  | _ => false

/-- `Registry.reference_id?/1`: `<kebab>@<version>`, the version without
leading zeros. -/
def refId (s : String) : Bool :=
  match s.splitOn "@" with
  | [b, v] => kebab b && !v.isEmpty && v.all Char.isDigit && (v == "0" || !v.startsWith "0")
  | _ => false

def refJ : Option JVal → Bool
  | some (.str s) => refId s
  | _ => false

def outputKinds : List String :=
  ["ratsprojekte-essenz", "freigabe-notiz", "sitzungsmappe", "kurzzitat-mit-quelle"]

/-- A `ziellabel`: sorted, unique, non-empty binding references. -/
def ziellabelOk : Option JVal → Bool
  | some (.arr xs) =>
    match strings? xs with
    | some ss => ss == sortDedup ss && sortStrings ss == ss && !ss.isEmpty && ss.all refId
    | none => false
  | _ => false

def releaseFields : List String :=
  ["schema", "release_id", "kind", "operation", "object", "workspace", "content_digest",
   "call_hash", "scope", "authority", "valid_from", "valid_until", "nonce"]

def offenlegungFields : List String := ["ausgabeart", "ziellabel"]

/-- `require_window/1`. -/
def windowError (j : JVal) : Option InputError :=
  if !natJ (j.get? "valid_from") then some ⟨"invalid_window", "$.valid_from"⟩
  else if !natJ (j.get? "valid_until") then some ⟨"invalid_window", "$.valid_until"⟩
  else match j.get? "valid_from", j.get? "valid_until" with
    | some (.int a), some (.int b) => if a ≤ b then none else some ⟨"invalid_window", "$.valid_from"⟩
    | _, _ => none

/-- `require_offenlegung_fields/1` of an Offenlegungsfreigabe; absent and
`null` are both `nil`. -/
def offenlegungError (j : JVal) : Option InputError :=
  match j.get? "ausgabeart" with
  | none | some .null => some ⟨"missing_field", "$.ausgabeart"⟩
  | a =>
    if !strIn outputKinds a then some ⟨"invalid_output_kind", "$.ausgabeart"⟩
    else match j.get? "ziellabel" with
      | none | some .null => some ⟨"missing_field", "$.ziellabel"⟩
      | z => if ziellabelOk z then none else some ⟨"invalid_ziellabel", "$.ziellabel"⟩

/-- `Release.validate/1`. -/
def releaseError : JVal → Option InputError
  | .obj kvs =>
    let j := JVal.obj kvs
    let offen := j.get? "kind" matches some (.str "offenlegungsfreigabe")
    (schemaError j (if offen then "komki-release/2" else "komki-release/1")).or <|
    (closedError kvs (if offen then releaseFields ++ offenlegungFields else releaseFields)).or <|
    (kebabError j "release_id").or <|
    (if strIn ["aktionsfreigabe", "offenlegungsfreigabe"] (j.get? "kind") then none
      else some ⟨"invalid_kind", "$.kind"⟩).or <|
    (if strIn knownOperations (j.get? "operation") then none
      else some ⟨"invalid_operation", "$.operation"⟩).or <|
    (if objectRefJ (j.get? "object") then none
      else some ⟨"invalid_reference_id", "$.object"⟩).or <|
    (kebabError j "workspace").or <|
    (if hex64 (j.get? "content_digest") then none
      else some ⟨"invalid_digest", "$.content_digest"⟩).or <|
    (if hex64 (j.get? "call_hash") then none else some ⟨"invalid_digest", "$.call_hash"⟩).or <|
    (kebabError j "scope").or <| (kebabError j "authority").or <| (windowError j).or <|
    (kebabError j "nonce").or <| if offen then offenlegungError j else none
  | _ => some ⟨"invalid_record", "$"⟩

def standFields : List String := ["schema", "stand_id", "version", "scope", "as_of", "consumed"]

/-- `validate_consumed/2`: every nonce and release id kebab-case. -/
def consumedError : Option JVal → Option InputError
  | some (.obj kvs) =>
    if kvs.all fun (n, r) => kebab n && kebabJ (some r) then none
    else some ⟨"invalid_reference_id", "$.consumed"⟩
  | _ => some ⟨"invalid_record", "$.consumed"⟩

/-- `Stand.validate/1`. -/
def standError : JVal → Option InputError
  | .obj kvs =>
    let j := JVal.obj kvs
    (schemaError j "komki-stand/1").or <| (closedError kvs standFields).or <|
    (kebabError j "stand_id").or <|
    (if natJ (j.get? "version") then none else some ⟨"invalid_stand_version", "$.version"⟩).or <|
    (kebabError j "scope").or <|
    (if intJ (j.get? "as_of") then none else some ⟨"invalid_as_of", "$.as_of"⟩).or <|
    consumedError (j.get? "consumed")
  | _ => some ⟨"invalid_record", "$"⟩

def proposalFields : List String :=
  ["release_id", "nonce", "stand_ref", "stand_version_after", "call_hash"]

/-- `validate_proposal/1`; the Offenlegung fields go by key, so `null`
counts as present. -/
def proposalError : JVal → Option InputError
  | .obj kvs =>
    let j := JVal.obj kvs
    let has := fun k => (kvs.lookup k).isSome
    (closedError kvs (proposalFields ++ offenlegungFields)).or <|
    (if has "ausgabeart" != has "ziellabel" then some (⟨"invalid_proposal", "$"⟩ : InputError)
      else if !has "ausgabeart" then none
      else if !strIn outputKinds (j.get? "ausgabeart") then
        some ⟨"invalid_proposal", "$.ausgabeart"⟩
      else if !ziellabelOk (j.get? "ziellabel") then some ⟨"invalid_proposal", "$.ziellabel"⟩
      else none).or <|
    (if proposalFields.all has then none else some (⟨"invalid_proposal", "$"⟩ : InputError)).or <|
    (kebabError j "release_id").or <| (kebabError j "nonce").or <|
    (if refJ (j.get? "stand_ref") then none
      else some (⟨"invalid_reference_id", "$.stand_ref"⟩ : InputError)).or <|
    (if hex64 (j.get? "call_hash") then none else some ⟨"invalid_proposal", "$.call_hash"⟩).or <|
    if natJ (j.get? "stand_version_after") then none
    else some ⟨"invalid_proposal", "$.stand_version_after"⟩
  | _ => some ⟨"invalid_proposal", "$"⟩

end KomkiSpec
