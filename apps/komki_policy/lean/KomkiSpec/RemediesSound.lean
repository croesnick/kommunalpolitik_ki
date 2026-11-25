import KomkiSpec.Remedies
import KomkiSpec.CatalogSound

/-!
# The catalog's shape (CONTRACT.md § 2.8)

`catalog_ascending`: within every entry the transitions follow the
normative order, so no GO comes before a continuation that violates
nothing (no compensatory leakage). `derive_deny_remedied` and
`derive_indeterminate_remedied`: every blocker and every missing piece of
evidence `derive` reports gets at least one continuation, no bare `deny`
(APPA theorem 5); `release_remedied`: the same for a denial of a release
branch.
-/

namespace KomkiSpec

/-- Ranks never fall: no GO before a non-violating continuation. -/
def Ascending (ts : List Transition) : Prop := ts.Pairwise fun a b => a.rank ≤ b.rank

theorem rank_le_four (t : Transition) : t.rank ≤ 4 := by
  cases t with
  | go g => cases g <;> simp [Transition.rank]
  | _ => simp [Transition.rank]

theorem pairwise_of_all {α : Type} {R : α → α → Prop} {l : List α}
    (h : ∀ a ∈ l, ∀ b ∈ l, R a b) : l.Pairwise R := by
  induction l with
  | nil => exact List.Pairwise.nil
  | cons x xs ih =>
    refine List.Pairwise.cons (fun b hb => h x List.mem_cons_self b (List.mem_cons_of_mem _ hb)) ?_
    exact ih fun a ha b hb => h a (List.mem_cons_of_mem _ ha) b (List.mem_cons_of_mem _ hb)

theorem ordered_ascending (ts : List Transition) : Ascending (ordered ts) := by
  unfold ordered Ascending
  apply List.Pairwise.filter
  rw [List.flatMap, List.pairwise_flatten]
  refine ⟨fun l hl => ?_, ?_⟩
  · obtain ⟨r, _, rfl⟩ := List.mem_map.1 hl
    apply pairwise_of_all
    intro a ha b hb
    simp only [List.mem_filter, beq_iff_eq] at ha hb
    omega
  · rw [List.pairwise_map]
    have : [0, 1, 2, 3, 4].Pairwise (· < ·) := by decide
    refine this.imp fun {i j} hij => ?_
    intro a ha b hb
    simp only [List.mem_filter, beq_iff_eq] at ha hb
    omega

/-- Stripping GOs, appending the strongest one and filling up with
`neuer_raum` keep the order. -/
theorem planned_ascending {ts : List Transition} (h : Ascending ts) (p : Transition → Bool)
    (extra : List Transition) (hx : ∀ t ∈ extra, t.rank = 4) (n : Transition) :
    Ascending (if (ts.filter p ++ extra).isEmpty then [n] else ts.filter p ++ extra) := by
  split
  · exact List.Pairwise.cons (by simp) List.Pairwise.nil
  · apply List.pairwise_append.2
    refine ⟨h.filter _, pairwise_of_all fun a ha b hb => by rw [hx a ha, hx b hb]; exact Nat.le_refl 4, ?_⟩
    intro a _ b hb
    rw [hx b hb]
    exact rank_le_four a

/-- § 2.8: the normative order holds in every entry of the catalog. -/
theorem catalog_ascending (Γ : Registry) (c : CatalogCtx) (fs : List Finding) :
    ∀ e ∈ catalog Γ c fs, Ascending e := by
  intro e he
  unfold catalog at he
  dsimp only at he
  split at he
  · obtain ⟨⟨f, ts⟩, hm, rfl⟩ := List.mem_map.1 he
    obtain ⟨f', _, hf⟩ := List.mem_map.1 hm
    cases hf
    exact ordered_ascending _
  · obtain ⟨⟨f, ts⟩, hm, rfl⟩ := List.mem_map.1 he
    obtain ⟨f', _, hf⟩ := List.mem_map.1 hm
    cases hf
    refine planned_ascending (ordered_ascending _) _ _ ?_ _
    intro t ht
    split at ht <;> simp_all [Transition.rank]

/-! ## No bare `deny` (APPA theorem 5) -/

