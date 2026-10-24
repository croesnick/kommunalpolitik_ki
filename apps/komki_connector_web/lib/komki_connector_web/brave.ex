defmodule KomkiConnectorWeb.Brave do
  @moduledoc """
  Brave Web Search API: Anfrage bauen, Antwort auf die Ergebnisform
  `web.search` abbilden (CONTRACT.md §5.2), HTTP-Status auf die
  geschlossenen Fehlercodes abbilden (§3).

  Endpunkt `GET /res/v1/web/search?q=<query>&count=<count>` mit den
  Headern `Accept: application/json` und `X-Subscription-Token`. Treffer
  stehen in `web.results[]` mit `title`, `url` und `description`; fehlt
  `web`, gibt es keine Treffer.
  """

  alias KomkiConnectorWeb.Text

  @path "res/v1/web/search"
  @max_title 300
  @max_snippet 1000

  @type result :: %{String.t() => String.t()}

  @doc "Vollstaendige Anfrage-URL relativ zur Basis-URL."
  @spec url(String.t(), String.t(), pos_integer()) :: String.t()
  def url(base_url, query, count) do
    base_url
    |> URI.parse()
    |> URI.merge(@path)
    |> Map.put(:query, URI.encode_query([{"q", query}, {"count", count}], :rfc3986))
    |> URI.to_string()
  end

  @doc "Anfrage-Header. Der Schluessel steht nur hier, nie in URL oder Log."
  @spec headers(String.t()) :: [{charlist(), charlist()}]
  def headers(api_key) do
    [
      {~c"accept", ~c"application/json"},
      {~c"x-subscription-token", String.to_charlist(api_key)}
    ]
  end

  @doc """
  Antwort-Body (JSON) zu hoechstens `count` Treffern. Treffer ohne Titel
  oder mit einer anderen als einer `http`/`https`-URL werden verworfen,
  bevor gezaehlt wird.
  """
  @spec parse(binary(), pos_integer()) :: {:ok, [result()]} | {:error, :bad_body}
  def parse(body, count) do
    case decode(body) do
      {:ok, %{} = doc} ->
        {:ok, doc |> web_results() |> Enum.flat_map(&result/1) |> Enum.take(count)}

      _ ->
        {:error, :bad_body}
    end
  end

  defp decode(body) do
    {:ok, :json.decode(body)}
  rescue
    _ -> :error
  end

  defp web_results(%{"web" => %{"results" => results}}) when is_list(results), do: results
  defp web_results(_doc), do: []

  defp result(%{"title" => title, "url" => url} = item)
       when is_binary(title) and is_binary(url) do
    title = Text.clean(title, @max_title)

    if title != "" and web_url?(url) do
      snippet = item |> Map.get("description") |> snippet()
      [%{"title" => title, "url" => url, "snippet" => snippet}]
    else
      []
    end
  end

  defp result(_item), do: []

  defp snippet(text) when is_binary(text), do: Text.clean(text, @max_snippet)
  defp snippet(_text), do: ""

  @doc "Nur absolute `http`/`https`-URLs mit Host gelten als Treffer."
  @spec web_url?(String.t()) :: boolean()
  def web_url?(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}} when scheme in ["http", "https"] ->
        is_binary(host) and host != ""

      _ ->
        false
    end
  end

  @doc """
  Fehlercode fuer einen HTTP-Status ungleich 200:

  * 401 → `credential-missing`: Brave lehnt den Schluessel ab; abhelfen
    kann nur die nutzende Person (neuer Schluessel im Schluesselbund).
  * 403 → `upstream-error`: der Schluessel ist bekannt, der Abo-Plan
    erlaubt die Anfrage aber nicht.
  * 429 → `upstream-error` mit Hinweis auf das Rate-Limit.
  * sonst → `upstream-error` mit dem Status.
  """
  @spec status_error(non_neg_integer()) :: {String.t(), String.t()}
  def status_error(401),
    do: {"credential-missing", "Brave lehnt den API-Schluessel ab (HTTP 401)"}

  def status_error(403),
    do: {"upstream-error", "Brave verweigert die Anfrage (HTTP 403, Abo-Plan pruefen)"}

  def status_error(429),
    do: {"upstream-error", "Rate-Limit von Brave erreicht (HTTP 429), spaeter erneut versuchen"}

  def status_error(status), do: {"upstream-error", "Brave antwortet mit HTTP #{status}"}
end
