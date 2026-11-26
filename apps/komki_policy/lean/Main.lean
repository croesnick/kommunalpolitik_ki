import KomkiSpec.Bridge

/-!
`komki-spec verify-batch <cases.jsonl>`: one case per line,
`{"id": n, "registry": …, "snapshot": …, "intent": …, "proof": …}`; prints
`<id> valid|invalid|input_error` or `<id> error <reason>` per line.

`komki-spec derive-batch <cases.jsonl>`: one case per line,
`{"id": n, "registry": …, "snapshot": …, "intent": …}`; prints `<id> <json>`
with `derive`'s decision, or `<id> error <reason>`.

`komki-spec release-batch` and `advance-batch`: the same for
`decide_with_release/5` (`{…, "release", "stand", "call_hash"}`) and for
`Stand.advance/2` (`{"id", "stand", "proposal"}`); `eval-batch` for
`Evaluator.evaluate/2` (`{"id", "expression", "facts"}`).

`komki-spec constants`: the fixed tables of the model, for the comparison
with `KomkiPolicy.Derive`.
-/

open KomkiSpec Lean

def runLine (run : JVal → Except String String) (line : String) : String :=
  match Json.parse line with
  | .error e => s!"? error {e}"
  | .ok json =>
    let j := JVal.ofJson json
    let id := match j.get? "id" with
      | some (.int i) => toString i
      | _ => "?"
    match run j with
    | .ok out => s!"{id} {out}"
    | .error e => s!"{id} error {e}"

def runBatch (run : JVal → Except String String) (path : String) : IO UInt32 := do
  for line in (← IO.FS.readFile path).splitOn "\n" do
    unless line.isEmpty do
      IO.println (runLine run line)
  return 0

def constants : Json :=
  Json.mkObj [
    ("required_premises", Json.mkObj (proofRules.map fun r => (r, toJson (requiredPremises r)))),
    ("proof_rules", toJson proofRules),
    ("output_operations", toJson outputOperations),
    ("handover_operations", toJson handoverOperations)]

def main : List String → IO UInt32
  | ["verify-batch", path] => runBatch (fun j => (verifyCase j).map (·.label)) path
  | ["derive-batch", path] => runBatch (fun j => (deriveCase j).map (·.compress)) path
  | ["release-batch", path] => runBatch (fun j => (releaseCase j).map (·.compress)) path
  | ["advance-batch", path] => runBatch (fun j => (advanceCase j).map (·.compress)) path
  | ["eval-batch", path] => runBatch (fun j => (evalCase j).map (·.compress)) path
  | ["constants"] => do
    IO.println constants.compress
    return 0
  | _ => do
    IO.eprintln "usage: komki-spec verify-batch|derive-batch|release-batch|advance-batch|eval-batch <cases.jsonl> | komki-spec constants"
    return 2
