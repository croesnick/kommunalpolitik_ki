defmodule SealedEnvelope.KeyAgreement.FileTestDouble do
  @moduledoc """
  TEST DOUBLE — not for real secrets. Keeps the P-256 private key in a plain
  file, so anyone who can read that file can open every envelope sealed to
  it. It exists so tests and agents can seal and open without hardware and
  without a consent prompt.

  Options:

  - `:path` (required) — the key file. `recipient/1` creates it with mode
    `0600` when it does not exist yet; `agree/3` only reads it.

  The key reference is the public key itself; it carries no secret.
  """

  @behaviour SealedEnvelope.KeyAgreement

  @curve :secp256r1

  @impl true
  def recipient(opts) do
    path = Keyword.fetch!(opts, :path)

    with {:ok, private} <- load_or_create(path) do
      {public, _} = :crypto.generate_key(:ecdh, @curve, private)
      {:ok, public, public}
    end
  end

  @impl true
  def agree(_key_ref, peer_public, opts) do
    with {:ok, private} <- load(Keyword.fetch!(opts, :path)) do
      {:ok, :crypto.compute_key(:ecdh, peer_public, private, @curve)}
    end
  end

  defp load_or_create(path) do
    case load(path) do
      {:error, :enoent} -> create(path)
      result -> result
    end
  end

  defp load(path) do
    case File.read(path) do
      {:ok, <<private::binary-size(32)>>} -> {:ok, private}
      {:ok, _other} -> {:error, :bad_key_file}
      {:error, reason} -> {:error, reason}
    end
  end

  # Exclusive create, then restrict the mode before the key is written.
  defp create(path) do
    {_, private} = :crypto.generate_key(:ecdh, @curve)

    with {:ok, io} <- File.open(path, [:write, :exclusive, :binary]) do
      try do
        with :ok <- File.chmod(path, 0o600), :ok <- IO.binwrite(io, private) do
          {:ok, private}
        end
      after
        File.close(io)
      end
    end
  end
end
