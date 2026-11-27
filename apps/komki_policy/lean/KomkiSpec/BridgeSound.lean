import KomkiSpec.ProofInputSound
import KomkiSpec.RegistryInputSound
import KomkiSpec.CallHashSound
import KomkiSpec.ReleaseInput
import KomkiSpec.VerifyReasons
import KomkiSpec.JsonParseCanon

/-!
# The bridge decides every accepted case

The differential test compares Elixir with the bridge, the soundness
theorems speak about the model. `deriveCase_decides`, `releaseCase_decides`:
once `Registry.compile/1` and the context checks (for a release also
`Release.validate/1` and `Stand.validate/1`) accept a case, the bridge does
not throw; it answers with `derive` resp. `deriveWithRelease` on the decoded
input, and the call hash comes from a call that always encodes, so
`callHashOf` never falls back to `""`. `deriveCase_unsupported` covers an
unsupported operation, which Elixir answers before it checks the snapshot;
`advanceCase_decides` covers `advance`, `verifyCase_decides` the report of
`verify`, whose verdict is then `verify`'s (`verifyCase_verdict`), and
`verifyCase_outputError` the output rule's input error, which Elixir reports
before it checks the proof tree. `decodeRegistry_transformations_sorted`:
the bridge keeps the transformations sorted by id, the order the remedy
catalog lists them in. `cliCase_verify`, `cliCase_decide`,
`cliCase_decide_release`, `cliCase_advance`: on accepted files the CLI's
exit code follows `cli.ex` (§ 7). The order of the checks and the error a rejected
case reports stay with the differential test.
-/

namespace KomkiSpec

theorem intentError_decodes {j : JVal} (h : intentError j = none) :
    ∃ I, decodeIntent j = .ok I := by
  unfold intentError at h
  split at h
  · next kvs =>
    simp only at h
    split at h
    · split at h
      · cases h
      · split at h
        · cases h
        split at h
        · cases h
        split at h
        · cases h
        split at h
        · cases h
        next _ _ hid _ _ hop =>
          obtain ⟨id, hid⟩ := kebabJ_some (by simpa using hid)
          obtain ⟨op, hop, _⟩ := strIn_some (by simpa using hop)
          exact ⟨_, by simp [decodeIntent, strAt_ok hid, strAt_ok hop]; rfl⟩
    · cases h
  · cases h

theorem lookup_mem_keys {β : Type} {l : List (String × β)} {x : String} {v : β}
    (h : l.lookup x = some v) : x ∈ l.map (·.1) := by
  induction l with
  | nil => simp [List.lookup] at h
  | cons p l ih =>
    obtain ⟨k, w⟩ := p
    by_cases hk : x = k
    · simp [hk]
    · have : (x == k) = false := by simpa using hk
      simp only [List.lookup, this] at h
      exact List.mem_cons_of_mem _ (ih h)

/-- A closed record carries no key outside `allowed`. -/
theorem firstUnknown_none {kvs : List (String × JVal)} {allowed : List String} {k : String}
    {v : JVal} (h : firstUnknown kvs allowed = none) (hk : kvs.lookup k = some v) :
    allowed.contains k = true := by
  apply Classical.byContradiction
  intro hc
  have hm : k ∈ sortStrings ((kvs.map (·.1)).filter fun k => !allowed.contains k) :=
    mem_sortStrings.2 (List.mem_filter.2 ⟨lookup_mem_keys hk, by simpa using hc⟩)
  simp only [firstUnknown, List.head?_eq_none_iff] at h
  rw [h] at hm
  simp at hm

theorem kebabError_str {j : JVal} {k : String} (h : kebabError j k = none) :
    ∃ s, j.get? k = some (.str s) := by
  unfold kebabError at h
  split at h
  · next hk => exact kebabJ_some hk
  · cases h

theorem natJ_int {o : Option JVal} (h : natJ o = true) : ∃ i, o = some (.int i) ∧ 0 ≤ i := by
  match o, h with
  | some (.int i), h => exact ⟨i, rfl, by simpa [natJ] using h⟩

theorem intJ_int {o : Option JVal} (h : intJ o = true) : ∃ i, o = some (.int i) := by
  match o, h with
  | some (.int i), _ => exact ⟨i, rfl⟩

theorem hex64_str {o : Option JVal} (h : hex64 o = true) : ∃ s, o = some (.str s) := by
  match o, h with
  | some (.str s), _ => exact ⟨s, rfl⟩

theorem ziellabelOk_strs {o : Option JVal} (h : ziellabelOk o = true) :
    ∃ xs ss, o = some (.arr xs) ∧ strings? xs = some ss := by
  match o, h with
  | some (.arr xs), h =>
    cases hss : strings? xs with
    | some ss => exact ⟨xs, ss, rfl, hss⟩
    | none => simp [ziellabelOk, hss] at h

