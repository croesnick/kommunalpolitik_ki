import KomkiSpec.Domain
import KomkiSpec.Remedies

/-!
# What the input checks guarantee (CONTRACT.md § 2.1, § 2.2, § 3)

The theorems assume what `Registry.compile/1` and `Context.validate_snapshot/2`
enforce. `Registry.compiledOk` and `Snapshot.validated` state that as
checks: the invariants the theorems use, plus well-typed expressions and
facts, so the evaluator only meets values of the declared type. The
differential test feeds corrupted registries and snapshots to Elixir;
whatever it accepts has to pass these checks.
-/

namespace KomkiSpec

/-- `type_compatible?/2`: a literal of the field's scalar type. -/
def literalFits (ty : String) : JVal → Bool
  | .str _ => ty == "string"
  | .bool _ => ty == "boolean"
  | .int _ => ty == "integer"
  | _ => false

def scalarType (ty : String) : Bool := ty == "string" || ty == "boolean" || ty == "integer"

/-- § 3: every field declared; `eq`/`member` on a scalar field with literals
of its type, `subset` on a `string_set` field, `at_most` on an `integer`
field with a non-negative bound. -/
def Expr.typed (ff : List (String × String)) : Expr → Bool
  | .tt | .ff => true
  | .eq f lit => match ff.lookup f with
    | some ty => literalFits ty lit
    | none => false
  | .member f lits => match ff.lookup f with
    | some ty => scalarType ty && lits.all (literalFits ty)
    | none => false
  | .subset f lits => match ff.lookup f with
    | some ty => ty == "string_set" && lits.all fun | .str _ => true | _ => false
    | none => false
  | .atMost f b => match ff.lookup f with
    | some ty => ty == "integer" && decide (0 ≤ b)
    | none => false
  | .all cs | .any cs => cs.attach.all fun ⟨c, _⟩ => c.typed ff

def subsetOfList (xs ys : List String) : Bool := xs.all ys.contains

/-- What `Registry.compile/1` guarantees and the model uses (§ 2.1). -/
def Registry.compiledOk (Γ : Registry) : Bool :=
  Γ.wellFormed &&
  Γ.factFields.all (fun (_, ty) => scalarType ty || ty == "string_set") &&
  Γ.environments.all (fun (_, obs) => !obs.isEmpty && subsetOfList obs Γ.observers) &&
  Γ.bindings.all (fun (_, bd) => !bd.readers.isEmpty &&
    bd.operations.all fun (_, j) => match Expr.ofJVal j with
      | some e => e.typed Γ.factFields
      | none => false) &&
  Γ.transformations.all (fun (_, input, output) => !input.isEmpty &&
    subsetOfList input (Γ.bindings.map (·.1)) && subsetOfList output (Γ.bindings.map (·.1)))

/-- A fact value of its declared type. -/
def valueFits (ty : String) : JVal → Bool
  | .str _ => ty == "string"
  | .bool _ => ty == "boolean"
  | .int _ => ty == "integer"
  | .arr xs => ty == "string_set" && xs.all fun | .str _ => true | _ => false
  | _ => false

/-- What `Context.validate_snapshot/2` guarantees against a compiled registry (§ 2.2). -/
def Snapshot.validated (Γ : Registry) (S : Snapshot) : Bool :=
  S.wellFormed && (Γ.environment? S.environment).isSome &&
  subsetOfList S.workspaceBindings (Γ.bindings.map (·.1)) &&
  subsetOfList S.objectLabels (Γ.bindings.map (·.1)) &&
  S.facts.all fun (n, v) =>
    if admitBaseFacts.contains n then valueFits "boolean" v
    else match Γ.factFields.lookup n with
      | some ty => valueFits ty v
      | none => false

/-- Every registry `Registry.compile/1` accepts meets the registry premises
of the theorems. -/
theorem Registry.compiledOk_sound {Γ : Registry} (h : Γ.compiledOk = true) :
    Γ.WellFormed ∧ Γ.AuthoritiesKnown := by
  simp only [Registry.compiledOk, Bool.and_eq_true] at h
  exact ⟨Registry.wellFormed_sound h.1.1.1.1, Registry.wellFormed_authorities h.1.1.1.1⟩

/-- Every snapshot `Context.validate_snapshot/2` accepts meets the snapshot
premise of the theorems, and its environment is registered. -/
theorem Snapshot.validated_sound {Γ : Registry} {S : Snapshot} (h : S.validated Γ = true) :
    S.WellFormed ∧ (Γ.environment? S.environment).isSome := by
  simp only [Snapshot.validated, Bool.and_eq_true] at h
  exact ⟨Snapshot.wellFormed_sound h.1.1.1.1, h.1.1.1.2⟩

end KomkiSpec
