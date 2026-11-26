import KomkiSpec.Derive

/-!
# Release branches, the stand transition and the catalog's GO offers

Mirrors `KomkiPolicy.Derive.decide_with_release/5` (Aktionsfreigabe § 4.6,
Offenlegungsfreigabe § 4.9), `KomkiPolicy.Stand.advance/2` (§ 2.7) and the
GO part of `KomkiPolicy.Remedies.catalog/3` (§ 2.8): which finding offers
which GO (`catalogGos`, which the catalog theorems are about). The whole
catalog is `catalog` in `Remedies.lean`; `catalog_gos` shows both offer the
same GOs.

The call hash is SHA-256 over the call (§ 2.6). The model takes the hash of
the decided call as a parameter `callHash`; the theorems hold for every
value, the bridge passes the one Elixir computes.
-/

namespace KomkiSpec

/-! ## Records (§ 2.6, § 2.7) -/

/-- A validated release (`Release.validate/1`). -/
structure Release where
  releaseId : String
  kind : String
  callHash : String
  scope : String
  authority : String
  validFrom : Int
  validUntil : Int
  nonce : String
  /-- Only an Offenlegungsfreigabe names them. -/
  ausgabeart : Option String := none
  ziellabel : List String := []

/-- A validated Offenlegungsstand (`Stand.validate/1`). -/
structure Stand where
  standId : String
  version : Nat
  scope : String
  asOf : Int
  /-- Nonce → release id. -/
  consumed : List (String × String)

/-- The consumption a permit plans (§ 4.6 step 4), the input of `advance`. -/
structure Proposal where
  releaseId : String
  nonce : String
  standRef : String
  standVersionAfter : Nat
  callHash : String
  ausgabeart : Option String := none
  ziellabel : List String := []

def Stand.ref (St : Stand) : String := St.standId ++ "@" ++ toString St.version

/-! ## The closed assignments of § 4.9 -/

/-- `@ziel_ausgabearten`: target environment → Ausgabeart. -/
def zielAusgabeart (env : String) : Option String :=
  [("ratsprojekte-bestand@1", "ratsprojekte-essenz")].lookup env

/-- `@offenlegung_ziellabel`: Ausgabeart → Ziellabel. -/
def ausgabeartZiellabel (art : String) : Option (List String) :=
  [("ratsprojekte-essenz", ["ratsprojekte@1"])].lookup art

/-- `Remedies.unbridgeable_observers_operations/0` and
`unbridgeable_recipient_operations/0`: no GO bridges these for `store`. -/
def unbridgeableOps : List String := ["store"]

/-! ## The release checks (§ 4.6 step 3) -/

def releaseChecks (Γ : Registry) (R : Release) (St : Stand) (callHash : String) : List Blocker :=
  (if R.callHash == callHash then [] else [{ code := "release_call_mismatch" }]) ++
  (if St.asOf < R.validFrom then [{ code := "release_not_yet_valid" }]
   else if St.asOf > R.validUntil then [{ code := "release_expired" }] else []) ++
  (if (St.consumed.lookup R.nonce).isSome then [{ code := "release_nonce_consumed" }] else []) ++
  (if R.scope == St.scope then [] else [{ code := "release_scope_mismatch" }]) ++
  (if Γ.observers.contains R.authority then [] else [{ code := "release_authority_unknown" }])

/-- `release_env_observers/2`: for `store`, an unproven observer list blocks. -/
def envObserverBlockers (S : Snapshot) (op : String) : List Blocker :=
  if unbridgeableOps.contains op && factState S "environment_observers_complete" != .true then
    [{ code := "recipients_unproven" }]
  else []

/-! ## Aktionsfreigabe (§ 4.6) -/

