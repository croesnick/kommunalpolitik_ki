defmodule KomkiEgress.Relay do
  @moduledoc """
  Reicht Bytes zwischen Client und Upstream durch, ohne sie anzusehen
  (keine TLS-Termination). Schließt eine Seite, wird die Schreibrichtung
  zur anderen Seite geschlossen (Half-Close); der Tunnel endet, wenn
  beide Seiten zu sind, bei einem Fehler oder nach `idle_ms` ohne Verkehr.
  Rückgabe sind die gezählten Bytes `{hin, zurück}`.
  """

  @spec run(:gen_tcp.socket(), :gen_tcp.socket(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def run(client, upstream, idle_ms) do
    :ok = :inet.setopts(client, active: :once)
    :ok = :inet.setopts(upstream, active: :once)

    state = %{client: client, upstream: upstream, open: 2, up: 0, down: 0, idle: idle_ms}
    result = loop(state)
    :gen_tcp.close(client)
    :gen_tcp.close(upstream)
    result
  end

  defp loop(%{open: 0} = s), do: {s.up, s.down}

  defp loop(s) do
    receive do
      {:tcp, socket, data} when socket == s.client or socket == s.upstream ->
        forward(s, socket, data)

      {:tcp_closed, socket} when socket == s.client or socket == s.upstream ->
        :gen_tcp.shutdown(peer(s, socket), :write)
        loop(%{s | open: s.open - 1})

      {:tcp_error, socket, _reason} when socket == s.client or socket == s.upstream ->
        {s.up, s.down}
    after
      s.idle -> {s.up, s.down}
    end
  end

  defp forward(s, socket, data) do
    s = count(s, socket, byte_size(data))

    with :ok <- :gen_tcp.send(peer(s, socket), data),
         :ok <- :inet.setopts(socket, active: :once) do
      loop(s)
    else
      _ -> {s.up, s.down}
    end
  end

  defp count(%{client: socket} = s, socket, n), do: %{s | up: s.up + n}
  defp count(s, _upstream, n), do: %{s | down: s.down + n}

  defp peer(%{client: socket, upstream: upstream}, socket), do: upstream
  defp peer(%{client: client}, _upstream), do: client
end
