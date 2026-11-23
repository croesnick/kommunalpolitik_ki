import KomkiKalkuel.Calculus
import KomkiKalkuel.Evaluator

/-!
# PROTOTYPE (throwaway): an executable `admit`, proven against the spec

Question: does an executable checker connect to the Prop-level spec? This
file mirrors `KomkiPolicy.Calculus.allowed_recipients/2` and a simplified
`admit` branch (CONTRACT.md § 4.3, without `not_quarantine` and
`workspace_contract_valid`), then proves: `admit = permit` implies the
Aufnahme rule of R.5.4. A miniature A.7 for one rule branch.
-/

namespace KomkiKalkuel

/-- Executable registry slice. `admitRule b` is `bindings[b].operations["admit"]`. -/
structure Registry (B O : Type) where
  observers : List O
  readers : B → List O
  admitRule : B → Option Expr

variable {B O : Type} [DecidableEq B] [DecidableEq O]

def Registry.toRules (Γ : Registry B O) : Rules B O where
  observers o := o ∈ Γ.observers
  readers b o := o ∈ Γ.readers b

/-- The invariant `registry.ex` enforces at compile time (`subset_observers`
on `readers`): every binding's readers lie in 𝒪. -/
def Registry.WellFormed (Γ : Registry B O) : Prop :=
  ∀ b o, o ∈ Γ.readers b → o ∈ Γ.observers

/-- Mirrors `allowed_recipients/2`: the empty label yields 𝒪, otherwise the
readers of all bindings are intersected. -/
def allowedRecipients (Γ : Registry B O) : List B → List O
  | [] => Γ.observers
  | b :: bs =>
    bs.foldl (fun acc b' => acc.filter fun o => decide (o ∈ Γ.readers b')) (Γ.readers b)

omit [DecidableEq B] in
theorem mem_foldl_filter (Γ : Registry B O) (bs : List B) (acc : List O) (o : O) :
    o ∈ bs.foldl (fun acc b' => acc.filter fun o => decide (o ∈ Γ.readers b')) acc ↔
      o ∈ acc ∧ ∀ b ∈ bs, o ∈ Γ.readers b := by
  induction bs generalizing acc with
  | nil => simp
  | cons b bs ih => simp [ih, List.mem_filter, and_assoc]

omit [DecidableEq B] in
/-- The Elixir computation is R_Γ(L), but only on a well-formed registry. -/
theorem mem_allowedRecipients (Γ : Registry B O) (wf : Γ.WellFormed) (L : List B) (o : O) :
    o ∈ allowedRecipients Γ L ↔ recipients Γ.toRules (· ∈ L) o := by
  cases L with
  | nil => simp [allowedRecipients, recipients, Registry.toRules]
  | cons b bs =>
    simp only [allowedRecipients, mem_foldl_filter, recipients, Registry.toRules]
    constructor
    · rintro ⟨hb, hbs⟩
      refine ⟨wf b o hb, fun b' hb' => ?_⟩
      rcases List.mem_cons.1 hb' with rfl | hb'
      · exact hb
      · exact hbs b' hb'
    · rintro ⟨_, h⟩
      exact ⟨h b (List.mem_cons.2 (Or.inl rfl)),
        fun b' hb' => h b' (List.mem_cons.2 (Or.inr hb'))⟩

inductive Decision where
  | permit
  | deny
  | indeterminate
  deriving DecidableEq, Repr

/-- CONTRACT.md § 4.4: known-false beats unknown, permit only if all premises hold. -/
def Decision.ofVerdict : Verdict → Decision
  | .true => .permit
  | .false => .deny
  | .unknown => .indeterminate

/-- An admit request, flattened from snapshot and intent. -/
structure AdmitInput (B O : Type) where
  workspaceBindings : List B
  objectLabels : List B
  environmentObservers : List O
  facts : Facts

/-- Base facts of CONTRACT.md § 4.2 (simplified: `false` always forbids). -/
def baseFacts : List String :=
  ["has_operation_right", "has_object_access_right", "audit_path_ready",
   "environment_observers_complete"]

def boolFact (facts : Facts) (name : String) : Verdict :=
  onFact facts name fun v => ofBool (decide (v = .bool true))

/-- `binding_condition(b)`: a binding without an admit rule forbids. -/
def conditionVerdict (Γ : Registry B O) (facts : Facts) (b : B) : Verdict :=
  match Γ.admitRule b with
  | none => .false
  | some e => eval facts e

