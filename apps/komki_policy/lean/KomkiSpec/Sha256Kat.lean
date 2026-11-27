import KomkiSpec.Sha256

/-!
# Known answers of the SHA-256 model

`Sha256.lean` computes the call hash in the model; the differential test
compares its bytes with Elixir's `:crypto`. Here the kernel itself checks
the model against fixed answers, independent of Elixir: the common test
messages (`""`, `"abc"`, the 448- and 896-bit messages) and the padding
boundaries at 55 and 64 bytes, where the length no longer fits the last
block, plus a UTF-8 message. The expected digests come from
`shasum -a 256`, an implementation independent of this one.
This checks the implementation on these inputs, not for every input.
-/

namespace KomkiSpec.Sha256

/-- The model's SHA-256 gives the standard digest on every listed message. -/
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
      "3f58f3fbc5b8023042312788a1e0732f38b21b027cefb23d38a2e6822ef8fbbc" := by
  decide +kernel

end KomkiSpec.Sha256
