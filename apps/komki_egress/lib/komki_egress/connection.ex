defmodule KomkiEgress.Connection do
  @moduledoc """
  Bearbeitet genau eine Client-Verbindung auf einem Connector-Port.

  Ablauf: Kopf lesen → CONNECT parsen → exakter Allowlist-Vergleich für
  diesen Port → Hostname auflösen → jede aufgelöste Adresse prüfen → mit
  genau einer geprüften Adresse verbinden (kein zweites Auflösen nach
  Namen) → `200 Connection Established` → durchreichen. Jede Ablehnung
  beantwortet die Verbindung mit einem Status und schließt sie.

  Am Ende steht genau eine Logzeile ohne Inhalte (`KomkiEgress.Log`).
  """

  alias KomkiEgress.{Relay, Request, Target}

  @upstream_opts [:binary, active: false, packet: :raw, nodelay: true, exit_on_close: false]

  @doc "Bedient `client` bis zum Ende; `opts` siehe `KomkiEgress.start/2`."
  @spec serve(:gen_tcp.socket(), pos_integer(), KomkiEgress.Config.entry(), map()) :: :ok
  def serve(client, port, entry, opts) do
    started = System.monotonic_time(:millisecond)
    record = %{port: port, connector: entry.connector, host: nil, address: nil}

    record =
      case establish(client, entry, opts, record) do
        {:ok, upstream, rest, record} ->
          # Scheitert das Senden, merkt das Durchreichen den Abbruch sofort.
          _ = :gen_tcp.send(client, "HTTP/1.1 200 Connection Established\r\n\r\n")
          {up, down} = relay(client, upstream, rest, opts.idle_timeout)
          Map.merge(record, %{decision: "allow", reason: nil, bytes_up: up, bytes_down: down})

        {:deny, reason, record} ->
          reject(client, reason)
          Map.merge(record, %{decision: "deny", reason: reason, bytes_up: 0, bytes_down: 0})
      end

    record = Map.put(record, :duration_ms, System.monotonic_time(:millisecond) - started)
    opts.log.(record)
    :ok
  end

  defp establish(client, entry, opts, record) do
    with {:ok, head, rest} <- Request.read_head(client, opts.max_header, opts.header_timeout),
         {:ok, target} <- Request.parse(head),
         record = %{record | host: Target.to_string(target)},
         :ok <- allowed(target, entry),
         {:ok, addresses} <- resolve(target, opts),
         {:ok, upstream, address} <- connect(addresses, target, opts) do
      {:ok, upstream, rest, %{record | address: address |> :inet.ntoa() |> List.to_string()}}
    else
      {:error, reason, host} -> {:deny, reason, %{record | host: host}}
      {:error, reason} -> {:deny, reason, record}
    end
  end

  # Der Host steht erst nach erfolgreichem Parsen fest; Ablehnungen danach
  # tragen ihn mit, damit das Log das verweigerte Ziel zeigt.
  defp allowed(target, entry) do
    host = Target.to_string(target)
    if MapSet.member?(entry.allow, host), do: :ok, else: {:error, :not_allowed, host}
  end

  defp resolve({host, _port} = target, opts) do
    case opts.resolver.(host) do
      {:ok, [_ | _] = addresses} ->
        if Enum.all?(addresses, opts.address_allowed?),
          do: {:ok, addresses},
          else: {:error, :blocked_address, Target.to_string(target)}

      _ ->
        {:error, :resolve_failed, Target.to_string(target)}
    end
  end

  defp connect(addresses, {_host, port} = target, opts) do
    Enum.find_value(addresses, {:error, :connect_failed, Target.to_string(target)}, fn address ->
      case :gen_tcp.connect(address, port, @upstream_opts, opts.connect_timeout) do
        {:ok, upstream} -> {:ok, upstream, address}
        {:error, _} -> nil
      end
    end)
  end

  defp relay(client, upstream, rest, idle_timeout) do
    case :gen_tcp.send(upstream, rest) do
      :ok ->
        {up, down} = Relay.run(client, upstream, idle_timeout)
        {up + byte_size(rest), down}

      {:error, _} ->
        :gen_tcp.close(upstream)
        :gen_tcp.close(client)
        {0, 0}
    end
  end

  defp reject(client, reason) do
    :gen_tcp.send(
      client,
      "HTTP/1.1 #{status(reason)}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    )

    :gen_tcp.close(client)
  end

  defp status(:header_timeout), do: "408 Request Timeout"
  defp status(:resolve_failed), do: "502 Bad Gateway"
  defp status(:connect_failed), do: "502 Bad Gateway"
  defp status(_policy), do: "403 Forbidden"
end
