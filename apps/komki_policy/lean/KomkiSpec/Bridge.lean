import Lean.Data.Json
import KomkiSpec.Domain

/-!
# Bridge: the CLI's JSON into the model

Unverified and deliberately thin. It reads the records `komki-policy verify`
and `decide` read and assumes they passed Elixir's input validation;
anything else is a decoding error, never a verdict. Sorting mirrors
`Registry.compile/1`. A registry or snapshot outside the domain the
theorems assume (`Registry.wellFormed`, `Snapshot.wellFormed`) is a decoding
error too. On the way out it writes `derive`'s decision in the
shape of `Derive.decide/3`, without the remedies.
-/

namespace KomkiSpec

open Lean (Json)

partial def JVal.ofJson : Json → JVal
  | .null => .null
  | .bool b => .bool b
  | .num n => if n.exponent == 0 then .int n.mantissa else .float n.mantissa n.exponent
  | .str s => .str s
  | .arr xs => .arr (xs.toList.map JVal.ofJson)
  | .obj kvs => .obj (kvs.toList.map fun (k, v) => (k, JVal.ofJson v))

abbrev Decode := Except String

def field (j : JVal) (k : String) : Decode JVal :=
  match j.get? k with
  | some v => pure v
  | none => throw s!"missing field {k}"

def asStr : JVal → Decode String
  | .str s => pure s
  | _ => throw "expected a string"

def asBool : JVal → Decode Bool
  | .bool b => pure b
  | _ => throw "expected a boolean"

def asArr : JVal → Decode (List JVal)
  | .arr xs => pure xs
  | _ => throw "expected an array"

def asObj : JVal → Decode (List (String × JVal))
  | .obj kvs => pure kvs
  | _ => throw "expected an object"

def asStrs (j : JVal) : Decode (List String) := do
  (← asArr j).mapM asStr

def strAt (j : JVal) (k : String) : Decode String := do
  asStr (← field j k)

def decodeRegistry (j : JVal) : Decode Registry := do
  let environments ← (← asObj (← field j "environments")).mapM fun (id, env) => do
    pure (id, sortStrings (← asStrs (← field env "observers")))
  let bindings ← (← asObj (← field j "bindings")).mapM fun (id, b) => do
    let readers := sortStrings (← asStrs (← field b "readers"))
    pure (id, { readers, operations := ← asObj (← field b "operations") : Binding })
  pure {
    registryId := ← strAt j "registry_id"
    observers := sortStrings (← asStrs (← field j "observers"))
    environments, bindings }

def decodeSnapshot (j : JVal) : Decode Snapshot := do
  let ws ← field j "workspace"
  let obj ← field j "object"
  let entries ← asObj (← field j "facts")
  let facts ← entries.mapM fun (name, entry) => do
    pure (name, ← field entry "value")
  let factSources ← entries.mapM fun (name, entry) => do
    pure (name, ← strAt entry "source", ← strAt entry "source_kind")
  pure {
    snapshotId := ← strAt j "snapshot_id"
    workspaceBindings := ← asStrs (← field ws "bindings")
    workspaceValid := ← asBool (← field ws "valid")
    environment := ← strAt ws "environment"
    classification := ← strAt obj "classification"
    objectLabels := ← asStrs (← field obj "labels")
    facts
    objectRef := (← strAt obj "object_id") ++ "@" ++ (← strAt obj "version")
    factSources }

def decodeWorld (j : JVal) : Decode (Registry × Snapshot) := do
  let Γ ← decodeRegistry (← field j "registry")
  let S ← decodeSnapshot (← field j "snapshot")
  unless Γ.wellFormed do throw "registry outside the validated domain"
  unless S.wellFormed do throw "snapshot outside the validated domain"
  pure (Γ, S)

def decodeIntent (j : JVal) : Decode Intent := do
  pure { intentId := ← strAt j "intent_id", operation := ← strAt j "operation" }

def decodePremise (j : JVal) : Decode Premise := do
  pure {
    name := ← strAt j "name"
    kind := ← strAt j "kind"
    value := ← asBool (← field j "value")
    fields := ← asObj j }