theorem asInt_ok {j : JVal} {k : String} {i : Int} (h : j.get? k = some (.int i)) :
    (do asInt (← field j k) : Decode Int) = .ok i := by
  simp [field_ok h, asInt]; rfl

/-- Every release `Release.validate/1` accepts decodes into the model. -/
theorem releaseError_decodes {j : JVal} (h : releaseError j = none) :
    ∃ R, decodeRelease j = .ok R := by
  cases j with
  | obj kvs =>
    simp only [releaseError, Option.or_eq_none_iff] at h
    obtain ⟨_, hclosed, hid, hkind, _, _, _, _, hch, hscope, hauth, hwin, hnonce, hoff⟩ := h
    obtain ⟨id, hid⟩ := kebabError_str hid
    obtain ⟨kind, hkind, _⟩ := strIn_some (by simpa using hkind)
    obtain ⟨ch, hch⟩ := hex64_str (by simpa using hch)
    obtain ⟨scope, hscope⟩ := kebabError_str hscope
    obtain ⟨auth, hauth⟩ := kebabError_str hauth
    obtain ⟨nonce, hnonce⟩ := kebabError_str hnonce
    unfold windowError at hwin
    split at hwin
    · cases hwin
    split at hwin
    · cases hwin
    next hf hu =>
    obtain ⟨a, ha, _⟩ := natJ_int (by simpa using hf)
    obtain ⟨b, hb, _⟩ := natJ_int (by simpa using hu)
    have hz : ∃ zs, (match (JVal.obj kvs).get? "ziellabel" with
        | some v => asStrs v
        | none => pure [] : Decode (List String)) = .ok zs := by
      cases hz : (JVal.obj kvs).get? "ziellabel" with
      | none => exact ⟨[], rfl⟩
      | some z =>
        by_cases ho : (JVal.obj kvs).get? "kind" = some (.str "offenlegungsfreigabe")
        · simp only [ho, ite_true] at hoff
          unfold offenlegungError at hoff
          split at hoff
          · cases hoff
          · cases hoff
          split at hoff
          · cases hoff
          rw [hz] at hoff
          split at hoff
          · cases hoff
          · cases hoff
          split at hoff
          · next hzl =>
            obtain ⟨xs, ss, hxs, hss⟩ := ziellabelOk_strs hzl
            cases hxs
            exact ⟨ss, asStrs_ok hss⟩
          · cases hoff
        · have hm := firstUnknown_none (by
            simpa [closedError, ho] using hclosed) (k := "ziellabel") hz
          simp [releaseFields] at hm
    obtain ⟨zs, hzs⟩ := hz
    obtain ⟨aa, haa⟩ : ∃ aa, optStrAt (.obj kvs) "ausgabeart" = .ok aa := by
      unfold optStrAt; split <;> exact ⟨_, rfl⟩
    cases hd : decodeRelease (.obj kvs) with
    | ok R => exact ⟨R, rfl⟩
    | error e =>
      simp only [decodeRelease, strAt_ok hid, strAt_ok hkind, strAt_ok hch, strAt_ok hscope,
        strAt_ok hauth, strAt_ok hnonce, field_ok ha, field_ok hb, asInt, haa,
        bind, Except.bind, pure, Except.pure] at hd
      cases hzl : (JVal.obj kvs).get? "ziellabel" with
      | none => simp [hzl] at hd
      | some z => simp only [hzl] at hd hzs; simp [hzs] at hd
  | _ => simp [releaseError] at h

/-- Every stand `Stand.validate/1` accepts decodes into the model. -/
theorem standError_decodes {j : JVal} (h : standError j = none) :
    ∃ St, decodeStand j = .ok St := by
  cases j with
  | obj kvs =>
    simp only [standError, Option.or_eq_none_iff] at h
    obtain ⟨_, _, hid, hver, hscope, hasof, hcons⟩ := h
    obtain ⟨id, hid⟩ := kebabError_str hid
    obtain ⟨scope, hscope⟩ := kebabError_str hscope
    obtain ⟨v, hv, hv0⟩ := natJ_int (by simpa using hver)
    obtain ⟨t, ht⟩ := intJ_int (by simpa using hasof)
    unfold consumedError at hcons
    split at hcons
    · next cs hcs =>
      split at hcons
      · next hall =>
        have hc : ∃ ps, (cs.mapM fun (n, r) => do pure (n, ← asStr r) :
            Decode (List (String × String))) = .ok ps := by
          clear hcs
          induction cs with
          | nil => exact ⟨[], rfl⟩
          | cons p cs ih =>
            obtain ⟨n, r⟩ := p
            simp only [List.all_cons, Bool.and_eq_true] at hall
            obtain ⟨s, hs⟩ := kebabJ_some hall.1.2
            cases hs
            obtain ⟨ps, hps⟩ := ih hall.2
            refine ⟨(n, s) :: ps, ?_⟩
            simp only [List.mapM_cons, bind, Except.bind, pure, Except.pure, asStr] at hps ⊢
            simp [hps]
        obtain ⟨ps, hps⟩ := hc
        simp only [bind, Except.bind, pure, Except.pure] at hps
        cases hd : decodeStand (.obj kvs) with
        | ok St => exact ⟨St, rfl⟩
        | error e =>
          simp only [decodeStand, field_ok hcs, asObj, hps, strAt_ok hid, strAt_ok hscope,
            field_ok hv, field_ok ht, asNat, asInt, bind, Except.bind, pure, Except.pure] at hd
          simp [show ¬ v < 0 by omega] at hd
      · cases hcons
    · cases hcons
  | _ => simp [standError] at h

