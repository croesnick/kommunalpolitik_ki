import KomkiSpec.ReleaseInput

/-!
# `Registry.compile/1` (CONTRACT.md § 2.1, § 3)

The compiler's validation on the parsed JSON: the first error as code and
path, in the order `registry.ex` checks, or none. Executable and held by
the differential test; `registryError_compiledOk` shows that an accepted
registry lies in the domain of the theorems.
-/

namespace KomkiSpec

def unsupported (path : String) : Option InputError := some ⟨"unsupported_expression", path⟩

/-- `op_type_check/5`: the literal fits the field's declared type `ty`. -/
def clauseTyped (op ty : String) (lit : JVal) : Bool :=
  if op == "eq" then literalFits ty lit
  else if op == "member" then
    scalarType ty && match lit with
      | .arr ls => ls.all (literalFits ty)
      | _ => false
  else if op == "subset" then
    ty == "string_set" && match lit with
      | .arr ls => ls.all fun | .str _ => true | _ => false
      | _ => false
  else
    ty == "integer" && match lit with
      | .int b => decide (0 ≤ b)
      | _ => false

/-- `compile_form/4` for the clause forms `eq`, `member`, `subset`, `at_most`. -/
def clauseError (ff : List (String × String)) (path op : String) : JVal → Option InputError
  | .arr [.str f, lit] =>
    match ff.lookup f with
    | none => some ⟨"unknown_fact_field", path⟩
    | some ty => if clauseTyped op ty lit then none else some ⟨"expression_type_mismatch", path⟩
  | _ => unsupported path

def clauseOps : List String := ["eq", "member", "subset", "at_most"]

mutual
/-- `compile_expression/3`. -/
def exprError (ff : List (String × String)) (path : String) : JVal → Option InputError
  | .bool _ => none
  | .obj [(k, .arr cs)] =>
    if k == "all" || k == "any" then exprsError ff path 0 cs
    else if clauseOps.contains k then clauseError ff path k (.arr cs)
    else unsupported path
  | .obj [(k, v)] => if clauseOps.contains k then clauseError ff path k v else unsupported path
  | _ => unsupported path

/-- The sub-expressions of `all`/`any`, at `path.[i]`. -/
def exprsError (ff : List (String × String)) (path : String) (i : Nat) :
    List JVal → Option InputError
  | [] => none
  | c :: cs => (exprError ff s!"{path}.[{i}]" c).or (exprsError ff path (i + 1) cs)
end

/-- `Validations.closed_fields/3` at `path`. -/
def closedAt (kvs : List (String × JVal)) (allowed : List String) (path : String) :
    Option InputError :=
  (firstUnknown kvs allowed).map fun k => ⟨"unknown_field", path ++ "." ++ k⟩

/-- `nonempty_unique_strings/2` and `kebab_strings/2`. -/
def observerListError (path : String) : Option JVal → Option InputError
  | some (.arr xs) =>
    if xs.isEmpty then some ⟨"empty_list", path⟩
    else match strings? xs with
      | none => some ⟨"invalid_entry", path⟩
      | some ss =>
        if (sortDedup ss).length != ss.length then some ⟨"duplicate_entry", path⟩
        else if !ss.all kebab then some ⟨"invalid_entry", path⟩
        else none
  | _ => some ⟨"invalid_observers", path⟩

/-- `subset_observers/3`. -/
def subsetObserversError (observers : List String) (path : String) (o : Option JVal) :
    Option InputError :=
  (observerListError path o).or <|
    if strIn' observers o then none else some ⟨"unknown_observer", path⟩
where
  strIn' (observers : List String) : Option JVal → Bool
    | some (.arr xs) => xs.all fun | .str s => observers.contains s | _ => false
    | _ => false

def authorityFields : List String := ["authority", "restriction", "output"]

def restrictionKinds : List String := ["readers", "operations", "auflagen"]

