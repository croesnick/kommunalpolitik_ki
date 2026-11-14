defmodule KomkiMock.Adapters.Brave do
  @moduledoc """
  The Brave Web Search API as `apps/komki_connector_web` speaks it:

      GET /res/v1/web/search?q=<query>&count=<1..20>

  Sources (API reference, read 2026-11-07:
  https://api-dashboard.search.brave.com/api-reference/web/search/get):
  `q` must not be empty and has at most 600 characters; `count` is 1 to
  20, default 20. A response carries `type`, `query.original` and `web`
  with `type: "search"` and `results`; a result has `title`, `url`,
  `description`, `age` and `type: "search_result"`. Errors are an object
  with `error.id`, `error.status`, `error.code` and `error.detail`; the
  reference lists it for 404, 422 and 429.

  Not verified against the documentation, chosen here on purpose:

  - No hits omit `web` (the connector reads both forms as no hits).
  - The `error.code` values and the 401 for a wrong token.
  - Rate-limit headers: the mock sends none.

  Data: `{"key", "quota", "pages": [{"title", "url", "description", "age"}]}`.
  A page is a hit when every word of the query appears in its title or
  description (case-insensitive); hits keep the order of `pages`.
  `key` (string or null) is the only accepted `x-subscription-token`;
  null accepts any. `quota` (integer or null) counts the searches left:
  each answered search uses one, and at 0 the mock answers 429 — the
  rate-limit form. Seeds are JSON files in `priv/seeds/brave/<name>.json`:
  `default` (four pages, one with a prompt injection in its description)
  and `empty`.
  """

  @behaviour KomkiMock.Adapter

  @impl true
  def seed(name), do: KomkiMock.Seeds.load("brave", name)

  @impl true
  def handle(%{method: "GET", path: "/res/v1/web/search"} = request, data) do
    params = URI.decode_query(request.query)

    cond do
      not authorized?(request, data["key"]) ->
        {error(401, "SUBSCRIPTION_TOKEN_INVALID", "The provided subscription token is invalid."),
         data}

      data["quota"] == 0 ->
        {error(429, "RATE_LIMITED", "Request rate limit exceeded for plan."), data}

      true ->
        search(params, data)
    end
  end

  def handle(_request, data), do: {json(404, %{"error" => "not found"}), data}

  defp authorized?(_request, nil), do: true

  defp authorized?(request, key),
    do: Enum.any?(request.headers, &(&1 == {"x-subscription-token", key}))

  defp search(params, data) do
    with {:ok, query} <- query(params["q"]),
         {:ok, count} <- count(params["count"]) do
      hits = data["pages"] |> Enum.filter(&hit?(&1, query)) |> Enum.take(count)
      {json(200, response(query, hits)), use_quota(data)}
    else
      {:error, detail} -> {error(422, "VALIDATION", detail), data}
    end
  end

  defp query(q) when is_binary(q) and q != "" and byte_size(q) <= 600, do: {:ok, q}
  defp query(_q), do: {:error, "q must be 1 to 600 characters."}

  defp count(nil), do: {:ok, 20}

  defp count(value) do
    case Integer.parse(value) do
      {count, ""} when count in 1..20 -> {:ok, count}
      _ -> {:error, "count must be an integer from 1 to 20."}
    end
  end

  defp hit?(page, query) do
    text = String.downcase(page["title"] <> " " <> Map.get(page, "description", ""))
    query |> String.downcase() |> String.split() |> Enum.all?(&String.contains?(text, &1))
  end

  defp response(query, []), do: %{"type" => "search", "query" => %{"original" => query}}

  defp response(query, hits) do
    results = Enum.map(hits, &Map.put(&1, "type", "search_result"))

    %{
      "type" => "search",
      "query" => %{"original" => query},
      "web" => %{"type" => "search", "results" => results}
    }
  end

  defp use_quota(%{"quota" => quota} = data) when is_integer(quota),
    do: %{data | "quota" => quota - 1}

  defp use_quota(data), do: data

  defp error(status, code, detail) do
    json(status, %{
      "type" => "ErrorResponse",
      "error" => %{
        "id" => "komki-mock",
        "status" => status,
        "code" => code,
        "detail" => detail
      }
    })
  end

  defp json(status, body),
    do: {status, [{"content-type", "application/json"}], JSON.encode!(body)}
end
