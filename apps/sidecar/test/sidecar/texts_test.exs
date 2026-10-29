defmodule Sidecar.TextsTest do
  @moduledoc "The English default texts: every code has one, every kind a detail."

  use ExUnit.Case, async: true

  alias Sidecar.{Frame, Texts}

  test "describe/1 covers every error code exactly" do
    for code <- Frame.error_codes() -- ["internal"] do
      assert Texts.describe(code) == Texts.describe(code)
      refute Texts.describe(code) == "internal error"
    end
  end

  test "describe/1 falls back to internal for unknown codes" do
    assert Texts.describe("whatever") == "internal error"
  end

  test "transport/2 renders every kind" do
    kinds = [
      :no_token,
      :request_too_large,
      :connect_timeout,
      :connect_failed,
      :send_failed,
      :recv_timeout,
      :recv_failed,
      :bad_reply_frame,
      :reply_mismatch
    ]

    for kind <- kinds do
      assert is_binary(Texts.transport(kind, :some_reason))
    end
  end

  test "params_error/2 renders every kind" do
    kinds = [
      {:unknown_fields, %{names: ["b", "a"]}},
      {:not_object, %{}},
      {:missing_required, %{name: "text"}},
      {:invalid_utf8, %{name: "text"}},
      {:too_long, %{name: "text", max: 200}},
      {:blank, %{name: "text"}},
      {:bad_format, %{name: "text"}},
      {:out_of_range, %{name: "limit", min: 1, max: 20}},
      {:wrong_type, %{name: "limit", type: :integer}}
    ]

    for {kind, info} <- kinds do
      assert is_binary(Texts.params_error(kind, info))
    end

    assert Texts.params_error(:unknown_fields, %{names: ["b", "a"]}) ==
             "unknown fields: a, b"
  end
end