theorem refJ_str {o : Option JVal} (h : refJ o = true) : ∃ s, o = some (.str s) := by
  match o, h with
  | some (.str s), _ => exact ⟨s, rfl⟩

/-- Every proposal `validate_proposal/1` accepts decodes into the model. -/
theorem proposalError_decodes {j : JVal} (h : proposalError j = none) :
    ∃ P, decodeProposal j = .ok P := by
  cases j with
  | obj kvs =>
    simp only [proposalError, Option.or_eq_none_iff] at h
    obtain ⟨_, hoff, _, hid, hnonce, href, hch, hver⟩ := h
    obtain ⟨id, hid⟩ := kebabError_str hid
    obtain ⟨nonce, hnonce⟩ := kebabError_str hnonce
    obtain ⟨sref, href⟩ := refJ_str (by simpa using href)
    obtain ⟨ch, hch⟩ := hex64_str (by simpa using hch)
    obtain ⟨v, hv, hv0⟩ := natJ_int (by simpa using hver)
    obtain ⟨aa, haa⟩ : ∃ aa, optStrAt (.obj kvs) "ausgabeart" = .ok aa := by
      unfold optStrAt; split <;> exact ⟨_, rfl⟩
    have hz : ∃ zs, (match (JVal.obj kvs).get? "ziellabel" with
        | some v => asStrs v
        | none => pure [] : Decode (List String)) = .ok zs := by
      cases hz : (JVal.obj kvs).get? "ziellabel" with
      | none => exact ⟨[], rfl⟩
      | some z =>
        have hhas : (kvs.lookup "ziellabel").isSome = true := by
          simp only [JVal.get?] at hz; simp [hz]
        simp only [hhas] at hoff
        split at hoff
        · cases hoff
        split at hoff
        · next ha => simp_all
        split at hoff
        · cases hoff
        split at hoff
        · cases hoff
        next hzl =>
        rw [hz] at hzl
        obtain ⟨xs, ss, hxs, hss⟩ := ziellabelOk_strs (by simpa using hzl)
        cases hxs
        exact ⟨ss, asStrs_ok hss⟩
    obtain ⟨zs, hzs⟩ := hz
    simp only [pure, Except.pure] at hzs
    cases hd : decodeProposal (.obj kvs) with
    | ok P => exact ⟨P, rfl⟩
    | error e =>
      simp only [decodeProposal, strAt_ok hid, strAt_ok hnonce, strAt_ok href, strAt_ok hch,
        field_ok hv, asNat, asInt, haa, bind, Except.bind, pure, Except.pure] at hd
      simp only [show ¬ v < 0 by omega, ite_false] at hd
      cases hzl : (JVal.obj kvs).get? "ziellabel" with
      | none => simp [hzl] at hd
      | some z => simp only [hzl] at hd hzs; simp [hzs] at hd
  | _ => simp [proposalError] at h

/-- On every case whose stand and proposal the input checks accept,
`advanceCase` answers with `advance` on the decoded input. -/
theorem advanceCase_decides {j st pr : JVal} (hst : j.get? "stand" = some st)
    (hpr : j.get? "proposal" = some pr) (hste : standError st = none)
    (hpe : proposalError pr = none) :
    ∃ St P, decodeStand st = .ok St ∧ decodeProposal pr = .ok P ∧
      advanceCase j = .ok (match advance St P with
        | .ok St' => Lean.Json.mkObj [("ok", St'.toJson)]
        | .refused code => Lean.Json.mkObj [("refused", .str code)]) := by
  obtain ⟨St, hSt⟩ := standError_decodes hste
  obtain ⟨P, hP⟩ := proposalError_decodes hpe
  refine ⟨St, P, hSt, hP, ?_⟩
  simp only [advanceCase, field_ok hst, field_ok hpr, hste, hpe, hSt, hP, bind, Except.bind,
    pure, Except.pure, Option.or]
  cases advance St P <;> rfl

