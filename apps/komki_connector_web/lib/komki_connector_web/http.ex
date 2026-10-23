defmodule KomkiConnectorWeb.Http do
  @moduledoc """
  Duenne Schicht ueber `:httpc` (OTP, keine Deps).

  * Je Connector-Instanz ein eigenes httpc-Profil, damit die Proxy-Option
    nicht global gilt.
  * Mit Proxy laeuft HTTPS per `CONNECT host:443` ueber `komki-egress`
    (CONTRACT.md §9). Klartext-HTTP geht nie ueber den Proxy; `http://`
    gibt es nur fuer den Mock auf Loopback (`--base-url`).
  * TLS mit `verify_peer`, CA-Speicher des Systems
    (`:public_key.cacerts_get/0`), SNI und Hostname-Pruefung.
  * Fehler werden auf `:timeout` oder `:failed` reduziert: die Gruende
    von httpc koennen die Anfrage enthalten und gehoeren nicht in
    Antworten oder Logs.
  """

  @max_body 2_097_152

  @type proxy :: {charlist(), :inet.port_number()} | nil
  @type header :: {charlist(), charlist()}

  @doc "httpc-Profil starten (idempotent) und Proxy-Optionen setzen."
  @spec start_profile(atom(), proxy()) :: :ok | {:error, term()}
  def start_profile(profile, proxy) do
    with {:ok, _} <- Application.ensure_all_started([:inets, :ssl]),
         :ok <- ensure_profile(profile) do
      :httpc.set_options(proxy_options(proxy), profile)
    end
  end

  defp ensure_profile(profile) do
    case :inets.start(:httpc, profile: profile) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  httpc-Profiloptionen fuer den Proxy. Nur `https_proxy`: httpc tunnelt
  HTTPS dann per CONNECT. Ohne Proxy keine Option: das Profil ist frisch
  und gehoert nur dieser Instanz, also gilt httpcs Default (kein Proxy).
  """
  @spec proxy_options(proxy()) :: keyword()
  def proxy_options(nil), do: []
  def proxy_options({host, port}), do: [https_proxy: {{host, port}, []}]

  @doc "GET mit Gesamt-Timeout in Millisekunden."
  @spec get(atom(), String.t(), [header()], pos_integer()) ::
          {:ok, non_neg_integer(), binary()} | {:error, :timeout | :failed | :too_large}
  def get(profile, url, headers, timeout) do
    request = {String.to_charlist(url), headers}

    http_opts = [
      timeout: timeout,
      connect_timeout: timeout,
      autoredirect: false,
      ssl: ssl_options(URI.parse(url).host)
    ]

    case :httpc.request(:get, request, http_opts, [body_format: :binary], profile) do
      {:ok, {_status_line, _headers, body}} when byte_size(body) > @max_body ->
        {:error, :too_large}

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:ok, status, body}

      {:error, reason} ->
        {:error, classify(reason)}
    end
  end

  @doc "TLS-Optionen: Zertifikats- und Hostname-Pruefung gegen `host`."
  @spec ssl_options(String.t() | nil) :: list()
  def ssl_options(host) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      server_name_indication: String.to_charlist(host || ""),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end

  defp classify(:timeout), do: :timeout
  defp classify({:failed_connect, reasons}), do: failed_connect(reasons)
  defp classify(_reason), do: :failed

  defp failed_connect(reasons) when is_list(reasons) do
    if Enum.any?(reasons, &match?({_, _, :timeout}, &1)), do: :timeout, else: :failed
  end

  defp failed_connect(_reasons), do: :failed
end