def aktionBlockers (Γ : Registry) (S : Snapshot) (op : String) (R : Release) (St : Stand)
    (callHash : String) : List Blocker :=
  let checked := checkedLabel op S
  (workspaceFindings S).blockers ++ envObserverBlockers S op ++
  (if handoverOperations.contains op then (labelPreservationFindings S checked).blockers else []) ++
  (if unbridgeableOps.contains op then
     (recipientFindings Γ (actualRecipients Γ S) checked).blockers else []) ++
  releaseChecks Γ R St callHash

/-! ## Offenlegungsfreigabe (§ 4.9) -/

/-- `Calculus.lockerungsbeduerftige_bindungen/3`: bindings whose readers miss part of ρ. -/
def lockerungsbeduerftig (Γ : Registry) (checked rho : List String) : List String :=
  checked.filter fun b =>
    match Γ.binding? b with
    | none => true
    | some bd => !(rho.filter fun o => !bd.readers.contains o).isEmpty

/-- `befugnis?/3`: the binding carries {authority, readers, Ausgabeart}. -/
def befugnis (Γ : Registry) (b authority art : String) : Bool :=
  match Γ.binding? b with
  | none => false
  | some bd => bd.befugnisse.any fun (a, r, o) => a == authority && r == "readers" && o == art

def ziellabelBlockers (Γ : Registry) (S : Snapshot) (R : Release) : List Blocker :=
  if zielAusgabeart S.environment != R.ausgabeart then [{ code := "ausgabeart_unpassend" }]
  else if R.ziellabel.any fun b => (Γ.binding? b).isNone then [{ code := "ziellabel_unknown" }]
  else if (R.ausgabeart.bind ausgabeartZiellabel) != some R.ziellabel then
    [{ code := "ziellabel_unpassend" }]
  else []

def befugnisBlockers (Γ : Registry) (S : Snapshot) (R : Release) : List Blocker :=
  let checked := checkedLabel "store" S
  (lockerungsbeduerftig Γ checked (actualRecipients Γ S)).filterMap fun b =>
    if befugnis Γ b R.authority (R.ausgabeart.getD "") then none
    else some { code := "lockerungsbefugnis_fehlt", binding := some b }

