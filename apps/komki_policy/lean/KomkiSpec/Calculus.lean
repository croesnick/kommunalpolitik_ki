/-!
# The RFC 0003 calculus (R.5.1, R.5.2, Anhang A)

R.5.1 (recipient sets), R.5.2 (Erlaubt), A.2 (monotonicity), the V_o lemma
of A.5 and the label core of A.3 (preservation along paths).

Sets are predicates `α → Prop`; `Sub` stands in for Mathlib's `⊆`.
-/

namespace KomkiSpec

/-- `s ⊆ t` for predicate sets. -/
def Sub {α : Type} (s t : α → Prop) : Prop := ∀ a, s a → t a

/-- The parts of a fixed Regelstand Γ that R.5.1 needs: the observer space 𝒪
and each binding's Empfängerkreis R_b. -/
structure Rules (B O : Type) where
  observers : O → Prop
  readers : B → O → Prop

/-- A Verarbeitungssituation c, reduced to what Erlaubt reads (R.5.2).
`condition` takes the binding and nothing else: R.5.2 forbids a predicate
that depends on which other bindings are checked, and here that rule is a
type signature. -/
structure Situation (B O : Type) where
  base : Prop
  observers : O → Prop
  condition : B → Prop

variable {B O : Type}

/-- R_Γ(L) = ⋂_{b ∈ L} R_b with R_Γ(∅) = 𝒪 (R.5.1). Intersecting with 𝒪
makes the empty case fall out of the general formula. -/
def recipients (Γ : Rules B O) (L : B → Prop) : O → Prop :=
  fun o => Γ.observers o ∧ ∀ b, L b → Γ.readers b o

/-- Erlaubt_Γ(c, L) = Basis ∧ ρ_Γ(c) ⊆ R_Γ(L) ∧ ⋀_{b ∈ L} P_b(c) (R.5.2). -/
def Permitted (Γ : Rules B O) (c : Situation B O) (L : B → Prop) : Prop :=
  c.base ∧ Sub c.observers (recipients Γ L) ∧ ∀ b, L b → c.condition b

/-- The RFC's case split agrees with the uniform formula, given R_b ⊆ 𝒪:
for a non-empty label, R_Γ(L) is the plain intersection of the R_b. -/
theorem recipients_nonempty (Γ : Rules B O)
    (wf : ∀ b o, Γ.readers b o → Γ.observers o)
    {L : B → Prop} {b₀ : B} (hb₀ : L b₀) (o : O) :
    recipients Γ L o ↔ ∀ b, L b → Γ.readers b o :=
  ⟨fun h => h.2, fun h => ⟨wf b₀ o (h b₀ hb₀), h⟩⟩

/-- A.2: more bindings, never more recipients. -/
theorem recipients_antitone (Γ : Rules B O) {L₁ L₂ : B → Prop} (h : Sub L₁ L₂) :
    Sub (recipients Γ L₂) (recipients Γ L₁) :=
  fun _ ⟨hO, hR⟩ => ⟨hO, fun b hb => hR b (h b hb)⟩

/-- A.2, second half: at fixed c, Erlaubt under L₂ implies Erlaubt under L₁ ⊆ L₂. -/
theorem permitted_antitone (Γ : Rules B O) (c : Situation B O) {L₁ L₂ : B → Prop}
    (h : Sub L₁ L₂) (hp : Permitted Γ c L₂) : Permitted Γ c L₁ :=
  let ⟨hBase, hRec, hCond⟩ := hp
  ⟨hBase, fun o ho => recipients_antitone Γ h o (hRec o ho), fun b hb => hCond b (h b hb)⟩

/-- V_o = {L | o ∈ R_Γ(L)} (A.5). -/
def Visible (Γ : Rules B O) (o : O) (L : B → Prop) : Prop := recipients Γ L o

/-- A.5: V_o is downward closed. -/
theorem visible_downward_closed (Γ : Rules B O) {o : O} {L₁ L₂ : B → Prop}
    (h : Sub L₁ L₂) (hv : Visible Γ o L₂) : Visible Γ o L₁ :=
  recipients_antitone Γ h o hv

/-- The label effect of one regular step on a modelled path (A.3).
`admitEmit`: Aufnahme of x into a room W (λ(x) ⊆ B_W, R.5.4), then an
output y of W (B_W ⊆ λ(y), R.5.5). `keep`: storage and plain transfer
remove no binding (R.5.6). There is deliberately no Lockerung step. -/
inductive Step : (B → Prop) → (B → Prop) → Prop
  | admitEmit {lx bw ly : B → Prop} : Sub lx bw → Sub bw ly → Step lx ly
  | keep {l : B → Prop} : Step l l

/-- A path of regular steps. -/
inductive Path : (B → Prop) → (B → Prop) → Prop
  | refl {l : B → Prop} : Path l l
  | cons {l₁ l₂ l₃ : B → Prop} : Step l₁ l₂ → Path l₂ l₃ → Path l₁ l₃

/-- A.3: without Lockerung, λ(x) ⊆ λ(y) along every path. -/
theorem preservation {lx ly : B → Prop} (p : Path lx ly) : Sub lx ly := by
  induction p with
  | refl => exact fun _ h => h
  | cons s _ ih =>
    cases s with
    | admitEmit h₁ h₂ => exact fun b hb => ih b (h₂ b (h₁ b hb))
    | keep => exact ih

/-- A.3, corollary: if o ∉ R_Γ(λ(x)), no event that depends on x reaches o
without a Lockerung. -/
theorem no_forbidden_recipient (Γ : Rules B O) (c : Situation B O)
    {lx ly : B → Prop} {o : O}
    (hno : ¬ recipients Γ lx o) (p : Path lx ly) (hobs : c.observers o) :
    ¬ Permitted Γ c ly :=
  fun ⟨_, hRec, _⟩ => hno (recipients_antitone Γ (preservation p) o (hRec o hobs))

end KomkiSpec
