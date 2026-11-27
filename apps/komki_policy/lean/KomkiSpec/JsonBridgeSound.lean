import KomkiSpec.BridgeSound
import KomkiSpec.JsonRoundtrip

/-!
# The bridge's JSON path on canonical text

`jsonCase` is the bridge's `json-batch`: parse the bytes, mask floats,
encode canonically, hash. `jsonCase_canonical`: on the bytes of a value's
canonical text it answers with that same text and its SHA-256, so the
canonical form is a fixed point of the path (CONTRACT.md § 6). It rests on
`parse_canonical` and on `encode_maskFloats`: what encodes holds no float,
so masking leaves it as it is.
-/

namespace KomkiSpec

mutual
theorem encode_maskFloats : ∀ (v : JVal) {d : Nat} {s : String},
    Json.encode d v = .ok s → maskFloats v = v
  | .null, _, _, _ => rfl
  | .bool _, _, _, _ => rfl
  | .int _, _, _, _ => rfl
  | .str _, _, _, _ => rfl
  | .float _ _, _, _, h => by unfold Json.encode at h; split at h <;> cases h
  | .arr [], _, _, _ => rfl
  | .arr (x :: xs), d, s, h => by
    obtain ⟨is, hi, _⟩ := Json.encode_arr h
    simp only [maskFloats, encodeItems_maskFloats (x :: xs) hi]
  | .obj [], _, _, _ => rfl
  | .obj (kv :: kvs), d, s, h => by
    obtain ⟨k, v⟩ := kv
    obtain ⟨es, he, _⟩ := Json.encode_obj h
    simp only [maskFloats, encodeEntries_maskFloats ((k, v) :: kvs) he]

theorem encodeItems_maskFloats : ∀ (xs : List JVal) {d : Nat} {is : List String},
    Json.encodeItems d xs = .ok is → maskFloatsList xs = xs
  | [], _, _, _ => rfl
  | x :: xs, d, is, h => by
    obtain ⟨i, is', hx, hxs, _⟩ := Json.encodeItems_cons h
    simp only [maskFloatsList, encode_maskFloats x hx, encodeItems_maskFloats xs hxs]

theorem encodeEntries_maskFloats : ∀ (kvs : List (String × JVal)) {d : Nat}
    {es : List (String × String)}, Json.encodeEntries d kvs = .ok es → maskFloatsObj kvs = kvs
  | [], _, _, _ => rfl
  | (k, v) :: kvs, d, es, h => by
    obtain ⟨sv, es', hv, hes, _⟩ := Json.encodeEntries_cons h
    simp only [maskFloatsObj, encode_maskFloats v hv, encodeEntries_maskFloats kvs hes]
end

/-- Main theorem: on the hex of a value's canonical text, `jsonCase`
answers with that text and its SHA-256; the canonical form is a fixed
point of the bridge's JSON path. -/
theorem jsonCase_canonical {j : JVal} {h : String} {v : JVal} {t : String}
    (hj : j.get? "hex" = some (.str h)) (hb : hexBytes h = .ok t.toUTF8) (hs : v.Strict)
    (hc : Json.canonical v = .ok t) :
    jsonCase j = .ok (Lean.Json.mkObj [("ok", .str t), ("sha256", .str (Sha256.hex t.toUTF8))]) := by
  have hm : maskFloats v = v := by
    unfold Json.canonical at hc
    cases he : Json.encode 0 v with
    | error _ => simp [he, Except.map] at hc
    | ok s => exact encode_maskFloats v he
  have hp := Json.parse_canonical hs hc
  simp only [String.toUTF8_eq_toByteArray] at hp hb
  simp [jsonCase, strAt_ok hj, hb, hp, hm, hc, bind, Except.bind, pure, Except.pure]

end KomkiSpec
