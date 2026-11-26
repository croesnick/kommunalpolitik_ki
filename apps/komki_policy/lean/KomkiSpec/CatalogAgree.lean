import KomkiSpec.CatalogSound
import KomkiSpec.RemediesSound

/-!
# `catalogGos` is the GO part of `catalog` (CONTRACT.md § 2.8)

The effectiveness theorems (`CatalogSound.lean`) speak about `catalogGos`,
order and completeness (`RemediesSound.lean`) about `catalog`. Both model
`Remedies.catalog/3`; `catalog_gos` shows they offer the same GOs, entry by
entry, for every finding `derive` can report. The effectiveness theorems
therefore hold for the whole catalog (`remedies_aktion_effective`,
`remedies_offenlegung_effective`).
-/

namespace KomkiSpec

/-- The GOs of a catalog entry, in order. -/
def gosOf : List Transition → List Go
  | [] => []
  | .go g :: ts => g :: gosOf ts
  | _ :: ts => gosOf ts

theorem gosOf_append (a b : List Transition) : gosOf (a ++ b) = gosOf a ++ gosOf b := by
  induction a with
  | nil => rfl
  | cons t ts ih => cases t <;> simp [gosOf, ih]

theorem gosOf_filter (p : Transition → Bool) (ts : List Transition) :
    gosOf (ts.filter p) = (gosOf ts).filter fun g => p (.go g) := by
  induction ts with
  | nil => rfl
  | cons t ts ih =>
    by_cases hp : p t = true <;> cases t <;> simp_all [gosOf]

theorem gosOf_flatMap {α : Type} (l : List α) (f : α → List Transition) :
    gosOf (l.flatMap f) = l.flatMap fun a => gosOf (f a) := by
  induction l with
  | nil => rfl
  | cons a as ih => simp [List.flatMap_cons, gosOf_append, ih]

theorem gosOf_eq_nil {ts : List Transition} (h : ∀ t ∈ ts, ∀ g, t ≠ .go g) : gosOf ts = [] := by
  induction ts with
  | nil => rfl
  | cons t ts ih =>
    have rest := ih fun u hu => h u (List.mem_cons_of_mem _ hu)
    cases t <;> simp [gosOf, rest]
    exact h _ List.mem_cons_self _ rfl

theorem gosOf_matching (Γ : Registry) (c : CatalogCtx) : gosOf (matchingTransformations Γ c) = [] := by
  apply gosOf_eq_nil
  intro t ht g
  unfold matchingTransformations at ht
  obtain ⟨⟨_, _, _⟩, _, rfl⟩ := List.mem_map.1 ht
  simp

theorem gosOf_fill (c : CatalogCtx) (l : List Transition) :
    gosOf (if l.isEmpty then [neuerRaum c] else l) = gosOf l := by
  cases l <;> rfl

/-- `ordered` keeps a single GO where it is. -/
theorem gosOf_ordered {ts : List Transition} (h : (gosOf ts).length ≤ 1) :
    gosOf (ordered ts) = gosOf ts := by
  unfold ordered
  rw [gosOf_filter, gosOf_flatMap]
  simp only [gosOf_filter]
  generalize gosOf ts = gs at h ⊢
  match gs, h with
  | [], _ => simp
  | [g], _ => cases g <;> simp [Transition.rank]

theorem regularGos_length (c : CatalogCtx) (code : String) : (regularGos c code).length ≤ 1 := by
  unfold regularGos
  repeat (first | split | simp)

/-- One finding: the GOs of its transitions are `regularGos`. -/
theorem transitions_gos (Γ : Registry) (c : CatalogCtx) (f : Finding)
    (hf : f.evidence = true → f.code ∈ derivedEvidenceCodes) :
    gosOf (ordered (if c.rule == "release" then releaseTransitions c f
      else regularTransitions Γ c f)) = regularGos c f.code := by
  have raw : gosOf (if c.rule == "release" then releaseTransitions c f
      else regularTransitions Γ c f) = regularGos c f.code := by
    obtain ⟨code, evidence, condition, fact⟩ := f
    simp only at hf ⊢
    unfold regularGos
    by_cases hrel : (c.rule == "release") = true
    · simp only [hrel, ite_true, releaseTransitions]
      by_cases hk : (c.releaseKind == some "offenlegungsfreigabe") = true <;>
        simp only [hk, ite_true, ite_false, Bool.false_eq_true] <;> split <;> simp [gosOf]
    · simp only [hrel, Bool.false_eq_true, ite_false, regularTransitions]
      have cg : gosOf (callGo c) = if outputOperations.contains c.rule then
          (match c.callHash with
          | some h => [Go.aktion h]
          | none => []) else [] := by
        unfold callGo
        split
        · cases c.callHash <;> rfl
        · rfl
      by_cases h1 : (code == "object_quarantine") = true
      · simp [h1, gosOf]
      simp only [h1, Bool.false_eq_true, ↓reduceIte]
      by_cases hm : code ∈ ["workspace_invalid", "label_not_preserved", "basis_right_false",
          "binding_condition_false", "audit_path_not_ready", "label_not_included",
          "recipient_not_allowed", "missing_operation_rule", "missing_fact", "recipients_unproven"]
      · simp only [List.mem_cons, List.not_mem_nil, or_false] at hm
        rcases hm with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
          cases evidence <;> by_cases ho : c.rule ∈ outputOperations <;>
          simp_all [gosOf, gosOf_append, gosOf_matching, neuerRaum, unbridgeableCodes,
            derivedEvidenceCodes] <;>
          cases c.callHash <;> rfl
      · simp_all [gosOf, unbridgeableCodes]
  rw [gosOf_ordered (raw ▸ regularGos_length c f.code), raw]

