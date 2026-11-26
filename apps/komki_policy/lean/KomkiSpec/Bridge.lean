import Lean.Data.Json
import KomkiSpec.Verify

/-!
# Bridge: the CLI's JSON into the model

Unverified and deliberately thin. It reads the records `komki-policy verify`
reads and assumes they passed Elixir's input validation; anything else is a
decoding error, never a verdict. Sorting mirrors `Registry.compile/1`.
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
  let facts ← (← asObj (← field j "facts")).mapM fun (name, entry) => do
    pure (name, ← field entry "value")
  pure {
    snapshotId := ← strAt j "snapshot_id"
    workspaceBindings := ← asStrs (← field ws "bindings")
    workspaceValid := ← asBool (← field ws "valid")
    environment := ← strAt ws "environment"
    classification := ← strAt obj "classification"
    objectLabels := ← asStrs (← field obj "labels")
    facts }

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
  | .outOfScope => "out_of_scope"

/-- One case `{"registry", "snapshot", "intent", "proof"}` → verdict. -/
def verifyCase (j : JVal) : Decode Outcome := do
  pure (verify (← decodeRegistry (← field j "registry")) (← decodeSnapshot (← field j "snapshot"))
    (← decodeIntent (← field j "intent")) (← decodeProof (← field j "proof")))

end KomkiSpec
