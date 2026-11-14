defmodule Sidecar.Peer do
  @moduledoc """
  Optional peer-credential check: the caller's peer uid must match the
  sidecar's own — defense in depth on top of the capability token,
  against processes of *other* users reaching a socket whose file or
  directory permissions have been loosened. It cannot tell processes of
  the same uid apart; against those, only the token helps.

  Verified against a C reference on macOS (Darwin 27, OTP 29.1.2):
  `:socket.getopt_native/3` returns the kernel's credential structure
  only with a **raw integer level**. The `:socket` atom resolves through
  the NIF's option table, where `LOCAL_PEERCRED`'s number (`0x001`)
  collides with `SO_DEBUG` and yields four zero bytes instead of a
  credential.
  """

  # {level, option, byte size, uid offset} — the uid is a little-endian
  # 32-bit integer inside the kernel's credential structure.
  #   darwin: SOL_SOCKET (0), LOCAL_PEERCRED (0x001), struct xucred (76 bytes)
  #   linux:  SOL_SOCKET (1), SO_PEERCRED (17),    struct ucred (12 bytes)
  @cred_specs %{
    darwin: {0, 0x001, 76, 4},
    linux: {1, 17, 12, 4}
  }

  @doc "Can this platform report peer credentials at all?"
  @spec supported?() :: boolean()
  def supported? do
    match?({:unix, os} when os in [:darwin, :linux], :os.type())
  end

  @doc """
  The calling peer's uid of an accepted sidecar socket.
  `{:error, :unsupported}` where the platform cannot report it.
  """
  @spec peer_uid(:socket.socket()) ::
          {:ok, non_neg_integer()} | {:error, :unsupported | :short_cred | term()}
  def peer_uid(sock) do
    case cred_spec() do
      {level, option, size, offset} ->
        case :socket.getopt_native(sock, {level, option}, size) do
          {:ok, bin} when byte_size(bin) >= offset + 4 ->
            {:ok, bin |> :binary.part(offset, 4) |> :binary.decode_unsigned(:little)}

          {:ok, _bin} ->
            {:error, :short_cred}

          {:error, reason} ->
            {:error, reason}
        end

      nil ->
        {:error, :unsupported}
    end
  end

  @doc """
  Checks an accepted socket against `expected_uid`. `:ok` on a match;
  `{:error, {:uid_mismatch, got, expected}}` when the peer is someone
  else, or the raw `getopt` error when the credentials cannot be read.
  """
  @spec check(:socket.socket(), non_neg_integer()) ::
          :ok | {:error, {:uid_mismatch, non_neg_integer(), non_neg_integer()} | term()}
  def check(sock, expected_uid) do
    case peer_uid(sock) do
      {:ok, ^expected_uid} -> :ok
      {:ok, other} -> {:error, {:uid_mismatch, other, expected_uid}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cred_spec do
    case :os.type() do
      {:unix, os} -> Map.get(@cred_specs, os)
      _ -> nil
    end
  end
end