/-- A registry `compile/1` accepts and a snapshot the context check accepts
decode into the validated domain, so `decodeWorld` does not throw. -/
theorem decodeWorld_ok {j r s : JVal} (hr : j.get? "registry" = some r)
    (hs : j.get? "snapshot" = some s) (hreg : registryError r = none) {Γ : Registry}
    (hΓ : decodeRegistry r = .ok Γ) (hse : snapshotError Γ s = none) :
    ∃ S, decodeSnapshot s = .ok S ∧ S.validated Γ = true ∧ decodeWorld j = .ok (Γ, S) := by
  obtain ⟨Γ', hΓ', hok⟩ := registryError_compiledOk hreg
  rw [hΓ] at hΓ'
  cases hΓ'
  obtain ⟨S, hS, hval⟩ := snapshotError_validated hse
  have hwΓ : Γ.wellFormed = true := by
    simp only [Registry.compiledOk, Bool.and_eq_true] at hok
    exact hok.1.1.1.1
  have hwS : S.wellFormed = true := by
    simp only [Snapshot.validated, Bool.and_eq_true] at hval
    exact hval.1.1.1.1
  refine ⟨S, hS, hval, ?_⟩
  simp [decodeWorld, field_ok hr, field_ok hs, hΓ, hS, hwΓ, hwS, bind, Except.bind, pure,
    Except.pure]

/-- An unsupported operation: `decide_validated?/4` answers `unsupported`
after the intent check, before the snapshot is checked; so does the bridge.
`Γ` names the decoded registry. -/
theorem deriveCase_unsupported {j r i s : JVal} (hr : j.get? "registry" = some r)
    (hi : j.get? "intent" = some i) (hs : j.get? "snapshot" = some s) {Γ : Registry}
    (hΓ : decodeRegistry r = .ok Γ) (hie : intentError i = none) {I : Intent}
    (hI : decodeIntent i = .ok I) (hop : proofRules.contains I.operation = false) :
    deriveCase j = .ok (Lean.Json.mkObj [("unsupported", .bool true)]) := by
  have hn : I.operation ∉ proofRules := by simpa using hop
  simp [deriveCase, field_ok hr, field_ok hi, field_ok hs, hΓ, hI, hie, hn, bind,
    Except.bind, pure, Except.pure]

/-- On every case the input checks accept, `deriveCase` decides: it throws
nothing, and its answer is `derive` on the decoded input, which lies in the
validated domain, with the call hash of a call that encodes. `Γ` names the
decoded registry. -/
theorem deriveCase_decides {j r i s : JVal} (hr : j.get? "registry" = some r)
    (hi : j.get? "intent" = some i) (hs : j.get? "snapshot" = some s)
    (hreg : registryError r = none) {Γ : Registry} (hΓ : decodeRegistry r = .ok Γ)
    (hctx : contextError Γ i s = none) :
    ∃ S I, decodeSnapshot s = .ok S ∧ decodeIntent i = .ok I ∧ S.validated Γ = true ∧
      (callHashInput S I).isSome ∧
      deriveCase j = .ok (if proofRules.contains I.operation then
        (derive Γ S I).toJson Γ S I.operation (callHashOf S I)
      else Lean.Json.mkObj [("unsupported", .bool true)]) := by
  simp only [contextError, Option.or_eq_none_iff] at hctx
  obtain ⟨hie, hse, hce⟩ := hctx
  obtain ⟨S, hS, hval, hw⟩ := decodeWorld_ok hr hs hreg hΓ hse
  obtain ⟨I, hI⟩ := intentError_decodes hie
  refine ⟨S, I, hS, hI, hval, callHashInput_isSome hval I, ?_⟩
  simp only [deriveCase, field_ok hr, field_ok hi, field_ok hs, hΓ, hw, hI, hie, hse, hce,
    bind, Except.bind, pure, Except.pure, Option.or]
  cases proofRules.contains I.operation <;> simp

/-- On every case the input checks accept, `releaseCase` decides: it throws
nothing, and its answer is `deriveWithRelease` on the decoded input (which
may itself answer `unsupported` or an input error), with the call hash of a
call that encodes. `Γ` names the decoded registry. -/
theorem releaseCase_decides {j r i s rel st : JVal} (hr : j.get? "registry" = some r)
    (hi : j.get? "intent" = some i) (hs : j.get? "snapshot" = some s)
    (hrel : j.get? "release" = some rel) (hst : j.get? "stand" = some st)
    (hreg : registryError r = none) {Γ : Registry} (hΓ : decodeRegistry r = .ok Γ)
    (hctx : contextError Γ i s = none) (hre : releaseError rel = none)
    (hste : standError st = none) :
    ∃ S I R St, decodeSnapshot s = .ok S ∧ decodeIntent i = .ok I ∧
      decodeRelease rel = .ok R ∧ decodeStand st = .ok St ∧ S.validated Γ = true ∧
      (callHashInput S I).isSome ∧
      releaseCase j = .ok (match deriveWithRelease Γ S I R St (callHashOf S I) with
        | .decision d => releaseDecisionJson Γ S I.operation R (callHashOf S I) d
        | .inputError code => inputErrorJson ⟨code, modelErrorPath code⟩
        | .unsupported => Lean.Json.mkObj [("unsupported", .bool true)]) := by
  have hctx' := hctx
  simp only [contextError, Option.or_eq_none_iff] at hctx'
  obtain ⟨hie, hse, _⟩ := hctx'
  obtain ⟨S, hS, hval, hw⟩ := decodeWorld_ok hr hs hreg hΓ hse
  obtain ⟨I, hI⟩ := intentError_decodes hie
  obtain ⟨R, hR⟩ := releaseError_decodes hre
  obtain ⟨St, hSt⟩ := standError_decodes hste
  refine ⟨S, I, R, St, hS, hI, hR, hSt, hval, callHashInput_isSome hval I, ?_⟩
  simp only [releaseCase, field_ok hr, field_ok hi, field_ok hs, field_ok hrel, field_ok hst,
    hΓ, hw, hI, hR, hSt, hctx, hre, hste, bind, Except.bind, pure, Except.pure, Option.or]
  cases deriveWithRelease Γ S I R St (callHashOf S I) <;> rfl

