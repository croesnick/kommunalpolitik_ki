import KomkiSpec.ProofInput
import KomkiSpec.Input

/-!
# `Context`'s input validation (CONTRACT.md § 2.2, § 2.3)

`validate_intent/1`, `validate_snapshot/2` and `ensure_coherence/2` in
`context.ex` on the parsed JSON: the first error as code and path, in the
order `context.ex` checks, or none. Executable and held by the
differential test; `snapshotError_validated` shows that an accepted
snapshot lies in the domain of the theorems.
-/

namespace KomkiSpec

/-- `Registry.kebab_id?/1`: `\A[a-z0-9]+(?:-[a-z0-9]+)*\z`. -/
def kebab (s : String) : Bool :=
  (s.splitOn "-").all fun p => !p.isEmpty && p.all fun c => c.isLower || c.isDigit

def kebabJ : Option JVal → Bool
  | some (.str s) => kebab s
  | _ => false

/-- `object_ref?/1`: `<object_id>@<version>`, both kebab-case. -/
def objectRefJ : Option JVal → Bool
  | some (.str s) =>
    match s.splitOn "@" with
    | [o, v] => kebab o && kebab v
    | _ => false
  | _ => false

def strIn (xs : List String) : Option JVal → Bool
  | some (.str s) => xs.contains s
  | _ => false

def intentFields : List String := ["schema", "intent_id", "operation", "object", "workspace"]

def knownOperations : List String := ["start", "admit", "emit", "transfer", "store"]

/-- `validate_intent/1`. -/
def intentError : JVal → Option InputError
  | .obj kvs =>
    let j := JVal.obj kvs
    match j.get? "schema" with
    | some (.str "komki-intent/1") =>
      match firstUnknown kvs intentFields with
      | some k => some ⟨"unknown_field", "$." ++ k⟩
      | none =>
        if !kebabJ (j.get? "intent_id") then some ⟨"invalid_reference_id", "$.intent_id"⟩
        else if !objectRefJ (j.get? "object") then some ⟨"invalid_reference_id", "$.object"⟩
        else if !kebabJ (j.get? "workspace") then some ⟨"invalid_reference_id", "$.workspace"⟩
        else if !strIn knownOperations (j.get? "operation") then
          some ⟨"invalid_operation", "$.operation"⟩
        else none
    | _ => some ⟨"invalid_schema", "$.schema"⟩
  | _ => some ⟨"invalid_record", "$"⟩

def snapshotFields : List String :=
  ["schema", "snapshot_id", "registry_ref", "identity", "workspace", "object", "facts"]

def workspaceFields : List String := ["workspace_id", "bindings", "valid", "environment"]

def objectFields : List String := ["object_id", "version", "classification", "labels"]

def factEntryFields : List String := ["value", "source", "source_kind"]

def sourceKinds : List String := ["administered", "technical", "assumption", "test"]

/-- `member_of_registry/4`: strings, sorted and unique, all in `against`. -/
def refsError (ids : Option JVal) (against : List String) (path code : String) :
    Option InputError :=
  match ids with
  | some (.arr xs) =>
    match strings? xs with
    | some ss =>
      if !(sortStrings ss == ss && sortDedup ss == ss) then some ⟨"unsorted_references", path⟩
      else if !ss.all against.contains then some ⟨code, path⟩
      else none
    | none => some ⟨"invalid_reference_list", path⟩
  | _ => some ⟨"invalid_reference_list", path⟩

def bindingIds (Γ : Registry) : List String := Γ.bindings.map (·.1)

/-- `validate_workspace/2`. -/
def workspaceError (Γ : Registry) : Option JVal → Option InputError
  | some (.obj kvs) =>
    let w := JVal.obj kvs
    match firstUnknown kvs workspaceFields with
    | some k => some ⟨"unknown_field", "$.workspace." ++ k⟩
    | none =>
      if !kebabJ (w.get? "workspace_id") then
        some ⟨"invalid_reference_id", "$.workspace.workspace_id"⟩
      else if !(match w.get? "valid" with
          | some (.bool _) => true
          | _ => false) then some ⟨"invalid_flag", "$.workspace.valid"⟩
      else
        (refsError (w.get? "bindings") (bindingIds Γ) "$.workspace.bindings"
          "unknown_binding_reference").or
        (if !strIn (Γ.environments.map (·.1)) (w.get? "environment") then
          some ⟨"unknown_environment", "$.workspace.environment"⟩
        else none)
  | _ => some ⟨"invalid_record", "$.workspace"⟩