def decodeProof (j : JVal) : Decode Proof := do
  pure {
    rule := ← strAt j "rule"
    conclusion := ← strAt j "conclusion"
    registryRef := ← strAt j "registry_ref"
    snapshotRef := ← strAt j "snapshot_ref"
    intentRef := ← strAt j "intent_ref"
    checkedLabel := ← asStrs (← field j "checked_label")
    premises := ← (← asArr (← field j "premises")).mapM decodePremise }

def Outcome.label : Outcome → String
  | .valid => "valid"
  | .invalid => "invalid"
  | .inputError => "input_error"

/-- One case `{"registry", "snapshot", "intent", "proof"}` → verdict. -/
def verifyCase (j : JVal) : Decode Outcome := do
  let (Γ, S) ← decodeWorld j
  pure (verify Γ S (← decodeIntent (← field j "intent")) (← decodeProof (← field j "proof")))

/-! ## `derive`'s decision as JSON -/

partial def JVal.toJson : JVal → Json
  | .null => .null
  | .bool b => .bool b
  | .int i => .num (Lean.JsonNumber.fromInt i)
  | .float m e => .num ⟨m, e⟩
  | .str s => .str s
  | .arr xs => .arr (xs.map JVal.toJson).toArray
  | .obj kvs => Json.mkObj (kvs.map fun (k, v) => (k, JVal.toJson v))

def optStr : Option String → Json
  | some s => .str s
  | none => .null

def Blocker.toJson (b : Blocker) : Json :=
  Json.mkObj <|
    [("code", .str b.code), ("binding", optStr b.binding), ("condition", optStr b.condition)] ++
    match b.outside with
    | some os => [("recipients_outside", Lean.toJson os)]
    | none => []

def Evidence.toJson (e : Evidence) : Json :=
  Json.mkObj [("code", .str e.code), ("fact", optStr e.fact), ("binding", optStr e.binding)]

def Proof.toJson (P : Proof) : Json :=
  Json.mkObj [("schema", .str "komki-proof/1"), ("rule", .str P.rule),
    ("conclusion", .str P.conclusion), ("registry_ref", .str P.registryRef),
    ("snapshot_ref", .str P.snapshotRef), ("intent_ref", .str P.intentRef),
    ("checked_label", Lean.toJson P.checkedLabel),
    ("premises", .arr (P.premises.map fun p => (JVal.obj p.fields).toJson).toArray)]

/-- The fields of `Derive.decide/3` this model decides: everything but the
echoes of the input and the remedies. -/
def decisionJson (S : Snapshot) (rule : String) (d : Decision) : Json :=
  let checked := Lean.toJson (checkedLabel rule S)
  let (name, blockers, evidence, proof, assigned) : String × Json × Json × Json × Json :=
    match d with
    | .permit P => ("permit", .null, .null, P.toJson, checked)
    | .deny bs => ("deny", .arr (bs.map Blocker.toJson).toArray, .null, .null, .null)
    | .indeterminate es => ("indeterminate", .null, .arr (es.map Evidence.toJson).toArray, .null, .null)
  let digest := ((S.facts.lookup "output_content_digest").map JVal.toJson).getD .null
  let output :=
    if rule == "admit" then []
    else if rule == "emit" then [("assigned_label", assigned), ("content_digest", digest)]
    else [("content_digest", digest)]
  Json.mkObj <|
    [("decision", .str name), ("rule", .str rule), ("checked_label", checked),
     ("blockers", blockers), ("missing_evidence", evidence), ("proof", proof)] ++ output

def Derived.toJson (S : Snapshot) (rule : String) : Derived → Json
  | .decision d => decisionJson S rule d
  | .inputError code => Json.mkObj [("input_error", .str code)]
  | .unsupported => Json.mkObj [("unsupported", .bool true)]

/-- One case `{"registry", "snapshot", "intent"}` → decision. -/
def deriveCase (j : JVal) : Decode Json := do
  let (Γ, S) ← decodeWorld j
  let I ← decodeIntent (← field j "intent")
  pure ((derive Γ S I).toJson S I.operation)

end KomkiSpec
