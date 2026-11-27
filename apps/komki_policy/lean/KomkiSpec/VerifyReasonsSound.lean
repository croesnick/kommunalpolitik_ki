import KomkiSpec.VerifyReasons

/-!
# What a finding of `verify` names

`verifyReport_verdict` settles whether the report has findings. Here: what
each finding says is grounded in the case (`verifyReasons_grounded`). Its
code is one `verify.ex` reports (`reasonCodes`), a binding it names belongs
to the checked label or is a premise's `binding`, and a fact it names is a
premise's `fact`. A finding never points at a binding or a fact the case
does not contain. Which premise a finding names, and which check a code
belongs to, stay with the differential test.
-/

namespace KomkiSpec

/-- A finding grounded in the case: a code `verify.ex` reports, a binding of
the checked label or a premise's `binding`, a premise's `fact`. -/
def Reason.Grounded (S : Snapshot) (P : Proof) (r : Reason) : Prop :=
  r.code ∈ reasonCodes ∧
  (∀ b, r.binding = some b →
    b ∈ checkedLabel P.rule S ∨ ∃ p ∈ P.premises, p.strField? "binding" = some b) ∧
  (∀ f, r.fact = some f → ∃ p ∈ P.premises, p.strField? "fact" = some f)

/-- A finding about one premise names only that premise's binding and fact. -/
def Reason.Local (p : Premise) (r : Reason) : Prop :=
  r.code ∈ reasonCodes ∧ (r.binding = none ∨ r.binding = p.strField? "binding") ∧
    (r.fact = none ∨ r.fact = p.strField? "fact")

theorem mem_reasonIf {b : Bool} {r₀ r : Reason} (h : r ∈ reasonIf b r₀) : r = r₀ := by
  unfold reasonIf at h
  split at h <;> simp_all

theorem factReasons_local {S : Snapshot} {p : Premise} :
    ∀ r ∈ factReasons S p, r.Local p := by
  intro r hr
  unfold factReasons at hr
  cases hf : p.strField? "fact" with
  | none =>
    simp only [hf, List.mem_singleton] at hr
    subst hr
    simp [Reason.Local, reasonCodes]
  | some f =>
    simp only [hf] at hr
    have hclaim : ∀ v, r ∈ (match v with
        | JVal.bool b =>
          if (p.value != b) = true then [{ code := "fact_value_mismatch", fact := some f }]
          else reasonIf (!b) { code := "premise_not_true", fact := some f }
        | _ => [{ code := "fact_value_mismatch", fact := some f }] : List Reason) →
        r.Local p := by
      intro v hv
      split at hv
      · split at hv
        · simp only [List.mem_singleton] at hv; subst hv; simp [Reason.Local, reasonCodes, hf]
        · have := mem_reasonIf hv; subst this; simp [Reason.Local, reasonCodes, hf]
      · simp only [List.mem_singleton] at hv; subst hv; simp [Reason.Local, reasonCodes, hf]
    split at hr
    · exact hclaim (.bool S.workspaceValid) hr
    · split at hr
      · simp only [List.mem_singleton] at hr; subst hr; simp [Reason.Local, reasonCodes, hf]
      · exact hclaim _ hr

theorem conditionReasons_local {Γ : Registry} {S : Snapshot} {rule : String} {p : Premise} :
    ∀ r ∈ conditionReasons Γ S rule p, r.Local p := by
  intro r hr
  unfold conditionReasons at hr
  have hcl : ∀ code ∈ reasonCodes,
      ({ code, binding := p.strField? "binding" } : Reason).Local p := by
    intro code hc
    exact ⟨hc, Or.inr rfl, Or.inl rfl⟩
  simp only at hr
  split at hr
  · simp only [List.mem_cons] at hr
    rcases hr with rfl | hr
    · exact hcl _ (by simp [reasonCodes])
    · rw [mem_reasonIf hr]; exact hcl _ (by simp [reasonCodes])
  · simp only [List.mem_append] at hr
    rcases hr with (hr | hr) | hr
    · rw [mem_reasonIf hr]; exact hcl _ (by simp [reasonCodes])
    · split at hr
      · simp only [List.mem_singleton] at hr; subst hr; exact hcl _ (by simp [reasonCodes])
      · simp only [List.mem_append] at hr
        rcases hr with hr | hr
        · rw [mem_reasonIf hr]; exact hcl _ (by simp [reasonCodes])
        · split at hr
          · simp at hr
          · simp only [List.mem_singleton] at hr; subst hr; exact hcl _ (by simp [reasonCodes])
          · simp only [List.mem_singleton] at hr; subst hr; exact hcl _ (by simp [reasonCodes])
    · rw [mem_reasonIf hr]; exact hcl _ (by simp [reasonCodes])

