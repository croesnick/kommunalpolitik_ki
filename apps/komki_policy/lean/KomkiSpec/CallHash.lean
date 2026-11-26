import KomkiSpec.Json
import KomkiSpec.Sha256
import KomkiSpec.Model

/-!
# The call hash (CONTRACT.md § 2.6)

`Release.call_hash/4`: SHA-256 over the canonical JSON of the call's
`content_digest`, object, operation and workspace, lowercase hex. The model
takes the hash as a parameter `callHash`; the theorems hold for every value,
so for this one too. The bridge computes it here, and the differential test
compares every decision and catalog that names it with Elixir.
-/

namespace KomkiSpec

/-- `output_call_hash/2`: an absent digest enters as `null`. -/
def callHashOf (S : Snapshot) (I : Intent) : String :=
  let payload := JVal.obj [("content_digest", (S.fact? "output_content_digest").getD .null),
    ("object", .str S.objectRef), ("operation", .str I.operation),
    ("workspace", .str S.workspaceId)]
  -- Fact values are strings, booleans, integers or string sets
  -- (`Snapshot.validated`), so encoding never fails here.
  match Json.canonical payload with
  | .ok text => Sha256.hex text.toUTF8
  | .error _ => ""

end KomkiSpec
