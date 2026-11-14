defmodule Sidecar.Client do
  @moduledoc """
  Caller side of the frame protocol: one connection per call (connect,
  one request, one response, close). Default timeout 15 s.

  The sidecar's token is read from the file beside the socket on every
  call (`Sidecar.Token.for_socket/1`), so a restarted sidecar brings
  its new token without restarting the caller.

  A sidecar's error details never travel onward: the client replaces
  them with the fixed text of the code, rendered by `texts` (default
  `Sidecar.Texts`). Free text from the other side of the socket would
  otherwise be a channel straight into a caller's context.
  """

  alias Sidecar.{Frame, Texts, Token}

  @default_timeout 15_000

  @type reply :: {:ok, map()} | {:error, %{String.t() => String.t()}}

  @doc """
  Performs a call against the sidecar socket. Returns `{:ok, result}`
  or `{:error, %{"code" => ..., "detail" => ...}}` — transport failures
  are mapped onto the closed error codes.

  Options: `timeout:` (default 15 s), `texts:` (default `Sidecar.Texts`).
  """
  @spec call(Path.t(), String.t(), String.t(), map(), map(), keyword()) :: reply()
  def call(socket_path, call_id, op, params, context \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    texts = Keyword.get(opts, :texts, Texts)
    deadline = System.monotonic_time(:millisecond) + timeout

    with {:ok, sock} <- connect(socket_path, timeout, texts) do
      try do
        with {:ok, token} <- token(socket_path, texts),
             {:ok, frame} <- encode(Frame.request(token, call_id, op, params, context), texts) do
          exchange(sock, frame, call_id, texts, remaining(deadline))
        end
      after
        :gen_tcp.close(sock)
      end
    end
  end

  defp token(socket_path, texts) do
    case Token.read(Token.for_socket(socket_path)) do
      {:ok, token} -> {:ok, token}
      :error -> err("unauthorized", texts.transport(:no_token, nil))
    end
  end

  defp encode(map, texts) do
    case Frame.encode(map) do
      {:ok, bin} -> {:ok, bin}
      {:error, :too_large} -> err("too-large", texts.transport(:request_too_large, nil))
    end
  end

  defp connect(path, timeout, texts) do
    case :gen_tcp.connect({:local, String.to_charlist(path)}, 0, Frame.socket_opts(), timeout) do
      {:ok, sock} -> {:ok, sock}
      {:error, :timeout} -> err("upstream-timeout", texts.transport(:connect_timeout, :timeout))
      {:error, reason} -> err("upstream-error", texts.transport(:connect_failed, reason))
    end
  end

  defp exchange(sock, frame, call_id, texts, timeout) do
    with :ok <- send_frame(sock, frame, texts),
         {:ok, bin} <- recv(sock, timeout, texts),
         {:ok, reply} <- decode(bin, texts) do
      interpret(reply, call_id, texts)
    end
  end

  defp send_frame(sock, frame, texts) do
    case :gen_tcp.send(sock, frame) do
      :ok -> :ok
      {:error, reason} -> err("upstream-error", texts.transport(:send_failed, reason))
    end
  end

  defp recv(sock, timeout, texts) do
    case :gen_tcp.recv(sock, 0, max(timeout, 0)) do
      {:ok, bin} -> {:ok, bin}
      {:error, :timeout} -> err("upstream-timeout", texts.transport(:recv_timeout, :timeout))
      {:error, reason} -> err("upstream-error", texts.transport(:recv_failed, reason))
    end
  end

  defp decode(bin, texts) do
    case Frame.decode(bin) do
      {:ok, reply} -> {:ok, reply}
      {:error, :bad_frame} -> err("upstream-error", texts.transport(:bad_reply_frame, nil))
    end
  end

  # The reply must carry this call's own call_id; anything else cannot be
  # matched and is discarded (fail-closed).
  defp interpret(%{"call_id" => call_id, "ok" => true, "result" => result}, call_id, _texts)
       when is_map(result),
       do: {:ok, result}

  defp interpret(
         %{"call_id" => call_id, "ok" => false, "error" => %{"code" => code}},
         call_id,
         texts
       )
       when is_binary(code) do
    code = if code in Frame.error_codes(), do: code, else: "internal"
    {:error, %{"code" => code, "detail" => texts.describe(code)}}
  end

  # Rejection without token: the sidecar deliberately reports no call_id.
  defp interpret(
         %{"call_id" => "", "ok" => false, "error" => %{"code" => "unauthorized"}},
         _call_id,
         texts
       ),
       do: err("unauthorized", texts.describe("unauthorized"))

  defp interpret(_reply, _call_id, texts),
    do: err("upstream-error", texts.transport(:reply_mismatch, nil))

  defp remaining(deadline), do: deadline - System.monotonic_time(:millisecond)

  defp err(code, detail), do: {:error, %{"code" => code, "detail" => detail}}
end
