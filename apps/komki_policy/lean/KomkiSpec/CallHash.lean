import KomkiSpec.Json
import KomkiSpec.Sha256
import KomkiSpec.Model

/-!
# The call hash (CONTRACT.md § 2.6)

`Release.call_hash/4`: SHA-256 over the canonical JSON of the call's
`content_digest`, object, operation and workspace, lowercase hex. The model
takes the hash as a parameter `callHash`; the theorems hold for every value,
so for this one too. The bridge computes it here, and the differential test
compares every decision and catalog that names it with Elixir. That the
hash binds the call up to SHA-256 collisions is `callHashInput_injective`
(`CallHashSound.lean`).
-/

namespace KomkiSpec

/-- The object `output_call_hash/2` encodes; an absent digest enters as `null`. -/
def callPayload (S : Snapshot) (I : Intent) : JVal :=
  JVal.obj [("content_digest", (S.fact? "output_content_digest").getD .null),
    ("object", .str S.objectRef), ("operation", .str I.operation),
    ("workspace", .str S.workspaceId)]

/-- The bytes SHA-256 runs over. For a validated snapshot they always exist
(`callHashInput_isSome`). -/
def callHashInput (S : Snapshot) (I : Intent) : Option ByteArray :=
  match Json.canonical (callPayload S I) with
  | .ok text => some text.toUTF8
  | .error _ => none

/-- `output_call_hash/2`. -/
def callHashOf (S : Snapshot) (I : Intent) : String :=
  match callHashInput S I with
  | some bytes => Sha256.hex bytes
  | none => ""

end KomkiSpec
