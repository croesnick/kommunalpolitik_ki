defmodule Sidecar.Frame do
  @moduledoc """
  Frame protocol v1: 4 bytes of big-endian length followed by UTF-8 JSON,
  at most 1 MiB per frame.

  These functions encode and decode only the JSON part; the length prefix
  itself is written by the transport — `packet: 4` on the caller's
  `gen_tcp` socket, or manual framing on the server's `:socket`.
  """

  @version 1
  @max_bytes 1_048_576

  @error_codes ~w(bad-request unknown-op not-found upstream-error upstream-timeout
                  credential-missing forbidden-path too-large unauthorized internal)

  @doc "Protocol version."
  @spec version() :: pos_integer()
  def version, do: @version

  @doc "Largest allowed frame length in bytes."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The closed set of error codes."
  @spec error_codes() :: [String.t()]
  def error_codes, do: @error_codes

  @doc """
  Socket options for the caller side (`gen_tcp`): the length prefix plus
  the size limit are enforced by the inet driver.
  """
  @spec socket_opts() :: list()
  def socket_opts, do: [:binary, packet: 4, packet_size: @max_bytes, active: false]

  @doc "Builds a request frame; `token` is the sidecar's capability token."
  @spec request(String.t(), String.t(), String.t(), map(), map()) :: map()
  def request(token, call_id, op, params, context \\ %{}) do
    base = %{
      "v" => @version,
      "token" => token,
      "call_id" => call_id,
      "op" => op,
      "params" => params
    }

    if context == %{}, do: base, else: Map.put(base, "context", context)
  end

  @doc "Builds a success reply."
  @spec ok(String.t(), map()) :: map()
  def ok(call_id, result),
    do: %{"v" => @version, "call_id" => call_id, "ok" => true, "result" => result}

  @doc "Builds an error reply; unknown codes collapse to `internal`."
  @spec error(String.t(), String.t(), String.t()) :: map()
  def error(call_id, code, detail) do
    code = if code in @error_codes, do: code, else: "internal"

    %{
      "v" => @version,
      "call_id" => call_id,
      "ok" => false,
      "error" => %{"code" => code, "detail" => detail}
    }
  end

  @doc "JSON-encodes a frame."
  @spec encode(map()) :: {:ok, binary()} | {:error, :too_large}
  def encode(map) do
    bin = map |> :json.encode() |> IO.iodata_to_binary()
    if byte_size(bin) > @max_bytes, do: {:error, :too_large}, else: {:ok, bin}
  end

  @doc """
  JSON-decodes a frame. Requires an object with `"v" == 1`; anything else
  is `{:error, :bad_frame}`.
  """
  @spec decode(binary()) :: {:ok, map()} | {:error, :bad_frame}
  def decode(bin) when is_binary(bin) do
    case safe_decode(bin) do
      {:ok, %{"v" => @version} = map} -> {:ok, map}
      _ -> {:error, :bad_frame}
    end
  end

  defp safe_decode(bin) do
    {:ok, :json.decode(bin)}
  rescue
    _ -> {:error, :bad_frame}
  end
end
