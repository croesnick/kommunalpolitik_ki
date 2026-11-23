/-!
# PROTOTYPE (throwaway): the three-valued B.4 evaluator

Mirrors `KomkiPolicy.Evaluator` (CONTRACT.md § 3) and proves what its
moduledoc promises: a missing fact yields `unknown`, never a default. Stated
as monotonicity: adding facts can turn `unknown` into `true` or `false`, but
never flips a known verdict.
-/

namespace KomkiKalkuel

/-- Fact values (`fact_fields`: string, boolean, integer, string_set). -/
inductive Value where
  | str (s : String)
  | bool (b : Bool)
  | int (i : Int)
  | strs (ss : List String)
  deriving DecidableEq, Repr

/-- The restricted policy language of B.4. -/
inductive Expr where
  | tt
  | ff
  | all (cs : List Expr)
  | any (cs : List Expr)
  | eq (field : String) (lit : Value)
  | member (field : String) (lits : List Value)
  | subset (field : String) (lits : List String)
  | atMost (field : String) (bound : Int)
  deriving Repr

inductive Verdict where
  | true
  | false
  | unknown
  deriving DecidableEq, Repr

/-- Snapshot facts; `none` is a missing fact. -/
abbrev Facts := String → Option Value

def ofBool : Bool → Verdict
  | true => .true
  | false => .false

/-- `all`: known `false` beats `unknown`; empty `all` is `true`. -/
def allVerdict (vs : List Verdict) : Verdict :=
  if vs = [] then .true
  else if Verdict.false ∈ vs then .false
  else if Verdict.unknown ∈ vs then .unknown
  else .true

/-- `any`: known `true` beats `unknown`; empty `any` is `false`. -/
def anyVerdict (vs : List Verdict) : Verdict :=
  if vs = [] then .false
  else if Verdict.true ∈ vs then .true
  else if Verdict.unknown ∈ vs then .unknown
  else .false

/-- Mirrors `fact_value/2`: a missing fact is `unknown`, otherwise `k` decides. -/
def onFact (facts : Facts) (field : String) (k : Value → Verdict) : Verdict :=
  match facts field with
  | none => .unknown
  | some v => k v

/-- Ill-typed facts are `false` here. Elixir never sees them: `context.ex`
type-checks snapshot facts against `fact_fields`. Lean demands an answer. -/
def eval (facts : Facts) : Expr → Verdict
  | .tt => .true
  | .ff => .false
  | .all cs => allVerdict (cs.map (eval facts))
  | .any cs => anyVerdict (cs.map (eval facts))
  | .eq f lit => onFact facts f fun v => ofBool (decide (v = lit))
  | .member f lits => onFact facts f fun v => ofBool (decide (v ∈ lits))
  | .subset f lits => onFact facts f fun
      | .strs ss => ofBool (ss.all fun s => decide (s ∈ lits))
      | _ => .false
  | .atMost f bound => onFact facts f fun
      | .int i => ofBool (decide (i ≤ bound))
      | _ => .false

/-- Information order: `unknown` may become anything, a known verdict stays. -/
def Refines (v w : Verdict) : Prop := v = .unknown ∨ v = w

/-- `g` extends `f`: every fact present in `f` is in `g` with the same value. -/
def Extends (f g : Facts) : Prop := ∀ k v, f k = some v → g k = some v

theorem onFact_mono {f g : Facts} (h : Extends f g) (field : String) (k : Value → Verdict) :
    Refines (onFact f field k) (onFact g field k) := by
  unfold onFact
  cases hf : f field with
  | none => exact Or.inl rfl
  | some v => rw [h field v hf]; exact Or.inr rfl