/-- On every case whose context and proof tree the input checks accept,
`verifyCase` answers with `verifyReport` on the decoded input; an output
rule's input error comes from `verifyReport` as well. `Γ` names the decoded
registry. With a missing output prerequisite the proof tree need not be
accepted (`verifyCase_outputError`). -/
theorem verifyCase_decides {j r i s pr : JVal} (hr : j.get? "registry" = some r)
    (hi : j.get? "intent" = some i) (hs : j.get? "snapshot" = some s)
    (hp : j.get? "proof" = some pr) (hreg : registryError r = none) {Γ : Registry}
    (hΓ : decodeRegistry r = .ok Γ) (hctx : contextError Γ i s = none)
    (hpe : proofError pr = none) :
    ∃ S I P, decodeSnapshot s = .ok S ∧ decodeIntent i = .ok I ∧ decodeProof pr = .ok P ∧
      S.validated Γ = true ∧ verifyCase j = .ok (verifyReport Γ S I P) := by
  have hctx' := hctx
  simp only [contextError, Option.or_eq_none_iff] at hctx'
  obtain ⟨hie, hse, _⟩ := hctx'
  obtain ⟨S, hS, hval, hw⟩ := decodeWorld_ok hr hs hreg hΓ hse
  obtain ⟨I, hI⟩ := intentError_decodes hie
  obtain ⟨P, hP, _⟩ := proofError_decodes hpe
  refine ⟨S, I, P, hS, hI, hP, hval, ?_⟩
  simp only [verifyCase, field_ok hr, field_ok hi, field_ok hs, field_ok hp, hΓ, hctx, hw, hI,
    hpe, hP, bind, Except.bind, pure, Except.pure]
  unfold verifyReport
  cases outputInputError? S I.operation <;> rfl

/-- The bridge's verdict on such a case is `verify`'s, so every theorem about
`verify` speaks about what the differential test compares. -/
theorem verifyCase_verdict {j r i s pr : JVal} (hr : j.get? "registry" = some r)
    (hi : j.get? "intent" = some i) (hs : j.get? "snapshot" = some s)
    (hp : j.get? "proof" = some pr) (hreg : registryError r = none) {Γ : Registry}
    (hΓ : decodeRegistry r = .ok Γ) (hctx : contextError Γ i s = none)
    (hpe : proofError pr = none) :
    ∃ S I P, decodeSnapshot s = .ok S ∧ decodeIntent i = .ok I ∧ decodeProof pr = .ok P ∧
      S.validated Γ = true ∧ (verifyCase j).map Report.verdict = .ok (verify Γ S I P) := by
  obtain ⟨S, I, P, hS, hI, hP, hval, h⟩ := verifyCase_decides hr hi hs hp hreg hΓ hctx hpe
  exact ⟨S, I, P, hS, hI, hP, hval, by rw [h, ← verifyReport_verdict]; rfl⟩

/-- A missing output prerequisite (§ 4.5): as `check/4`, the bridge reports
it before it checks the proof tree, whatever the tree. -/
theorem verifyCase_outputError {j r i s pr : JVal} (hr : j.get? "registry" = some r)
    (hi : j.get? "intent" = some i) (hs : j.get? "snapshot" = some s)
    (hp : j.get? "proof" = some pr) (hreg : registryError r = none) {Γ : Registry}
    (hΓ : decodeRegistry r = .ok Γ) (hctx : contextError Γ i s = none) {S : Snapshot}
    {I : Intent} (hS : decodeSnapshot s = .ok S) (hI : decodeIntent i = .ok I) {e : InputError}
    (he : outputInputError? S I.operation = some e) :
    verifyCase j = .ok (.error e) := by
  have hctx' := hctx
  simp only [contextError, Option.or_eq_none_iff] at hctx'
  obtain ⟨_, hse, _⟩ := hctx'
  obtain ⟨S', hS', _, hw⟩ := decodeWorld_ok hr hs hreg hΓ hse
  rw [hS] at hS'
  cases hS'
  simp only [verifyCase, field_ok hr, field_ok hi, field_ok hs, field_ok hp, hΓ, hctx, hw, hI,
    he, bind, Except.bind, pure, Except.pure]

