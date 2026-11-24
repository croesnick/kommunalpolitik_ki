/-!
# JSON values as `verify.ex` sees them

`KomkiPolicy.JSON.parse` yields Elixir terms; `verify.ex` compares them with
`==`. Objects here are key-sorted lists with unique keys, so the derived
structural `BEq` is Elixir's map equality. Lean cannot derive `DecidableEq`
for this nested type; the soundness proofs never need it, because every
check they rely on matches on patterns instead of comparing with `==`.
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
  deriving BEq, Repr, Inhabited

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
