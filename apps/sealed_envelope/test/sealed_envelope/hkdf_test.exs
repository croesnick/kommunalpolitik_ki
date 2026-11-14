defmodule SealedEnvelope.HKDFTest do
  @moduledoc "RFC 5869, appendix A: the SHA-256 test cases."

  use ExUnit.Case, async: true

  alias SealedEnvelope.HKDF

  test "test case 1: basic" do
    okm =
      HKDF.derive(
        h("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"),
        h("000102030405060708090a0b0c"),
        h("f0f1f2f3f4f5f6f7f8f9"),
        42
      )

    assert okm ==
             h(
               "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
             )
  end

  test "test case 3: empty salt and info" do
    okm = HKDF.derive(h("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), "", "", 42)

    assert okm ==
             h(
               "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"
             )
  end

  test "exact block multiples and short outputs" do
    assert byte_size(HKDF.derive("ikm", "salt", "info", 32)) == 32
    assert byte_size(HKDF.derive("ikm", "salt", "info", 64)) == 64
    assert byte_size(HKDF.derive("ikm", "salt", "info", 1)) == 1

    assert binary_part(HKDF.derive("ikm", "salt", "info", 64), 0, 32) ==
             HKDF.derive("ikm", "salt", "info", 32)
  end

  defp h(hex), do: Base.decode16!(hex, case: :lower)
end
