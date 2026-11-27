import KomkiSpec.CallHash
import KomkiSpec.JsonCanonical
import KomkiSpec.Input

/-!
# The call hash binds the call (CONTRACT.md § 2.6)

For a validated snapshot the canonical payload always encodes
(`callHashInput_isSome`), so `callHashOf` never falls back to `""`. Equal
hashed bytes mean equal digest, object, operation and workspace
(`callHashInput_injective`); what remains is SHA-256's collision resistance.
-/

namespace KomkiSpec

open Json

theorem canon_of_fits {ty : String} : ∀ {v : JVal}, valueFits ty v = true → v.Canon
  | .str _, _ | .bool _, _ | .int _, _ => trivial
  | .arr xs, h => by
    simp [valueFits] at h
    show JVal.CanonList xs
    induction xs with
    | nil => trivial
    | cons x xs ih =>
      have hx := h.2 x List.mem_cons_self
      cases x <;> simp at hx
      exact ⟨trivial, ih ⟨h.1, fun y hy => h.2 y (List.mem_cons_of_mem _ hy)⟩⟩
  | .null, h | .float _ _, h | .obj _, h => by simp [valueFits] at h

theorem encode_str_ok (d : Nat) (s : String) (hd : d ≤ maxDepth) :
    encode d (.str s) = .ok (encodeString s) := by
  rw [encode]; simp [Nat.not_lt.mpr hd]

theorem encodeEntries_cons_ok {d : Nat} {k : String} {v : JVal} {sv : String}
    {kvs : List (String × JVal)} {es : List (String × String)}
    (hv : encode d v = .ok sv) (hs : encodeEntries d kvs = .ok es) :
    encodeEntries d ((k, v) :: kvs) = .ok ((k, sv) :: es) := by
  simp [encodeEntries, hv, hs, bind, Except.bind]

theorem encodeItems_strs_ok (d : Nat) (hd : d ≤ maxDepth) :
    ∀ xs : List JVal, (∀ x ∈ xs, ∃ s, x = .str s) → ∃ is, encodeItems d xs = .ok is
  | [], _ => ⟨[], rfl⟩
  | x :: xs, h => by
    obtain ⟨is, his⟩ := encodeItems_strs_ok d hd xs fun y hy => h y (List.mem_cons_of_mem _ hy)
    obtain ⟨s, rfl⟩ := h x List.mem_cons_self
    exact ⟨encodeString s :: is, by simp [encodeItems, encode_str_ok d s hd, his, bind, Except.bind]⟩

theorem encode_fits {ty : String} {v : JVal} {d : Nat} (hv : valueFits ty v = true)
    (hd : d < maxDepth) : ∃ s, encode d v = .ok s := by
  cases v with
  | arr xs =>
    simp [valueFits] at hv
    obtain ⟨is, his⟩ := encodeItems_strs_ok (d + 1) hd xs fun x hx => by
      have := hv.2 x hx
      cases x <;> simp_all
    cases xs with
    | nil => exact ⟨"[]", by rw [encode]; simp [Nat.not_lt.mpr (Nat.le_of_lt hd)]⟩
    | cons x xs =>
      exact ⟨"[\n" ++ ",\n".intercalate (is.map (pad (d + 1) ++ ·)) ++ "\n" ++ pad d ++ "]", by
        rw [encode]; simp [Nat.not_lt.mpr (Nat.le_of_lt hd), his, bind, Except.bind]
        exact List.cons_ne_nil _ _⟩
  | _ => first
    | exact ⟨_, by rw [encode]; simp [Nat.not_lt.mpr (Nat.le_of_lt hd)]; rfl⟩
    | simp [valueFits] at hv

theorem lookup_mem {n : String} {v : JVal} :
    ∀ {l : List (String × JVal)}, l.lookup n = some v → (n, v) ∈ l
  | [], h => by simp at h
  | (k, w) :: l, h => by
    simp only [List.lookup] at h
    split at h
    · rename_i hk; simp at h hk; subst h hk; exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (lookup_mem h)

theorem fact_fits {Γ : Registry} {S : Snapshot} (hS : S.validated Γ = true) {n : String}
    {v : JVal} (h : S.fact? n = some v) : ∃ ty, valueFits ty v = true := by
  simp only [Snapshot.validated, Bool.and_eq_true, List.all_eq_true] at hS
  have := hS.2 _ (lookup_mem h)
  simp only at this
  split at this
  · exact ⟨_, this⟩
  · split at this
    · exact ⟨_, this⟩
    · cases this

