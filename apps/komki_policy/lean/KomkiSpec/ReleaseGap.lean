import KomkiSpec.ReleaseSound
import KomkiSpec.Input
import KomkiSpec.CallHash

/-!
# Open release questions as theorems (#354, #638, #673)

`enginePath_handover` (A.3 along a path) covers the normal branch with a
proof tree only. An Aktionsfreigabe decides without one, and for `emit` and
`transfer` its blockers leave out the recipient check (`aktionBlockers`
checks recipients only for `unbridgeableOps`, that is `store`; CONTRACT.md
§ 2.8 offers an Aktionsfreigabe for `recipient_not_allowed`, except with
`store`). `aktion_bridges_recipient` makes that concrete: a registry and a
snapshot in the validated domain where the normal branch denies with
`recipient_not_allowed` and an Aktionsfreigabe for the same call permits.
RFC 0003 A.3 (corollary) and R.5.7 ask otherwise, and by R.6.1 an
Aktionsfreigabe is no Lockerung; whether it may keep doing this is open in
#354. Should #354 close the gap, this theorem fails and tells.

`ReleaseGap638.offenlegung_drops_without_befugnis` records the second open
question, #638: an Offenlegungsfreigabe removes a binding from the label
without its authority's Befugnis when the binding's readers already cover
the store, while R.5.7 asks the Befugnis for every removed binding. With
the binding its operation rules go too (§ 4.9 step 8). The fixture
`case_offenlegung_permit` is such a case already: `web-oeffentlich-fall@1`
goes without a Befugnis.

`ReleaseGap673.release_any_environment` records #673: the call hash binds
digest, object, operation and workspace, not the environment
(`callHashOf_environment`), and the release branch reads it only as
`R.callHash == c` (`permits_callHash`). A release a person gave for the emit
into one environment permits the same emit into another, though R.6.2 asks
a release to fix its target.
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

namespace KomkiSpec.ReleaseGap638

/-- `b2`: read by `p` and `q`; `ratsprojekte@1`: read by `p` only. -/
def b2 : Binding := { readers := ["p", "q"], operations := [] }
def rp : Binding := { readers := ["p"], operations := [] }

/-- The store `ratsprojekte-bestand@1` is observed by `p`; `a` is an authority. -/
def Γ : Registry :=
  { registryId := "r", observers := ["a", "p", "q"],
    environments := [("ratsprojekte-bestand@1", ["p"])],
    bindings := [("b2", b2), ("ratsprojekte@1", rp)],
    factFields := [("output_content_digest", "string")] }

/-- An object labelled `b2` and `ratsprojekte@1`, stored into the Bestand. -/
def S : Snapshot :=
  { snapshotId := "s", workspaceBindings := ["b2", "ratsprojekte@1"], workspaceValid := true,
    environment := "ratsprojekte-bestand@1", classification := "classified",
    objectLabels := ["b2", "ratsprojekte@1"],
    facts := [("audit_path_ready", .bool true), ("environment_observers_complete", .bool true),
      ("has_operation_right", .bool true), ("output_content_digest", .str "d")] }

/-- An Offenlegungsfreigabe of authority `a` to the Ziellabel `[ratsprojekte@1]`. -/
def R : Release :=
  { releaseId := "g", kind := "offenlegungsfreigabe", callHash := "h", scope := "sc",
    authority := "a", validFrom := 0, validUntil := 10, nonce := "n",
    ausgabeart := some "ratsprojekte-essenz", ziellabel := ["ratsprojekte@1"] }

def St : Stand := { standId := "st", version := 0, scope := "sc", asOf := 5, consumed := [] }

theorem compiledOk : Γ.compiledOk = true := by
  simp [Registry.compiledOk, Γ, b2, rp, Registry.wellFormed, scalarType, subsetOfList]

theorem validated : S.validated Γ = true := by
  simp [Snapshot.validated, Snapshot.wellFormed, S, Γ, sortStrings, sortDedup]
  decide