/-- The recipient test under the Ziellabel; skipped for an unregistered one,
which `ziellabel_unknown` already denies (#632). -/
def ziellabelRecipientBlockers (Γ : Registry) (S : Snapshot) (R : Release) : List Blocker :=
  if R.ziellabel.all fun b => (Γ.binding? b).isSome then
    (recipientFindings Γ (actualRecipients Γ S) R.ziellabel).blockers
  else []

def offenlegungBlockers (Γ : Registry) (S : Snapshot) (R : Release) (St : Stand)
    (callHash : String) : List Blocker :=
  (workspaceFindings S).blockers ++
  (labelPreservationFindings S (checkedLabel "store" S)).blockers ++
  releaseChecks Γ R St callHash ++ envObserverBlockers S "store" ++
  ziellabelBlockers Γ S R ++ befugnisBlockers Γ S R ++ ziellabelRecipientBlockers Γ S R

/-! ## The release decision -/

inductive ReleaseDecision where
  | permit (proposal : Proposal)
  | deny (blockers : List Blocker)

inductive ReleaseDerived where
  | decision (d : ReleaseDecision)
  | inputError (code : String)
  | unsupported

def proposalOf (R : Release) (St : Stand) (callHash : String) : Proposal :=
  { releaseId := R.releaseId, nonce := R.nonce, standRef := St.ref,
    standVersionAfter := St.version + 1, callHash,
    ausgabeart := if R.kind == "offenlegungsfreigabe" then R.ausgabeart else none,
    ziellabel := if R.kind == "offenlegungsfreigabe" then R.ziellabel else [] }

def releaseBlockers (Γ : Registry) (S : Snapshot) (op : String) (R : Release) (St : Stand)
    (callHash : String) : List Blocker :=
  if R.kind == "offenlegungsfreigabe" then offenlegungBlockers Γ S R St callHash
  else aktionBlockers Γ S op R St callHash

/-- `decide_with_release/5`: snapshot first (`unknown_environment`), then
whether the branch exists (`unsupported`), then the output prerequisites. -/
def deriveWithRelease (Γ : Registry) (S : Snapshot) (I : Intent) (R : Release) (St : Stand)
    (callHash : String) : ReleaseDerived :=
  if (Γ.environment? S.environment).isNone then .inputError "unknown_environment"
  else if !outputOperations.contains I.operation then .unsupported
  else if !(R.kind == "aktionsfreigabe" ||
      (R.kind == "offenlegungsfreigabe" && I.operation == "store")) then .unsupported
  else if (S.facts.lookup "output_content_digest").isNone then .inputError "emit_digest_missing"
  else if S.classification != "classified" then .inputError "emit_object_not_classified"
  else
    match releaseBlockers Γ S I.operation R St callHash with
    | [] => .decision (.permit (proposalOf R St callHash))
    | bs => .decision (.deny bs)

/-! ## `advance` (§ 2.7) -/

inductive Advanced where
  | ok (St : Stand)
  | refused (code : String)

/-- Compare-and-swap on the version, then the nonce. -/
def advance (St : Stand) (P : Proposal) : Advanced :=
  if P.standRef == St.ref && P.standVersionAfter == St.version + 1 then
    if (St.consumed.lookup P.nonce).isSome then .refused "nonce_already_consumed"
    else .ok { St with version := St.version + 1, consumed := (P.nonce, P.releaseId) :: St.consumed }
  else .refused "stand_version_conflict"

/-! ## The catalog's GO offers (§ 2.8) -/

/-- A GO a catalog entry offers. -/
inductive Go where
  /-- `aktionsfreigabe` scope `call`. -/
  | aktion (callHash : String)
  /-- `aktionsfreigabe` scope `object` (quarantine). -/
  | object (ref : String)
  /-- `offenlegungsfreigabe` scope `call`. -/
  | offenlegung (callHash art : String) (ziellabel : List String)
  deriving BEq

def unbridgeableCodes : List String := ["workspace_invalid", "label_not_preserved"]

def offenlegungUnbridgeableCodes : List String :=
  ["lockerungsbefugnis_fehlt", "ausgabeart_unpassend", "ziellabel_unknown",
   "ziellabel_unpassend", "recipients_unproven"]

def callGoCodes : List String :=
  ["basis_right_false", "binding_condition_false", "audit_path_not_ready",
   "recipient_not_allowed", "missing_operation_rule"]

/-- What `Registry.compile/1` enforces for relaxation authorities: each one
is an observer of 𝒪 (§ 2.1). -/
def Registry.AuthoritiesKnown (Γ : Registry) : Prop :=
  ∀ b bd, Γ.binding? b = some bd → ∀ x ∈ bd.befugnisse, x.1 ∈ Γ.observers

/-- The authorities with a Befugnis {readers, `art`} on binding `b`. -/
def befugteFor (Γ : Registry) (art b : String) : List String :=
  match Γ.binding? b with
  | none => []
  | some bd => bd.befugnisse.filterMap fun (a, r, o) =>
      if r == "readers" && o == art then some a else none

/-- `Calculus.lockerungsbefugte/4`: authorities with a Befugnis on every
lockerungsbedürftige binding; none if no binding needs one. -/
def lockerungsbefugte (Γ : Registry) (checked rho : List String) (art : String) : List String :=
  match lockerungsbeduerftig Γ checked rho with
  | [] => []
  | b :: bs =>
    sortDedup ((befugteFor Γ art b).filter fun a => bs.all fun b' => (befugteFor Γ art b').contains a)

/-- The decision a catalog belongs to, as `remedies_context/2` hands it over. -/
structure CatalogCtx where
  /-- `admit`, `emit`, `store`, `transfer` or `release`. -/
  rule : String
  callHash : Option String
  objectRef : String
  checked : List String
  rho : List String
  observersProven : Bool
  ausgabeart : Option String
  ziellabel : List String
  /-- Only for `release`: the kind of the presented release. -/
  releaseKind : Option String := none
  /-- λ(x) for `admit`, `[]` otherwise (`remedies_context/2`). -/
  objectLabels : List String := []