theorem allVerdict_mono {α : Type} (cs : List α) (p q : α → Verdict)
    (h : ∀ c ∈ cs, Refines (p c) (q c)) :
    Refines (allVerdict (cs.map p)) (allVerdict (cs.map q)) := by
  unfold allVerdict
  by_cases hnil : cs = []
  · subst hnil; exact Or.inr rfl
  have hnp : cs.map p ≠ [] := by simpa using hnil
  have hnq : cs.map q ≠ [] := by simpa using hnil
  by_cases hf : Verdict.false ∈ cs.map p
  · have hf' : Verdict.false ∈ cs.map q := by
      obtain ⟨c, hc, hpc⟩ := List.mem_map.1 hf
      rcases h c hc with hu | he
      · rw [hpc] at hu; cases hu
      · exact List.mem_map.2 ⟨c, hc, by rw [← he, hpc]⟩
    simp only [hnp, hnq, hf, hf', ite_false, ite_true]
    exact Or.inr rfl
  by_cases hu : Verdict.unknown ∈ cs.map p
  · simp only [hnp, hf, hu, ite_false, ite_true]
    exact Or.inl rfl
  have hq : ∀ c ∈ cs, q c = .true := by
    intro c hc
    have hpc : p c = .true := by
      cases hp : p c with
      | true => rfl
      | false => exact absurd (List.mem_map.2 ⟨c, hc, hp⟩) hf
      | unknown => exact absurd (List.mem_map.2 ⟨c, hc, hp⟩) hu
    rcases h c hc with hu' | he
    · rw [hpc] at hu'; cases hu'
    · rw [← he, hpc]
  have hf' : Verdict.false ∉ cs.map q := fun hm => by
    obtain ⟨c, hc, hqc⟩ := List.mem_map.1 hm
    rw [hq c hc] at hqc; cases hqc
  have hu' : Verdict.unknown ∉ cs.map q := fun hm => by
    obtain ⟨c, hc, hqc⟩ := List.mem_map.1 hm
    rw [hq c hc] at hqc; cases hqc
  simp only [hnp, hnq, hf, hu, hf', hu', ite_false]
  exact Or.inr rfl

theorem anyVerdict_mono {α : Type} (cs : List α) (p q : α → Verdict)
    (h : ∀ c ∈ cs, Refines (p c) (q c)) :
    Refines (anyVerdict (cs.map p)) (anyVerdict (cs.map q)) := by
  unfold anyVerdict
  by_cases hnil : cs = []
  · subst hnil; exact Or.inr rfl
  have hnp : cs.map p ≠ [] := by simpa using hnil
  have hnq : cs.map q ≠ [] := by simpa using hnil
  by_cases ht : Verdict.true ∈ cs.map p
  · have ht' : Verdict.true ∈ cs.map q := by
      obtain ⟨c, hc, hpc⟩ := List.mem_map.1 ht
      rcases h c hc with hu | he
      · rw [hpc] at hu; cases hu
      · exact List.mem_map.2 ⟨c, hc, by rw [← he, hpc]⟩
    simp only [hnp, hnq, ht, ht', ite_false, ite_true]
    exact Or.inr rfl
  by_cases hu : Verdict.unknown ∈ cs.map p
  · simp only [hnp, ht, hu, ite_false, ite_true]
    exact Or.inl rfl
  have hq : ∀ c ∈ cs, q c = .false := by
    intro c hc
    have hpc : p c = .false := by
      cases hp : p c with
      | false => rfl
      | true => exact absurd (List.mem_map.2 ⟨c, hc, hp⟩) ht
      | unknown => exact absurd (List.mem_map.2 ⟨c, hc, hp⟩) hu
    rcases h c hc with hu' | he
    · rw [hpc] at hu'; cases hu'
    · rw [← he, hpc]
  have ht' : Verdict.true ∉ cs.map q := fun hm => by
    obtain ⟨c, hc, hqc⟩ := List.mem_map.1 hm
    rw [hq c hc] at hqc; cases hqc
  have hu' : Verdict.unknown ∉ cs.map q := fun hm => by
    obtain ⟨c, hc, hqc⟩ := List.mem_map.1 hm
    rw [hq c hc] at hqc; cases hqc
  simp only [hnp, hnq, ht, hu, ht', hu', ite_false]
  exact Or.inr rfl

/-- More facts never flip a known verdict. -/
theorem eval_mono {f g : Facts} (h : Extends f g) : ∀ e, Refines (eval f e) (eval g e)
  | .tt => by simp only [eval]; exact Or.inr rfl
  | .ff => by simp only [eval]; exact Or.inr rfl
  | .all cs => by
      simp only [eval]
      exact allVerdict_mono cs _ _ fun c _ => eval_mono h c
  | .any cs => by
      simp only [eval]
      exact anyVerdict_mono cs _ _ fun c _ => eval_mono h c
  | .eq _ _ => by simp only [eval]; exact onFact_mono h _ _
  | .member _ _ => by simp only [eval]; exact onFact_mono h _ _
  | .subset _ _ => by simp only [eval]; exact onFact_mono h _ _
  | .atMost _ _ => by simp only [eval]; exact onFact_mono h _ _

/-- A `true` condition stays `true` under every extension of the facts: no
permit rests on a fact that was missing. -/
theorem eval_true_stable {f g : Facts} (h : Extends f g) {e : Expr}
    (ht : eval f e = .true) : eval g e = .true := by
  rcases eval_mono h e with hu | he
  · rw [ht] at hu; cases hu
  · rw [← he, ht]

/-- Likewise for `false`: a deny stays a deny when evidence arrives. -/
theorem eval_false_stable {f g : Facts} (h : Extends f g) {e : Expr}
    (hf : eval f e = .false) : eval g e = .false := by
  rcases eval_mono h e with hu | he
  · rw [hf] at hu; cases hu
  · rw [← he, hf]

end KomkiKalkuel
