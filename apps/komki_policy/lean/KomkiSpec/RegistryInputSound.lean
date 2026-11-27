import KomkiSpec.ContextInputSound
import KomkiSpec.RegistryInput

/-!
# What `Registry.compile/1` guarantees the model

`registryError_compiledOk`: every registry `Registry.compile/1` accepts
decodes into the model and lies in the domain the theorems assume
(`Registry.compiledOk`, hence `Registry.WellFormed` and
`Registry.AuthoritiesKnown` by `Registry.compiledOk_sound`).
-/

namespace KomkiSpec

theorem clauseError_typed {ff : List (String × String)} {path k : String} {v : JVal}
    (hk : clauseOps.contains k = true) (h : clauseError ff path k v = none) :
    ∃ e, Expr.ofJVal (.obj [(k, v)]) = some e ∧ e.typed ff = true := by
  unfold clauseError at h
  split at h
  · next f lit =>
    split at h
    · simp at h
    · next ty hty =>
      split at h
      · next ht =>
        simp only [clauseOps, List.contains_cons, List.contains_nil, Bool.or_false,
          Bool.or_eq_true, beq_iff_eq] at hk
        rcases hk with rfl | rfl | rfl | rfl
        · exact ⟨.eq f lit, by simp [Expr.ofJVal], by simpa [Expr.typed, hty, clauseTyped] using ht⟩
        · cases lit <;> simp [clauseTyped] at ht
          next ls => exact ⟨.member f ls, by simp [Expr.ofJVal],
            by simpa [Expr.typed, hty, List.all_eq_true] using ht⟩
        · cases lit <;> simp [clauseTyped] at ht
          next ls =>
            refine ⟨.subset f ls, by simp [Expr.ofJVal], ?_⟩
            obtain ⟨h1, h2⟩ := ht
            simp only [Expr.typed, hty, h1, beq_self_eq_true, Bool.true_and, List.all_eq_true]
            intro x hx
            have := h2 x hx
            cases x <;> simp_all
        · cases lit <;> simp [clauseTyped] at ht
          next b => exact ⟨.atMost f b, by simp [Expr.ofJVal], by simpa [Expr.typed, hty] using ht⟩
      · cases h
  · simp [unsupported] at h

mutual
theorem exprError_typed {ff : List (String × String)} :
    ∀ {path : String} {j : JVal}, exprError ff path j = none →
      ∃ e, Expr.ofJVal j = some e ∧ e.typed ff = true
  | _, .bool true, _ => ⟨.tt, by simp [Expr.ofJVal], by simp [Expr.typed]⟩
  | _, .bool false, _ => ⟨.ff, by simp [Expr.ofJVal], by simp [Expr.typed]⟩
  | path, .obj [(k, .arr cs)], h => by
    simp only [exprError] at h
    split at h
    · next hk =>
      obtain ⟨es, hes, hty⟩ := exprsError_typed h
      have hall : (cs.mapM Expr.ofJVal).map Expr.all = some (.all es) := by simp [hes]
      have hany : (cs.mapM Expr.ofJVal).map Expr.any = some (.any es) := by simp [hes]
      have htyped : (es.attach.all fun ⟨c, _⟩ => c.typed ff) = true := by
        simpa [List.all_eq_true] using fun c hc => hty c hc
      simp only [Bool.or_eq_true, beq_iff_eq] at hk
      rcases hk with rfl | rfl
      · exact ⟨.all es, by simp [Expr.ofJVal, hes], by simpa [Expr.typed] using htyped⟩
      · exact ⟨.any es, by simp [Expr.ofJVal, hes], by simpa [Expr.typed] using htyped⟩
    · split at h
      · next hk => exact clauseError_typed hk h
      · simp [unsupported] at h
  | _, .obj [(_, .null)], h | _, .obj [(_, .bool _)], h | _, .obj [(_, .int _)], h
  | _, .obj [(_, .float _ _)], h | _, .obj [(_, .str _)], h | _, .obj [(_, .obj _)], h => by
    simp only [exprError] at h
    split at h <;> simp [clauseError, unsupported] at h
  | _, .null, h | _, .int _, h | _, .float _ _, h | _, .str _, h | _, .arr _, h
  | _, .obj [], h | _, .obj (_ :: _ :: _), h => by
    unfold exprError at h
    (try split at h) <;> simp_all [unsupported]

