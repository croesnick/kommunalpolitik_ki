import KomkiSpec.ReleaseSound
import KomkiSpec.Input

/-!
# What an Aktionsfreigabe bridges for `emit` and `transfer` (#354)

`enginePath_handover` (A.3 along a path) covers the normal branch with a
proof tree only. An Aktionsfreigabe decides without one, and for `emit` and
`transfer` its blockers leave out the recipient check (`aktionBlockers`
checks recipients only for `unbridgeableOps`, that is `store`; CONTRACT.md
§ 2.8 offers an Aktionsfreigabe for `recipient_not_allowed`, except with
`store`). `aktion_bridges_recipient` makes that concrete: a registry and a
snapshot in the validated domain where the normal branch denies with
`recipient_not_allowed` and an Aktionsfreigabe for the same call permits.
RFC 0003 A.3 and R.6.2 ask otherwise; whether the Aktionsfreigabe may keep
doing this is open in #354. Should #354 close the gap, this theorem fails
and tells.
-/

namespace KomkiSpec.ReleaseGap

/-- `b@1`: readable by `a`, `emit` and `transfer` always allowed. -/
def b : Binding := { readers := ["a"], operations := [("emit", .bool true), ("transfer", .bool true)] }

/-- One binding `b@1` readable by `a`; the environment `env` holds only `w`. -/
def Γ : Registry :=
  { registryId := "r", observers := ["a", "w"], environments := [("env", ["w"])],
    bindings := [("b@1", b)],
    factFields := [("output_content_digest", "string")] }

/-- An object labelled `b@1` in a room with `b@1`, its every fact true. -/
def S : Snapshot :=
  { snapshotId := "s", workspaceBindings := ["b@1"], workspaceValid := true,
    environment := "env", classification := "classified", objectLabels := ["b@1"],
    facts := [("audit_path_ready", .bool true), ("environment_observers_complete", .bool true),
      ("has_operation_right", .bool true), ("output_content_digest", .str "d")] }

def R : Release :=
  { releaseId := "g", kind := "aktionsfreigabe", callHash := "h", scope := "sc",
    authority := "a", validFrom := 0, validUntil := 10, nonce := "n" }

def St : Stand := { standId := "st", version := 0, scope := "sc", asOf := 5, consumed := [] }

def deniesWith (code : String) : Derived → Bool
  | .decision (.deny bs) => bs.any (·.code == code)
  | _ => false

def permits : ReleaseDerived → Bool
  | .decision (.permit _) => true
  | _ => false

theorem compiledOk : Γ.compiledOk = true := by
  simp [Registry.compiledOk, Γ, b, Expr.ofJVal, Registry.wellFormed, scalarType, subsetOfList,
    Expr.typed]

theorem validated : S.validated Γ = true := by decide +kernel

/-- The gap of #354: for `emit` and for `transfer`, in the validated domain,
the normal branch denies `w` as a recipient of `b@1`, and an Aktionsfreigabe
for the same call permits it. -/
theorem aktion_bridges_recipient :
    Γ.compiledOk = true ∧ S.validated Γ = true ∧
    (∀ op ∈ ["emit", "transfer"],
      deniesWith "recipient_not_allowed" (derive Γ S ⟨"i", op⟩) = true ∧
      permits (deriveWithRelease Γ S ⟨"i", op⟩ R St "h") = true) := by
  refine ⟨compiledOk, validated, ?_⟩
  decide +kernel

end KomkiSpec.ReleaseGap