/-- The blocker codes the normal branch of `derive` can report (§ 2.4). -/
def derivedBlockerCodes : List String :=
  ["object_quarantine", "workspace_invalid", "basis_right_false", "audit_path_not_ready",
   "label_not_included", "label_not_preserved", "recipient_not_allowed",
   "missing_operation_rule", "binding_condition_false"]

/-- The evidence codes it can report. -/
def derivedEvidenceCodes : List String := ["missing_fact", "recipients_unproven"]

theorem premise_codes {Γ : Registry} {S : Snapshot} {rule : String} :
    ∀ f ∈ premiseFindings Γ S rule,
      (∀ b ∈ f.blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ f.evidence, e.code ∈ derivedEvidenceCodes) := by
  intro f hf
  unfold premiseFindings at hf
  dsimp only at hf
  have cond : ∀ x, (∀ b ∈ (conditionFindings Γ S rule x).blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ (conditionFindings Γ S rule x).evidence, e.code ∈ derivedEvidenceCodes) := by
    intro x
    unfold conditionFindings
    split
    · simp [blocking, derivedBlockerCodes]
    · split <;> simp [blocking, lacking, holds, derivedBlockerCodes, derivedEvidenceCodes]
  have basis : ∀ n, (∀ b ∈ (basisFindings S n).blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ (basisFindings S n).evidence, e.code ∈ derivedEvidenceCodes) := by
    intro n
    unfold basisFindings
    split
    · simp [holds]
    · split <;> simp [blocking, derivedBlockerCodes]
    · simp [lacking, derivedEvidenceCodes]
  have env : (∀ b ∈ (envFindings S).blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ (envFindings S).evidence, e.code ∈ derivedEvidenceCodes) := by
    unfold envFindings; split <;> simp [holds, lacking, derivedEvidenceCodes]
  have quar : (∀ b ∈ (quarantineFindings S).blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ (quarantineFindings S).evidence, e.code ∈ derivedEvidenceCodes) := by
    unfold quarantineFindings; split <;> simp [holds, blocking, derivedBlockerCodes]
  have ws : (∀ b ∈ (workspaceFindings S).blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ (workspaceFindings S).evidence, e.code ∈ derivedEvidenceCodes) := by
    unfold workspaceFindings; split <;> simp [holds, blocking, derivedBlockerCodes]
  have incl : ∀ L, (∀ b ∈ (labelInclusionFindings S L).blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ (labelInclusionFindings S L).evidence, e.code ∈ derivedEvidenceCodes) := by
    intro L; unfold labelInclusionFindings; split <;> simp [holds, blocking, derivedBlockerCodes]
  have pres : ∀ L, (∀ b ∈ (labelPreservationFindings S L).blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ (labelPreservationFindings S L).evidence, e.code ∈ derivedEvidenceCodes) := by
    intro L; unfold labelPreservationFindings; split <;> simp [holds, blocking, derivedBlockerCodes]
  have recp : ∀ rho L, (∀ b ∈ (recipientFindings Γ rho L).blockers, b.code ∈ derivedBlockerCodes) ∧
      (∀ e ∈ (recipientFindings Γ rho L).evidence, e.code ∈ derivedEvidenceCodes) := by
    intro rho L; unfold recipientFindings; dsimp only; split <;> simp [holds, blocking, derivedBlockerCodes]
  by_cases ha : (rule == "admit") = true
  · simp only [ha, ite_true, List.mem_append, List.mem_cons, List.not_mem_nil, or_false,
      List.mem_map] at hf
    rcases hf with (rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl) | ⟨x, _, rfl⟩
    · exact quar
    · exact ws
    · exact basis _
    · exact basis _
    · exact basis _
    · exact env
    · exact incl _
    · exact recp _ _
    · exact cond x
  simp only [ha, Bool.false_eq_true, ite_false] at hf
  by_cases he : (rule == "emit") = true
  · simp only [he, ite_true, List.mem_append, List.mem_cons, List.not_mem_nil, or_false,
      List.mem_map] at hf
    rcases hf with (rfl | rfl | rfl | rfl | rfl) | ⟨x, _, rfl⟩
    · exact ws
    · exact basis _
    · exact basis _
    · exact env
    · exact recp _ _
    · exact cond x
  simp only [he, Bool.false_eq_true, ite_false, List.mem_append, List.mem_cons,
    List.not_mem_nil, or_false, List.mem_map] at hf
  rcases hf with (rfl | rfl | rfl | rfl | rfl | rfl) | ⟨x, _, rfl⟩
  · exact ws
  · exact basis _
  · exact basis _
  · exact env
  · exact pres _
  · exact recp _ _
  · exact cond x

