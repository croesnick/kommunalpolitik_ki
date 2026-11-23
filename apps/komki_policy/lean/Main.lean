import KomkiSpec.Bridge

/-!
`komki-spec verify-batch <cases.jsonl>`: one case per line,
`{"id": n, "registry": …, "snapshot": …, "intent": …, "proof": …}`; prints
`<id> valid|invalid|out_of_scope` or `<id> error <reason>` per line.

`komki-spec constants`: the fixed tables of the model, for the comparison
with `KomkiPolicy.Derive`.
-/

open KomkiSpec Lean

def runLine (line : String) : String :=
  match Json.parse line with
  | .error e => s!"? error {e}"
  | .ok json =>
    let j := JVal.ofJson json
    let id := match j.get? "id" with
      | some (.int i) => toString i
      | _ => "?"
    match verifyCase j with
    | .ok outcome => s!"{id} {outcome.label}"
    | .error e => s!"{id} error {e}"

def constants : Json :=
  Json.mkObj [("admit_premises", toJson admitPremises), ("proof_rules", toJson proofRules)]

def main : List String → IO UInt32
  | ["verify-batch", path] => do
    for line in (← IO.FS.readFile path).splitOn "\n" do
      unless line.isEmpty do
        IO.println (runLine line)
    return 0
  | ["constants"] => do
    IO.println constants.compress
    return 0
  | _ => do
    IO.eprintln "usage: komki-spec verify-batch <cases.jsonl> | komki-spec constants"
    return 2
