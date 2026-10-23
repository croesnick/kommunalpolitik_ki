defmodule KomkiEgress do
  @moduledoc """
  Egress-Proxy für Connectoren (CONTRACT §9): ein CONNECT-Proxy mit einem
  Loopback-Port je Connector und einer exakten Host-Allowlist je Port.
  Seatbelt kann ausgehenden Verkehr nicht nach Host filtern; diese
  Prüfung übernimmt deshalb dieser Prozess als einziger mit Outbound.
  """

  alias KomkiEgress.{Address, Config, Listener, Log, Resolver}

  @defaults %{
    resolver: &Resolver.resolve/1,
    address_allowed?: &Address.public?/1,
    log: &Log.write/1,
    max_header: 8192,
    header_timeout: 10_000,
    connect_timeout: 10_000,
    idle_timeout: 300_000
  }

  @doc """
  Startet je Port aus `config` einen Listener (verlinkt mit dem Aufrufer).

  Optionen (Keyword), nur aus Code erreichbar, nicht über argv:

    * `:resolver` – `fn host -> {:ok, [ip]} | {:error, _}` (Tests: lokaler Upstream)
    * `:address_allowed?` – Prüfung je aufgelöster Adresse (Tests: Loopback zulassen)
    * `:log` – Senke für die Logzeile je Verbindung
    * `:max_header` (8192 Bytes), `:header_timeout`, `:connect_timeout`,
      `:idle_timeout` (Millisekunden)
  """
  @spec start(Config.t(), keyword()) :: {:ok, [pid()]} | {:error, String.t()}
  def start(config, opts \\ []) do
    opts = Map.merge(@defaults, Map.new(opts))

    config
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn {port, entry}, {:ok, pids} ->
      case Listener.start_link(port, entry, opts) do
        {:ok, pid} ->
          {:cont, {:ok, [pid | pids]}}

        {:error, reason} ->
          stop(pids)
          {:halt, {:error, "Port #{port} lässt sich nicht binden: #{inspect(reason)}"}}
      end
    end)
  end

  @doc "Beendet Listener aus `start/2`; laufende Tunnel bleiben unberührt."
  @spec stop([pid()]) :: :ok
  def stop(pids) do
    Enum.each(pids, fn pid ->
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end)
  end
end
