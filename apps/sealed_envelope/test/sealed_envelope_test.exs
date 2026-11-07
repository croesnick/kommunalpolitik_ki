defmodule SealedEnvelopeTest do
  @moduledoc "Seal and open through the file test double; every way an envelope can fail."

  use ExUnit.Case, async: true

  alias SealedEnvelope.KeyAgreement.FileTestDouble

  defmodule Refusing do
    @moduledoc false
    @behaviour SealedEnvelope.KeyAgreement

    @impl true
    def recipient(opts), do: Keyword.fetch!(opts, :recipient)

    @impl true
    def agree(_ref, _peer, _opts), do: {:error, :refused}
  end

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    %{provider: {FileTestDouble, path: Path.join(dir, "key")}, dir: dir}
  end

  describe "roundtrip" do
    test "opens what it sealed", %{provider: provider} do
      for plaintext <- ["api-key-123", "", <<0, 255, 10, 13>>, String.duplicate("x", 100_000)] do
        assert {:ok, envelope} = SealedEnvelope.seal(plaintext, provider)
        assert {:ok, ^plaintext} = SealedEnvelope.open(envelope, provider)
      end
    end

    test "an envelope is one line of ASCII with the ktv2 prefix", %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("line\nbreak", provider)

      assert "ktv2." <> _ = envelope
      refute envelope =~ ~r/[^\x21-\x7e]/
      assert SealedEnvelope.well_formed?(envelope)
    end

    test "sealing twice gives different envelopes", %{provider: provider} do
      {:ok, a} = SealedEnvelope.seal("same", provider)
      {:ok, b} = SealedEnvelope.seal("same", provider)

      refute a == b
    end
  end

  describe "wrong key and tampering" do
    test "another key cannot open it", %{provider: provider, dir: dir} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)
      other = {FileTestDouble, path: Path.join(dir, "other-key")}
      {:ok, _} = SealedEnvelope.seal("init", other)

      assert {:error, :invalid} = SealedEnvelope.open(envelope, other)
    end

    test "a flipped bit in the box fails authentication", %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)

      tampered =
        update(envelope, "box", fn <<head::binary-size(20), byte, rest::binary>> ->
          <<head::binary, Bitwise.bxor(byte, 1), rest::binary>>
        end)

      assert {:error, :invalid} = SealedEnvelope.open(tampered, provider)
    end

    test "the key reference is bound to the ciphertext", %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)
      tampered = update(envelope, "key", &(&1 <> "x"))

      assert {:error, :invalid} = SealedEnvelope.open(tampered, provider)
    end

    test "another valid ephemeral key fails authentication", %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)
      {other_eph, _} = :crypto.generate_key(:ecdh, :secp256r1)
      tampered = update(envelope, "eph", fn _ -> other_eph end)

      assert {:error, :invalid} = SealedEnvelope.open(tampered, provider)
    end
  end

  describe "format" do
    test "another prefix or plaintext is an unknown format", %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)
      "ktv2." <> body = envelope

      for text <- ["ktv1." <> body, "ktv3." <> body, body, "plaintext", ""] do
        assert {:error, :unknown_format} = SealedEnvelope.open(text, provider)
        refute SealedEnvelope.well_formed?(text)
      end
    end

    test "missing, extra or mistyped fields are malformed", %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)
      fields = fields(envelope)

      broken = [
        Map.delete(fields, "key"),
        Map.delete(fields, "eph"),
        Map.delete(fields, "box"),
        Map.put(fields, "v", "2"),
        Map.put(fields, "key", 42),
        Map.put(fields, "box", "not base64!"),
        Map.put(fields, "key", "")
      ]

      variants = Enum.map(broken, &("ktv2." <> Base.encode64(JSON.encode!(&1))))

      for text <- variants ++ ["ktv2.", "ktv2.not-base64", "ktv2." <> Base.encode64("[]")] do
        assert {:error, :malformed} = SealedEnvelope.open(text, provider), text
        refute SealedEnvelope.well_formed?(text)
      end
    end

    test "an ephemeral key off the curve is malformed, not passed to the provider",
         %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)

      for eph <- [<<4, 1::512>>, <<4, 0::512>>, <<2, 1::256>>, <<1, 2, 3>>] do
        tampered = update(envelope, "eph", fn _ -> eph end)
        assert {:error, :malformed} = SealedEnvelope.open(tampered, {Refusing, []})
      end
    end

    test "a box shorter than nonce and tag is malformed", %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)
      tampered = update(envelope, "box", &binary_part(&1, 0, 27))

      assert {:error, :malformed} = SealedEnvelope.open(tampered, provider)
    end
  end

  describe "provider" do
    test "a refusal comes back wrapped", %{provider: provider} do
      {:ok, envelope} = SealedEnvelope.seal("secret", provider)

      assert {:error, {:key_agreement, :refused}} = SealedEnvelope.open(envelope, {Refusing, []})
    end

    test "seal rejects a bad recipient" do
      {pub, _} = :crypto.generate_key(:ecdh, :secp256r1)

      for {recipient, reason} <- [
            {{:error, :no_enclave}, :no_enclave},
            {{:ok, "ref", <<4, 1::512>>}, :invalid_public_key},
            {{:ok, "", pub}, :invalid_key_ref}
          ] do
        assert {:error, {:key_agreement, ^reason}} =
                 SealedEnvelope.seal("secret", {Refusing, recipient: recipient})
      end
    end
  end

  defp fields("ktv2." <> encoded), do: encoded |> Base.decode64!() |> JSON.decode!()

  defp update(envelope, field, fun) do
    fields = fields(envelope)
    value = fields |> Map.fetch!(field) |> Base.decode64!() |> fun.() |> Base.encode64()
    "ktv2." <> Base.encode64(JSON.encode!(Map.put(fields, field, value)))
  end
end
