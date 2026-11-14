defmodule KomkiMock.Adapters.RisTest do
  @moduledoc "The RIS adapter on its own: seeds and the rendered guest endpoints."

  use ExUnit.Case, async: true

  alias KomkiMock.Adapters.Ris

  setup do
    {:ok, data} = Ris.seed("default")
    %{data: data}
  end

  test "seeds are JSON files; unknown or path-like names are refused" do
    assert {:ok, %{"meetings" => [_, _]}} = Ris.seed("default")
    assert :error = Ris.seed("nope")
    assert :error = Ris.seed("../ris/default")
  end

  test "the meeting list ignores the time window", %{data: data} do
    assert {200, %{"items" => items}} =
             get(data, "/guestmeetings", "client=32&from=1990-01-01&until=1990-12-31")

    assert Enum.map(items, & &1["id"]) == [1001, 1002]
    assert %{"meetingdate" => "2026-09-15T18:00:00", "committeename" => "Stadtrat"} = hd(items)
  end

  test "a meeting splits its items into the public and the protected part", %{data: data} do
    assert {200, %{"parts" => [public, protected]}} = get(data, "/guestmeetings/1002")

    assert %{"protectedpart" => false, "agendaitems" => [_, _]} = public
    assert %{"protectedpart" => true, "agendaitems" => [%{"id" => "1002-3"}]} = protected
    assert {404, _} = get(data, "/guestmeetings/9999")
  end

  test "an agenda item carries its text as Base64 HTML", %{data: data} do
    assert {200, item} = get(data, "/guestagendaitems/1001-2")
    assert %{"restricted" => true, "meetingid" => 1001, "textblocks" => [block]} = item
    assert Base.decode64!(block["content"]) =~ "<p>Verkauf des Flurstücks"
    assert {404, _} = get(data, "/guestagendaitems/1001-9")
  end

  test "the data decides what is served", %{data: data} do
    [meeting | _] = data["meetings"]
    data = %{data | "meetings" => [%{meeting | "name" => "Sondersitzung"}]}

    assert {200, %{"items" => [%{"name" => "Sondersitzung"}]}} = get(data, "/guestmeetings")
  end

  test "only GET and the login are served; unknown paths answer 404", %{data: data} do
    assert {{405, _, _}, ^data} = Ris.handle(request("POST", "/guestmeetings", ""), data)
    assert {404, _} = get(data, "/nope/1001")
  end

  test "the login hands out the token only for the seed's account", %{data: data} do
    assert {200, %{"token" => "mock-ris-token"}} =
             post_auth(data, %{
               "login" => "ratsmitglied@komki.example",
               "password" => "mock-passwort"
             })

    assert {401, _} =
             post_auth(data, %{"login" => "ratsmitglied@komki.example", "password" => "falsch"})

    assert {401, _} = post_auth(data, %{"login" => "ratsmitglied@komki.example"})
    assert {401, _} = post_auth(Map.delete(data, "account"), %{"login" => "", "password" => ""})
  end

  test "signed-in endpoints need the token and answer like the guest ones", %{data: data} do
    assert {401, _} = get(data, "/meetings/1001")
    assert {401, _} = get(data, "/agendaitems/1001-1", "", "Bearer falsch")

    assert get(data, "/meetings/1002", "", "Bearer mock-ris-token") ==
             get(data, "/guestmeetings/1002")

    assert get(data, "/agendaitems/1001-1", "", "Bearer mock-ris-token") ==
             get(data, "/guestagendaitems/1001-1")
  end

  test "with guest_texts false only the signed-in endpoint carries the text", %{data: data} do
    data = Map.put(data, "guest_texts", false)

    assert {200, %{"textsanddocsvisible" => false, "textblocks" => []}} =
             get(data, "/guestagendaitems/1001-1")

    assert {200, %{"textsanddocsvisible" => true, "textblocks" => [_]}} =
             get(data, "/agendaitems/1001-1", "", "Bearer mock-ris-token")
  end

  defp get(data, path, query \\ "", authorization \\ nil) do
    headers = if authorization, do: [{"authorization", authorization}], else: []
    request = %{request("GET", path, query) | headers: headers}
    {{status, _headers, body}, ^data} = Ris.handle(request, data)
    {status, JSON.decode!(body)}
  end

  defp post_auth(data, body) do
    request = %{request("POST", "/auth", "") | body: JSON.encode!(body)}
    {{status, _headers, resp}, ^data} = Ris.handle(request, data)
    {status, JSON.decode!(resp)}
  end

  defp request(method, path, query),
    do: %{method: method, path: path, query: query, headers: [], body: ""}
end
