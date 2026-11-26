import KomkiSpec.VerifyReasons

/-!
# `verify`'s proof validation (CONTRACT.md § 2.5, § 5)

`validate_proof/1` in `verify.ex` on the proof as parsed JSON: the first
error as code and path, in the order `verify.ex` checks, or none. The
detail text is prose and left out. Executable and held by the differential
test.
-/

namespace KomkiSpec

def proofFields : List String :=
  ["schema", "rule", "conclusion", "registry_ref", "snapshot_ref", "intent_ref", "checked_label",
   "premises"]

def requiredProofValues : List String := proofFields.drop 1

def premiseKinds : List String := ["object_check", "fact", "computed", "condition"]

/-- `@premise_shape_keys`: the closed keys of a (name, kind) pair of § 2.5. -/
def pairShapeKeys : List ((String × String) × List String) :=
  let fact := ["fact", "kind", "name", "source", "source_kind", "value"]
  [(("not_quarantine", "object_check"), ["classification", "kind", "name", "object", "value"]),
   (("workspace_contract_valid", "fact"), ["fact", "kind", "name", "source", "value"]),
   (("has_operation_right", "fact"), fact),
   (("has_object_access_right", "fact"), fact),
   (("audit_path_ready", "fact"), fact),
   (("environment_observers_complete", "fact"), fact),
   (("label_inclusion", "computed"), ["checked_label", "kind", "name", "object_labels", "value"]),
   (("label_assignment", "computed"), ["assigned_label", "checked_label", "kind", "name", "value"]),
   (("label_preservation", "computed"),
    ["checked_label", "kind", "name", "value", "workspace_bindings"]),
   (("recipient_inclusion", "computed"),
    ["actual_recipients", "allowed_recipients", "kind", "name", "value"]),
   (("binding_condition", "condition"),
    ["binding", "expression", "fact_refs", "kind", "name", "value"])]

/-- `@generic_premise_shape_keys`: the closed keys of any other pair. -/
def kindShapeKeys : List (String × List String) :=
  [("object_check", ["classification", "kind", "name", "object", "value"]),
   ("fact", ["fact", "kind", "name", "source", "source_kind", "value"]),
   ("computed", ["kind", "name", "value"]),
   ("condition", ["binding", "expression", "kind", "name", "value"])]

/-- `@pair_required_keys`. -/
def pairRequiredKeys : List ((String × String) × List String) :=
  [(("workspace_contract_valid", "fact"), ["fact", "source", "value"]),
   (("binding_condition", "condition"), ["binding", "expression", "fact_refs", "value"])]

/-- `@premise_required_keys`. -/
def kindRequiredKeys : List (String × List String) :=
  [("object_check", ["classification", "object", "value"]),
   ("fact", ["fact", "source", "source_kind", "value"]),
   ("computed", ["value"]),
   ("condition", ["binding", "expression", "value"])]

/-- The first key outside `allowed`, in `Enum.sort/1` order. -/
def firstUnknown (kvs : List (String × JVal)) (allowed : List String) : Option String :=
  (sortStrings ((kvs.map (·.1)).filter fun k => !allowed.contains k)).head?

def isStr : Option JVal → Bool
  | some (.str _) => true
  | _ => false

/-- `nil` (absent or `null`) or a string. -/
def nullOrStr : Option JVal → Bool
  | none | some .null | some (.str _) => true
  | _ => false

def isStrList : Option JVal → Bool
  | some (.arr xs) => xs.all fun | .str _ => true | _ => false
  | _ => false

/-- `premise_entry/2`. -/
def premiseError (path : String) : JVal → Option InputError
  | .obj kvs =>
    let j := JVal.obj kvs
    match j.get? "kind" with
    | none => some ⟨"missing_field", path ++ ".kind"⟩
    | some (.str kind) =>
      if !premiseKinds.contains kind then some ⟨"invalid_premise_kind", path ++ ".kind"⟩ else
      match j.get? "name" with
      | some (.str name) =>
        let closed := (pairShapeKeys.lookup (name, kind)).getD ((kindShapeKeys.lookup kind).getD [])
        let required :=
          (pairRequiredKeys.lookup (name, kind)).getD ((kindRequiredKeys.lookup kind).getD [])
        match firstUnknown kvs closed with
        | some k => some ⟨"unknown_premise_field", path ++ "." ++ k⟩
        | none =>
          if !required.all (fun k => (kvs.lookup k).isSome) then some ⟨"missing_field", path⟩
          else if kind == "condition" &&
              !(match j.get? "expression" with
                | some (.bool _) | some (.obj _) => true
                | _ => false) then some ⟨"invalid_entry", path ++ ".expression"⟩
          else if !(match j.get? "value" with
                | some (.bool _) => true
                | _ => false) then some ⟨"invalid_entry", path ++ ".value"⟩
          else if !nullOrStr (j.get? "binding") then some ⟨"invalid_entry", path ++ ".binding"⟩
          else if !nullOrStr (j.get? "fact") then some ⟨"invalid_entry", path ++ ".fact"⟩
          else none
      | _ => some ⟨"missing_field", path ++ ".name"⟩
    | some _ => some ⟨"invalid_premise_kind", path ++ ".kind"⟩
  | _ => some ⟨"invalid_premise", path⟩

/-- `validate_premises/2`: the first premise with an error, counting from `i`. -/
def premisesError (i : Nat) : List JVal → Option InputError
  | [] => none
  | p :: ps => (premiseError s!"$.premises.[{i}]" p).or (premisesError (i + 1) ps)

/-- `validate_proof/1`. -/
def proofError : JVal → Option InputError
  | .obj kvs =>
    let j := JVal.obj kvs
    match j.get? "schema" with
    | none => some ⟨"missing_field", "$.schema"⟩
    | some (.str "komki-proof/1") =>
      match firstUnknown kvs proofFields with
      | some k => some ⟨"unknown_field", "$." ++ k⟩
      | none =>
        if !requiredProofValues.all (fun k => (kvs.lookup k).isSome) then
          some ⟨"missing_field", "$"⟩
        else
          match ["rule", "conclusion", "registry_ref", "snapshot_ref", "intent_ref"].find?
              (fun k => !isStr (j.get? k)) with
          | some k => some ⟨"invalid_entry", "$." ++ k⟩
          | none =>
            if !isStrList (j.get? "checked_label") then some ⟨"invalid_entry", "$.checked_label"⟩
            else
              match j.get? "premises" with
              | some (.arr ps) => premisesError 0 ps
              | _ => some ⟨"invalid_entry", "$.premises"⟩
    | some _ => some ⟨"invalid_schema", "$.schema"⟩
  | _ => some ⟨"invalid_record", "$"⟩

end KomkiSpec
