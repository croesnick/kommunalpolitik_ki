import Lean.Data.Json
import KomkiSpec.Domain
import KomkiSpec.Input

/-!
# Bridge: the CLI's JSON into the model

Unverified and deliberately thin. It reads the records `komki-policy verify`
and `decide` read and assumes they passed Elixir's input validation;
anything else is a decoding error, never a verdict. Sorting mirrors
`Registry.compile/1`. A registry or snapshot outside the domain the
theorems assume (`Registry.wellFormed`, `Snapshot.wellFormed`) is a decoding
error too. On the way out it writes `derive`'s decision in the
shape of `Derive.decide/3`, without the remedies.
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
    let befugnisse ← match b.get? "relaxation_authorities" with
      | some (.arr es) => es.mapM fun e => do
          pure (← strAt e "authority", ← strAt e "restriction", ← strAt e "output")
      | _ => pure []
    pure (id, { readers, operations := ← asObj (← field b "operations"), befugnisse : Binding })
  let transformations ← match j.get? "transformations" with
    | some (.obj ts) => ts.mapM fun (id, t) => do
        pure (id, ← asStrs (← field t "input_labels"), ← asStrs (← field t "output_labels"))
    | _ => pure []
  pure {
    registryId := ← strAt j "registry_id"
    observers := sortStrings (← asStrs (← field j "observers"))
    environments, bindings
    factFields := ← match j.get? "fact_fields" with
      | some (.obj fs) => fs.mapM fun (n, t) => do pure (n, ← asStr t)
      | _ => pure []
    transformations := transformations.mergeSort fun a b => !decide (b.1 < a.1) }

def decodeSnapshot (j : JVal) : Decode Snapshot := do
  let ws ← field j "workspace"
  let obj ← field j "object"
  let entries ← asObj (← field j "facts")
  let facts ← entries.mapM fun (name, entry) => do
    pure (name, ← field entry "value")
  let factSources ← entries.mapM fun (name, entry) => do
    pure (name, ← strAt entry "source", ← strAt entry "source_kind")
  pure {
    snapshotId := ← strAt j "snapshot_id"
    workspaceBindings := ← asStrs (← field ws "bindings")
    workspaceValid := ← asBool (← field ws "valid")
    environment := ← strAt ws "environment"
    classification := ← strAt obj "classification"
    objectLabels := ← asStrs (← field obj "labels")
    facts
    objectRef := (← strAt obj "object_id") ++ "@" ++ (← strAt obj "version")
    factSources }

def decodeWorld (j : JVal) : Decode (Registry × Snapshot) := do
  let Γ ← decodeRegistry (← field j "registry")
  let S ← decodeSnapshot (← field j "snapshot")
  unless Γ.wellFormed do throw "registry outside the validated domain"
  unless S.wellFormed do throw "snapshot outside the validated domain"
  pure (Γ, S)

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
  | .inputError => "input_error"

/-- One case `{"registry", "snapshot", "intent", "proof"}` → verdict. -/
def verifyCase (j : JVal) : Decode Outcome := do
  let (Γ, S) ← decodeWorld j
  pure (verify Γ S (← decodeIntent (← field j "intent")) (← decodeProof (← field j "proof")))

/-! ## `derive`'s decision as JSON -/

partial def JVal.toJson : JVal → Json
  | .null => .null
  | .bool b => .bool b
  | .int i => .num (Lean.JsonNumber.fromInt i)
  | .float m e => .num ⟨m, e⟩
  | .str s => .str s
  | .arr xs => .arr (xs.map JVal.toJson).toArray
  | .obj kvs => Json.mkObj (kvs.map fun (k, v) => (k, JVal.toJson v))

def optStr : Option String → Json
  | some s => .str s
  | none => .null

def Blocker.toJson (b : Blocker) : Json :=
  Json.mkObj <|
    [("code", .str b.code), ("binding", optStr b.binding), ("condition", optStr b.condition)] ++
    match b.outside with
    | some os => [("recipients_outside", Lean.toJson os)]
    | none => []

