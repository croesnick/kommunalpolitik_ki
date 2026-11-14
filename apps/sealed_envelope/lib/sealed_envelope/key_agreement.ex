defmodule SealedEnvelope.KeyAgreement do
  @moduledoc """
  The one thing `SealedEnvelope` cannot do itself: hold the recipient's
  private key and run the P-256 key agreement with it.

  A provider is typically a hardware adapter (for example a Secure Enclave
  helper that asks for Touch ID before it agrees). The envelope core never
  sees the private key, and the provider never sees plaintext or the
  envelope — only the opaque key reference it handed out and an ephemeral
  public key.

  Public keys are P-256 points in uncompressed form (65 bytes, `0x04 ‖ X ‖ Y`,
  the same as CryptoKit's `x963Representation`). The shared secret is the
  32-byte x-coordinate of the ECDH result, as returned by `:crypto.compute_key/4`
  and CryptoKit's `SharedSecret`. `SealedEnvelope` checks that the peer key
  passed to `agree/3` is a valid point on the curve before calling it.

  Providers are passed as `{module, opts}`; `opts` are the provider's own
  (a key path, a prompt reason, a timeout).
  """

  @typedoc "Opaque, non-empty key reference; only the provider interprets it."
  @type key_ref :: binary()

  @typedoc "P-256 public key, uncompressed (65 bytes)."
  @type public_key :: binary()

  @doc """
  The key to seal to: its reference and its public key. A provider may hand
  out the same key every time or a fresh one per seal.
  """
  @callback recipient(opts :: keyword()) ::
              {:ok, key_ref(), public_key()} | {:error, term()}

  @doc """
  ECDH between the private key behind `key_ref` and `peer_public_key`.
  Returns the 32-byte shared secret. This is where a hardware provider asks
  the user for consent.
  """
  @callback agree(key_ref(), peer_public_key :: public_key(), opts :: keyword()) ::
              {:ok, shared_secret :: binary()} | {:error, term()}
end
