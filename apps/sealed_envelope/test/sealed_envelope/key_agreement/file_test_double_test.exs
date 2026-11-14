defmodule SealedEnvelope.KeyAgreement.FileTestDoubleTest do
  @moduledoc "The file-backed test double: key file creation, reuse and agreement."

  use ExUnit.Case, async: true

  alias SealedEnvelope.KeyAgreement.FileTestDouble

  @moduletag :tmp_dir

  test "recipient/1 creates a 0600 key file once and reuses it", %{tmp_dir: dir} do
    path = Path.join(dir, "key")

    assert {:ok, ref, public} = FileTestDouble.recipient(path: path)
    assert ref == public
    assert byte_size(public) == 65
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert {:ok, ^ref, ^public} = FileTestDouble.recipient(path: path)
  end

  test "agree/3 matches the ECDH the sealing side computes", %{tmp_dir: dir} do
    path = Path.join(dir, "key")
    {:ok, ref, public} = FileTestDouble.recipient(path: path)
    {eph, eph_private} = :crypto.generate_key(:ecdh, :secp256r1)

    assert {:ok, shared} = FileTestDouble.agree(ref, eph, path: path)
    assert shared == :crypto.compute_key(:ecdh, public, eph_private, :secp256r1)
    assert byte_size(shared) == 32
  end

  test "agree/3 never creates a key file", %{tmp_dir: dir} do
    path = Path.join(dir, "missing")
    {eph, _} = :crypto.generate_key(:ecdh, :secp256r1)

    assert {:error, :enoent} = FileTestDouble.agree("ref", eph, path: path)
    refute File.exists?(path)
  end

  test "a key file of the wrong size is rejected", %{tmp_dir: dir} do
    path = Path.join(dir, "key")
    File.write!(path, "short")

    assert {:error, :bad_key_file} = FileTestDouble.recipient(path: path)
  end
end