def Evidence.toJson (e : Evidence) : Json :=
  Json.mkObj [("code", .str e.code), ("fact", optStr e.fact), ("binding", optStr e.binding)]

def Proof.toJson (P : Proof) : Json :=
  Json.mkObj [("schema", .str "komki-proof/1"), ("rule", .str P.rule),
    ("conclusion", .str P.conclusion), ("registry_ref", .str P.registryRef),
    ("snapshot_ref", .str P.snapshotRef), ("intent_ref", .str P.intentRef),
    ("checked_label", Lean.toJson P.checkedLabel),
    ("premises", .arr (P.premises.map fun p => (JVal.obj p.fields).toJson).toArray)]

def Go.toJson : Go → Json
  | .aktion h => Json.mkObj [("type", "aktionsfreigabe"), ("scope", "call"), ("call_hash", h)]
  | .object r => Json.mkObj [("type", "aktionsfreigabe"), ("scope", "object"), ("object", r)]
  | .offenlegung h art zl => Json.mkObj [("type", "offenlegungsfreigabe"), ("scope", "call"),
      ("call_hash", h), ("ausgabeart", art), ("ziellabel", Lean.toJson zl)]

def Transition.toJson : Transition → Json
  | .fakt facts => Json.mkObj [("type", "fakt_nachreichen"), ("facts", Lean.toJson facts)]
  | .transformation id out => Json.mkObj [("type", "registrierte_transformation"),
      ("transformation", .str id), ("output_labels", Lean.toJson out)]
  | .neuerRaum rb rr => Json.mkObj [("type", "neuer_raum"), ("required_bindings", Lean.toJson rb),
      ("required_recipients", Lean.toJson rr)]
  | .go g => g.toJson

/-- The `remedies` entries: each finding with its transitions. -/
def remediesJson (findings : List Json) (catalogue : List (List Transition)) : Json :=
  .arr ((findings.zip catalogue).map fun (f, ts) =>
    match f with
    | .obj kvs => Json.obj (kvs.insert "transitions" (.arr (ts.map Transition.toJson).toArray))
    | other => other).toArray

def gosJson (gos : List (List Go)) : Json :=
  .arr (gos.map fun g => Json.arr (g.map Go.toJson).toArray).toArray

/-- The fields of `Derive.decide/3` this model decides: everything but the
echoes of the input; the remedies come from `decisionRemedies`, the GO
offers the theorems are about from `decisionGos`. -/
def decisionJson (S : Snapshot) (rule : String) (d : Decision) : Json :=
  let checked := Lean.toJson (checkedLabel rule S)
  let (name, blockers, evidence, proof, assigned) : String × Json × Json × Json × Json :=
    match d with
    | .permit P => ("permit", .null, .null, P.toJson, checked)
    | .deny bs => ("deny", .arr (bs.map Blocker.toJson).toArray, .null, .null, .null)
    | .indeterminate es => ("indeterminate", .null, .arr (es.map Evidence.toJson).toArray, .null, .null)
  let digest := ((S.facts.lookup "output_content_digest").map JVal.toJson).getD .null
  let output :=
    if rule == "admit" then []
    else if rule == "emit" then [("assigned_label", assigned), ("content_digest", digest)]
    else [("content_digest", digest)]
  Json.mkObj <|
    [("decision", .str name), ("rule", .str rule), ("checked_label", checked),
     ("blockers", blockers), ("missing_evidence", evidence), ("proof", proof)] ++ output

/-- The GO offers per finding of a `deny` or `indeterminate`. -/
def decisionGos (Γ : Registry) (S : Snapshot) (rule callHash : String) : Decision → Json
  | .permit _ => .null
  | .deny bs => gosJson (catalogGos Γ (normalCatalogCtx Γ S rule callHash) (bs.map (·.code)))
  | .indeterminate es =>
    gosJson (catalogGos Γ (normalCatalogCtx Γ S rule callHash) (es.map (·.code)))

