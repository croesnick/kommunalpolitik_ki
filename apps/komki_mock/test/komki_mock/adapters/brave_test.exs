defmodule KomkiMock.Adapters.BraveTest do
  @moduledoc "The Brave adapter on its own: hits, no hits, errors and the rate-limit form."

  use ExUnit.Case, async: true

  alias KomkiMock.Adapters.Brave

  setup do
    {:ok, data} = Brave.seed("default")
    %{data: data}
  end

  test "seeds are JSON files; unknown or path-like names are refused" do
    assert {:ok, %{"pages" => [_, _, _, _]}} = Brave.seed("default")
    assert {:ok, %{"pages" => []}} = Brave.seed("empty")
    assert :error = Brave.seed("nope")
    assert :error = Brave.seed("../brave/default")
  end

  test "hits: every query word in title or description, in page order", %{data: data} do
    assert {200, body, _} = search(data, "q=radweg%20bahnhofstra%C3%9Fe")

    assert %{"type" => "search", "query" => %{"original" => "radweg bahnhofstraße"}} = body
    assert %{"type" => "search", "results" => results} = body["web"]

    assert Enum.map(results, & &1["url"]) == [
             "https://gartenstadt.example/radverkehrskonzept",
             "https://zeitung.example/leserbrief-radweg"
           ]

    assert Enum.all?(results, &(&1["type"] == "search_result"))
  end

  test "count limits the hits", %{data: data} do
    assert {200, %{"web" => %{"results" => [_]}}, _} = search(data, "q=radweg&count=1")
  end

  test "no hits: the answer has no web key", %{data: data} do
    assert {200, body, _} = search(data, "q=Kl%C3%A4ranlage")
    refute Map.has_key?(body, "web")

    {:ok, empty} = Brave.seed("empty")
    assert {200, body, _} = search(empty, "q=radweg")
    refute Map.has_key?(body, "web")
  end

  test "invalid parameters answer 422", %{data: data} do
    assert {422, %{"error" => %{"status" => 422}}, ^data} = search(data, "q=")
    assert {422, _, _} = search(data, "q=radweg&count=21")
    assert {422, _, _} = search(data, "q=radweg&count=x")
  end

  test "a set key rejects other tokens with 401", %{data: data} do
    data = %{data | "key" => "BSA-mock"}

    assert {401, %{"type" => "ErrorResponse", "error" => %{"status" => 401}}, ^data} =
             search(data, "q=radweg", [{"x-subscription-token", "falsch"}])

    assert {200, _, _} = search(data, "q=radweg", [{"x-subscription-token", "BSA-mock"}])
  end

  test "rate limit: the quota counts down, then 429", %{data: data} do
    data = %{data | "quota" => 1}

    assert {200, _, data} = search(data, "q=radweg")
    assert data["quota"] == 0

    assert {429, %{"type" => "ErrorResponse", "error" => error}, ^data} =
             search(data, "q=radweg")

    assert %{"status" => 429, "code" => "RATE_LIMITED"} = error
  end

  test "other paths answer 404", %{data: data} do
    assert {{404, _, _}, ^data} =
             Brave.handle(
               %{method: "GET", path: "/res/v1/news/search", query: "", headers: [], body: ""},
               data
             )
  end

  defp search(data, query, headers \\ []) do
    request = %{
      method: "GET",
      path: "/res/v1/web/search",
      query: query,
      headers: headers,
      body: ""
    }

    {{status, _headers, body}, data} = Brave.handle(request, data)
    {status, JSON.decode!(body), data}
  end
end