theorem mem_ordered {t : Transition} {ts : List Transition} (ht : t ∈ ts) (hr : t.rank ≠ 0) :
    t ∈ ordered ts := by
  unfold ordered
  rw [List.mem_filter]
  refine ⟨?_, ?_⟩
  · rw [List.mem_flatMap]
    refine ⟨t.rank, ?_, List.mem_filter.2 ⟨ht, by simp⟩⟩
    have := rank_le_four t
    simp only [List.mem_cons, List.not_mem_nil, or_false]
    omega
  · cases t with
    | fakt facts => simp [Transition.rank] at hr
    | _ => rfl

/-- Every code `derive` reports has a continuation `ordered` keeps:
`neuer_raum`, or for a quarantined object the Erstklassifikation. -/
theorem regular_keeps {Γ : Registry} {c : CatalogCtx} {f : Finding}
    (h : (f.evidence = false ∧ f.code ∈ derivedBlockerCodes) ∨
      (f.evidence = true ∧ f.code ∈ derivedEvidenceCodes)) :
    ∃ t ∈ regularTransitions Γ c f, t.rank ≠ 0 := by
  have hnr : (neuerRaum c).rank ≠ 0 := by simp [neuerRaum, Transition.rank]
  rcases h with ⟨hev, hc⟩ | ⟨hev, hc⟩
  · simp only [derivedBlockerCodes, List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with hc | hc | hc | hc | hc | hc | hc | hc | hc
    · exact ⟨.go (.object c.objectRef), by simp [regularTransitions, hc], by simp [Transition.rank]⟩
    all_goals exact ⟨neuerRaum c, by simp [regularTransitions, hc, hev, unbridgeableCodes], hnr⟩
  · simp only [derivedEvidenceCodes, List.mem_cons, List.not_mem_nil, or_false] at hc
    rcases hc with hc | hc
    all_goals exact ⟨neuerRaum c, by simp [regularTransitions, hc, hev, unbridgeableCodes], hnr⟩

theorem fill_nonempty {l : List Transition} {n : Transition} :
    (if l.isEmpty then [n] else l) ≠ [] := by
  split
  · simp
  · next h => intro hl; rw [hl] at h; exact h rfl

/-- No entry of the catalog is empty when its findings come from `derive`. -/
theorem catalog_nonempty {Γ : Registry} {c : CatalogCtx} {fs : List Finding}
    (hrel : c.rule ≠ "release")
    (hfs : ∀ f ∈ fs, (f.evidence = false ∧ f.code ∈ derivedBlockerCodes) ∨
      (f.evidence = true ∧ f.code ∈ derivedEvidenceCodes)) :
    ∀ e ∈ catalog Γ c fs, e ≠ [] := by
  intro e he
  have hr : (c.rule == "release") = false := by simpa using hrel
  unfold catalog at he
  dsimp only at he
  split at he
  · obtain ⟨p, hm, rfl⟩ := List.mem_map.1 he
    obtain ⟨f', hf', rfl⟩ := List.mem_map.1 hm
    dsimp only
    simp only [hr, Bool.false_eq_true, ite_false]
    obtain ⟨t, ht, hrank⟩ := regular_keeps (Γ := Γ) (c := c) (hfs f' hf')
    exact List.ne_nil_of_mem (mem_ordered ht hrank)
  · obtain ⟨p, hm, rfl⟩ := List.mem_map.1 he
    obtain ⟨f', _, rfl⟩ := List.mem_map.1 hm
    exact fill_nonempty

theorem decideRule_indeterminate {Γ : Registry} {S : Snapshot} {I : Intent}
    {es : List Evidence} (h : decideRule Γ S I = .indeterminate es) :
    es = evidenceOf (premiseFindings Γ S I.operation) := by
  unfold decideRule at h
  dsimp only at h
  split at h
  · cases h
  · split at h
    · cases h; rfl
    · cases h

theorem rule_not_release {r : String} (h : proofRules.contains r = true) : r ≠ "release" := by
  rcases rule_cases h with rfl | rfl | rfl | rfl <;> decide

/-- No bare `deny` (§ 2.8, APPA theorem 5): every blocker gets a continuation. -/
theorem derive_deny_remedied {Γ : Registry} {S : Snapshot} {I : Intent} {bs : List Blocker}
    {c : String} (hd : derive Γ S I = .decision (.deny bs)) :
    ∀ e ∈ catalog Γ (normalCatalogCtx Γ S I.operation c) (bs.map Blocker.finding), e ≠ [] := by
  obtain ⟨hr, _, _, hdr⟩ := derive_decision hd
  have hbs := decideRule_deny hdr
  apply catalog_nonempty (by simpa [normalCatalogCtx] using rule_not_release hr)
  intro f hf
  obtain ⟨b, hb, rfl⟩ := List.mem_map.1 hf
  rw [hbs] at hb
  simp only [blockersOf, List.mem_flatten, List.mem_map] at hb
  obtain ⟨_, ⟨g, hg, rfl⟩, hb⟩ := hb
  exact Or.inl ⟨rfl, (premise_codes g hg).1 b hb⟩

/-- No bare `indeterminate`: every missing piece of evidence gets a continuation. -/
theorem derive_indeterminate_remedied {Γ : Registry} {S : Snapshot} {I : Intent}
    {es : List Evidence} {c : String} (hd : derive Γ S I = .decision (.indeterminate es)) :
    ∀ e ∈ catalog Γ (normalCatalogCtx Γ S I.operation c) (es.map Evidence.finding), e ≠ [] := by
  obtain ⟨hr, _, _, hdr⟩ := derive_decision hd
  have hes := decideRule_indeterminate hdr
  apply catalog_nonempty (by simpa [normalCatalogCtx] using rule_not_release hr)
  intro f hf
  obtain ⟨e, he, rfl⟩ := List.mem_map.1 hf
  rw [hes] at he
  simp only [evidenceOf, List.mem_flatten, List.mem_map] at he
  obtain ⟨_, ⟨g, hg, rfl⟩, he⟩ := he
  exact Or.inr ⟨rfl, (premise_codes g hg).2 e he⟩

/-- No bare `deny` after a release either (§ 2.8): every blocker of a release
branch gets a continuation, a fresh GO or `neuer_raum`. -/
theorem release_remedied {Γ : Registry} {c : CatalogCtx} (hrel : c.rule = "release")
    (fs : List Finding) : ∀ e ∈ catalog Γ c fs, e ≠ [] := by
  intro e he
  have hr : (c.rule == "release") = true := by simpa using hrel
  unfold catalog at he
  dsimp only at he
  split at he
  · obtain ⟨p, hm, rfl⟩ := List.mem_map.1 he
    obtain ⟨f, _, rfl⟩ := List.mem_map.1 hm
    dsimp only
    have : ∃ t ∈ releaseTransitions c f, t.rank ≠ 0 := by
      unfold releaseTransitions
      split
      · split
        · exact ⟨_, List.mem_singleton_self _, by simp [Transition.rank]⟩
        · exact ⟨_, List.mem_singleton_self _, by simp [Transition.rank]⟩
      · split
        · exact ⟨_, List.mem_singleton_self _, by simp [Transition.rank]⟩
        · exact ⟨_, List.mem_singleton_self _, by simp [Transition.rank]⟩
    obtain ⟨t, ht, hrank⟩ := this
    exact List.ne_nil_of_mem (mem_ordered ht hrank)
  · obtain ⟨p, hm, rfl⟩ := List.mem_map.1 he
    obtain ⟨f, _, rfl⟩ := List.mem_map.1 hm
    exact fill_nonempty

end KomkiSpec