/-- The premises of § 4.3 in order; the validation label is B_W, never λ(x). -/
def admitPremises (Γ : Registry B O) (i : AdmitInput B O) : List Verdict :=
  baseFacts.map (boolFact i.facts) ++
  [ofBool (i.objectLabels.all fun b => decide (b ∈ i.workspaceBindings)),
   ofBool (i.environmentObservers.all fun o =>
     decide (o ∈ allowedRecipients Γ i.workspaceBindings))] ++
  i.workspaceBindings.map (conditionVerdict Γ i.facts)

def admit (Γ : Registry B O) (i : AdmitInput B O) : Decision :=
  .ofVerdict (allVerdict (admitPremises Γ i))

/-- The Verarbeitungssituation Aufnahme(x, W) as the spec sees it. -/
def admitSituation (Γ : Registry B O) (i : AdmitInput B O) : Situation B O where
  base := ∀ n ∈ baseFacts, i.facts n = some (.bool true)
  observers o := o ∈ i.environmentObservers
  condition b := conditionVerdict Γ i.facts b = .true

theorem ofBool_eq_true {b : Bool} : ofBool b = .true ↔ b = true := by
  cases b <;> simp [ofBool]

theorem allVerdict_eq_true (vs : List Verdict) :
    allVerdict vs = .true ↔ ∀ v ∈ vs, v = .true := by
  unfold allVerdict
  by_cases hnil : vs = []
  · subst hnil; simp
  rw [ite_eq_right hnil]
  by_cases hf : Verdict.false ∈ vs
  · rw [ite_eq_left hf]
    exact ⟨fun h => (nomatch h), fun h => (nomatch h _ hf)⟩
  rw [ite_eq_right hf]
  by_cases hu : Verdict.unknown ∈ vs
  · rw [ite_eq_left hu]
    exact ⟨fun h => (nomatch h), fun h => (nomatch h _ hu)⟩
  rw [ite_eq_right hu]
  refine ⟨fun _ v hv => ?_, fun _ => rfl⟩
  cases v with
  | true => rfl
  | false => exact absurd hv hf
  | unknown => exact absurd hv hu

theorem boolFact_true {f : Facts} {n : String} (h : boolFact f n = .true) :
    f n = some (.bool true) := by
  unfold boolFact onFact at h
  cases hf : f n with
  | none => simp [hf] at h
  | some v => simp [hf, ofBool_eq_true] at h; rw [h]

/-- Miniature A.7 for `admit`: a permit implies the Aufnahme rule of R.5.4,
λ(x) ⊆ B_W ∧ Erlaubt_Γ(Aufnahme(x, W), B_W). -/
theorem admit_sound (Γ : Registry B O) (wf : Γ.WellFormed) (i : AdmitInput B O)
    (h : admit Γ i = .permit) :
    Sub (· ∈ i.objectLabels) (· ∈ i.workspaceBindings) ∧
    Permitted Γ.toRules (admitSituation Γ i) (· ∈ i.workspaceBindings) := by
  have hall : ∀ v ∈ admitPremises Γ i, v = .true := by
    rw [← allVerdict_eq_true]
    unfold admit at h
    revert h
    cases allVerdict (admitPremises Γ i) <;> simp [Decision.ofVerdict]
  have hLabels := hall _ (List.mem_append.2 (Or.inl (List.mem_append.2
    (Or.inr (List.mem_cons.2 (Or.inl rfl))))))
  have hRec := hall _ (List.mem_append.2 (Or.inl (List.mem_append.2
    (Or.inr (List.mem_cons.2 (Or.inr (List.mem_cons.2 (Or.inl rfl))))))))
  refine ⟨fun b hb => ?_, fun n hn => ?_, fun o ho => ?_, fun b hb => ?_⟩
  · exact of_decide_eq_true (List.all_eq_true.1 (ofBool_eq_true.1 hLabels) b hb)
  · exact boolFact_true (hall _ (List.mem_append.2 (Or.inl (List.mem_append.2
      (Or.inl (List.mem_map.2 ⟨n, hn, rfl⟩))))))
  · exact (mem_allowedRecipients Γ wf _ o).1
      (of_decide_eq_true (List.all_eq_true.1 (ofBool_eq_true.1 hRec) o ho))
  · exact hall _ (List.mem_append.2 (Or.inr (List.mem_map.2 ⟨b, hb, rfl⟩)))

end KomkiKalkuel