/-- The whole catalog of a `deny` or `indeterminate` (§ 2.8). -/
def decisionRemedies (Γ : Registry) (S : Snapshot) (rule callHash : String) : Decision → Json
  | .permit _ => .null
  | .deny bs => remediesJson (bs.map Blocker.toJson)
      (catalog Γ (normalCatalogCtx Γ S rule callHash) (bs.map Blocker.finding))
  | .indeterminate es => remediesJson (es.map Evidence.toJson)
      (catalog Γ (normalCatalogCtx Γ S rule callHash) (es.map Evidence.finding))

def withField (j : Json) (k : String) (v : Json) : Json :=
  match j with
  | .obj kvs => .obj (kvs.insert k v)
  | other => other

def Derived.toJson (Γ : Registry) (S : Snapshot) (rule callHash : String) : Derived → Json
  | .decision d => withField (withField (decisionJson S rule d) "gos" (decisionGos Γ S rule callHash d))
      "remedies" (decisionRemedies Γ S rule callHash d)
  | .inputError code => Json.mkObj [("input_error", .str code)]
  | .unsupported => Json.mkObj [("unsupported", .bool true)]

def optStrAt (j : JVal) (k : String) : Decode (Option String) :=
  match j.get? k with
  | some (.str s) => pure (some s)
  | _ => pure none

/-- One case `{"registry", "snapshot", "intent", "call_hash"}` → decision. -/
def deriveCase (j : JVal) : Decode Json := do
  let (Γ, S) ← decodeWorld j
  let I ← decodeIntent (← field j "intent")
  let callHash := (← optStrAt j "call_hash").getD ""
  pure ((derive Γ S I).toJson Γ S I.operation callHash)

/-! ## Release branches and `advance` -/

def asInt : JVal → Decode Int
  | .int i => pure i
  | _ => throw "expected an integer"

def asNat (j : JVal) : Decode Nat := do
  let i ← asInt j
  if i < 0 then throw "expected a non-negative integer" else pure i.toNat

def decodeRelease (j : JVal) : Decode Release := do
  pure {
    releaseId := ← strAt j "release_id", kind := ← strAt j "kind"
    callHash := ← strAt j "call_hash", scope := ← strAt j "scope"
    authority := ← strAt j "authority", validFrom := ← asInt (← field j "valid_from")
    validUntil := ← asInt (← field j "valid_until"), nonce := ← strAt j "nonce"
    ausgabeart := ← optStrAt j "ausgabeart"
    ziellabel := ← match j.get? "ziellabel" with
      | some v => asStrs v
      | none => pure [] }

def decodeStand (j : JVal) : Decode Stand := do
  let consumed ← (← asObj (← field j "consumed")).mapM fun (n, r) => do pure (n, ← asStr r)
  pure {
    standId := ← strAt j "stand_id", version := ← asNat (← field j "version")
    scope := ← strAt j "scope", asOf := ← asInt (← field j "as_of"), consumed }

def decodeProposal (j : JVal) : Decode Proposal := do
  pure {
    releaseId := ← strAt j "release_id", nonce := ← strAt j "nonce"
    standRef := ← strAt j "stand_ref"
    standVersionAfter := ← asNat (← field j "stand_version_after")
    callHash := ← strAt j "call_hash", ausgabeart := ← optStrAt j "ausgabeart"
    ziellabel := ← match j.get? "ziellabel" with
      | some v => asStrs v
      | none => pure [] }

def Proposal.toJson (P : Proposal) : Json :=
  Json.mkObj <|
    [("release_id", .str P.releaseId), ("nonce", .str P.nonce), ("stand_ref", .str P.standRef),
     ("stand_version_after", Lean.toJson P.standVersionAfter), ("call_hash", .str P.callHash)] ++
    match P.ausgabeart with
    | some art => [("ausgabeart", .str art), ("ziellabel", Lean.toJson P.ziellabel)]
    | none => []

def Stand.toJson (St : Stand) : Json :=
  Json.mkObj [("stand_id", .str St.standId), ("version", Lean.toJson St.version),
    ("scope", .str St.scope), ("as_of", Lean.toJson St.asOf),
    ("consumed", Json.mkObj (St.consumed.map fun (n, r) => (n, .str r)))]

