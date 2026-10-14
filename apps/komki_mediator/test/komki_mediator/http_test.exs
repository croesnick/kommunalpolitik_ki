defmodule KomkiMediator.HTTPTest do
  use ExUnit.Case, async: false

  alias KomkiMediator.{Supervisor, TestHelpers}

  @test_ports [49_721, 49_722, 49_723]
  @setup_headers [
    {"content-type", "application/json"},
    {"accept", "application/json"}
  ]
  @body_timeout [receive_timeout: 5000]

  setup do
    # Ueberreste frueherer benannter Prozesse weg, danach startet der
    # Supervisor Journal und Env selbst.
    TestHelpers.stop_named(KomkiMediator.Env)
    TestHelpers.stop_named(KomkiMediator.Journal)

    {:ok, _} = Finch.start_link(name: KomkiMediatorTestFinch)

    case start_test_server() do
      {:ok, port, _base} ->
        %{port: port}

      :all_ports_taken ->
        {:skip, :all_test_ports_taken}
    end
  end

  test "/healthz: 200 mit dem Vertrag fixierter Schluessel", %{port: port} do
    assert {:ok, %Finch.Response{status: 200, body: body}} =
             get(port, "/healthz", @setup_headers)

    {:ok, health} = JSON.decode(body)

    assert health["status"] == "ok"
    assert health["fassung_id"] == "komki-mediator/1"
    assert health["tools"] == ["ping", "admit_document"]
    assert health["registry_id"] == "reg-komki-arbeitsraum"
    assert health["gamma_hash"] =~ "sha256:"
  end

  test "POST /mcp: initialize and tools/list liefern die Fassung", %{port: port} do
    initialize =
      %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-06-18",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "komki-mediator-test", "version" => "0"}
        }
      }

    assert {:ok, %Finch.Response{status: 200, headers: headers, body: body}} =
             mcp_post(port, initialize, [])

    {:ok, reply} = JSON.decode(body)
    assert reply["result"]["serverInfo"]["name"] == "komki"

    session_id = session_id_from_headers(headers)
    assert is_binary(session_id) and session_id != ""

    # MCP-Handschuh: erst die "initialized"-Notification (202), dann tools/list.
    initialized = %{"jsonrpc" => "2.0", "method" => "notifications/initialized", "params" => %{}}

    assert {:ok, %Finch.Response{status: 202}} =
             mcp_post(port, initialized, [{"mcp-session-id", session_id}])

    tools_list = %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}}

    assert {:ok, %Finch.Response{status: 200, body: body2}} =
             mcp_post(port, tools_list, [{"mcp-session-id", session_id}])

    {:ok, reply2} = JSON.decode(body2)

    names = Enum.map(reply2["result"]["tools"], fn tool -> tool["name"] end)

    # D.9: die advertised Flaeche == die Fassung.
    assert Enum.sort(names) == Enum.sort(KomkiMediator.Fassung.tools())
  end

  # -----------------------------------------------------------------------
  # Helfer
  # -----------------------------------------------------------------------

  defp start_test_server do
    Enum.find_value(@test_ports, fn port ->
      base = TestHelpers.provisioned_base()
      {gamma, room} = TestHelpers.load_room_env(base)

      case Supervisor.start_link(
             {Path.join([base, "mediator", "journal", "pdr.jsonl"]), gamma, room, port}
           ) do
        {:ok, _pid} -> {:ok, port, base}
        {:error, _} -> nil
      end
    end) || :all_ports_taken
  end

  defp get(port, path, headers) do
    request = Finch.build(:get, url(port, path), headers)
    Finch.request(request, KomkiMediatorTestFinch, @body_timeout)
  end

  defp mcp_post(port, body, extra_headers) do
    headers = @setup_headers ++ extra_headers
    request = Finch.build(:post, url(port, "/mcp"), headers, JSON.encode!(body))
    Finch.request(request, KomkiMediatorTestFinch, @body_timeout)
  end

  defp url(port, path), do: "http://127.0.0.1:#{port}#{path}"

  defp session_id_from_headers(headers) do
    Enum.find_value(headers, fn {name, value} -> if name == "mcp-session-id", do: value end)
  end
end
