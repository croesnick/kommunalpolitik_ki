defmodule Sidecar.Texts do
  @moduledoc """
  Every text a caller may surface to its own users, in one injectable
  behaviour: the fixed text per error code, the details of transport
  failures, and parameter-validation errors.

  A sidecar's own error details never cross the socket — the client
  replaces them with the fixed text of the code (`describe/1`). The
  remaining strings this library produces for callers are the transport
  details and the parameter errors. Hosts with their own user-facing
  language implement this behaviour and pass their module via the
  `texts:` option of `Sidecar.Client.call/6` and `Sidecar.Params.check/3`.

  This module is also the default implementation, in English.
  """

  @doc """
  The fixed text for an error code — the only detail a caller's error
  map carries, and the only thing a caller learns about a failure it
  did not cause itself.
  """
  @callback describe(code :: String.t()) :: String.t()

  @doc """
  Detail for a transport failure on the caller side. `kind` is one of
  `:no_token | :request_too_large | :connect_timeout | :connect_failed |
  :send_failed | :recv_timeout | :recv_failed | :bad_reply_frame |
  :reply_mismatch`; `reason` is the transport's error term where one
  exists.
  """
  @callback transport(kind :: atom(), reason :: term()) :: String.t()

  @doc """
  Detail for a parameter-schema violation. `kind` is one of
  `:unknown_fields | :not_object | :missing_required | :invalid_utf8 |
  :too_long | :blank | :bad_format | :out_of_range | :wrong_type`;
  `info` carries the pieces of the message (`name`, `names`, `max`,
  `min`, `type` as applicable).
  """
  @callback params_error(kind :: atom(), info :: map()) :: String.t()

  @doc "Fixed text per error code."
  @spec describe(String.t()) :: String.t()
  def describe("bad-request"), do: "invalid request"
  def describe("unknown-op"), do: "unknown operation"
  def describe("not-found"), do: "not found"
  def describe("upstream-error"), do: "upstream service error"
  def describe("upstream-timeout"), do: "upstream service did not respond"
  def describe("credential-missing"), do: "credentials missing"
  def describe("forbidden-path"), do: "path not allowed"
  def describe("too-large"), do: "request or response too large"
  def describe("unauthorized"), do: "call not authorized"
  def describe(_code), do: "internal error"

  @doc "Detail for a transport failure on the caller side."
  @spec transport(atom(), term()) :: String.t()
  def transport(:no_token, _reason), do: "sidecar token missing"
  def transport(:request_too_large, _reason), do: "request exceeds 1 MiB"
  def transport(:connect_timeout, _reason), do: "sidecar did not respond"

  def transport(:connect_failed, reason),
    do: "sidecar unreachable: #{inspect(reason)}"

  def transport(:send_failed, reason),
    do: "send failed: #{inspect(reason)}"

  def transport(:recv_timeout, _reason), do: "no reply from sidecar within timeout"
  def transport(:recv_failed, reason), do: "receive failed: #{inspect(reason)}"

  def transport(:bad_reply_frame, _reason),
    do: "invalid reply frame"

  def transport(:reply_mismatch, _reason),
    do: "reply does not match the request"

  @doc "Detail for a parameter-schema violation."
  @spec params_error(atom(), map()) :: String.t()
  def params_error(:unknown_fields, %{names: names}),
    do: "unknown fields: #{Enum.join(Enum.sort(names), ", ")}"

  def params_error(:not_object, _info), do: "parameters must be an object"

  def params_error(:missing_required, %{name: name}),
    do: "required field missing: #{name}"

  def params_error(:invalid_utf8, %{name: name}),
    do: "#{name}: not valid UTF-8"

  def params_error(:too_long, %{name: name, max: max}),
    do: "#{name}: longer than #{max} characters"

  def params_error(:blank, %{name: name}), do: "#{name}: empty"

  def params_error(:bad_format, %{name: name}),
    do: "#{name}: invalid format"

  def params_error(:out_of_range, %{name: name, min: min, max: max}),
    do: "#{name}: outside #{min}..#{max}"

  def params_error(:wrong_type, %{name: name, type: type}),
    do: "#{name}: expected #{type}"
end
