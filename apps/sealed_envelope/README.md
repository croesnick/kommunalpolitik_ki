# sealed_envelope

Seal a secret to a P-256 key that lives somewhere you cannot reach from
Erlang (a Secure Enclave, a token, an HSM) and open it only through that
key's owner — in Elixir, with zero runtime dependencies (`:crypto` from
OTP, `JSON` from Elixir 1.18+).

komki uses it for the secrets in its keychain: a small Swift helper holds
the Secure Enclave key and only performs the key agreement after Touch ID;
everything else happens here. It is a candidate for a standalone Hex
package ([issue #224](https://github.com/croesnick/kommunalpolitik_ki/issues/224)),
which is why code and docs are deliberately English.

## How it works

```elixir
provider = {MyEnclave, reason: "Unlock the API key"}

{:ok, envelope} = SealedEnvelope.seal("secret", provider)
{:ok, "secret"} = SealedEnvelope.open(envelope, provider)
```

- **One fixed suite.** P-256 ECDH with an ephemeral key, HKDF-SHA256
  (salt: the ephemeral public key, info: `"ktv2"`), AES-256-GCM. P-256
  because it is the curve Secure Enclaves offer for key agreement.
- **The provider only agrees.** `SealedEnvelope.KeyAgreement` has two
  callbacks: `recipient/1` hands out a key reference and its public key,
  `agree/3` returns the ECDH shared secret for that reference and an
  ephemeral public key. The provider never sees plaintext; this library
  never sees the private key.
- **One line of ASCII.** `ktv2.` followed by Base64 of a JSON object with
  exactly `key`, `eph` and `box`. The key reference is bound to the
  ciphertext as associated data.
- **Closed errors.** `:unknown_format`, `:malformed`, `:invalid` (wrong key
  or tampered), `{:key_agreement, reason}`. Invalid curve points are
  rejected before a provider sees them.

## Test double

`SealedEnvelope.KeyAgreement.FileTestDouble` keeps its private key in a
`0600` file so tests and agents can seal and open without hardware and
without a prompt. It is a test double: anyone who can read the file can
open every envelope sealed to it.

## Development

```bash
cd apps/sealed_envelope
mix test
mix credo --strict
mix dialyzer
```
