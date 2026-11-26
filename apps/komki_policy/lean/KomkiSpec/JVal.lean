/-!
# JSON values as `verify.ex` sees them

`KomkiPolicy.JSON.parse` yields Elixir terms; `verify.ex` compares them with
`==`. Objects here are key-sorted lists with unique keys, so structural
equality is Elixir's map equality. It is written out by hand: Lean derives
`BEq` for this nested type only as an opaque function, about which nothing
can be proven, not even that a value equals itself.
-/

namespace KomkiSpec

inductive JVal where
  | null
  | bool (b : Bool)
  | int (i : Int)
  /-- Kept apart from `int`, so `3.0` never equals `3`: CONTRACT.md § 5
  compares claimed expressions structurally (`!==` in `verify.ex`, #626). -/
  | float (mantissa : Int) (exponent : Nat)
  | str (s : String)
  | arr (xs : List JVal)
  | obj (kvs : List (String × JVal))
  deriving Repr, Inhabited

mutual
/-- Structural equality; `float` never equals `int`. -/
def JVal.beq : JVal → JVal → Bool
  | .null, .null => true
  | .bool a, .bool b => a == b
  | .int a, .int b => a == b
  | .float m e, .float m' e' => m == m' && e == e'
  | .str a, .str b => a == b
  | .arr xs, .arr ys => JVal.beqList xs ys
  | .obj xs, .obj ys => JVal.beqObj xs ys
  | _, _ => false

def JVal.beqList : List JVal → List JVal → Bool
  | [], [] => true
  | x :: xs, y :: ys => JVal.beq x y && JVal.beqList xs ys
  | _, _ => false

def JVal.beqObj : List (String × JVal) → List (String × JVal) → Bool
  | [], [] => true
  | (k, v) :: xs, (k', v') :: ys => k == k' && JVal.beq v v' && JVal.beqObj xs ys
  | _, _ => false
end

instance : BEq JVal := ⟨JVal.beq⟩

mutual
theorem JVal.beq_refl : (j : JVal) → JVal.beq j j = true
  | .null => rfl
  | .bool _ => by simp [JVal.beq]
  | .int _ => by simp [JVal.beq]
  | .float _ _ => by simp [JVal.beq]
  | .str _ => by simp [JVal.beq]
  | .arr xs => by simp only [JVal.beq]; exact JVal.beqList_refl xs
  | .obj kvs => by simp only [JVal.beq]; exact JVal.beqObj_refl kvs

theorem JVal.beqList_refl : (xs : List JVal) → JVal.beqList xs xs = true
  | [] => rfl
  | x :: xs => by simp only [JVal.beqList, JVal.beq_refl x, JVal.beqList_refl xs, Bool.and_self]

theorem JVal.beqObj_refl : (kvs : List (String × JVal)) → JVal.beqObj kvs kvs = true
  | [] => rfl
  | (k, v) :: kvs => by
    simp only [JVal.beqObj, beq_self_eq_true, JVal.beq_refl v, JVal.beqObj_refl kvs,
      Bool.and_self]
end

instance : ReflBEq JVal := ⟨JVal.beq_refl _⟩

/-- `map[key]`: `none` where Elixir's `Map.get` returns `nil`. -/
def JVal.get? : JVal → String → Option JVal
  | .obj kvs, k => kvs.lookup k
  | _, _ => none

/-- A list of strings as the JSON array Elixir compares against. -/
def strs (xs : List String) : JVal := .arr (xs.map .str)

/-- `Enum.sort/1` on strings: bytewise, which is code-point order. -/
def sortStrings (xs : List String) : List String :=
  xs.mergeSort fun a b => !decide (b < a)

/-- `Enum.sort(Enum.uniq(xs))`. -/
def sortDedup (xs : List String) : List String :=
  (sortStrings xs).eraseDups

end KomkiSpec