/-- `validate_object/2`. -/
def objectError (Γ : Registry) : Option JVal → Option InputError
  | some (.obj kvs) =>
    let o := JVal.obj kvs
    match firstUnknown kvs objectFields with
    | some k => some ⟨"unknown_field", "$.object." ++ k⟩
    | none =>
      if !kebabJ (o.get? "object_id") then some ⟨"invalid_reference_id", "$.object.object_id"⟩
      else if !kebabJ (o.get? "version") then some ⟨"invalid_reference_id", "$.object.version"⟩
      else if !strIn ["classified", "quarantine"] (o.get? "classification") then
        some ⟨"invalid_classification", "$.object.classification"⟩
      else
        refsError (o.get? "labels") (bindingIds Γ) "$.object.labels" "unknown_binding_reference"
  | _ => some ⟨"invalid_record", "$.object"⟩

/-- The type a fact's value must have: a base fact is boolean (§ 4.2). -/
def factType (Γ : Registry) (name : String) : String :=
  if admitBaseFacts.contains name then "boolean" else (Γ.factFields.lookup name).getD "boolean"

/-- `validate_fact_entry/2`. -/
def factError (Γ : Registry) (name : String) : JVal → Option InputError
  | .obj kvs =>
    let e := JVal.obj kvs
    let path := "$.facts." ++ name
    match firstUnknown kvs factEntryFields with
    | some k => some ⟨"unknown_field", path ++ "." ++ k⟩
    | none =>
      if !((Γ.factFields.lookup name).isSome || admitBaseFacts.contains name) then
        some ⟨"unknown_fact_field", path⟩
      else if !isStr (e.get? "source") then some ⟨"invalid_source", path ++ ".source"⟩
      else if !strIn sourceKinds (e.get? "source_kind") then
        some ⟨"invalid_source_kind", path ++ ".source_kind"⟩
      else if !(match e.get? "value" with
          | some v => valueFits (factType Γ name) v
          | none => false) then some ⟨"invalid_fact_value", path ++ ".value"⟩
      else none
  | _ => some ⟨"invalid_record", "$.facts." ++ name⟩

/-- `validate_facts/2`: the entries in name order. -/
def factsError (Γ : Registry) : Option JVal → Option InputError
  | some (.obj kvs) =>
    (kvs.mergeSort fun a b => !decide (b.1 < a.1)).findSome? fun (n, e) => factError Γ n e
  | _ => some ⟨"invalid_record", "$.facts"⟩

/-- `validate_snapshot/2`. -/
def snapshotError (Γ : Registry) : JVal → Option InputError
  | .obj kvs =>
    let j := JVal.obj kvs
    match j.get? "schema" with
    | some (.str "komki-snapshot/1") =>
      match firstUnknown kvs snapshotFields with
      | some k => some ⟨"unknown_field", "$." ++ k⟩
      | none =>
        if !kebabJ (j.get? "snapshot_id") then some ⟨"invalid_reference_id", "$.snapshot_id"⟩
        else if !strIn [Γ.registryId] (j.get? "registry_ref") then
          some ⟨"registry_ref_mismatch", "$.registry_ref"⟩
        else if !strIn Γ.observers (j.get? "identity") then
          some ⟨"unknown_observer", "$.identity"⟩
        else
          (workspaceError Γ (j.get? "workspace")).or
            ((objectError Γ (j.get? "object")).or (factsError Γ (j.get? "facts")))
    | _ => some ⟨"invalid_schema", "$.schema"⟩
  | _ => some ⟨"invalid_record", "$"⟩

/-- `ensure_coherence/2` on a validated intent and snapshot. -/
def coherenceError (intent snapshot : JVal) : Option InputError :=
  let str : Option JVal → String
    | some (.str s) => s
    | _ => ""
  let ws := (snapshot.get? "workspace").bind (·.get? "workspace_id")
  let obj := snapshot.get? "object"
  let objRef := str (obj.bind (·.get? "object_id")) ++ "@" ++ str (obj.bind (·.get? "version"))
  if str (intent.get? "workspace") != str ws then some ⟨"intent_snapshot_mismatch", "$.workspace"⟩
  else if str (intent.get? "object") != objRef then
    some ⟨"intent_snapshot_mismatch", "$.object"⟩
  else none

end KomkiSpec
