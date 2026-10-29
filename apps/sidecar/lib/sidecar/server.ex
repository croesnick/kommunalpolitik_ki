defmodule Sidecar.Server do
  @moduledoc """
  Sidecar side of the frame protocol.

  A sidecar implements the behaviour and calls `run/5` from its entry
  point:

      {:ok, creds} = Sidecar.Server.read_credentials()
      Sidecar.Server.run(MySidecar, socket_path, init_arg, creds,
        credential_key: "MY_SIDECAR_TOKEN"
      )

  `run/5` binds the Unix socket (file `0600` afterwards) and serves
  exactly one request per connection. Every request must carry the
  token from the stdin credentials under `credential_key:` — without a
  valid token the sidecar refuses to start, and a request without the
  matching token gets `unauthorized`, before `ping`. The reserved
  operation `ping` is answered by the server itself, from the manifest.
  Parameters are validated against the manifest schema before
  `handle_op/4` runs — a sidecar never sees unchecked arguments.

  Transport is the `:socket` module with manual length-prefix framing
  (the caller side stays on `gen_tcp`); this is what makes the optional
  peer-uid check possible (`Sidecar.Peer`, option `peer_credentials:`).

  Options:

  - `credential_key:` (default `"SIDECAR_TOKEN"`) — the stdin key that
    holds the capability token.
  - `peer_credentials:` (default `false`) — `true` rejects connections
    whose peer uid is not the sidecar's own; an integer rejects
    connections whose peer uid is not that value. Where the platform
    cannot report peer credentials the check is disabled with a warning.
  """

  require Logger

  alias Sidecar.{Frame, Params, Peer, Token}

  @recv_timeout 15_000
  @default_credential_key "SIDECAR_TOKEN"

  @typedoc """
  One operation of the manifest. `params` is the closed schema the
  server validates against; other keys flow through untouched.
  """
  @type op_spec :: %{required(:params) => Params.schema(), optional(atom()) => term()}

  @typedoc """
  The sidecar's manifest as data: a `fassung` label and the operations
  with their schemas. Hosts pass their own (richer) manifest maps —
  this library reads only what it names here.
  """
  @type manifest :: %{
          required(:fassung) => String.t(),
          required(:ops) => %{(op :: String.t()) => op_spec()},
          optional(atom()) => term()
        }

  @doc "The sidecar's manifest (data, not an id)."
  @callback manifest() :: manifest()

  @doc "Builds the state from the init argument (credentials, options)."
  @callback init(term()) :: {:ok, term()} | {:error, String.t()}

  @doc "Executes one validated operation."
  @callback handle_op(op :: String.t(), params :: map(), context :: map(), state :: term()) ::
              {:ok, map()} | {:error, String.t(), String.t()}

  @doc """
  Reads exactly one JSON line of credentials from stdin. Empty input
  gives `%{}`. Values must be strings.
  """
  @spec read_credentials(IO.device()) :: {:ok, %{String.t() => String.t()}} | {:error, String.t()}
  def read_credentials(device \\ :stdio) do
    case IO.read(device, :eof) do
      :eof -> {:ok, %{}}
      {:error, reason} -> {:error, "stdin: #{inspect(reason)}"}
      data -> parse_credentials(String.trim(IO.iodata_to_binary(data)))
    end
  end

  defp parse_credentials(""), do: {:ok, %{}}

  defp parse_credentials(line) do
    case safe_json(line) do
      {:ok, map} when is_map(map) -> string_map(map)
      _ -> {:error, "credentials are not a JSON object"}
    end
  end

  defp string_map(map) do
    if Enum.all?(map, fn {k, v} -> is_binary(k) and is_binary(v) end),
      do: {:ok, map},
      else: {:error, "credential values must be strings"}
  end

  defp safe_json(line) do
    {:ok, :json.decode(line)}
  rescue
    _ -> :error
  end

  @doc """
  Binds the socket and serves requests until the process ends. `creds`
  is the stdin line from `read_credentials/1`; its token entry under
  `credential_key:` is mandatory (fail-closed).
  """
  @spec run(module(), Path.t(), term(), %{String.t() => String.t()}, keyword()) ::
          no_return() | {:error, :invalid_token | String.t() | term()}
  def run(module, socket_path, init_arg, creds, opts \\ []) do
    credential_key = Keyword.get(opts, :credential_key, @default_credential_key)

    with {:ok, token} <- fetch_token(creds, credential_key),
         {:ok, peer} <- peer_config(opts),
         {:ok, state} <- module.init(init_arg),
         {:ok, listener} <- listen(socket_path) do
      peer = expected_uid(peer, socket_path)
      manifest = module.manifest()
      Logger.info("sidecar #{manifest.fassung} listening on #{socket_path}")
      accept_loop(listener, module, state, token, peer: peer)
    end
  end

  @doc "The token from the stdin credentials; no valid token, no start."
  @spec fetch_token(map(), String.t()) :: {:ok, String.t()} | {:error, :invalid_token}
  def fetch_token(creds, credential_key) do
    token = Map.get(creds, credential_key)

    if Token.valid?(token), do: {:ok, token}, else: {:error, :invalid_token}
  end

  @doc """
  Binds the socket (a stale file is removed first) and restricts the
  socket file to `0600`.
  """
  @spec listen(Path.t()) :: {:ok, :socket.socket()} | {:error, term()}
  def listen(socket_path) do
    _ = File.rm(socket_path)

    with {:ok, listener} <- :socket.open(:local, :stream, :default),
         :ok <- :socket.bind(listener, %{family: :local, path: socket_path}),
         :ok <- :socket.listen(listener),
         :ok <- File.chmod(socket_path, 0o600) do
      {:ok, listener}
    end
  end

  @doc "Accept loop: one process per connection, one request each."
  @spec accept_loop(:socket.socket(), module(), term(), String.t(), keyword()) :: no_return()
  def accept_loop(listener, module, state, token, opts \\ []) do
    peer = Keyword.get(opts, :peer, false)

    case :socket.accept(listener) do
      {:ok, sock} ->
        hand_over(sock, fn -> serve(sock, module, state, token, peer) end)
        accept_loop(listener, module, state, token, peer: peer)

      {:error, :closed} ->
        exit(:normal)

      {:error, reason} ->
        Logger.error("accept failed: #{inspect(reason)}")
        accept_loop(listener, module, state, token, peer: peer)
    end
  end

  # The accepted socket belongs to this process. The serving process
  # waits until it owns the socket, so the socket's lifetime follows it
  # from the first byte on — a crash in serve/5 closes the connection.
  defp hand_over(sock, fun) do
    {:ok, pid} = Task.start(fn -> receive(do: (:handed_over -> fun.())) end)

    case :socket.setopt(sock, {:otp, :controlling_process}, pid) do
      :ok ->
        send(pid, :handed_over)

      {:error, reason} ->
        Logger.error("socket handover failed: #{inspect(reason)}")
        Process.exit(pid, :kill)
        :socket.close(sock)
    end
  end

  @doc "Serves one connection: peer check, read request, reply, close."
  @spec serve(:socket.socket(), module(), term(), String.t(), false | non_neg_integer()) :: :ok
  def serve(sock, module, state, token, peer \\ false) do
    case peer_check(sock, peer) do
      :ok ->
        started = System.monotonic_time(:millisecond)
        reply = request(sock, module, state, token, started)
        send_reply(sock, reply)
        :socket.close(sock)

      {:error, reason} ->
        # Before any read: a caller that cannot be verified learns
        # nothing, not even whether a sidecar is listening.
        Logger.warning("connection rejected: #{inspect(reason)}")
        :socket.close(sock)
    end
  end

  defp peer_check(_sock, false), do: :ok

  defp peer_check(sock, expected_uid) do
    case Peer.check(sock, expected_uid) do
      :ok -> :ok
      {:error, {:uid_mismatch, got, expected}} -> {:error, {:peer_uid_mismatch, got, expected}}
      {:error, reason} -> {:error, {:peer_uid_unreadable, reason}}
    end
  end

  defp request(sock, module, state, token, started) do
    deadline = started + @recv_timeout

    case recv_frame(sock, deadline) do
      {:ok, bin} ->
        reply = handle_frame(bin, module, state, token)
        log(module, reply, started)
        reply

      # No reply for malformed transports: the caller's own timeout
      # reports the failure, never a half-written frame.
      {:error, _reason} ->
        nil
    end
  end

  # Manual framing: 4 bytes of big-endian length, then exactly that many
  # bytes of JSON. Oversized declarations close the connection — the
  # same limit `packet_size` enforces for `gen_tcp` callers.
  defp recv_frame(sock, deadline) do
    with {:ok, <<len::big-32>>} <- recv(sock, 4, deadline),
         :ok <- check_length(len) do
      recv(sock, len, deadline)
    end
  end

  defp check_length(len) do
    if len >= 1 and len <= Frame.max_bytes(), do: :ok, else: {:error, {:oversized_frame, len}}
  end

  defp recv(sock, length, deadline) do
    :socket.recv(sock, length, max(deadline - System.monotonic_time(:millisecond), 0))
  end

  defp send_reply(_sock, nil), do: :ok

  defp send_reply(sock, reply) do
    bin =
      case Frame.encode(reply) do
        {:ok, bin} ->
          bin

        {:error, :too_large} ->
          {:ok, bin} =
            Frame.encode(Frame.error(reply["call_id"], "too-large", "reply exceeds 1 MiB"))

          bin
      end

    # Log first, then send: once the caller has the reply, the log line
    # is already written.
    _ = :socket.send(sock, <<byte_size(bin)::big-32, bin::binary>>)
    :ok
  end

  @doc false
  # Public for tests: one frame (binary) to the reply map.
  @spec handle_frame(binary(), module(), term(), String.t()) :: map()
  def handle_frame(bin, module, state, token) do
    with {:ok, frame} <- Frame.decode(bin),
         :ok <- authorize(frame, token),
         {:ok, call_id, op, params, context} <- shape(frame) do
      dispatch(module, call_id, op, params, context, state)
    else
      {:error, :bad_frame} -> Frame.error("", "bad-request", "invalid frame")
      {:error, :unauthorized} -> Frame.error("", "unauthorized", "token missing or mismatched")
      {:error, call_id, detail} -> Frame.error(call_id, "bad-request", detail)
    end
  end

  # Before everything else, including ping: without a token the caller
  # learns nothing about the sidecar, not even the call_id it sent.
  defp authorize(frame, token) do
    if Token.equal?(frame["token"], token) do
      :ok
    else
      Logger.warning("request without a valid token rejected")
      {:error, :unauthorized}
    end
  end

  defp shape(%{"call_id" => call_id, "op" => op, "params" => params} = frame)
       when is_binary(call_id) and is_binary(op) and is_map(params) do
    case Map.get(frame, "context", %{}) do
      context when is_map(context) -> {:ok, call_id, op, params, context}
      _ -> {:error, call_id, "context must be an object"}
    end
  end

  defp shape(frame), do: {:error, to_string(frame["call_id"] || ""), "frame fields missing"}

  defp dispatch(module, call_id, "ping", _params, _context, _state) do
    manifest = module.manifest()

    Frame.ok(call_id, %{"fassung" => manifest.fassung, "ops" => Enum.sort(Map.keys(manifest.ops))})
  end

  defp dispatch(module, call_id, op, params, context, state) do
    manifest = module.manifest()

    with {:ok, spec} <- fetch_op(manifest, op),
         {:ok, checked} <- Params.check(spec.params, params) do
      run_op(module, call_id, op, checked, context, state)
    else
      {:error, :unknown_op} -> Frame.error(call_id, "unknown-op", "unknown operation: #{op}")
      {:error, {:params, detail}} -> Frame.error(call_id, "bad-request", detail)
    end
  end

  defp fetch_op(manifest, op) do
    case Map.fetch(manifest.ops, op) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, :unknown_op}
    end
  end

  defp run_op(module, call_id, op, params, context, state) do
    case module.handle_op(op, params, context, state) do
      {:ok, result} when is_map(result) -> Frame.ok(call_id, result)
      {:error, code, detail} -> Frame.error(call_id, code, detail)
    end
  rescue
    e ->
      # Only the exception type: a message can carry values from the
      # request (a MatchError prints its arguments).
      Logger.error("handle_op #{op} crashed: #{inspect(e.__struct__)}")
      Frame.error(call_id, "internal", "internal error")
  end

  # Log without payload: the operation (not derivable from call_id), the
  # outcome, the duration. A failed operation's own detail text lives
  # here and nowhere else — the client does not forward it.
  defp log(module, reply, started) do
    ms = System.monotonic_time(:millisecond) - started

    outcome =
      if reply["ok"],
        do: "ok",
        else: get_in(reply, ["error", "code"]) <> " detail=" <> inspect(reply["error"]["detail"])

    Logger.info(
      "sidecar=#{module.manifest().fassung} call=#{reply["call_id"]} outcome=#{outcome} ms=#{ms}"
    )
  end

  # Validates the peer_credentials option before anything is bound:
  # false (off), :own (the sidecar's own uid), or an explicit uid.
  defp peer_config(opts) do
    case Keyword.get(opts, :peer_credentials, false) do
      false ->
        {:ok, false}

      true ->
        if Peer.supported?() do
          {:ok, :own}
        else
          Logger.warning("peer credentials unavailable on this platform; check disabled")
          {:ok, false}
        end

      uid when is_integer(uid) and uid >= 0 ->
        {:ok, uid}

      other ->
        {:error, {:invalid_peer_credentials, other}}
    end
  end

  # The sidecar's own uid is the owner of the socket file it just created.
  defp expected_uid(:own, socket_path), do: File.stat!(socket_path).uid
  defp expected_uid(peer, _socket_path), do: peer
end