/-- The question of #638: an Offenlegungsfreigabe that removes `b2` from the
object's label (`b2 ∈ L ∖ L'`) without any Befugnis of its authority for
`b2` permits the store, because `b2`'s readers already cover the store's
observers. R.5.7 asks the Befugnis for every removed binding. -/
theorem offenlegung_drops_without_befugnis :
    Γ.compiledOk = true ∧ S.validated Γ = true ∧
    ReleaseGap.permits (deriveWithRelease Γ S ⟨"i", "store"⟩ R St "h") = true ∧
    "b2" ∈ S.objectLabels ∧ "b2" ∉ R.ziellabel ∧
    befugnis Γ "b2" R.authority "ratsprojekte-essenz" = false := by
  refine ⟨compiledOk, validated, ?_⟩
  decide +kernel

end KomkiSpec.ReleaseGap638

namespace KomkiSpec.ReleaseGap673
open ReleaseGap

/-- The call hash names digest, object, operation and workspace, not the
environment. -/
theorem callHashOf_environment (S : Snapshot) (I : Intent) (e : String) :
    callHashOf { S with environment := e } I = callHashOf S I := rfl

/-- `b@1`, read by `a`, `w` and `x`: both environments are allowed
recipients, so the witness does not lean on #354. -/
def b2 : Binding :=
  { readers := ["a", "w", "x"], operations := [("emit", .bool true), ("transfer", .bool true)] }

def envs2 : List (String × List String) := [("env", ["w"]), ("env2", ["x"])]

/-- Two environments, `env` observed by `w` and `env2` observed by `x`. -/
def Γ2 : Registry :=
  { registryId := "r", observers := ["a", "w", "x"], environments := envs2,
    bindings := [("b@1", b2)], factFields := [("output_content_digest", "string")] }

/-- The object of `ReleaseGap`, but the operation right is false: the
normal branch blocks with `basis_right_false`, which an Aktionsfreigabe
bridges. -/
def S2 : Snapshot :=
  { ReleaseGap.S with
    facts := [("audit_path_ready", .bool true), ("environment_observers_complete", .bool true),
      ("has_operation_right", .bool false), ("output_content_digest", .str "d")] }

def I : Intent := ⟨"i", "emit"⟩

/-- `permits` as the branch's guards and empty blockers. -/
theorem permits_eq (Γ : Registry) (S : Snapshot) (I : Intent) (R : Release) (St : Stand)
    (c : String) :
    permits (deriveWithRelease Γ S I R St c) =
      ((Γ.environment? S.environment).isSome && outputOperations.contains I.operation &&
        (R.kind == "aktionsfreigabe" || (R.kind == "offenlegungsfreigabe" && I.operation == "store")) &&
        (S.facts.lookup "output_content_digest").isSome && S.classification == "classified" &&
        (releaseBlockers Γ S I.operation R St c).isEmpty) := by
  unfold deriveWithRelease
  cases he : Γ.environment? S.environment <;>
    cases ho : outputOperations.contains I.operation <;>
    cases hk : (R.kind == "aktionsfreigabe" || (R.kind == "offenlegungsfreigabe" && I.operation == "store")) <;>
    cases hd : S.facts.lookup "output_content_digest" <;>
    cases hc : S.classification == "classified" <;>
    cases hb : releaseBlockers Γ S I.operation R St c <;>
    simp_all [permits]

/-- The release branch reads the call hash only as `R.callHash == c`: a
release bound to its call decides as one bound to any other matching hash. -/
theorem permits_callHash (Γ : Registry) (S : Snapshot) (I : Intent) (R : Release) (St : Stand)
    (c c' : String) :
    permits (deriveWithRelease Γ S I { R with callHash := c } St c) =
      permits (deriveWithRelease Γ S I { R with callHash := c' } St c') := by
  have hb : ∀ op, releaseBlockers Γ S op { R with callHash := c } St c =
      releaseBlockers Γ S op { R with callHash := c' } St c' := by
    intro op
    simp [releaseBlockers, aktionBlockers, offenlegungBlockers, releaseChecks, befugnisBlockers,
      ziellabelBlockers, ziellabelRecipientBlockers, befugnis]
  rw [permits_eq, permits_eq, hb]

theorem compiledOk : Γ2.compiledOk = true := by
  simp [Registry.compiledOk, Γ2, b2, envs2, Expr.ofJVal, Registry.wellFormed, scalarType,
    subsetOfList, Expr.typed]

theorem validated : ∀ e ∈ ["env", "env2"], ({ S2 with environment := e }).validated Γ2 = true := by
  decide +kernel

/-- The gap of #673: a release bound to the call hash of the emit into `env`
also binds the same emit into `env2`, and permits both, though the normal
branch blocks both (`basis_right_false`). R.6.2 asks a release to fix its
target. Independent of #354 in substance: both environments are allowed
recipients, and closing only #354 keeps both permits. The proof would need
work then, though: the release branch would compute the recipient check,
which `decide +kernel` does not reduce, so prove that part by `simp`. -/
theorem release_any_environment :
    Γ2.compiledOk = true ∧
    callHashOf { S2 with environment := "env2" } I = callHashOf { S2 with environment := "env" } I ∧
    ∀ e ∈ ["env", "env2"],
      ({ S2 with environment := e }).validated Γ2 = true ∧
      ReleaseGap.deniesWith "basis_right_false" (derive Γ2 { S2 with environment := e } I) = true ∧
      permits (deriveWithRelease Γ2 { S2 with environment := e } I
        { R with callHash := callHashOf { S2 with environment := "env" } I } St
        (callHashOf { S2 with environment := e } I)) = true := by
  refine ⟨compiledOk, rfl, ?_⟩
  intro e he
  refine ⟨validated e he, ?_⟩
  erw [permits_callHash Γ2 _ I R St (callHashOf { S2 with environment := "env" } I) "h"]
  revert e
  decide +kernel

end KomkiSpec.ReleaseGap673