theorem exprsError_typed {ff : List (String × String)} :
    ∀ {path : String} {i : Nat} {cs : List JVal}, exprsError ff path i cs = none →
      ∃ es, cs.mapM Expr.ofJVal = some es ∧ ∀ e ∈ es, e.typed ff = true
  | _, _, [], _ => ⟨[], rfl, by simp⟩
  | path, i, c :: cs, h => by
    simp only [exprsError, Option.or_eq_none_iff] at h
    obtain ⟨e, he, ht⟩ := exprError_typed h.1
    obtain ⟨es, hes, hts⟩ := exprsError_typed h.2
    refine ⟨e :: es, by simp [List.mapM_cons, he, hes], ?_⟩
    intro x hx
    simp only [List.mem_cons] at hx
    rcases hx with rfl | hx
    · exact ht
    · exact hts x hx
end

theorem mapM_pure {α β : Type} {f : α → Decode β} {g : α → β} {xs : List α}
    (h : ∀ x ∈ xs, f x = .ok (g x)) : xs.mapM f = .ok (xs.map g) := by
  induction xs with
  | nil => rfl
  | cons x xs ih =>
    simp only [List.mapM_cons, List.map_cons, h x List.mem_cons_self,
      ih fun y hy => h y (List.mem_cons_of_mem _ hy)]
    rfl

theorem strings_mem {xs : List JVal} {ss : List String} (h : strings? xs = some ss) {s : String}
    (hs : s ∈ ss) : JVal.str s ∈ xs := by
  induction xs generalizing ss with
  | nil => simp [strings?] at h; subst h; simp at hs
  | cons x xs ih =>
    cases x <;> simp [strings?, List.mapM_cons] at h
    obtain ⟨rs, hrs, h⟩ := Option.bind_eq_some_iff.1 h
    cases h
    simp only [List.mem_cons] at hs ⊢
    rcases hs with rfl | hs
    · exact Or.inl rfl
    · exact Or.inr (ih hrs hs)

theorem asStrs_ok {xs : List JVal} {ss : List String} (h : strings? xs = some ss) :
    asStrs (.arr xs) = .ok ss := by
  simp only [asStrs, asArr, bind, Except.bind, pure, Except.pure, strings_mapM h]

theorem observerListError_none {path : String} {o : Option JVal}
    (h : observerListError path o = none) :
    ∃ xs ss, o = some (.arr xs) ∧ strings? xs = some ss ∧ ss ≠ [] := by
  unfold observerListError at h
  split at h
  · next xs =>
    split at h
    · simp at h
    · next hne =>
      split at h
      · simp at h
      · next ss hss =>
        refine ⟨xs, ss, rfl, hss, ?_⟩
        rintro rfl
        cases xs with
        | nil => simp at hne
        | cons x xs =>
          cases x <;> simp [strings?, List.mapM_cons] at hss <;>
            (obtain ⟨rs, _, hss⟩ := Option.bind_eq_some_iff.1 hss; cases hss)
  · simp at h

