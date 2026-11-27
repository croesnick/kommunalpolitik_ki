import KomkiSpec.Bridge

/-!
`komki-spec verify-batch <cases.jsonl>`: one case per line,
`{"id": n, "registry": …, "snapshot": …, "intent": …, "proof": …}`; prints
`<id> <json>` with `check/4`'s reasons and result, or `{"input_error": code}`,
or `<id> error <reason>` per line.

`komki-spec derive-batch <cases.jsonl>`: one case per line,
`{"id": n, "registry": …, "snapshot": …, "intent": …}`; prints `<id> <json>`
with `derive`'s decision, or `<id> error <reason>`.

`komki-spec release-batch` and `advance-batch`: the same for
`decide_with_release/5` (`{…, "release", "stand"}`) and for
`Stand.advance/2` (`{"id", "stand", "proposal"}`); `eval-batch` for
`Evaluator.evaluate/2` (`{"id", "expression", "facts"}`); `domain-batch`
checks a registry (and snapshot) against the domain the input checks
guarantee (`{"id", "registry", "snapshot"?}`); `json-batch` runs bytes
through the strict parser and the canonical encoder (`{"id", "hex"}`);
`cli-batch` runs `komki-policy decide|verify|advance` on file bytes
(`{"id", "command", "files": {name: hex}}`).

`komki-spec constants`: the fixed tables of the model, for the comparison
with `KomkiPolicy.Derive`.
-/

open KomkiSpec Lean

/-- Each line goes through the strict parser, which keeps `1.0e3` a float
as `JSON.parse/1` does. -/
def runLine (run : JVal → Except String String) (line : String) : String :=
  match KomkiSpec.Json.parse line.toUTF8 with
  | .error e => s!"? error {e}"
  | .ok j =>
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
    ("handover_operations", toJson handoverOperations),
    ("reason_codes", toJson reasonCodes)]

def main : List String → IO UInt32
  | ["verify-batch", path] => runBatch (fun j => (verifyCase j).map (·.toJson.compress)) path
  | ["derive-batch", path] => runBatch (fun j => (deriveCase j).map (·.compress)) path
  | ["release-batch", path] => runBatch (fun j => (releaseCase j).map (·.compress)) path
  | ["advance-batch", path] => runBatch (fun j => (advanceCase j).map (·.compress)) path
  | ["eval-batch", path] => runBatch (fun j => (evalCase j).map (·.compress)) path
  | ["domain-batch", path] => runBatch (fun j => (domainCase j).map (·.compress)) path
  | ["json-batch", path] => runBatch (fun j => (jsonCase j).map (·.compress)) path
  | ["cli-batch", path] => runBatch (fun j => (cliCase j).map (·.compress)) path
  | ["constants"] => do
    IO.println constants.compress
    return 0
  | _ => do
    IO.eprintln "usage: komki-spec verify-batch|derive-batch|release-batch|advance-batch|eval-batch|domain-batch|json-batch|cli-batch <cases.jsonl> | komki-spec constants"
    return 2