theorem callPayload_ok {Γ : Registry} {S : Snapshot} (hS : S.validated Γ = true) (I : Intent) :
    ∃ t, canonical (callPayload S I) = .ok t := by
  have hm : (0 : Nat) < maxDepth := by decide
  have h1 : (1 : Nat) < maxDepth := by decide
  obtain ⟨sd, hd⟩ : ∃ sd, encode 1 ((S.fact? "output_content_digest").getD .null) = .ok sd := by
    cases hf : S.fact? "output_content_digest" with
    | none => exact ⟨"null", by rw [Option.getD_none, encode]; simp [Nat.not_lt.mpr (Nat.le_of_lt h1)]⟩
    | some v =>
      obtain ⟨ty, hty⟩ := fact_fits hS hf
      rw [Option.getD_some]
      exact encode_fits hty h1
  have he := encodeEntries_cons_ok (k := "content_digest") hd
    (encodeEntries_cons_ok (k := "object") (encode_str_ok 1 S.objectRef (Nat.le_of_lt h1))
      (encodeEntries_cons_ok (k := "operation") (encode_str_ok 1 I.operation (Nat.le_of_lt h1))
        (encodeEntries_cons_ok (k := "workspace") (encode_str_ok 1 S.workspaceId (Nat.le_of_lt h1))
          (kvs := []) (es := []) rfl)))
  cases hc : canonical (callPayload S I) with
  | ok t => exact ⟨t, rfl⟩
  | error _ =>
    unfold canonical callPayload at hc
    rw [encode.eq_def] at hc
    simp [Nat.not_lt.mpr (Nat.le_of_lt hm), he, bind, Except.bind, Except.map] at hc

theorem callPayload_canon {Γ : Registry} {S : Snapshot} (hS : S.validated Γ = true) (I : Intent) :
    (callPayload S I).Canon := by
  have hd : ((S.fact? "output_content_digest").getD .null).Canon := by
    cases hf : S.fact? "output_content_digest" with
    | none => trivial
    | some v => obtain ⟨_, hty⟩ := fact_fits hS hf; exact canon_of_fits hty
  exact ⟨by simp only [List.map_cons, List.map_nil]; decide, hd, trivial, trivial, trivial, trivial⟩

/-- Two calls whose payloads encode to the same canonical text agree on the
digest, the object, the operation and the workspace (CONTRACT.md § 2.6). -/
theorem callPayload_injective {Γ Γ' : Registry} {S S' : Snapshot} {I I' : Intent} {t : String}
    (hS : S.validated Γ = true) (hS' : S'.validated Γ' = true)
    (h : Json.canonical (callPayload S I) = .ok t) (h' : Json.canonical (callPayload S' I') = .ok t) :
    S.fact? "output_content_digest" = S'.fact? "output_content_digest" ∧
      S.objectRef = S'.objectRef ∧ I.operation = I'.operation ∧ S.workspaceId = S'.workspaceId := by
  have he := Json.canonical_injective (callPayload_canon hS I) (callPayload_canon hS' I') h h'
  simp only [callPayload, JVal.obj.injEq, List.cons.injEq, Prod.mk.injEq, JVal.str.injEq,
    true_and, and_true] at he
  obtain ⟨hd, ho, hop, hw⟩ := he
  refine ⟨?_, ho, hop, hw⟩
  cases hf : S.fact? "output_content_digest" <;> cases hf' : S'.fact? "output_content_digest" <;>
    simp [hf, hf'] at hd ⊢
  · obtain ⟨_, hty⟩ := fact_fits hS' hf'; subst hd; simp [valueFits] at hty
  · obtain ⟨_, hty⟩ := fact_fits hS hf; subst hd; simp [valueFits] at hty
  · exact hd

theorem callHashInput_isSome {Γ : Registry} {S : Snapshot} (hS : S.validated Γ = true)
    (I : Intent) : (callHashInput S I).isSome := by
  obtain ⟨t, ht⟩ := callPayload_ok hS I
  simp [callHashInput, ht]

/-- Two calls whose hashed bytes agree are the same call: same digest, object,
operation and workspace. Different calls with the same hash would need a
SHA-256 collision. -/
theorem callHashInput_injective {Γ Γ' : Registry} {S S' : Snapshot} {I I' : Intent}
    (hS : S.validated Γ = true) (hS' : S'.validated Γ' = true)
    (h : callHashInput S I = callHashInput S' I') :
    S.fact? "output_content_digest" = S'.fact? "output_content_digest" ∧
      S.objectRef = S'.objectRef ∧ I.operation = I'.operation ∧ S.workspaceId = S'.workspaceId := by
  obtain ⟨t, ht⟩ := callPayload_ok hS I
  obtain ⟨t', ht'⟩ := callPayload_ok hS' I'
  simp only [callHashInput, ht, ht', Option.some.injEq] at h
  rw [String.toByteArray_inj.mp h] at ht
  exact callPayload_injective hS hS' ht ht'

end KomkiSpec
