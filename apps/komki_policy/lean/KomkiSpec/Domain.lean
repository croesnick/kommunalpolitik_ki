import KomkiSpec.DeriveSound
import KomkiSpec.Release

/-!
# The validated domain, checked at runtime

The theorems assume what `Registry.compile/1` and `Context` enforce
(`Registry.WellFormed`, `Snapshot.WellFormed`). The bridge checks both on
every case of the differential test, so an input Elixir lets through outside
that domain turns the test red instead of slipping past the theorems.
-/

namespace KomkiSpec

def Registry.wellFormed (Γ : Registry) : Bool :=
  Γ.bindings.all fun (_, bd) =>
    bd.readers.all Γ.observers.contains && bd.befugnisse.all fun x => Γ.observers.contains x.1

def Snapshot.wellFormed (S : Snapshot) : Bool :=
  (S.classification == "classified" || S.classification == "quarantine") &&
  admitBaseFacts.all (fun n => match S.fact? n with
    | none | some (.bool _) => true
    | _ => false) &&
  sortStrings S.workspaceBindings == S.workspaceBindings &&
  sortDedup S.workspaceBindings == S.workspaceBindings &&
  sortStrings S.objectLabels == S.objectLabels &&
  sortDedup S.objectLabels == S.objectLabels

theorem mem_of_lookup {β : Type} {l : List (String × β)} {a : String} {b : β}
    (h : l.lookup a = some b) : (a, b) ∈ l := by
  induction l with
  | nil => simp [List.lookup] at h
  | cons p ps ih =>
    obtain ⟨k, v⟩ := p
    simp only [List.lookup] at h
    split at h
    · next hk =>
      cases h
      rw [beq_iff_eq] at hk
      subst hk
      exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (ih h)

theorem Registry.wellFormed_sound {Γ : Registry} (h : Γ.wellFormed = true) : Γ.WellFormed := by
  intro b o ho
  unfold Registry.readersOf Registry.binding? at ho
  split at ho
  · next bd hbd =>
    have hmem : (b, bd) ∈ Γ.bindings := mem_of_lookup hbd
    have := List.all_eq_true.1 h _ hmem
    simp only [Bool.and_eq_true] at this
    exact List.contains_iff_mem.1 (List.all_eq_true.1 this.1 o ho)
  · cases ho

theorem Registry.wellFormed_authorities {Γ : Registry} (h : Γ.wellFormed = true) :
    Γ.AuthoritiesKnown := by
  intro b bd hbd x hx
  unfold Registry.binding? at hbd
  have := List.all_eq_true.1 h _ (mem_of_lookup hbd)
  simp only [Bool.and_eq_true] at this
  exact List.contains_iff_mem.1 (List.all_eq_true.1 this.2 x hx)

theorem Snapshot.wellFormed_sound {S : Snapshot} (h : S.wellFormed = true) : S.WellFormed := by
  simp only [Snapshot.wellFormed, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq,
    List.all_eq_true] at h
  obtain ⟨⟨⟨⟨⟨hc, hf⟩, hbs⟩, hbu⟩, hls⟩, hlu⟩ := h
  refine ⟨hc, fun n hn v hv => ?_, hbs, hbu, hls, hlu⟩
  have := hf n hn
  rw [hv] at this
  cases v <;> simp_all

end KomkiSpec
