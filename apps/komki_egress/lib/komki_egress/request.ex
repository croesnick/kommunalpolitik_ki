defmodule KomkiEgress.Request do
  @moduledoc """
  Liest und parst den Request-Kopf einer Client-Verbindung.

  Erlaubt ist nur `CONNECT host:port HTTP/1.x`. Weitere Kopfzeilen werden
  ignoriert. Der Kopf ist in der Größe begrenzt und muss innerhalb einer
  Frist vollständig sein; Bytes, die der Client schon nach dem Kopf
  geschickt hat (z. B. ein früher TLS-ClientHello), kommen als `rest`
  zurück und werden später durchgereicht.
  """

  alias KomkiEgress.Target

  @terminator "\r\n\r\n"

  @type read_error :: :header_too_large | :header_timeout | :closed

  @doc """
  Liest vom passiven Socket, bis der Kopf mit einer Leerzeile endet.
  Gibt `{:ok, kopf, rest}` zurück.
  """
  @spec read_head(:gen_tcp.socket(), pos_integer(), pos_integer()) ::
          {:ok, binary(), binary()} | {:error, read_error()}
  def read_head(socket, max_bytes, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    read_loop(socket, "", max_bytes, deadline)
  end

  defp read_loop(socket, buffer, max_bytes, deadline) do
    case :binary.split(buffer, @terminator) do
      [head, rest] when byte_size(head) + 4 <= max_bytes ->
        {:ok, head, rest}

      [_head, _rest] ->
        {:error, :header_too_large}

      [_] when byte_size(buffer) >= max_bytes ->
        {:error, :header_too_large}

      [_] ->
        remaining = deadline - System.monotonic_time(:millisecond)
        recv(socket, buffer, max_bytes, deadline, remaining)
    end
  end

  defp recv(_socket, _buffer, _max, _deadline, remaining) when remaining <= 0,
    do: {:error, :header_timeout}

  defp recv(socket, buffer, max_bytes, deadline, remaining) do
    case :gen_tcp.recv(socket, 0, remaining) do
      {:ok, data} -> read_loop(socket, buffer <> data, max_bytes, deadline)
      {:error, :timeout} -> {:error, :header_timeout}
      {:error, _} -> {:error, :closed}
    end
  end

  @doc "Parst den Kopf zu einem Ziel `{host, port}`."
  @spec parse(binary()) :: {:ok, Target.t()} | {:error, :method | :malformed | :ip_literal}
  def parse(head) do
    [request_line | _] = String.split(head, "\r\n", parts: 2)

    case String.split(request_line, " ") do
      ["CONNECT", authority, "HTTP/1." <> minor] when minor in ["0", "1"] ->
        Target.parse(authority)

      [method, _, "HTTP/1." <> _] when method != "CONNECT" ->
        {:error, :method}

      _ ->
        {:error, :malformed}
    end
  end
end