theorem subsetObserversError_none {observers : List String} {path : String} {o : Option JVal}
    (h : subsetObserversError observers path o = none) :
    ∃ xs ss, o = some (.arr xs) ∧ strings? xs = some ss ∧ ss ≠ [] ∧ ∀ s ∈ ss, s ∈ observers := by
  simp only [subsetObserversError, Option.or_eq_none_iff] at h
  obtain ⟨xs, ss, rfl, hss, hne⟩ := observerListError_none h.1
  refine ⟨xs, ss, rfl, hss, hne, fun s hs => ?_⟩
  have hin := h.2
  split at hin
  · next hall =>
    simp only [subsetObserversError.strIn', List.all_eq_true] at hall
    simpa using hall _ (strings_mem hss hs)
  · simp at hin

/-- A relaxation authority that passed `authority_entry/3`. -/
def AuthorityOk (observers : List String) (e : JVal) : Prop :=
  ∃ a r o, e.get? "authority" = some (.str a) ∧ e.get? "restriction" = some (.str r) ∧
    e.get? "output" = some (.str o) ∧ a ∈ observers

theorem authorityError_none {observers : List String} {path : String} {e : JVal}
    (h : authorityError observers path e = none) : AuthorityOk observers e := by
  unfold authorityError at h
  split at h
  · simp only [Option.or_eq_none_iff] at h
    obtain ⟨-, h1, h2, h3, h4, -⟩ := h
    split at h1 <;> try (simp at h1; done)
    split at h2 <;> try (simp at h2; done)
    split at h3 <;> try (simp at h3; done)
    split at h4 <;> try (simp at h4; done)
    rename_i hk hobs hr ho
    obtain ⟨a, ha, hm⟩ := strIn_some hobs
    obtain ⟨r, hr, -⟩ := strIn_some hr
    obtain ⟨o, ho⟩ := kebabJ_some ho
    exact ⟨a, r, o, ha, hr, ho, hm⟩
  · simp at h

theorem authoritiesErrorFrom_none {observers : List String} {path : String} :
    ∀ {i : Nat} {es : List JVal}, authoritiesErrorFrom observers path i es = none →
      ∀ e ∈ es, AuthorityOk observers e
  | _, [], _ => by simp
  | i, e :: es, h => by
    simp only [authoritiesErrorFrom, Option.or_eq_none_iff] at h
    intro x hx
    simp only [List.mem_cons] at hx
    rcases hx with rfl | hx
    · exact authorityError_none h.1
    · exact authoritiesErrorFrom_none h.2 x hx

theorem authoritiesError_none {observers : List String} {path : String} {o : Option JVal}
    (h : authoritiesError observers path o = none) :
    ∃ es, o = some (.arr es) ∧ ∀ e ∈ es, AuthorityOk observers e := by
  unfold authoritiesError at h
  split at h
  · next es =>
    simp only [Option.or_eq_none_iff] at h
    exact ⟨es, rfl, authoritiesErrorFrom_none h.1⟩
  · simp at h

theorem mem_byKey {kvs : List (String × JVal)} {p : String × JVal} :
    p ∈ byKey kvs ↔ p ∈ kvs := List.mem_mergeSort

/-- The operations of a binding that passed `validate_operations/3`. -/
def OperationsOk (ff : List (String × String)) (o : Option JVal) : Prop :=
  ∃ kvs, o = some (.obj kvs) ∧ ∀ p ∈ kvs, ∃ e, Expr.ofJVal p.2 = some e ∧ e.typed ff = true

theorem operationsError_none {ff : List (String × String)} {path : String} {o : Option JVal}
    (h : operationsError ff path o = none) : OperationsOk ff o := by
  unfold operationsError at h
  split at h
  · next kvs =>
    split at h
    · simp at h
    · rw [List.findSome?_eq_none_iff] at h
      exact ⟨kvs, rfl, fun p hp => exprError_typed (h p (mem_byKey.2 hp))⟩
  · simp at h

/-- A binding that passed `binding_part/4`. -/
def BindingOk (ff : List (String × String)) (observers : List String) (b : JVal) : Prop :=
  (∃ xs ss, b.get? "readers" = some (.arr xs) ∧ strings? xs = some ss ∧ ss ≠ [] ∧
    ∀ s ∈ ss, s ∈ observers) ∧
  (∃ es, b.get? "relaxation_authorities" = some (.arr es) ∧ ∀ e ∈ es, AuthorityOk observers e) ∧
  OperationsOk ff (b.get? "operations")

theorem bindingError_none {ff : List (String × String)} {observers : List String} {path : String}
    {b : JVal} (h : bindingError ff observers path b = none) : BindingOk ff observers b := by
  unfold bindingError at h
  split at h
  · simp only [Option.or_eq_none_iff] at h
    obtain ⟨-, h1, h2, h3⟩ := h
    exact ⟨subsetObserversError_none h1, authoritiesError_none h2, operationsError_none h3⟩
  · simp at h

/-- An environment that passed `environment_part/3`. -/
def EnvironmentOk (observers : List String) (e : JVal) : Prop :=
  ∃ xs ss, e.get? "observers" = some (.arr xs) ∧ strings? xs = some ss ∧ ss ≠ [] ∧
    ∀ s ∈ ss, s ∈ observers

theorem environmentError_none {observers : List String} {path : String} {e : JVal}
    (h : environmentError observers path e = none) : EnvironmentOk observers e := by
  unfold environmentError at h
  split at h
  · simp only [Option.or_eq_none_iff] at h
    exact subsetObserversError_none h.2
  · simp at h

theorem entriesError_none {path empty : String} {part : String → JVal → Option InputError}
    {o : Option JVal} (h : entriesError path empty part o = none) :
    ∃ kvs, o = some (.obj kvs) ∧ kvs ≠ [] ∧ ∀ p ∈ kvs, part (path ++ "." ++ p.1) p.2 = none := by
  unfold entriesError at h
  split at h
  · next kv kvs =>
    rw [List.findSome?_eq_none_iff] at h
    refine ⟨kv :: kvs, rfl, by simp, fun ⟨n, e⟩ hp => ?_⟩
    have := h (n, e) (mem_byKey.2 hp)
    by_cases hr : refId n = true
    · simpa [hr] using this
    · simp [hr] at this
  · simp at h

/-- A label list that passed `require_sorted_unique_bindings/4`. -/
def LabelsOk (bindingIds : List String) (nonempty : Bool) (o : Option JVal) : Prop :=
  ∃ xs ss, o = some (.arr xs) ∧ strings? xs = some ss ∧ (nonempty = true → ss ≠ []) ∧
    ∀ s ∈ ss, s ∈ bindingIds

theorem labelsError_none {bindingIds : List String} {nonempty : Bool} {path : String}
    {o : Option JVal} (h : labelsError bindingIds nonempty path o = none) :
    LabelsOk bindingIds nonempty o := by
  unfold labelsError at h
  split at h
  · next xs =>
    split at h
    · simp at h
    · next ss hss =>
      split at h
      · simp at h
      · next hne =>
        split at h
        · simp at h
        · split at h
          · simp at h
          · next hall =>
            refine ⟨xs, ss, rfl, hss, fun hn => by simpa [hn] using hne, fun s hs => ?_⟩
            simpa using (by simpa using hall : ∀ x ∈ ss, x ∈ bindingIds) s hs
  · simp at h

def TransformationOk (bindingIds : List String) (t : JVal) : Prop :=
  LabelsOk bindingIds true (t.get? "input_labels") ∧
    LabelsOk bindingIds false (t.get? "output_labels")

theorem transformationError_none {bindingIds : List String} {path : String} {t : JVal}
    (h : transformationError bindingIds path t = none) : TransformationOk bindingIds t := by
  unfold transformationError at h
  split at h
  · simp only [Option.or_eq_none_iff] at h
    exact ⟨labelsError_none h.2.1, labelsError_none h.2.2⟩
  · simp at h

theorem transformationsError_none {bindingIds : List String} {o : Option JVal}
    (h : transformationsError bindingIds o = none) :
    (∀ kvs, o ≠ some (.obj kvs)) ∨
      ∃ kvs, o = some (.obj kvs) ∧ ∀ p ∈ kvs, TransformationOk bindingIds p.2 := by
  unfold transformationsError at h
  split at h
  · exact Or.inl (by simp)
  · exact Or.inl (by simp)
  · next kvs =>
    rw [List.findSome?_eq_none_iff] at h
    refine Or.inr ⟨kvs, rfl, fun ⟨n, e⟩ hp => ?_⟩
    have := h (n, e) (mem_byKey.2 hp)
    by_cases hr : refId n = true
    · exact transformationError_none (by simpa [hr] using this)
    · simp [hr] at this
  · simp at h

/-! ## Decoding an accepted registry -/

def objOf : Option JVal → List (String × JVal)
  | some (.obj kvs) => kvs
  | _ => []

def arrOf : Option JVal → List JVal
  | some (.arr xs) => xs
  | _ => []

def envOf (p : String × JVal) : String × List String :=
  (p.1, sortStrings (strsOf (p.2.get? "observers")))

def authorityOf (e : JVal) : String × String × String :=
  (strField e "authority", strField e "restriction", strField e "output")

def bindingOf (p : String × JVal) : String × Binding :=
  (p.1, { readers := sortStrings (strsOf (p.2.get? "readers")),
          operations := objOf (p.2.get? "operations"),
          befugnisse := (arrOf (p.2.get? "relaxation_authorities")).map authorityOf })

def transformationOf (p : String × JVal) : String × List String × List String :=
  (p.1, strsOf (p.2.get? "input_labels"), strsOf (p.2.get? "output_labels"))

theorem strsOf_eq {o : Option JVal} {xs : List JVal} {ss : List String} (ho : o = some (.arr xs))
    (h : strings? xs = some ss) : strsOf o = ss := by
  subst ho; simp [strsOf, h]

theorem decodeEnvironment_ok {observers : List String} {p : String × JVal}
    (h : EnvironmentOk observers p.2) : decodeEnvironment p = .ok (envOf p) := by
  obtain ⟨xs, ss, hxs, hss, -, -⟩ := h
  simp only [decodeEnvironment, envOf, field_ok hxs, asStrs_ok hss, strsOf_eq hxs hss, bind,
    Except.bind, pure, Except.pure]

theorem decodeAuthority_ok {observers : List String} {e : JVal} (h : AuthorityOk observers e) :
    decodeAuthority e = .ok (authorityOf e) := by
  obtain ⟨a, r, o, ha, hr, ho, -⟩ := h
  simp only [decodeAuthority, authorityOf, strAt_ok ha, strAt_ok hr, strAt_ok ho, strField, ha, hr,
    ho, bind, Except.bind, pure, Except.pure]

theorem decodeBinding_ok {ff : List (String × String)} {observers : List String}
    {p : String × JVal} (h : BindingOk ff observers p.2) : decodeBinding p = .ok (bindingOf p) := by
  obtain ⟨⟨xs, ss, hxs, hss, -, -⟩, ⟨es, hes, hok⟩, ⟨ops, hops, -⟩⟩ := h
  have ha : decodeAuthorities (some (.arr es)) = .ok (es.map authorityOf) := by
    simp only [decodeAuthorities]; exact mapM_pure fun e he => decodeAuthority_ok (hok e he)
  simp only [decodeBinding, bindingOf, field_ok hxs, asStrs_ok hss, strsOf_eq hxs hss, hes, ha,
    field_ok hops, asObj, objOf, hops, arrOf, bind, Except.bind, pure, Except.pure]

theorem decodeTransformation_ok {bindingIds : List String} {p : String × JVal}
    (h : TransformationOk bindingIds p.2) :
    decodeTransformation p = .ok (transformationOf p) := by
  obtain ⟨⟨xs, ss, hxs, hss, -, -⟩, ⟨ys, ts, hys, hts, -, -⟩⟩ := h
  simp only [decodeTransformation, transformationOf, field_ok hxs, asStrs_ok hss,
    strsOf_eq hxs hss, field_ok hys, asStrs_ok hts, strsOf_eq hys hts, bind, Except.bind, pure,
    Except.pure]

theorem factFieldsError_none {o : Option JVal} (h : factFieldsError o = none) :
    ∃ fs, o = some (.obj fs) ∧ ∀ p ∈ fs, ∃ t, p.2 = .str t ∧ t ∈ factTypes := by
  unfold factFieldsError at h
  split at h
  · next fs =>
    split at h
    · next hall =>
      refine ⟨fs, rfl, fun ⟨n, t⟩ hp => ?_⟩
      have := List.all_eq_true.1 hall (n, t) hp
      obtain ⟨s, hs, hm⟩ := strIn_some this
      exact ⟨s, by simpa using hs, hm⟩
    · simp at h
  · simp at h

theorem contains_sortStrings {xs : List String} {s : String} :
    (sortStrings xs).contains s = true ↔ s ∈ xs := by
  simp [sortStrings, List.mem_mergeSort]

/-- Main theorem: every registry `Registry.compile/1` accepts decodes into
the model and lies in the domain the theorems assume. -/
theorem registryError_compiledOk {j : JVal} (h : registryError j = none) :
    ∃ Γ, decodeRegistry j = .ok Γ ∧ Γ.compiledOk = true := by
  unfold registryError at h
  split at h
  · rename_i kvs
    simp only [Option.or_eq_none_iff] at h
    obtain ⟨-, -, hid, hobs, hff, henv, hbind, htr⟩ := h
    have hk : kebabJ ((JVal.obj kvs).get? "registry_id") = true := by
      cases hc : kebabJ ((JVal.obj kvs).get? "registry_id") <;> simp_all
    obtain ⟨rid, hrid⟩ := kebabJ_some hk
    obtain ⟨oxs, oss, hoxs, hoss, hone⟩ := observerListError_none hobs
    have hobsOf : strsOf ((JVal.obj kvs).get? "observers") = oss := strsOf_eq hoxs hoss
    obtain ⟨fs, hfs, hfsOk⟩ := factFieldsError_none hff
    have hffOf : factFieldsOf ((JVal.obj kvs).get? "fact_fields") = fs.map factFieldOf := by
      simp [factFieldsOf, hfs]
    obtain ⟨envs, henvs, -, henvOk⟩ := entriesError_none henv
    obtain ⟨bs, hbs, -, hbOk⟩ := entriesError_none hbind
    rw [hobsOf] at henvOk hbOk
    rw [hffOf] at hbOk
    have hkeys : keysOf ((JVal.obj kvs).get? "bindings") = bs.map (·.1) := by simp [keysOf, hbs]
    rw [hkeys] at htr
    have hdf : decodeFactFields ((JVal.obj kvs).get? "fact_fields") = .ok (fs.map factFieldOf) := by
      rw [hfs]
      refine mapM_pure fun ⟨n, t⟩ hp => ?_
      obtain ⟨s, hs, -⟩ := hfsOk (n, t) hp
      simp only at hs
      subst hs
      simp only [decodeFactField, factFieldOf, asStr, bind, Except.bind, pure, Except.pure]
    have hde : envs.mapM decodeEnvironment = .ok (envs.map envOf) :=
      mapM_pure fun p hp => decodeEnvironment_ok (environmentError_none (henvOk p hp))
    have hdb : bs.mapM decodeBinding = .ok (bs.map bindingOf) :=
      mapM_pure fun p hp => decodeBinding_ok (bindingError_none (hbOk p hp))
    obtain ⟨tl, htl, htlOk⟩ : ∃ tl, decodeTransformations ((JVal.obj kvs).get? "transformations") =
        .ok tl ∧ ∀ t ∈ tl, t.2.1 ≠ [] ∧ (∀ s ∈ t.2.1, s ∈ bs.map (·.1)) ∧
          ∀ s ∈ t.2.2, s ∈ bs.map (·.1) := by
      rcases transformationsError_none htr with hno | ⟨ts, hts, htOk⟩
      · refine ⟨[], ?_, by simp⟩
        cases ht : (JVal.obj kvs).get? "transformations" with
        | none => rfl
        | some v =>
          cases v <;> try rfl
          next ts => exact absurd ht (hno ts)
      · refine ⟨ts.map transformationOf, by
          rw [hts]; exact mapM_pure fun p hp => decodeTransformation_ok (htOk p hp), ?_⟩
        intro t ht
        obtain ⟨p, hp, rfl⟩ := List.mem_map.1 ht
        obtain ⟨⟨xs, ss, hxs, hss, hne, hin⟩, ⟨ys, us, hys, hus, -, hin'⟩⟩ := htOk p hp
        simp only [transformationOf, strsOf_eq hxs hss, strsOf_eq hys hus]
        exact ⟨hne rfl, hin, hin'⟩
    refine ⟨{ registryId := rid
              observers := sortStrings oss
              environments := envs.map envOf
              bindings := bs.map bindingOf
              factFields := fs.map factFieldOf
              transformations := tl.mergeSort (fun a b => !decide (b.1 < a.1)) }, ?_, ?_⟩
    · simp only [decodeRegistry, field_ok henvs, field_ok hbs, asObj, hde, hdb, htl, hdf,
        strAt_ok hrid, field_ok hoxs, asStrs_ok hoss, bind, Except.bind, pure, Except.pure]
    · have hobsC : ∀ s, s ∈ oss → (sortStrings oss).contains s = true :=
        fun s hs => contains_sortStrings.2 hs
      have hkeysB : (bs.map bindingOf).map (·.1) = bs.map (·.1) := by
        simp [bindingOf, Function.comp_def]
      simp only [Registry.compiledOk, Registry.wellFormed, Bool.and_eq_true, List.all_eq_true]
      refine ⟨⟨⟨⟨fun x hx => ?_, fun x hx => ?_⟩, fun x hx => ?_⟩, fun x hx => ?_⟩, fun x hx => ?_⟩
      · -- readers and relaxation authorities are observers
        obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hx
        obtain ⟨⟨xs, ss, hxs, hss, -, hin⟩, ⟨es, hes, hok⟩, -⟩ := bindingError_none (hbOk p hp)
        simp only [bindingOf, strsOf_eq hxs hss, arrOf, hes, List.mem_map]
        refine ⟨fun s hs => hobsC s (hin s (List.mem_mergeSort.1 hs)), ?_⟩
        rintro _ ⟨e, he, rfl⟩
        obtain ⟨a, r, o, ha, -, -, hm⟩ := hok e he
        simpa [authorityOf, strField, ha] using hobsC a hm
      · -- fact types
        obtain ⟨⟨n, t⟩, hp, rfl⟩ := List.mem_map.1 hx
        obtain ⟨s, hs, hm⟩ := hfsOk (n, t) hp
        simp only at hs
        subst hs
        simp only [factTypes, List.mem_cons, List.not_mem_nil, or_false] at hm
        rcases hm with rfl | rfl | rfl | rfl <;> rfl
      · -- environments: non-empty, observers
        obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hx
        obtain ⟨xs, ss, hxs, hss, hne, hin⟩ := environmentError_none (henvOk p hp)
        simp only [envOf, strsOf_eq hxs hss, Bool.not_eq_true', List.isEmpty_eq_false_iff,
          subsetOfList, List.all_eq_true]
        refine ⟨fun h0 => hne (by simpa [sortStrings] using congrArg List.length h0), ?_⟩
        exact fun s hs => hobsC s (hin s (List.mem_mergeSort.1 hs))
      · -- bindings: non-empty readers, typed expressions
        obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hx
        obtain ⟨⟨xs, ss, hxs, hss, hne, -⟩, -, ⟨ops, hops, hty⟩⟩ := bindingError_none (hbOk p hp)
        simp only [bindingOf, strsOf_eq hxs hss, objOf, hops, Bool.not_eq_true',
          List.isEmpty_eq_false_iff]
        refine ⟨fun h0 => hne (by simpa [sortStrings] using congrArg List.length h0), ?_⟩
        intro q hq
        obtain ⟨e, he, ht⟩ := hty q hq
        simp [he, ht]
      · -- transformations: non-empty input, labels are bindings
        obtain ⟨hne, hin, hout⟩ := htlOk x (List.mem_mergeSort.1 hx)
        simp only [hkeysB, Bool.not_eq_true', List.isEmpty_eq_false_iff, subsetOfList,
          List.all_eq_true, List.contains_iff_mem]
        exact ⟨⟨hne, hin⟩, hout⟩
  · simp at h

end KomkiSpec
