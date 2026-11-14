defmodule KomkiConnectorRis.CLI do
  @moduledoc """
  Escript entry `komki-connector-ris` (CONTRACT.md §4):

      komki-connector-ris --socket <path> [--base-url <url>] [--proxy 127.0.0.1:<port>]

  Reads the credentials line from stdin first (token, optionally
  `RIS_ZUGANG`), signs in to the RIS with `RIS_ZUGANG`, then binds the
  socket and serves requests until SIGTERM. Logs to stderr, without payload.
  """

  alias KomkiConnector.Launch
  alias Sidecar.Server

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    _ = :logger.update_handler_config(:default, :config, %{type: :standard_error})

    with {:ok, opts} <- parse(argv),
         {:ok, credentials} <- Server.read_credentials(),
         init_arg =
           Map.put(opts, :credentials, Map.delete(credentials, Launch.credential_key())),
         {:error, reason} <- Launch.run(KomkiConnectorRis, opts.socket, init_arg, credentials) do
      fail(if is_binary(reason), do: reason, else: inspect(reason))
    else
      {:error, message} -> fail(message)
    end
  end

  @doc "Argumente pruefen. Oeffentlich fuer Tests."
  @spec parse([String.t()]) :: {:ok, map()} | {:error, String.t()}
  def parse(argv) do
    case OptionParser.parse(argv, strict: [socket: :string, base_url: :string, proxy: :string]) do
      {opts, [], []} -> build(opts)
      _ -> {:error, usage()}
    end
  end

  defp build(opts) do
    with {:ok, socket} <- socket(opts[:socket]),
         {:ok, base_url} <- base_url(opts[:base_url]),
         {:ok, proxy} <- proxy(opts[:proxy]) do
      {:ok, %{socket: socket, base_url: base_url, proxy: proxy}}
    end
  end

  defp socket(nil), do: {:error, usage()}
  defp socket(path), do: {:ok, path}

  defp base_url(nil), do: {:ok, KomkiConnectorRis.defaults().base_url}

  defp base_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, query: nil, fragment: nil}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, if(String.ends_with?(url, "/"), do: url, else: url <> "/")}

      _ ->
        {:error, "--base-url muss eine http(s)-URL ohne Query sein"}
    end
  end

  defp proxy(nil), do: {:ok, nil}

  defp proxy(value) do
    with [_, host, port] <- Regex.run(~r/^([A-Za-z0-9.-]+):(\d{1,5})$/, value),
         port = String.to_integer(port),
         true <- port in 1..65_535 do
      {:ok, {host, port}}
    else
      _ -> {:error, "--proxy erwartet host:port"}
    end
  end

  defp usage,
    do:
      "Aufruf: komki-connector-ris --socket <pfad> [--base-url <url>] [--proxy 127.0.0.1:<port>]"

  @spec fail(String.t()) :: no_return()
  defp fail(message) do
    IO.puts(:stderr, "komki-connector-ris: " <> message)
    System.halt(1)
  end
end
