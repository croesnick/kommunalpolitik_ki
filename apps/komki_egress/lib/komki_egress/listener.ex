defmodule KomkiEgress.Listener do
  @moduledoc """
  Ein Loopback-Listener je Connector-Port. Nimmt Verbindungen an und
  übergibt jede an einen eigenen, nicht verlinkten Prozess
  (`KomkiEgress.Connection`), damit ein Absturz in einer Verbindung den
  Listener nicht mitreißt.
  """

  alias KomkiEgress.Connection

  @listen_opts [
    :binary,
    ip: {127, 0, 0, 1},
    active: false,
    packet: :raw,
    reuseaddr: true,
    nodelay: true,
    exit_on_close: false,
    backlog: 128
  ]

  @doc """
  Startet den Listener verlinkt mit dem Aufrufer. Kehrt erst zurück, wenn
  der Port gebunden ist oder das Binden gescheitert ist.
  """
  @spec start_link(pos_integer(), KomkiEgress.Config.entry(), map()) ::
          {:ok, pid()} | {:error, term()}
  def start_link(port, entry, opts) do
    parent = self()
    ref = make_ref()
    pid = spawn_link(fn -> init(parent, ref, port, entry, opts) end)

    receive do
      {^ref, :ok} -> {:ok, pid}
      {^ref, {:error, reason}} -> {:error, reason}
    end
  end

  defp init(parent, ref, port, entry, opts) do
    case :gen_tcp.listen(port, @listen_opts) do
      {:ok, listen} ->
        send(parent, {ref, :ok})
        accept_loop(listen, port, entry, opts)

      {:error, reason} ->
        send(parent, {ref, {:error, reason}})
    end
  end

  defp accept_loop(listen, port, entry, opts) do
    case :gen_tcp.accept(listen) do
      {:ok, client} ->
        handover(client, port, entry, opts)
        accept_loop(listen, port, entry, opts)

      {:error, :closed} ->
        :ok

      {:error, _transient} ->
        accept_loop(listen, port, entry, opts)
    end
  end

  # Der Verbindungsprozess wartet auf :go, bis er Eigentümer des Sockets ist.
  defp handover(client, port, entry, opts) do
    pid =
      spawn(fn ->
        receive do
          :go -> Connection.serve(client, port, entry, opts)
        end
      end)

    case :gen_tcp.controlling_process(client, pid) do
      :ok ->
        send(pid, :go)

      {:error, _} ->
        Process.exit(pid, :kill)
        :gen_tcp.close(client)
    end
  end
end