theorem premiseReasons_local {Γ : Registry} {S : Snapshot} {rule : String} {p : Premise} :
    ∀ r ∈ premiseReasons Γ S rule p, r.Local p := by
  intro r hr
  have hfail : ∀ {ok : Bool} {code : String}, code ∈ reasonCodes → r ∈ failIf ok code →
      r.Local p := by
    intro ok code hc h
    simp only [failIf] at h
    rw [mem_reasonIf h]
    exact ⟨hc, Or.inl rfl, Or.inl rfl⟩
  unfold premiseReasons at hr
  split at hr
  · exact factReasons_local r hr
  split at hr
  · unfold quarantineReasons at hr
    split at hr
    · simp only [List.mem_singleton] at hr; subst hr; simp [Reason.Local, reasonCodes]
    · rw [mem_reasonIf hr]; simp [Reason.Local, reasonCodes]
  split at hr
  · exact conditionReasons_local r hr
  split at hr
  · split at hr
    · exact hfail (by simp [reasonCodes]) hr
    split at hr
    · exact hfail (by simp [reasonCodes]) hr
    split at hr
    · exact hfail (by simp [reasonCodes]) hr
    split at hr
    · exact hfail (by simp [reasonCodes]) hr
    · simp at hr
  · simp at hr

theorem local_grounded {S : Snapshot} {P : Proof} {p : Premise} (hp : p ∈ P.premises)
    {r : Reason} (h : r.Local p) : r.Grounded S P := by
  obtain ⟨hc, hb, hf⟩ := h
  refine ⟨hc, fun b hb' => ?_, fun f hf' => ?_⟩
  · rcases hb with hb | hb
    · simp [hb] at hb'
    · exact Or.inr ⟨p, hp, hb ▸ hb'⟩
  · rcases hf with hf | hf
    · simp [hf] at hf'
    · exact ⟨p, hp, hf ▸ hf'⟩

/-- Main theorem: every finding of `verify` is grounded in the case. Its
code is one `verify.ex` reports, a binding it names belongs to the checked
label or is a premise's `binding`, and a fact it names is a premise's
`fact`. -/
theorem verifyReasons_grounded {Γ : Registry} {S : Snapshot} {I : Intent} {P : Proof} :
    ∀ r ∈ verifyReasons Γ S I P, r.Grounded S P := by
  intro r hr
  have plain : ∀ code ∈ reasonCodes, ({ code } : Reason).Grounded S P := fun code hc =>
    ⟨hc, fun _ h => by simp at h, fun _ h => by simp at h⟩
  unfold verifyReasons at hr
  simp only at hr
  split at hr
  · unfold referenceReasons at hr
    simp only [List.mem_append] at hr
    rcases hr with ((hr | hr) | hr) | hr
    · rw [mem_reasonIf hr]; exact plain _ (by simp [reasonCodes])
    · rw [mem_reasonIf hr]; exact plain _ (by simp [reasonCodes])
    · rw [mem_reasonIf hr]; exact plain _ (by simp [reasonCodes])
    · split at hr
      · rw [mem_reasonIf hr]; exact plain _ (by simp [reasonCodes])
      · simp only [List.mem_singleton] at hr; subst hr; exact plain _ (by simp [reasonCodes])
  split at hr
  · simp only [labelReasons] at hr
    rw [mem_reasonIf hr]; exact plain _ (by simp [reasonCodes])
  split at hr
  · unfold requiredSetReasons at hr
    simp only [List.mem_append, List.mem_map, List.mem_filter] at hr
    rcases hr with (⟨_, _, rfl⟩ | ⟨b, ⟨hb, _⟩, rfl⟩) | ⟨p, ⟨hp, _⟩, rfl⟩
    · exact plain _ (by simp [reasonCodes])
    · exact ⟨by simp [reasonCodes], fun b' h => by cases h; exact Or.inl hb,
        fun _ h => by simp at h⟩
    · exact ⟨by simp [reasonCodes], fun b h => Or.inr ⟨p, hp, h⟩, fun _ h => by simp at h⟩
  simp only [List.mem_append] at hr
  rcases hr with hr | hr
  · simp only [predicateReasons, List.mem_flatMap, List.mem_filter] at hr
    obtain ⟨_, _, p, ⟨hp, _⟩, hr⟩ := hr
    exact local_grounded hp (premiseReasons_local r hr)
  · unfold conclusionReasons at hr
    simp only [List.mem_append] at hr
    rcases hr with hr | hr
    · rw [mem_reasonIf hr]; exact plain _ (by simp [reasonCodes])
    · rw [mem_reasonIf hr]; exact plain _ (by simp [reasonCodes])

end KomkiSpec