/-- `release_remedies_context/4`. -/
def releaseCatalogCtx (Γ : Registry) (S : Snapshot) (rule : String) (R : Release)
    (callHash : String) : CatalogCtx :=
  { rule := "release", releaseKind := some R.kind, callHash := some callHash,
    objectRef := S.objectRef, checked := checkedLabel rule S, rho := actualRecipients Γ S,
    observersProven := factState S "environment_observers_complete" == .true,
    ausgabeart := R.ausgabeart, ziellabel := R.ziellabel }

def releaseDecisionJson (Γ : Registry) (S : Snapshot) (rule : String) (R : Release)
    (callHash : String) (d : ReleaseDecision) : Json :=
  let checked := Lean.toJson (checkedLabel rule S)
  let (name, blockers, proposal, assigned, gos, remedies) :
      String × Json × Json × Json × Json × Json :=
    match d with
    | .permit P => ("permit", .null, P.toJson, checked, .null, .null)
    | .deny bs => ("deny", .arr (bs.map Blocker.toJson).toArray, .null, .null,
        gosJson (catalogGos Γ (releaseCatalogCtx Γ S rule R callHash) (bs.map (·.code))),
        remediesJson (bs.map Blocker.toJson)
          (catalog Γ (releaseCatalogCtx Γ S rule R callHash) (bs.map Blocker.finding)))
  let digest := ((S.facts.lookup "output_content_digest").map JVal.toJson).getD .null
  Json.mkObj <|
    [("decision", .str name), ("rule", .str rule), ("checked_label", checked),
     ("blockers", blockers), ("release", proposal), ("content_digest", digest), ("gos", gos),
     ("remedies", remedies)] ++
    if rule == "emit" then [("assigned_label", assigned)] else []

/-- One case `{"registry", "snapshot", "intent", "release", "stand", "call_hash"}`. -/
def releaseCase (j : JVal) : Decode Json := do
  let (Γ, S) ← decodeWorld j
  let I ← decodeIntent (← field j "intent")
  let R ← decodeRelease (← field j "release")
  let St ← decodeStand (← field j "stand")
  let c ← strAt j "call_hash"
  pure <| match deriveWithRelease Γ S I R St c with
    | .decision d => releaseDecisionJson Γ S I.operation R c d
    | .inputError code => Json.mkObj [("input_error", .str code)]
    | .unsupported => Json.mkObj [("unsupported", .bool true)]

/-- One case `{"stand", "proposal"}`. -/
def advanceCase (j : JVal) : Decode Json := do
  let St ← decodeStand (← field j "stand")
  let P ← decodeProposal (← field j "proposal")
  pure <| match advance St P with
    | .ok St' => Json.mkObj [("ok", St'.toJson)]
    | .refused code => Json.mkObj [("refused", .str code)]

/-- One case `{"expression", "facts"}` → the verdict of `eval` (§ 3). -/
def evalCase (j : JVal) : Decode Json := do
  let e ← match Expr.ofJVal (← field j "expression") with
    | some e => pure e
    | none => throw "expression outside B.4"
  let facts ← (← asObj (← field j "facts")).mapM fun (name, entry) => do
    pure (name, ← field entry "value")
  let verdict := match eval (fun n => facts.lookup n) e with
    | .true => "true"
    | .false => "false"
    | .unknown => "unknown"
  pure (Json.mkObj [("verdict", .str verdict)])

/-- One case `{"registry", "snapshot"?}` → whether each lies in the domain
the input checks guarantee (`Registry.compiledOk`, `Snapshot.validated`). -/
def domainCase (j : JVal) : Decode Json := do
  let Γ ← decodeRegistry (← field j "registry")
  let snapshot ← match j.get? "snapshot" with
    | some s => do pure (some (Snapshot.validated Γ (← decodeSnapshot s)))
    | none => pure none
  pure (Json.mkObj [("registry", .bool Γ.compiledOk),
    ("snapshot", match snapshot with | some b => .bool b | none => .null)])

end KomkiSpec
