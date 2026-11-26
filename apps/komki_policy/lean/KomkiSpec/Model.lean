import KomkiSpec.Calculus
import KomkiSpec.Evaluator

/-!
# Inputs of `verify`, after Elixir has validated them

The records of CONTRACT.md § 2.1–2.5 in the shape `verify.ex` works on:
`Registry.compile/1` has sorted observers and readers, `Context` has checked
the snapshot and the intent, and the proof has passed `validate_proof/1`.
Premises keep their raw fields, because `verify.ex` reads them as a map.
-/

namespace KomkiSpec

structure Binding where
  readers : List String
  /-- Rule name → expression, as compiled (unparsed JSON). -/
  operations : List (String × JVal)
  /-- `relaxation_authorities`: (authority, restriction, output) (§ 2.1, R.2.2). -/
  befugnisse : List (String × String × String) := []

structure Registry where
  registryId : String
  /-- 𝒪, sorted. -/
  observers : List String
  /-- Environment → observers, sorted. -/
  environments : List (String × List String)
  bindings : List (String × Binding)
  /-- `transformations`: id → (input labels, output labels), sorted by id (§ 2.1). -/
  transformations : List (String × List String × List String) := []

structure Snapshot where
  snapshotId : String
  /-- B_W: sorted, unique, registered. -/
  workspaceBindings : List String
  workspaceValid : Bool
  environment : String
  classification : String
  /-- λ(x): sorted, unique, registered. -/
  objectLabels : List String
  /-- Fact name → `value`. -/
  facts : List (String × JVal)
  /-- `object_id@version`; only the tree `derive` builds names it. -/
  objectRef : String := ""
  /-- Fact name → (`source`, `source_kind`); only the tree `derive` builds names them. -/
  factSources : List (String × String × String) := []

structure Intent where
  intentId : String
  operation : String

structure Premise where
  name : String
  kind : String
  value : Bool
  /-- The whole premise object. -/
  fields : List (String × JVal)

structure Proof where
  rule : String
  conclusion : String
  registryRef : String
  snapshotRef : String
  intentRef : String
  checkedLabel : List String
  premises : List Premise

def Registry.binding? (Γ : Registry) (b : String) : Option Binding := Γ.bindings.lookup b

def Registry.environment? (Γ : Registry) (env : String) : Option (List String) :=
  Γ.environments.lookup env

/-- `bindings[b].operations[rule]`. -/
def Registry.ruleExpr? (Γ : Registry) (b rule : String) : Option JVal :=
  (Γ.binding? b).bind fun bd => bd.operations.lookup rule

/-- R_b; an unregistered binding has no readers. -/
def Registry.readersOf (Γ : Registry) (b : String) : List String :=
  match Γ.binding? b with
  | some bd => bd.readers
  | none => []

/-- The invariant `Registry.compile/1` enforces: readers ⊆ 𝒪. -/
def Registry.WellFormed (Γ : Registry) : Prop :=
  ∀ b o, o ∈ Γ.readersOf b → o ∈ Γ.observers

/-- Γ as the calculus sees it (R.5.1). -/
def Registry.rules (Γ : Registry) : Rules String String where
  observers o := o ∈ Γ.observers
  readers b o := o ∈ Γ.readersOf b

def Snapshot.fact? (S : Snapshot) : Facts := fun n => S.facts.lookup n

def Premise.get? (p : Premise) (k : String) : Option JVal := p.fields.lookup k

/-- A string field of a premise; `none` if absent or not a string. -/
def Premise.strField? (p : Premise) (k : String) : Option String :=
  match p.get? k with
  | some (.str s) => some s
  | _ => none

end KomkiSpec
