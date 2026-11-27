import KomkiSpec.Sha256

/-!
# Known answers of the SHA-256 model

`Sha256.lean` computes the call hash in the model; the differential test
compares its bytes with Elixir's `:crypto`. Here the kernel itself checks
the model against fixed answers, independent of Elixir: the common test
messages (`""`, `"abc"`, the 448- and 896-bit messages), the padding
boundaries at 55 bytes (the length just fits), 56 bytes (the 448-bit
message: the length spills into a second block) and 64 bytes (an exact
block), a UTF-8 message, and a call-hash input in canonical form over four
blocks. The expected digests come from `shasum -a 256`, an implementation
independent of this one. Lengths from 8 KiB on, where the length field's
third byte is used, are left to the differential test.
This checks the implementation on these inputs, not for every input.
-/

namespace KomkiSpec.Sha256

/-- The model's SHA-256 gives the digest of `shasum -a 256` on every listed message. -/
theorem known_answers :
    hex "".toUTF8 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ∧
    hex "abc".toUTF8 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ∧
    hex "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".toUTF8 =
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" ∧
    hex ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno" ++
      "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu").toUTF8 =
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1" ∧
    hex (String.ofList (List.replicate 55 'a')).toUTF8 =
      "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318" ∧
    hex (String.ofList (List.replicate 64 'a')).toUTF8 =
      "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb" ∧
    hex "Grüße aus Köln 😀".toUTF8 =
      "3f58f3fbc5b8023042312788a1e0732f38b21b027cefb23d38a2e6822ef8fbbc" ∧
    hex "{\n  \"content_digest\": \"abababababababababababababababababababababababababababababababab\",\n  \"object\": \"beschluss-haushalt-2026@3\",\n  \"operation\": \"emit\",\n  \"workspace\": \"ratsarbeit-finanzen\"\n}\n".toUTF8 =
      "108618537f99c17a4b3330fee34615f276ea432a13116ad8287b82d4c56b0352" := by
  decide +kernel

end KomkiSpec.Sha256
