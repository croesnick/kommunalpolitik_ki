defmodule SealedEnvelope.HKDF do
  @moduledoc """
  HKDF with HMAC-SHA256 (RFC 5869). OTP's `:crypto` has HMAC but no HKDF;
  this is the same derivation CryptoKit's `hkdfDerivedSymmetricKey` performs.
  """

  @hash_bytes 32
  @max_length 255 * @hash_bytes

  @doc "Extract-then-expand: `length` bytes of key material from `ikm`."
  @spec derive(binary(), binary(), binary(), pos_integer()) :: binary()
  def derive(ikm, salt, info, length) when length in 1..@max_length//1 do
    prk = hmac(salt, ikm)
    blocks = div(length + @hash_bytes - 1, @hash_bytes)

    {okm, _last} =
      Enum.map_reduce(1..blocks, <<>>, fn counter, previous ->
        block = hmac(prk, [previous, info, counter])
        {block, block}
      end)

    okm |> IO.iodata_to_binary() |> binary_part(0, length)
  end

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)
end
