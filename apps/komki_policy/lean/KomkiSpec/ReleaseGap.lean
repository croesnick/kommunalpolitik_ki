import KomkiSpec.ReleaseSound
import KomkiSpec.Input

/-!
# Open release questions as theorems (#354, #638)

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
