defmodule KomkiConnectorRatsprojekte.CLI do
  @moduledoc """
  DURCHSTICH #409 (Wegwerf): Rollen-Einstieg `komki-connector-ratsprojekte`
  (Multicall, CONTRACT.md §4):

      komki-connector-ratsprojekte --socket <pfad> --hub-socket <pfad>

  Liest zuerst die Credentials von stdin (eine JSON-Zeile:
  `KOMKI_CONNECTOR_TOKEN` und `KOMKI_HUB_TOKEN`), bindet dann den Socket
  und bedient Anfragen bis SIGTERM. Log auf stderr, ohne Payloads.
  """

  alias KomkiConnector.Launch
  alias KomkiConnectorRatsprojekte
  alias Sidecar.Server

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    log_to_stderr()

    with {:ok, opts} <- parse(argv),
         {:ok, creds} <- Server.read_credentials(),
         init_arg = %{
           hub_socket: opts.hub_socket,
           credentials: Map.delete(creds, Launch.credential_key())
         },
         {:error, reason} <- Launch.run(KomkiConnectorRatsprojekte, opts.socket, init_arg, creds) do
      fail(format_reason(reason))
    else
      {:error, message} when is_binary(message) -> fail(message)
      _ -> :ok
    end
  end

  defp parse(argv) do
    case OptionParser.parse(argv, strict: [socket: :string, hub_socket: :string]) do
      {opts, [], []} ->
        with {:ok, socket} <- required(opts, :socket, "--socket"),
             {:ok, hub_socket} <- required(opts, :hub_socket, "--hub-socket") do
          {:ok, %{socket: socket, hub_socket: hub_socket}}
        end

      _ ->
        {:error, "Aufruf: komki-connector-ratsprojekte --socket <pfad> --hub-socket <pfad>"}
    end
  end

  defp required(opts, key, flag) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when value != "" -> {:ok, value}
      _ -> {:error, "#{flag} fehlt"}
    end
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  # CONTRACT.md §4: Log auf stderr (komki up leitet es in die Logdatei um).
  defp log_to_stderr do
    _ = :logger.remove_handler(:default)

    _ =
      :logger.add_handler(:default, :logger_std_h, %{
        config: %{type: :standard_error},
        filter_default: :log,
        filters: [],
        formatter: Logger.default_formatter()
      })

    :ok
  end

  @spec fail(String.t()) :: no_return()
  defp fail(message) do
    IO.puts(:stderr, "komki-connector-ratsprojekte: " <> message)
    System.halt(1)
  end
end
