defmodule Sidecar.Token do
  @moduledoc """
  Capability tokens, one per sidecar start.

  A `0600` Unix socket is unreachable for a sandboxed process, but that
  alone trusts every other process of the same uid. So every request
  carries a token that the sidecar's starter generates before launch:
  the sidecar receives it over stdin (under a key the starter chooses),
  the caller reads it from the `0600` file beside the socket
  (`for_socket/1`). Comparison is constant time. The token never
  appears in argv, the environment, logs, or replies.
  """

  @bytes 32

  @doc "A fresh token: 32 bytes of randomness as hex."
  @spec generate() :: String.t()
  def generate, do: Base.encode16(:crypto.strong_rand_bytes(@bytes), case: :lower)

  @doc "Token file of sidecar `id` inside `dir`."
  @spec path(Path.t(), String.t()) :: Path.t()
  def path(connectors_dir, id), do: Path.join(connectors_dir, id <> ".token")

  @doc "Token file beside the sidecar socket `<dir>/<id>.sock`: `<dir>/<id>.token`."
  @spec for_socket(Path.t()) :: Path.t()
  def for_socket(socket_path), do: Path.rootname(socket_path) <> ".token"

  @doc "Write the token with mode `0600` (created empty first, then filled)."
  @spec write!(Path.t(), String.t()) :: :ok
  def write!(path, token) do
    _ = File.rm(path)
    File.write!(path, "", [:exclusive])
    File.chmod!(path, 0o600)
    File.write!(path, token)
  end

  @doc "Generate a fresh token for the sidecar at `socket_path` and store it."
  @spec provision!(Path.t()) :: String.t()
  def provision!(socket_path) do
    token = generate()
    write!(for_socket(socket_path), token)
    token
  end

  @doc "Read the token; `:error` if the file is missing or holds no token."
  @spec read(Path.t()) :: {:ok, String.t()} | :error
  def read(path) do
    case File.read(path) do
      {:ok, token} -> if valid?(token), do: {:ok, token}, else: :error
      {:error, _} -> :error
    end
  end

  @doc "A formally valid token (64 hex characters)?"
  @spec valid?(term()) :: boolean()
  def valid?(token), do: is_binary(token) and token =~ ~r/\A[0-9a-f]{64}\z/

  @doc "Constant-time comparison; invalid values are never equal."
  @spec equal?(term(), String.t()) :: boolean()
  def equal?(given, expected) do
    valid?(given) and valid?(expected) and :crypto.hash_equals(given, expected)
  end
end
