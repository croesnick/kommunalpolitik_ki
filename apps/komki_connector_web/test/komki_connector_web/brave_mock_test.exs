defmodule KomkiConnectorWeb.BraveMockTest do
  @moduledoc """
  Der Web-Connector gegen den Brave-Mock der Mock-Runtime (apps/komki_mock),
  ohne Netz: Loopback statt api.search.brave.com.
  """

  use ExUnit.Case, async: true

  alias KomkiConnectorWeb.Connector
  alias KomkiMock.Server

  @key "BSA-mock-0123456789"

  setup do
    dir = Path.join(System.tmp_dir!(), "kmweb-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    mock = start_supervised!({Server, adapter: KomkiMock.Adapters.Brave, dir: dir})
    %{"data" => data} = Server.state(mock)
    {:ok, _} = Server.put_data(mock, %{data | "key" => @key})

    {:ok, state} =
      Connector.init(%{
        credentials: %{"BRAVE_API_KEY" => @key},
        base_url: "http://127.0.0.1:#{Server.ports(mock).data}/",
        # Own httpc profile, without proxy; the tests of this module run one by one.
        profile: :brave_mock_test,
        timeout: 2_000
      })

    %{mock: mock, state: state, data: data}
  end

  defp search(state, query, count \\ 5),
    do: Connector.handle_op("search", %{"query" => query, "count" => count}, %{}, state)

  test "Treffer in der Ergebnisform des Connectors", %{state: state, mock: mock} do
    assert {:ok, %{"results" => results}} = search(state, "Radweg Bahnhofstraße")

    assert [%{"title" => "Radverkehrskonzept Gartenstadt 2030", "snippet" => snippet} | _] =
             results

    assert snippet =~ "Radweg in der Bahnhofstraße"
    assert length(results) == 2

    assert [%{"path" => "/res/v1/web/search", "status" => 200}] = Server.log(mock)
  end

  test "keine Treffer", %{state: state} do
    assert {:ok, %{"results" => []}} = search(state, "Kläranlage")
  end

  test "falscher Schlüssel ergibt credential-missing", %{mock: mock, data: data, state: state} do
    {:ok, _} = Server.put_data(mock, %{data | "key" => "ein-anderer"})
    assert {:error, "credential-missing", _} = search(state, "Radweg")
  end

  test "Rate-Limit nach aufgebrauchtem Kontingent", %{mock: mock, data: data, state: state} do
    {:ok, _} = Server.put_data(mock, %{data | "key" => @key, "quota" => 1})

    assert {:ok, _} = search(state, "Radweg")
    assert {:error, "upstream-error", detail} = search(state, "Radweg")
    assert detail =~ "429"
  end

  test "Störfälle der Runtime: Fehler und nicht erreichbar", %{mock: mock, state: state} do
    {:ok, _} = Server.scenario(mock, "error")
    assert {:error, "upstream-error", _} = search(state, "Radweg")

    {:ok, _} = Server.scenario(mock, "refused")
    assert {:error, "upstream-error", _} = search(state, "Radweg")

    {:ok, _} = Server.reset(mock)
    assert {:ok, %{"results" => [_ | _]}} = search(state, "Radweg")
  end
end