/-- `remedies_context/2` of the normal branch. -/
def normalCatalogCtx (Γ : Registry) (S : Snapshot) (rule callHash : String) : CatalogCtx :=
  let art := zielAusgabeart S.environment
  { rule, callHash := if outputOperations.contains rule then some callHash else none,
    objectRef := S.objectRef, checked := checkedLabel rule S, rho := actualRecipients Γ S,
    observersProven := factState S "environment_observers_complete" == .true,
    ausgabeart := art, ziellabel := (art.bind ausgabeartZiellabel).getD [],
    objectLabels := if rule == "admit" then S.objectLabels else [] }

/-- `regular_transitions/4` and `release_transitions/2`, GO entries only. -/
def regularGos (c : CatalogCtx) (code : String) : List Go :=
  if c.rule == "release" then
    if c.releaseKind == some "offenlegungsfreigabe" then
      if unbridgeableCodes.contains code || offenlegungUnbridgeableCodes.contains code ||
          code == "recipient_not_allowed" then []
      else [.offenlegung (c.callHash.getD "") (c.ausgabeart.getD "") c.ziellabel]
    else if unbridgeableCodes.contains code then []
    else [.aktion (c.callHash.getD "")]
  else if code == "object_quarantine" then [.object c.objectRef]
  else if outputOperations.contains c.rule &&
      ["basis_right_false", "binding_condition_false", "audit_path_not_ready",
       "recipient_not_allowed", "missing_operation_rule"].contains code then
    match c.callHash with
    | some h => [.aktion h]
    | none => []
  else []

/-- `unbridgeable?/2`. -/
def unbridgeableFor (rule code : String) : Bool :=
  if rule == "release" && (code == "recipient_not_allowed" || code == "recipients_unproven") then
    true
  else if code == "recipient_not_allowed" then unbridgeableOps.contains rule
  else unbridgeableCodes.contains code

def observersUnproven (c : CatalogCtx) : Bool := c.rule == "store" && !c.observersProven

/-- `offenlegung_offerable?/2`, with the Ziellabel condition of #631. -/
def offenlegungOfferable (Γ : Registry) (c : CatalogCtx) : Bool :=
  match c.ausgabeart, c.callHash with
  | some art, some _ =>
    !c.ziellabel.isEmpty && c.ziellabel.all (fun b => (Γ.binding? b).isSome) &&
    (c.rho.filter fun o => !(allowedRecipients Γ c.ziellabel).contains o).isEmpty &&
    !(lockerungsbefugte Γ c.checked c.rho art).isEmpty
  | _, _ => false

/-- `catalog/3`, GO entries per finding, after `withhold_call_go/3`. -/
def catalogGos (Γ : Registry) (c : CatalogCtx) (codes : List String) : List (List Go) :=
  let stripAktion0 := codes.any (unbridgeableFor c.rule) || observersUnproven c
  let stripOff := codes.any (fun k => unbridgeableCodes.contains k ||
      offenlegungUnbridgeableCodes.contains k) ||
    (c.rule == "release" && codes.contains "recipient_not_allowed") || observersUnproven c
  let instead := c.rule == "store" && codes.contains "recipient_not_allowed" &&
    c.rule != "release" && offenlegungOfferable Γ c && !stripOff
  let stripAktion := stripAktion0 || instead
  codes.map fun code =>
    let gos := (regularGos c code).filter fun
      | .aktion _ => !stripAktion
      | .offenlegung _ _ _ => !stripOff
      | .object _ => true
    gos ++ (if instead && callGoCodes.contains code then
      [.offenlegung (c.callHash.getD "") (c.ausgabeart.getD "") c.ziellabel] else [])

end KomkiSpec
