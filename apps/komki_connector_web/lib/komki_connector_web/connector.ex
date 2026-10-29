defmodule KomkiConnectorWeb.Connector do
  @moduledoc """
  Connector `web` (Fassung `komki-web/1`, CONTRACT.md §5.1): eine
  Operation `search(query, count)` gegen die Brave Web Search API.

  Der API-Schluessel lebt nur im Zustand (`State`), und zwar in einer
  Closure: weder `inspect/1` (Elixir) noch `~p` (Erlang-Crash-Reports)
  zeigen deren Umgebung. Zusaetzlich laesst die Inspect-Implementierung
  das Feld ganz weg. Fehlt der Schluessel, liefert jede Suche
  `credential-missing`; der Socket bindet trotzdem (`komki doctor` sieht
  den Connector ueber `ping`).
  """

  @behaviour Sidecar.Server

  require Logger

  alias KomkiConnectorWeb.{Brave, Http}

  @default_base_url "https://api.search.brave.com/"
  @default_timeout 10_000
  @default_profile :komki_connector_web

  defmodule State do
    @moduledoc "Zustand des Connectors; `api_key` ist eine Closure und fehlt in `inspect/1`."
    @derive {Inspect, except: [:api_key]}
    @enforce_keys [:base_url, :profile, :timeout]
    defstruct [:api_key, :base_url, :proxy, :profile, :timeout]

    @type t :: %__MODULE__{
            api_key: (-> String.t()) | nil,
            base_url: String.t(),
            proxy: KomkiConnectorWeb.Http.proxy(),
            profile: atom(),
            timeout: pos_integer()
          }
  end

  @doc "Default-Basis-URL der Brave-API."
  @spec default_base_url() :: String.t()
  def default_base_url, do: @default_base_url

  @impl true
  def manifest, do: KomkiConnector.Manifest.sidecar!("web")

  @doc """
  Init-Argument: Map mit `:credentials` (von stdin), optional `:proxy`,
  `:base_url`, `:timeout` (ms, Default 10 s, unter dem Vermittler-Timeout
  von 15 s) und `:profile` (httpc-Profil; Tests nutzen eigene Profile).
  """
  @impl true
  def init(arg) do
    state = %State{
      api_key: api_key(Map.get(arg, :credentials, %{})),
      base_url: Map.get(arg, :base_url) || @default_base_url,
      proxy: Map.get(arg, :proxy),
      profile: Map.get(arg, :profile, @default_profile),
      timeout: Map.get(arg, :timeout, @default_timeout)
    }

    case Http.start_profile(state.profile, state.proxy) do
      :ok -> {:ok, state}
      {:error, _reason} -> {:error, "httpc-Profil konnte nicht gestartet werden"}
    end
  end

  defp api_key(%{"BRAVE_API_KEY" => key}) when is_binary(key) and key != "", do: fn -> key end
  defp api_key(_credentials), do: nil

  @impl true
  def handle_op("search", _params, _context, %State{api_key: nil}),
    do: {:error, "credential-missing", "BRAVE_API_KEY fehlt (Schluesselbund brave-search-api)"}

  def handle_op("search", %{"query" => query, "count" => count}, _context, %State{} = state) do
    search(query, count, state)
  rescue
    # Eigene Rettung statt der des Servers: dessen Log nimmt die
    # Exception-Nachricht auf, und die koennte Werte aus dem Zustand
    # enthalten. Hier erscheint nur der Exception-Typ.
    e ->
      Logger.error("search abgestuerzt: #{inspect(e.__struct__)}")
      {:error, "internal", "interner Fehler"}
  end

  defp search(query, count, state) do
    url = Brave.url(state.base_url, query, count)

    case Http.get(state.profile, url, Brave.headers(state.api_key.()), state.timeout) do
      {:ok, 200, body} -> results(body, count)
      {:ok, status, _body} -> error(Brave.status_error(status))
      {:error, :timeout} -> {:error, "upstream-timeout", "Brave antwortet nicht rechtzeitig"}
      {:error, :too_large} -> {:error, "upstream-error", "Antwort von Brave zu gross"}
      {:error, :failed} -> {:error, "upstream-error", "Verbindung zu Brave fehlgeschlagen"}
    end
  end

  defp results(body, count) do
    case Brave.parse(body, count) do
      {:ok, results} ->
        {:ok, %{"results" => results, "abrufdatum" => abrufdatum()}}

      {:error, :bad_body} ->
        {:error, "upstream-error", "Antwort von Brave ist kein gueltiges JSON"}
    end
  end

  defp error({code, detail}), do: {:error, code, detail}

  # Zeitpunkt des Abrufs in UTC, ISO 8601 auf Sekunden.
  defp abrufdatum, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
