import KomkiSpec.ProofInputSound
import KomkiSpec.RegistryInputSound
import KomkiSpec.CallHashSound
import KomkiSpec.ReleaseInput

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
`advanceCase_decides` covers `advance`. The order of the checks and the
error a rejected case reports stay with the differential test.
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

end KomkiSpec