/-- `authority_entry/3`. -/
def authorityError (observers : List String) (path : String) : JVal → Option InputError
  | .obj kvs =>
    let e := JVal.obj kvs
    (closedAt kvs authorityFields path).or <|
    (if kebabJ (e.get? "authority") then none
      else some ⟨"invalid_reference_id", path ++ ".authority"⟩).or <|
    (if strIn observers (e.get? "authority") then none
      else some ⟨"unknown_observer", path ++ ".authority"⟩).or <|
    (if strIn restrictionKinds (e.get? "restriction") then none
      else some ⟨"invalid_restriction_kind", path ++ ".restriction"⟩).or <|
    (if kebabJ (e.get? "output") then none
      else some ⟨"invalid_reference_id", path ++ ".output"⟩).or <|
    if strIn outputKinds (e.get? "output") then none
    else some ⟨"invalid_output_kind", path ++ ".output"⟩
  | _ => some ⟨"invalid_record", path⟩

def authoritiesErrorFrom (observers : List String) (path : String) (i : Nat) :
    List JVal → Option InputError
  | [] => none
  | e :: es => (authorityError observers s!"{path}.[{i}]" e).or
      (authoritiesErrorFrom observers path (i + 1) es)

def strField (e : JVal) (k : String) : String :=
  match e.get? k with
  | some (.str s) => s
  | _ => ""

/-- `validate_relaxation_authorities/3`: each entry, then no duplicates. -/
def authoritiesError (observers : List String) (path : String) : Option JVal → Option InputError
  | some (.arr es) =>
    (authoritiesErrorFrom observers path 0 es).or <|
      let triples := es.map fun e => strField e "authority" ++ "\x00" ++ strField e "restriction" ++
        "\x00" ++ strField e "output"
      if (sortDedup triples).length == triples.length then none
      else some ⟨"duplicate_relaxation_authority", path⟩
  | _ => some ⟨"invalid_relaxation_authorities", path⟩

/-- Entries in key order, as `Enum.sort/1` on `Map.to_list/1`. -/
def byKey (kvs : List (String × JVal)) : List (String × JVal) :=
  kvs.mergeSort fun a b => !decide (b.1 < a.1)

/-- `validate_operations/3`. -/
def operationsError (ff : List (String × String)) (path : String) :
    Option JVal → Option InputError
  | some (.obj kvs) =>
    match (sortStrings ((kvs.map (·.1)).filter fun k => !knownOperations.contains k)).head? with
    | some k => some ⟨"unknown_operation", path ++ ".operations." ++ k⟩
    | none => (byKey kvs).findSome? fun (n, e) => exprError ff (path ++ ".operations." ++ n) e
  | _ => some ⟨"invalid_operations", path ++ ".operations"⟩

def bindingFields : List String := ["readers", "operations", "relaxation_authorities"]

/-- `binding_part/4`. -/
def bindingError (ff : List (String × String)) (observers : List String) (path : String) :
    JVal → Option InputError
  | .obj kvs =>
    let b := JVal.obj kvs
    (closedAt kvs bindingFields path).or <|
    (subsetObserversError observers (path ++ ".readers") (b.get? "readers")).or <|
    (authoritiesError observers (path ++ ".relaxation_authorities")
      (b.get? "relaxation_authorities")).or <|
    operationsError ff path (b.get? "operations")
  | _ => some ⟨"invalid_record", path⟩

/-- `environment_part/3`. -/
def environmentError (observers : List String) (path : String) : JVal → Option InputError
  | .obj kvs =>
    (closedAt kvs ["observers"] path).or <|
      subsetObserversError observers (path ++ ".observers") ((JVal.obj kvs).get? "observers")
  | _ => some ⟨"invalid_record", path⟩

/-- `collect_environments/3` and `collect_bindings/4`: non-empty, in key
order, each id a reference, each entry checked by `part`. -/
def entriesError (path empty : String) (part : String → JVal → Option InputError) :
    Option JVal → Option InputError
  | some (.obj (kv :: kvs)) =>
    (byKey (kv :: kvs)).findSome? fun (id, spec) =>
      if refId id then part (path ++ "." ++ id) spec else some ⟨"invalid_reference_id", path⟩
  | _ => some ⟨empty, path⟩

