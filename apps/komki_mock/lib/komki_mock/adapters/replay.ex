defmodule KomkiMock.Adapters.Replay do
  @moduledoc """
  Plays back recorded HTTP exchanges: the cassettes that
  `apps/komki_connector_ris/priv/ris_recorder.exs` records and
  `ris_gartenstadt.exs` generates. One JSON file per exchange:

      {"request":  {"method", "path", "query", "headers"},
       "response": {"status", "headers", "body_b64" | "body"}}

  The seed name is the cassette directory (best given as an absolute path:
  `reset` reads it again). Its `*.json` files, sorted by name, become the
  data; bodies are kept as Base64 so binary responses survive the state
  file.

  Matching: method, path and query exactly, where the query compares as a
  set of parameters (clients build it from maps, whose key order is not
  stable); for the paths in `@query_fallback_paths` the first recording of
  method and path when the query differs. Anything else answers 404.
  """

  @behaviour KomkiMock.Adapter

  # Endpoints whose query only picks a time window: a different window may
  # fall back to a recording of the same path. Everywhere else (e.g.
  # fulltextsearch) the fallback would silently answer a different question.
  @query_fallback_paths ~w(/guestmeetings)

  # Headers that do not replay: content-length follows the body, the rest
  # is hop-by-hop.
  @dropped_headers ~w(connection keep-alive proxy-authenticate proxy-authorization te trailer
                      transfer-encoding upgrade content-length)

  @impl true
  def seed(dir) do
    if File.dir?(dir) do
      cassettes =
        dir
        |> Path.join("*.json")
        |> Path.wildcard()
        |> Enum.sort()
        |> Enum.map(&load/1)

      {:ok, %{"cassettes" => cassettes}}
    else
      :error
    end
  end

  defp load(file) do
    %{"request" => request, "response" => response} = file |> File.read!() |> JSON.decode!()

    %{
      "method" => request["method"],
      "path" => request["path"],
      # A recording without query has null; Plug hands over "".
      "query" => request["query"] || "",
      "status" => response["status"],
      "headers" => response["headers"],
      "body_b64" => response["body_b64"] || Base.encode64(response["body"])
    }
  end

  @impl true
  def handle(request, %{"cassettes" => cassettes} = data) do
    case find(cassettes, request) do
      nil ->
        {{404, [{"content-type", "application/json"}], ~s({"error":"not found"})}, data}

      cassette ->
        headers =
          for [name, value] <- cassette["headers"],
              key = String.downcase(name),
              key not in @dropped_headers,
              do: {key, value}

        {{cassette["status"], headers, Base.decode64!(cassette["body_b64"])}, data}
    end
  end

  defp find(cassettes, %{method: method, path: path, query: query}) do
    same_route = &(&1["method"] == method and &1["path"] == path)
    params = params(query)

    Enum.find(cassettes, &(same_route.(&1) and params(&1["query"]) == params)) ||
      if path in @query_fallback_paths, do: Enum.find(cassettes, same_route)
  end

  defp params(query), do: query |> URI.query_decoder() |> Enum.sort()
end
