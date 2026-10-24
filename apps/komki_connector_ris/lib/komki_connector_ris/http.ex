defmodule KomkiConnectorRis.Http do
  @moduledoc """
  Duenne HTTP-Schicht ueber `:httpc` (keine Deps).

  - Eigenes httpc-Profil, damit Proxy-Einstellungen nichts anderes im
    Knoten beeinflussen. `start/1` setzt das Profil jedes Mal neu auf.
  - Mit Proxy laeuft HTTPS per CONNECT ueber `127.0.0.1:<port>`
    (`https_proxy`, CONTRACT.md §4/§9). Klartext-HTTP (nur Mock auf
    Loopback) geht direkt, weil `proxy` nicht gesetzt wird.
  - TLS mit `verify_peer`, CA-Zertifikaten des Systems
    (`KomkiConnector.TLS.cacerts/0`, PEM-Datei statt Schluesselbund) und Hostname-Pruefung.
  - Keine Weiterleitungen: eine Umleitung auf einen anderen Host waere
    eine Tuer am Egress-Proxy vorbei.
  """

  @profile :komki_connector_ris

  @type proxy :: {String.t(), :inet.port_number()} | nil
  @type error :: :not_found | :timeout | {:status, pos_integer()} | :bad_json | :unreachable

  @doc "Startet inets/ssl und setzt das httpc-Profil (samt Proxy) neu auf."
  @spec start(proxy()) :: :ok | {:error, term()}
  def start(proxy) do
    with {:ok, _} <- Application.ensure_all_started([:inets, :ssl]) do
      _ = :inets.stop(:httpc, @profile)
      {:ok, _pid} = :inets.start(:httpc, profile: @profile)

      case profile_options(proxy) do
        [] -> :ok
        opts -> :httpc.set_options(opts, @profile)
      end
    end
  end

  @doc "Name des httpc-Profils (fuer Tests und Diagnose)."
  @spec profile() :: atom()
  def profile, do: @profile

  @doc "Profil-Optionen fuer `:httpc.set_options/2`: nur der HTTPS-Proxy."
  @spec profile_options(proxy()) :: keyword()
  def profile_options(nil), do: []

  def profile_options({host, port}),
    do: [https_proxy: {{String.to_charlist(host), port}, []}]

  @doc "HTTP-Optionen fuer `:httpc.request/5` (Timeouts, TLS, keine Umleitung)."
  @spec http_options(String.t(), pos_integer()) :: keyword()
  def http_options(url, timeout_ms) do
    base = [timeout: timeout_ms, connect_timeout: timeout_ms, autoredirect: false]

    case URI.parse(url) do
      %URI{scheme: "https", host: host} -> [{:ssl, ssl_options(host)} | base]
      _ -> base
    end
  end

  @doc "TLS-Optionen: Zertifikatskette und Hostname werden geprueft."
  @spec ssl_options(String.t()) :: keyword()
  def ssl_options(host) do
    [
      verify: :verify_peer,
      cacerts: KomkiConnector.TLS.cacerts(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)],
      depth: 4
    ]
  end

  @doc "GET mit JSON-Antwort. Nur Status 200 gilt als Erfolg."
  @spec get_json(String.t(), [{String.t(), String.t()}], pos_integer()) ::
          {:ok, term()} | {:error, error()}
  def get_json(url, headers, timeout_ms) do
    request = {String.to_charlist(url), Enum.map(headers, &charlist_header/1)}

    case :httpc.request(
           :get,
           request,
           http_options(url, timeout_ms),
           [body_format: :binary],
           @profile
         ) do
      {:ok, {{_, 200, _}, _headers, body}} -> decode(body)
      {:ok, {{_, 404, _}, _headers, _body}} -> {:error, :not_found}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, classify(reason)}
    end
  end

  defp charlist_header({k, v}), do: {String.to_charlist(k), String.to_charlist(v)}

  defp decode(body) do
    {:ok, :json.decode(body)}
  rescue
    _ -> {:error, :bad_json}
  end

  # Zeitueberschreitung beim Verbinden oder Lesen ist :timeout, alles
  # andere (DNS, TLS, Verbindungsabbruch) :unreachable.
  defp classify(:timeout), do: :timeout

  defp classify({:failed_connect, details}) do
    if Enum.any?(details, &match?({_, _, :timeout}, &1)), do: :timeout, else: :unreachable
  end

  defp classify(_), do: :unreachable
end