/-- `catalogGos` is the GO part of `catalog`, entry by entry, whenever every
piece of evidence is `missing_fact` or `recipients_unproven`, as for
everything `derive` reports (`premise_codes`). -/
theorem catalog_gos (Γ : Registry) (c : CatalogCtx) (fs : List Finding)
    (hf : ∀ f ∈ fs, f.evidence = true → f.code ∈ derivedEvidenceCodes) :
    (catalog Γ c fs).map gosOf = catalogGos Γ c (fs.map (·.code)) := by
  have entry : ∀ f ∈ fs, gosOf (ordered (if c.rule == "release" then releaseTransitions c f
      else regularTransitions Γ c f)) = regularGos c f.code :=
    fun f hm => transitions_gos Γ c f (hf f hm)
  unfold catalog catalogGos
  dsimp only
  generalize ((List.map (fun x => x.code) fs).any (unbridgeableFor c.rule) ||
    observersUnproven c) = A
  generalize ((((List.map (fun x => x.code) fs).any fun k =>
      unbridgeableCodes.contains k || offenlegungUnbridgeableCodes.contains k) ||
    c.rule == "release" && (List.map (fun x => x.code) fs).contains "recipient_not_allowed") ||
    observersUnproven c) = B
  generalize (c.rule == "store" && (List.map (fun x => x.code) fs).contains "recipient_not_allowed" &&
    c.rule != "release" && offenlegungOfferable Γ c && !B) = I
  split
  · next h =>
    simp only [Bool.not_eq_true', Bool.or_eq_false_iff] at h
    obtain ⟨⟨rfl, rfl⟩, rfl⟩ := h
    simp only [List.map_map]
    apply List.map_congr_left
    intro f hm
    simp only [Function.comp, entry f hm, Bool.or_false, Bool.not_false, Bool.false_and,
      Bool.false_eq_true, ↓reduceIte, List.append_nil]
    symm
    apply List.filter_eq_self.2
    intro g _
    cases g <;> rfl
  · simp only [List.map_map]
    apply List.map_congr_left
    intro f hm
    simp only [Function.comp]
    rw [gosOf_fill, gosOf_append, gosOf_filter, entry f hm]
    congr 1
    · congr 1
      funext g
      cases g <;> rfl
    · split <;> rfl

theorem mem_gosOf {g : Go} {ts : List Transition} (h : Transition.go g ∈ ts) : g ∈ gosOf ts := by
  induction ts with
  | nil => cases h
  | cons t ts ih =>
    rcases List.mem_cons.1 h with rfl | ht
    · simp [gosOf]
    · cases t <;> simp [gosOf, ih ht]

theorem deny_go_mem {Γ : Registry} {c : CatalogCtx} {bs : List Blocker} {g : Go}
    (hm : Transition.go g ∈ (catalog Γ c (bs.map Blocker.finding)).flatten) :
    g ∈ (catalogGos Γ c (codesOf bs)).flatten := by
  have hcodes : codesOf bs = (bs.map Blocker.finding).map (·.code) := by
    simp [codesOf, Blocker.finding]
  rw [hcodes, ← catalog_gos Γ c _ (by simp [Blocker.finding])]
  obtain ⟨e, he, hge⟩ := List.mem_flatten.1 hm
  exact List.mem_flatten.2 ⟨gosOf e, List.mem_map.2 ⟨e, he, rfl⟩, mem_gosOf hge⟩

/-- `catalog_aktion_effective` for the whole catalog: every Aktions-GO an
entry of `Remedies.catalog/3` offers a denial takes effect. -/
theorem remedies_aktion_effective {Γ : Registry} {S : Snapshot} {I : Intent} {bs : List Blocker}
    {c h : String} {St : Stand} {nonce auth : String}
    (hd : derive Γ S I = .decision (.deny bs))
    (hm : Transition.go (.aktion h) ∈
      (catalog Γ (normalCatalogCtx Γ S I.operation c) (bs.map Blocker.finding)).flatten)
    (hn : St.consumed.lookup nonce = none) (ha : auth ∈ Γ.observers) :
    deriveWithRelease Γ S I (aktionRelease h auth nonce St) St c =
      .decision (.permit (proposalOf (aktionRelease h auth nonce St) St c)) :=
  catalog_aktion_effective hd (deny_go_mem hm) hn ha

/-- `catalog_offenlegung_effective` for the whole catalog. -/
theorem remedies_offenlegung_effective {Γ : Registry} {S : Snapshot} {I : Intent}
    {bs : List Blocker} {c h art : String} {zl : List String} {St : Stand} {nonce auth : String}
    (hd : derive Γ S I = .decision (.deny bs))
    (hm : Transition.go (.offenlegung h art zl) ∈
      (catalog Γ (normalCatalogCtx Γ S I.operation c) (bs.map Blocker.finding)).flatten)
    (hn : St.consumed.lookup nonce = none) (hak : Γ.AuthoritiesKnown)
    (hb : auth ∈ lockerungsbefugte Γ (checkedLabel I.operation S) (actualRecipients Γ S) art) :
    deriveWithRelease Γ S I (offenlegungRelease h art zl auth nonce St) St c =
      .decision (.permit (proposalOf (offenlegungRelease h art zl auth nonce St) St c)) :=
  catalog_offenlegung_effective hd (deny_go_mem hm) hn hak hb

end KomkiSpec
