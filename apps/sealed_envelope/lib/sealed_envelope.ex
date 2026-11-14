defmodule SealedEnvelope do
  @moduledoc """
  Seals a secret to a P-256 key that lives elsewhere — typically in
  hardware — and opens it only through that key's owner.

  The envelope does all the cryptography in Elixir. The only thing it
  delegates is the key agreement with the recipient's private key, through
  the `SealedEnvelope.KeyAgreement` behaviour. A hardware provider never
  sees plaintext, and this module never sees the private key.

      provider = {MyEnclave, reason: "Unlock the API key"}
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)
      {:ok, "secret"} = SealedEnvelope.open(envelope, provider)

  ## Format `ktv2`

  An envelope is one line of ASCII: `ktv2.` followed by Base64 of a JSON
  object with exactly three fields, each Base64 again:

  - `key` — the provider's opaque key reference
  - `eph` — the ephemeral P-256 public key, uncompressed (65 bytes)
  - `box` — AES-256-GCM nonce (12 bytes) ‖ ciphertext ‖ tag (16 bytes)

  Sealing generates an ephemeral P-256 key pair, runs ECDH with the
  recipient's public key and derives the AES key with
  HKDF-SHA256(shared secret, salt: `eph`, info: `"ktv2"`). The associated
  data is `"ktv2"` followed by the key reference, so an envelope cannot be
  re-pointed at another key. Opening asks the provider for the same shared
  secret.

  This module is the only schema instance of the format: nothing else
  builds or parses an envelope.

  ## Errors

  - `:unknown_format` — not a `ktv2` envelope (another prefix or plaintext)
  - `:malformed` — `ktv2` prefix, but the structure is broken
  - `:invalid` — well-formed, but authentication failed: wrong key or
    tampered envelope
  - `{:key_agreement, reason}` — the provider refused or failed
  """

  alias SealedEnvelope.HKDF

  @prefix "ktv2."
  @label "ktv2"
  @curve :secp256r1
  @nonce_bytes 12
  @tag_bytes 16

  @type provider :: {module(), keyword()}
  @type error :: :unknown_format | :malformed | :invalid | {:key_agreement, term()}

  @doc "Seal `plaintext` to the provider's recipient key. Needs no consent."
  @spec seal(binary(), provider()) :: {:ok, String.t()} | {:error, error()}
  def seal(plaintext, {module, opts}) when is_binary(plaintext) do
    with {:ok, ref, recipient} <- recipient(module, opts) do
      {eph, eph_private} = :crypto.generate_key(:ecdh, @curve)
      shared = :crypto.compute_key(:ecdh, recipient, eph_private, @curve)
      nonce = :crypto.strong_rand_bytes(@nonce_bytes)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(
          :aes_256_gcm,
          key(shared, eph),
          nonce,
          plaintext,
          aad(ref),
          true
        )

      {:ok, encode(ref, eph, nonce <> ciphertext <> tag)}
    end
  end

  @doc "Open an envelope; the provider decides whether to agree (and may ask the user)."
  @spec open(String.t(), provider()) :: {:ok, binary()} | {:error, error()}
  def open(envelope, {module, opts}) when is_binary(envelope) do
    with {:ok, ref, eph, box} <- decode(envelope),
         {:ok, shared} <- agree(module, ref, eph, opts) do
      decrypt(key(shared, eph), ref, box)
    end
  end

  @doc "Does `text` claim to be a `ktv2` envelope? Says nothing about its structure."
  @spec envelope?(String.t()) :: boolean()
  def envelope?(text) when is_binary(text), do: String.starts_with?(text, @prefix)

  @doc "Is `text` a structurally complete `ktv2` envelope? Opens nothing."
  @spec well_formed?(String.t()) :: boolean()
  def well_formed?(text) when is_binary(text), do: match?({:ok, _, _, _}, decode(text))

  defp recipient(module, opts) do
    case module.recipient(opts) do
      {:ok, ref, public} when is_binary(ref) and ref != "" ->
        if point?(public),
          do: {:ok, ref, public},
          else: {:error, {:key_agreement, :invalid_public_key}}

      {:ok, _ref, _public} ->
        {:error, {:key_agreement, :invalid_key_ref}}

      {:error, reason} ->
        {:error, {:key_agreement, reason}}
    end
  end

  defp agree(module, ref, eph, opts) do
    case module.agree(ref, eph, opts) do
      {:ok, shared} when is_binary(shared) -> {:ok, shared}
      {:error, reason} -> {:error, {:key_agreement, reason}}
    end
  end

  defp key(shared, eph), do: HKDF.derive(shared, eph, @label, 32)

  defp aad(ref), do: @label <> ref

  defp decrypt(key, ref, box) do
    <<nonce::binary-size(@nonce_bytes), rest::binary>> = box
    ciphertext = binary_part(rest, 0, byte_size(rest) - @tag_bytes)
    tag = binary_part(rest, byte_size(rest), -@tag_bytes)

    case :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, ciphertext, aad(ref), tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, :invalid}
    end
  end

  defp encode(ref, eph, box) do
    json =
      JSON.encode!(%{
        "key" => Base.encode64(ref),
        "eph" => Base.encode64(eph),
        "box" => Base.encode64(box)
      })

    @prefix <> Base.encode64(json)
  end

  defp decode(@prefix <> encoded) do
    with {:ok, json} <- Base.decode64(encoded),
         {:ok, %{"key" => key, "eph" => eph, "box" => box} = fields} when map_size(fields) == 3 <-
           JSON.decode(json),
         {:ok, ref} <- base64(key),
         {:ok, eph} <- base64(eph),
         {:ok, box} <- base64(box),
         true <- ref != "" and point?(eph) and byte_size(box) >= @nonce_bytes + @tag_bytes do
      {:ok, ref, eph, box}
    else
      _ -> {:error, :malformed}
    end
  end

  defp decode(_text), do: {:error, :unknown_format}

  defp base64(value) when is_binary(value), do: Base.decode64(value)
  defp base64(_value), do: :error

  # A valid uncompressed P-256 point. :crypto rejects points off the curve
  # when it computes with them, so a throwaway ECDH is the check; providers
  # rely on getting only valid points.
  defp point?(<<4, _::binary-size(64)>> = public) do
    {_, private} = :crypto.generate_key(:ecdh, @curve)
    _ = :crypto.compute_key(:ecdh, public, private, @curve)
    true
  rescue
    ErlangError -> false
  end

  defp point?(_public), do: false
end
