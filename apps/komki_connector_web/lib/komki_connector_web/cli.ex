defmodule KomkiConnectorWeb.CLI do
  @moduledoc """
  Escript-Einstieg `komki-connector-web` (CONTRACT.md §4):

      komki-connector-web --socket <pfad> [--proxy 127.0.0.1:<port>] [--base-url <url>]

  * `--socket`   Unix-Socket, den der Connector bindet (Pflicht).
  * `--proxy`    HTTP-CONNECT-Proxy `komki-egress` als `host:port`.
  * `--base-url` nur fuer Tests und Mock; Default `https://api.search.brave.com/`.

  Credentials kommen als eine JSON-Zeile ueber stdin
  (`{"BRAVE_API_KEY": "..."}`), nie ueber argv oder Umgebung. stdin wird
  vollstaendig gelesen, bevor der Socket bindet. Log geht nach stderr.
  """

  alias KomkiConnector.Server
  alias KomkiConnectorWeb.Connector

  @spec main([String.t()]) :: no_return()
  def main(argv) do
    log_to_stderr()

    with {:ok, opts} <- parse(argv),
         {:ok, creds} <- Server.read_credentials(),
         init_arg = Map.put(opts, :credentials, creds),
         {:error, reason} <- Server.run(Connector, opts.socket, init_arg) do
      fail("Start fehlgeschlagen: #{format_reason(reason)}")
    else
      {:error, message} when is_binary(message) -> fail(message)
    end
  end

  @doc "argv zu Optionen; unbekannte Argumente sind ein Fehler."
  @spec parse([String.t()]) :: {:ok, map()} | {:error, String.t()}
  def parse(argv) do
    case OptionParser.parse(argv, strict: [socket: :string, proxy: :string, base_url: :string]) do
      {parsed, [], []} -> build(parsed)
      _ -> {:error, usage()}
    end
  end

  defp build(parsed) do
    with {:ok, socket} <- fetch_socket(parsed),
         {:ok, proxy} <- parse_proxy(parsed[:proxy]),
         {:ok, base_url} <- parse_base_url(parsed[:base_url]) do
      {:ok, %{socket: socket, proxy: proxy, base_url: base_url}}
    end
  end

  defp fetch_socket(parsed) do
    case parsed[:socket] do
      socket when is_binary(socket) and socket != "" -> {:ok, socket}
      _ -> {:error, usage()}
    end
  end

  @doc "`host:port` zur httpc-Proxy-Angabe `{host, port}`."
  @spec parse_proxy(String.t() | nil) ::
          {:ok, KomkiConnectorWeb.Http.proxy()} | {:error, String.t()}
  def parse_proxy(nil), do: {:ok, nil}

  def parse_proxy(value) do
    with [host, port_str] when host != "" <- String.split(value, ":", parts: 2),
         {port, ""} when port in 1..65_535 <- Integer.parse(port_str) do
      {:ok, {String.to_charlist(host), port}}
    else
      _ -> {:error, "--proxy erwartet host:port"}
    end
  end

  defp parse_base_url(nil), do: {:ok, Connector.default_base_url()}

  defp parse_base_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        {:ok, url}

      _ ->
        {:error, "--base-url erwartet eine http- oder https-URL"}
    end
  end

  defp usage,
    do:
      "Aufruf: komki-connector-web --socket <pfad> [--proxy 127.0.0.1:<port>] [--base-url <url>]"

  defp log_to_stderr do
    _ = :logger.update_handler_config(:default, :config, %{type: :standard_error})
    :ok
  end

  # Nur Grundtypen ausgeben; Start-Fehler stammen aus listen/init.
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(_reason), do: "unbekannter Fehler"

  @spec fail(String.t()) :: no_return()
  defp fail(message) do
    IO.puts(:stderr, message)
    System.halt(1)
  end
end
