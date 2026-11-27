import KomkiSpec.Soundness

/-!
# A.3 along a path of rooms, at the engine

`Calculus.lean` proves preservation for label effects (`preservation`);
`handover_within_admitted` ties one hop to verified trees. Here every hop of
a path is verified trees: x is admitted into a room, and an output leaves
the same room, by `emit` or by `store` or `transfer`. What links the hops is
the mediator's duty, stated as the hypotheses of a hop: the admitting
snapshot names λ(x), B_W stays fixed in the room (RFC 4.1), and an emitted
object carries the label its tree assigns (R.5.5).

Only the normal branch with a proof tree is covered. A release decides
without a tree and still bridges `recipient_not_allowed` for `emit` and
`transfer` (CONTRACT.md § 4.6, #354); control paths through the start of a
room (R.5.3) have no rule in `proofRules`. `handover_within_admitted` is
the one-room case of `enginePath_handover`.
-/

namespace KomkiSpec

/-- The label an output leaves its room with: the `assigned_label` of an
`emit` tree, the object's labels for `store` and `transfer`. The mediator
writes λ(y) from the decision's `assigned_label`, which on a permit is the
checked label B_W; `emit_assignment` shows every `label_assignment` premise
of a valid tree assigns that same set. -/
def ExitLabel (S : Snapshot) (P : Proof) (ly : List String) : Prop :=
  if P.rule = "emit" then
    ∃ p ∈ P.premises, p.name = "label_assignment" ∧ ∃ xs,
      p.get? "assigned_label" = some (.arr xs) ∧ strings? xs = some ly
  else S.objectLabels = ly

/-- x (labels `lx`) admitted into a room with bindings `bw` by a verified tree. -/
def Admits (Γ : Registry) (bw lx : List String) : Prop :=
  ∃ S I P, verify Γ S I P = .valid ∧ P.rule = "admit" ∧ S.objectLabels = lx ∧
    S.workspaceBindings = bw

/-- An output (labels `ly`) leaving a room with bindings `bw` by a verified tree. -/
def Exits (Γ : Registry) (bw ly : List String) : Prop :=
  ∃ S I P, verify Γ S I P = .valid ∧
    (P.rule = "emit" ∨ handoverOperations.contains P.rule = true) ∧
    S.workspaceBindings = bw ∧ ExitLabel S P ly

/-- One hop: in through `admit`, out of the same room. -/
inductive Hop (Γ : Registry) (lx ly : List String) : Prop
  | mk (bw : List String) : Admits Γ bw lx → Exits Γ bw ly → Hop Γ lx ly

/-- A path of hops through rooms; no Lockerung step exists. -/
inductive EnginePath (Γ : Registry) : List String → List String → Prop
  | refl {l : List String} : EnginePath Γ l l
  | hop {lx ly lz : List String} : Hop Γ lx ly → EnginePath Γ ly lz → EnginePath Γ lx lz

/-- Every `label_assignment` premise of a valid `emit` tree assigns B_W, not
only the one `verify_emit_assigns` names: each premise fits its slot, so its
kind is `computed`, and each premise holds. -/
theorem emit_assignment {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof}
    (h : verify Γ S I P = .valid) (he : P.rule = "emit") {p : Premise} (hp : p ∈ P.premises)
    (hn : p.name = "label_assignment") :
    ∃ xs ls, p.get? "assigned_label" = some (.arr xs) ∧ strings? xs = some ls ∧
      ∀ l, l ∈ ls ↔ l ∈ S.workspaceBindings := by
  obtain ⟨_, _, _, hreq, hall, _⟩ := verify_valid h
  simp only [requiredSetOk, Bool.and_eq_true, List.all_eq_true] at hreq
  have hf := hreq.2 p hp
  have hk : p.kind = "computed" := by
    simp only [fitsSlot, Bool.and_eq_true, beq_iff_eq] at hf
    rw [hn] at hf
    exact (Option.some.inj hf.1.1.2).symm
  have hla : labelAssignmentOk S p = true := by
    simpa [premiseOk, hk, hn, he] using List.all_eq_true.1 hall p hp
  unfold labelAssignmentOk at hla
  simp only [Bool.and_eq_true] at hla
  have hassign := hla.1.1
  split at hassign
  · next xs hxs =>
    split at hassign
    · next ls hls =>
      refine ⟨xs, ls, hxs, hls, fun l => ?_⟩
      rw [beq_iff_eq] at hassign
      rw [← hassign, sortDedup, List.mem_eraseDups, mem_sortStrings]
    · cases hassign
  · cases hassign

/-- B_W ⊆ the label an output leaves its room with. -/
theorem exit_label {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof} {ly : List String}
    (wf : Γ.WellFormed) (h : verify Γ S I P = .valid)
    (hr : P.rule = "emit" ∨ handoverOperations.contains P.rule = true)
    (hl : ExitLabel S P ly) : ∀ l ∈ S.workspaceBindings, l ∈ ly := by
  unfold ExitLabel at hl
  by_cases he : P.rule = "emit"
  · simp only [he, ite_true] at hl
    obtain ⟨p, hp, hn, xs, hxs, hls⟩ := hl
    obtain ⟨xs', ls, hxs', hls', hiff⟩ := emit_assignment h he hp hn
    rw [hxs] at hxs'
    cases hxs'
    rw [hls] at hls'
    cases hls'
    exact fun l hl => (hiff l).2 hl
  · simp only [he, ite_false] at hl
    have hho : handoverOperations.contains P.rule = true := hr.resolve_left he
    obtain ⟨_, hna, hne, _⟩ := handover_rules P.rule (List.contains_iff_mem.1 hho)
    have ⟨hduty, _⟩ := verify_sound_rfc wf h
    simp only [LabelDuty, hna, hne, ite_false] at hduty
    exact fun l hl' => hl ▸ hduty l hl'

/-- A.3 at the engine: along every path of verified hops, λ(x) ⊆ λ(y). -/
theorem enginePath_preservation {Γ : Registry} (wf : Γ.WellFormed) {lx ly : List String}
    (p : EnginePath Γ lx ly) : ∀ l ∈ lx, l ∈ ly := by
  induction p with
  | refl => exact fun _ h => h
  | hop h _ ih =>
    obtain ⟨bw, ⟨S, I, P, hv, hr, hx, hb⟩, ⟨S', I', P', hv', hr', hb', hl⟩⟩ := h
    have ⟨hduty, _⟩ := verify_sound_rfc wf hv
    simp only [LabelDuty, hr, ite_true] at hduty
    have hexit := exit_label wf hv' hr' hl
    exact fun l hl' => ih l (hexit l (hb' ▸ hb ▸ hduty l (hx ▸ hl')))

/-- A.3, corollary at the engine: a verified `store` or `transfer` of an
object at the end of a path reaches only observers in R_Γ(λ(x)). -/
theorem enginePath_handover {Γ : Registry} (wf : Γ.WellFormed) {lx ly : List String}
    (p : EnginePath Γ lx ly) {S : Snapshot} {I : Intent} {P : Proof}
    (h : verify Γ S I P = .valid) (hr : handoverOperations.contains P.rule = true)
    (hy : S.objectLabels = ly) {env : List String} (henv : Γ.environment? S.environment = some env)
    {o : String} (ho : o ∈ env) : recipients Γ.rules (· ∈ lx) o := by
  have ⟨_, _, hrec, _⟩ := verify_sound_rfc wf h
  simp only [checkedLabel, hr, ite_true] at hrec
  exact recipients_antitone Γ.rules (fun l hl => hy ▸ enginePath_preservation wf p l hl) o
    (hrec o ⟨env, henv, ho⟩)

/-- Hence no verified `store` or `transfer` of anything that depends on x
reaches an observer outside R_Γ(λ(x)) without a Lockerung. -/
theorem enginePath_no_forbidden {Γ : Registry} (wf : Γ.WellFormed) {lx ly : List String}
    (p : EnginePath Γ lx ly) {S : Snapshot} {I : Intent} {P : Proof}
    (hr : handoverOperations.contains P.rule = true) (hy : S.objectLabels = ly)
    {env : List String} (henv : Γ.environment? S.environment = some env) {o : String}
    (ho : o ∈ env) (hno : ¬ recipients Γ.rules (· ∈ lx) o) : verify Γ S I P ≠ .valid :=
  fun h => hno (enginePath_handover wf p h hr hy henv ho)

end KomkiSpec
