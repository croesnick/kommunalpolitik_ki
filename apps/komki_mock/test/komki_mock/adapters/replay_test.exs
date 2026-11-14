defmodule KomkiMock.Adapters.ReplayTest do
  @moduledoc "The replay adapter on its own: loading cassettes and matching requests."

  use ExUnit.Case, async: true

  alias KomkiMock.Adapters.Replay

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    cassette(dir, "0001-get-guestmeetings.json", %{
      "request" => %{"method" => "GET", "path" => "/guestmeetings", "query" => "from=2026-01-01"},
      "response" => %{
        "status" => 200,
        "headers" => [["Content-Type", "application/json"], ["Content-Length", "999"]],
        "body_b64" => Base.encode64(~s({"items":[]}))
      }
    })

    cassette(dir, "0002-post-auth.json", %{
      "request" => %{"method" => "POST", "path" => "/auth", "query" => nil},
      "response" => %{"status" => 200, "headers" => [], "body" => ~s({"token":"t"})}
    })

    cassette(dir, "0003-get-fulltextsearch.json", %{
      "request" => %{"method" => "GET", "path" => "/fulltextsearch", "query" => "q=Linde"},
      "response" => %{"status" => 200, "headers" => [], "body" => "[]"}
    })

    {:ok, data} = Replay.seed(dir)
    %{data: data}
  end

  test "the seed is the cassette directory", %{data: data, tmp_dir: dir} do
    assert %{"cassettes" => [_, _, _]} = data
    assert :error = Replay.seed(Path.join(dir, "missing"))
  end

  test "an exact match replays status, headers and body", %{data: data} do
    assert {{200, headers, ~s({"items":[]})}, ^data} =
             Replay.handle(request("GET", "/guestmeetings", "from=2026-01-01"), data)

    assert headers == [{"content-type", "application/json"}]
  end

  test "the order of query parameters does not matter", %{data: data} do
    assert {{200, _, "[]"}, _} =
             Replay.handle(request("GET", "/fulltextsearch", "q=Linde"), data)

    data = put_in(data, ["cassettes", Access.at(2), "query"], "client=32&q=Linde")

    assert {{200, _, "[]"}, _} =
             Replay.handle(request("GET", "/fulltextsearch", "q=Linde&client=32"), data)
  end

  test "a recording without query matches an empty query", %{data: data} do
    assert {{200, [], ~s({"token":"t"})}, _} = Replay.handle(request("POST", "/auth", ""), data)
  end

  test "only time-window endpoints fall back to another query", %{data: data} do
    assert {{200, _, _}, _} = Replay.handle(request("GET", "/guestmeetings", "from=2025"), data)
    assert {{404, _, _}, _} = Replay.handle(request("GET", "/fulltextsearch", "q=Eiche"), data)
    assert {{404, _, _}, _} = Replay.handle(request("GET", "/nothing", ""), data)
  end

  defp cassette(dir, name, content), do: File.write!(Path.join(dir, name), JSON.encode!(content))

  defp request(method, path, query),
    do: %{method: method, path: path, query: query, headers: [], body: ""}
end