/-- The bridge keeps a registry's transformations sorted by id; Elixir sorts
them in `Remedies.matching_transformations/2`. -/
theorem decodeRegistry_transformations_sorted {j : JVal} {Γ : Registry}
    (h : decodeRegistry j = .ok Γ) :
    (Γ.transformations.map (·.1)).Pairwise (fun a b => ¬ b < a) := by
  unfold decodeRegistry at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  repeat' (first | (cases h; done) | split at h)
  cases h
  exact Json.mergeSort_keys_sorted _

/-- On a decoded registry the catalog offers its matching transformations
sorted by id (`entry_transformations`: in the registry's order). -/
theorem matchingTransformations_sorted {j : JVal} {Γ : Registry}
    (h : decodeRegistry j = .ok Γ) (c : CatalogCtx) :
    ∃ ts : List (String × List String),
      matchingTransformations Γ c = ts.map (fun (id, out) => .transformation id out) ∧
      (ts.map (·.1)).Pairwise (fun a b => ¬ b < a) := by
  let keep := fun (t : String × List String × List String) =>
    t.2.1.all c.objectLabels.contains && t.2.2.all c.checked.contains
  refine ⟨(Γ.transformations.filter keep).map fun t => (t.1, t.2.2), ?_, ?_⟩
  · simp [matchingTransformations, keep, List.map_map, Function.comp_def]
  · rw [List.map_map]
    have hs := decodeRegistry_transformations_sorted h
    have hsub := ((List.filter_sublist (p := keep) (l := Γ.transformations)).map (·.1))
    exact (hs.sublist hsub).imp id |> fun hp => by simpa [Function.comp_def] using hp

/-- The exit code § 7 assigns to a verdict of `verify`. -/
def verifyExit : Outcome → Nat
  | .valid => 0
  | .invalid => 1
  | .inputError => 2

/-- `cliCase` with `verify` on files that parse and pass the input checks:
the exit code is 0 exactly on `valid`, 1 on `invalid`, 2 on an output
rule's input error, as `cli.ex` (§ 7 contradicts itself here, #648), and the
output is `verify`'s report. `cliCase` models neither usage errors nor
extra or missing files; the CLI rejects those with `usage`. -/
theorem cliCase_verify {j : JVal} {files : List (String × JVal)}
    (hc : j.get? "command" = some (.str "verify")) (hf : j.get? "files" = some (.obj files))
    {hr hs hi hp : String} {br bs bi bp : ByteArray} {r s i pr : JVal}
    (hfr : files.lookup "registry" = some (.str hr)) (hbr : hexBytes hr = .ok br)
    (hpr : KomkiSpec.Json.parse br = .ok r)
    (hfs : files.lookup "snapshot" = some (.str hs)) (hbs : hexBytes hs = .ok bs)
    (hps : KomkiSpec.Json.parse bs = .ok s)
    (hfi : files.lookup "intent" = some (.str hi)) (hbi : hexBytes hi = .ok bi)
    (hpi : KomkiSpec.Json.parse bi = .ok i)
    (hfp : files.lookup "proof" = some (.str hp)) (hbp : hexBytes hp = .ok bp)
    (hpp : KomkiSpec.Json.parse bp = .ok pr)
    (hreg : registryError r = none) {Γ : Registry} (hΓ : decodeRegistry r = .ok Γ)
    (hctx : contextError Γ i s = none) (hpe : proofError pr = none) :
    ∃ S I P, decodeSnapshot s = .ok S ∧ decodeIntent i = .ok I ∧ decodeProof pr = .ok P ∧
      cliCase j = .ok (cliResult (verifyExit (verify Γ S I P)) (verifyReport Γ S I P).toJson) := by
  let input := JVal.obj [("registry", r), ("snapshot", s), ("intent", i), ("proof", pr)]
  obtain ⟨S, I, P, hS, hI, hP, _, hv⟩ :=
    verifyCase_decides (j := input) rfl rfl rfl rfl hreg hΓ hctx hpe
  refine ⟨S, I, P, hS, hI, hP, ?_⟩
  simp [cliCase, strAt_ok hc, field_ok hf, asObj, cliFiles, hfr, hbr, hpr, hfs, hbs, hps, hfi,
    hbi, hpi, hfp, hbp, hpp, hreg, bind, Except.bind, pure, Except.pure]
  rw [show verifyCase (JVal.obj [("registry", r), ("snapshot", s), ("intent", i), ("proof", pr)])
    = _ from hv, ← verifyReport_verdict]
  cases hvd : Report.verdict (verifyReport Γ S I P) <;> simp [hvd, verifyExit]

/-- The exit code § 7 assigns to an answer of `derive`. -/
def derivedExit : Derived → Nat
  | .decision _ => 0
  | .inputError _ => 2
  | .unsupported => 3

/-- The keys `cliCase` inspects classify an answer as `derivedExit` does. -/
theorem derived_exit (Γ : Registry) (S : Snapshot) (rule c : String) (r : Derived) :
    (if ((r.toJson Γ S rule c).getObjVal? "input_error").toOption.isSome then 2
      else if ((r.toJson Γ S rule c).getObjVal? "unsupported").toOption.isSome then 3
      else 0) = derivedExit r := by
  cases r with
  | decision d =>
    simp only [Derived.toJson, decisionJson]
    by_cases ha : rule = "admit"
    · subst ha; cases d <;> rfl
    · by_cases he : rule = "emit"
      · subst he; cases d <;> rfl
      · cases d <;> simp [ha, he] <;> rfl
  | inputError code => rfl
  | unsupported => rfl

/-- The exit code § 7 assigns to an answer of `deriveWithRelease`. -/
def releaseExit : ReleaseDerived → Nat
  | .decision _ => 0
  | .inputError _ => 2
  | .unsupported => 3

/-- The keys `cliCase` inspects classify an answer as `releaseExit` does. -/
theorem release_exit (Γ : Registry) (S : Snapshot) (I : Intent) (R : Release) (c : String)
    (r : ReleaseDerived) :
    let out := match r with
      | .decision d => releaseDecisionJson Γ S I.operation R c d
      | .inputError code => inputErrorJson ⟨code, modelErrorPath code⟩
      | .unsupported => Lean.Json.mkObj [("unsupported", .bool true)]
    (if (out.getObjVal? "input_error").toOption.isSome then 2
      else if (out.getObjVal? "unsupported").toOption.isSome then 3
      else 0) = releaseExit r := by
  cases r with
  | decision d =>
    simp only [releaseDecisionJson]
    by_cases he : I.operation = "emit"
    · rw [he]; cases d <;> rfl
    · cases d <;> simp [he] <;> rfl
  | inputError code => rfl
  | unsupported => rfl

/-- `cliCase` with `decide` and no release on files that parse and pass the
input checks: exit 0 on a decision, 2 on the model's input error, 3 on
`unsupported` (§ 7), and the output is `deriveCase`'s. -/
theorem cliCase_decide {j : JVal} {files : List (String × JVal)}
    (hc : j.get? "command" = some (.str "decide")) (hf : j.get? "files" = some (.obj files))
    {hr hs hi : String} {br bs bi : ByteArray} {r s i : JVal}
    (hfr : files.lookup "registry" = some (.str hr)) (hbr : hexBytes hr = .ok br)
    (hpr : KomkiSpec.Json.parse br = .ok r)
    (hfs : files.lookup "snapshot" = some (.str hs)) (hbs : hexBytes hs = .ok bs)
    (hps : KomkiSpec.Json.parse bs = .ok s)
    (hfi : files.lookup "intent" = some (.str hi)) (hbi : hexBytes hi = .ok bi)
    (hpi : KomkiSpec.Json.parse bi = .ok i)
    (hfrel : files.lookup "release" = none) (hfst : files.lookup "stand" = none)
    (hreg : registryError r = none) {Γ : Registry} (hΓ : decodeRegistry r = .ok Γ)
    (hctx : contextError Γ i s = none) :
    ∃ S I, decodeSnapshot s = .ok S ∧ decodeIntent i = .ok I ∧
      cliCase j = .ok (if proofRules.contains I.operation then
        cliResult (derivedExit (derive Γ S I))
          ((derive Γ S I).toJson Γ S I.operation (callHashOf S I))
      else cliResult 3 (Lean.Json.mkObj [("unsupported", .bool true)])) := by
  obtain ⟨S, I, hS, hI, _, _, hv⟩ :=
    deriveCase_decides (j := JVal.obj [("registry", r), ("snapshot", s), ("intent", i)])
      rfl rfl rfl hreg hΓ hctx
  refine ⟨S, I, hS, hI, ?_⟩
  simp [cliCase, strAt_ok hc, field_ok hf, asObj, cliFiles, hfr, hbr, hpr, hfs, hbs, hps, hfi,
    hbi, hpi, hfrel, hfst, hreg, bind, Except.bind, pure, Except.pure]
  rw [show deriveCase (JVal.obj [("registry", r), ("snapshot", s), ("intent", i)]) = _ from hv]
  by_cases hop : proofRules.contains I.operation = true
  · have hm : I.operation ∈ proofRules := by simpa using hop
    simp only [hop, hm, ite_true]
    rw [derived_exit]
    rfl
  · have hm : I.operation ∉ proofRules := by simpa using hop
    simp only [hop, hm, ite_false, Bool.false_eq_true]
    rfl

/-- `cliCase` with `decide`, a release and a stand on files that parse and
pass the input checks: exit 0 on a decision, 2 on the model's input error,
3 on `unsupported` (§ 7), and the output is `releaseCase`'s. -/
theorem cliCase_decide_release {j : JVal} {files : List (String × JVal)}
    (hc : j.get? "command" = some (.str "decide")) (hf : j.get? "files" = some (.obj files))
    {hr hs hi hl ht : String} {br bs bi bl bt : ByteArray} {r s i rel st : JVal}
    (hfr : files.lookup "registry" = some (.str hr)) (hbr : hexBytes hr = .ok br)
    (hpr : KomkiSpec.Json.parse br = .ok r)
    (hfs : files.lookup "snapshot" = some (.str hs)) (hbs : hexBytes hs = .ok bs)
    (hps : KomkiSpec.Json.parse bs = .ok s)
    (hfi : files.lookup "intent" = some (.str hi)) (hbi : hexBytes hi = .ok bi)
    (hpi : KomkiSpec.Json.parse bi = .ok i)
    (hfl : files.lookup "release" = some (.str hl)) (hbl : hexBytes hl = .ok bl)
    (hpl : KomkiSpec.Json.parse bl = .ok rel)
    (hft : files.lookup "stand" = some (.str ht)) (hbt : hexBytes ht = .ok bt)
    (hpt : KomkiSpec.Json.parse bt = .ok st)
    (hreg : registryError r = none) {Γ : Registry} (hΓ : decodeRegistry r = .ok Γ)
    (hctx : contextError Γ i s = none) (hre : releaseError rel = none)
    (hste : standError st = none) :
    ∃ S I R St, decodeSnapshot s = .ok S ∧ decodeIntent i = .ok I ∧
      decodeRelease rel = .ok R ∧ decodeStand st = .ok St ∧
      cliCase j = .ok (cliResult (releaseExit (deriveWithRelease Γ S I R St (callHashOf S I)))
        (match deriveWithRelease Γ S I R St (callHashOf S I) with
          | .decision d => releaseDecisionJson Γ S I.operation R (callHashOf S I) d
          | .inputError code => inputErrorJson ⟨code, modelErrorPath code⟩
          | .unsupported => Lean.Json.mkObj [("unsupported", .bool true)])) := by
  obtain ⟨S, I, R, St, hS, hI, hR, hSt, _, _, hv⟩ :=
    releaseCase_decides (j := JVal.obj [("registry", r), ("snapshot", s), ("intent", i),
      ("release", rel), ("stand", st)]) rfl rfl rfl rfl rfl hreg hΓ hctx hre hste
  refine ⟨S, I, R, St, hS, hI, hR, hSt, ?_⟩
  simp [cliCase, strAt_ok hc, field_ok hf, asObj, cliFiles, hfr, hbr, hpr, hfs, hbs, hps, hfi,
    hbi, hpi, hfl, hbl, hpl, hft, hbt, hpt, hreg, bind, Except.bind, pure, Except.pure]
  rw [show releaseCase (JVal.obj [("registry", r), ("snapshot", s), ("intent", i),
    ("release", rel), ("stand", st)]) = _ from hv]
  rw [← release_exit Γ S I R (callHashOf S I)]
  rfl

/-- `cliCase` with `advance` on a stand and a proposal that parse and pass
the input checks: exit 0 with the new stand, or 1 with the refusal, as
`cli.ex` (§ 7 contradicts itself on `refused`, #648). -/
theorem cliCase_advance {j : JVal} {files : List (String × JVal)}
    (hc : j.get? "command" = some (.str "advance")) (hf : j.get? "files" = some (.obj files))
    {hst hpr : String} {bst bpr : ByteArray} {st pr : JVal}
    (hfs : files.lookup "stand" = some (.str hst)) (hbs : hexBytes hst = .ok bst)
    (hps : KomkiSpec.Json.parse bst = .ok st)
    (hfp : files.lookup "proposal" = some (.str hpr)) (hbp : hexBytes hpr = .ok bpr)
    (hpp : KomkiSpec.Json.parse bpr = .ok pr)
    (hste : standError st = none) (hpe : proposalError pr = none) :
    ∃ St P, decodeStand st = .ok St ∧ decodeProposal pr = .ok P ∧
      cliCase j = .ok (match advance St P with
        | .ok St' => cliResult 0 (Lean.Json.mkObj [("ok", St'.toJson)])
        | .refused code => cliResult 1 (Lean.Json.mkObj [("refused", .str code)])) := by
  obtain ⟨St, P, hSt, hP, hv⟩ :=
    advanceCase_decides (j := JVal.obj [("stand", st), ("proposal", pr)]) rfl rfl hste hpe
  refine ⟨St, P, hSt, hP, ?_⟩
  simp [cliCase, strAt_ok hc, field_ok hf, asObj, cliFiles, hfs, hbs, hps, hfp, hbp, hpp,
    bind, Except.bind, pure, Except.pure]
  rw [show advanceCase (JVal.obj [("stand", st), ("proposal", pr)]) = _ from hv]
  cases advance St P <;> rfl

end KomkiSpec