/-- `require_sorted_unique_bindings/4`. -/
def labelsError (bindingIds : List String) (nonempty : Bool) (path : String) :
    Option JVal → Option InputError
  | some (.arr xs) =>
    match strings? xs with
    | none => some ⟨"invalid_transformations", path⟩
    | some ss =>
      if nonempty && ss.isEmpty then some ⟨"empty_list", path⟩
      else if !(sortStrings ss == ss && sortDedup ss == ss) then
        some ⟨"unsorted_references", path⟩
      else if !ss.all bindingIds.contains then some ⟨"unknown_binding_reference", path⟩
      else none
  | _ => some ⟨"invalid_transformations", path⟩

/-- `do_transformation_part/3`. -/
def transformationError (bindingIds : List String) (path : String) : JVal → Option InputError
  | .obj kvs =>
    let t := JVal.obj kvs
    (closedAt kvs ["input_labels", "output_labels"] path).or <|
    (labelsError bindingIds true (path ++ ".input_labels") (t.get? "input_labels")).or <|
    labelsError bindingIds false (path ++ ".output_labels") (t.get? "output_labels")
  | _ => some ⟨"invalid_record", path⟩

/-- `validate_transformations/2`: optional; absent and `null` are both `nil`. -/
def transformationsError (bindingIds : List String) : Option JVal → Option InputError
  | none | some .null => none
  | some (.obj kvs) =>
    (byKey kvs).findSome? fun (id, spec) =>
      if refId id then transformationError bindingIds ("$.transformations." ++ id) spec
      else some ⟨"invalid_reference_id", "$.transformations"⟩
  | _ => some ⟨"invalid_transformations", "$.transformations"⟩

def registryFields : List String :=
  ["schema", "registry_id", "observers", "fact_fields", "environments", "bindings",
   "transformations"]

def factTypes : List String := ["string", "boolean", "integer", "string_set"]

def factFieldOf (p : String × JVal) : String × String :=
  (p.1, match p.2 with | .str s => s | _ => "")

/-- The declared fact fields, once `validate_fact_fields/1` passed. -/
def factFieldsOf : Option JVal → List (String × String)
  | some (.obj fs) => fs.map factFieldOf
  | _ => []

def strsOf : Option JVal → List String
  | some (.arr xs) => (strings? xs).getD []
  | _ => []

def keysOf : Option JVal → List String
  | some (.obj kvs) => kvs.map (·.1)
  | _ => []

/-- `Validations.require_schema/3` with `:invalid_schema`. -/
def registrySchemaError : Option JVal → Option InputError
  | some (.str "komki-registry/2") => none
  | _ => some ⟨"invalid_schema", "$.schema"⟩

/-- `validate_fact_fields/1`. -/
def factFieldsError : Option JVal → Option InputError
  | some (.obj fs) =>
    if fs.all (fun (_, t) => strIn factTypes (some t)) then none
    else some ⟨"invalid_fact_type", "$.fact_fields"⟩
  | _ => some ⟨"invalid_fact_type", "$.fact_fields"⟩

/-- `Registry.compile/1`. -/
def registryError : JVal → Option InputError
  | .obj kvs =>
    let j := JVal.obj kvs
    let observers := strsOf (j.get? "observers")
    let ff := factFieldsOf (j.get? "fact_fields")
    (registrySchemaError (j.get? "schema")).or <|
    (closedAt kvs registryFields "$").or <|
    (if kebabJ (j.get? "registry_id") then none
      else some (⟨"invalid_registry_id", "$.registry_id"⟩ : InputError)).or <|
    (observerListError "$.observers" (j.get? "observers")).or <|
    (factFieldsError (j.get? "fact_fields")).or <|
    (entriesError "$.environments" "no_environments" (environmentError observers)
      (j.get? "environments")).or <|
    (entriesError "$.bindings" "no_bindings" (bindingError ff observers)
      (j.get? "bindings")).or <|
    transformationsError (keysOf (j.get? "bindings")) (j.get? "transformations")
  | _ => some ⟨"invalid_record", "$"⟩

end KomkiSpec
