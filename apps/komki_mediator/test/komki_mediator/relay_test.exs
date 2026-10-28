defmodule KomkiMediator.RelayTest do
  # Ticket #143: komki-relay.js (aus komki_cli, dort in pis pi-Home
  # geschrieben) uebersetzt stdio-MCP in HTTP ueber den Unix-Socket. Der Test
  # startet `node komki-relay.js` gegen einen echten Vermittler und spielt
  # den Handschlag, tools/list und tools/call ping durch.
  use ExUnit.Case, async: false

  alias KomkiMediator.TestHelpers

  @moduletag :node

  @relay Path.expand("../../../komki_cli/priv/komki-relay.js", __DIR__)
  @session "ses-00112233aabbccdd"

  setup do
    TestHelpers.stop_named(KomkiMediator.Env)
    TestHelpers.stop_named(KomkiMediator.Journal)
    server = TestHelpers.start_socket_server!()
    on_exit(fn -> File.rm(server.socket) end)
    server
  end

  test "initialize, tools/list und tools/call ping ueber das Relay", %{
    socket: socket,
    token: token,
    journal_path: journal_path
  } do
    relay = start_relay(socket, token)

    send_line(relay, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-06-18",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "relay-test", "version" => "0"}
      }
    })

    assert %{"id" => 1, "result" => %{"serverInfo" => %{"name" => "komki"}}} = read_line(relay)

    # Notification: 202 ohne Antwortzeile.
    send_line(relay, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
    send_line(relay, %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})

    assert %{"id" => 2, "result" => %{"tools" => tools}} = read_line(relay)
    assert Enum.sort(Enum.map(tools, & &1["name"])) == Enum.sort(KomkiMediator.Fassung.tools())

    send_line(relay, %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{"name" => "ping", "arguments" => %{}}
    })

    assert %{"id" => 3, "result" => %{"isError" => false}} = read_line(relay)

    assert [
             %{"tool" => "ping", "outcome" => "executing", "session_id" => @session},
             %{"tool" => "ping", "outcome" => "admitted", "session_id" => @session}
           ] = TestHelpers.journal_records(journal_path)

    Port.close(relay)
  end

  test "falsches Token: JSON-RPC-Fehler mit passender id, kein Token auf stdout", %{
    socket: socket
  } do
    wrong = String.duplicate("0", 64)
    relay = start_relay(socket, wrong)

    send_line(relay, %{"jsonrpc" => "2.0", "id" => 7, "method" => "tools/list"})

    assert %{"id" => 7, "error" => %{"code" => -32_000, "message" => message}} = read_line(relay)
    assert message =~ "401"
    refute message =~ wrong

    Port.close(relay)
  end

  test "Vermittler nicht erreichbar: JSON-RPC-Fehler statt Absturz", %{token: token} do
    relay = start_relay("/tmp/kmt-gibt-es-nicht.sock", token)

    send_line(relay, %{"jsonrpc" => "2.0", "id" => "a", "method" => "tools/list"})
    assert %{"id" => "a", "error" => %{"code" => -32_000}} = read_line(relay)

    Port.close(relay)
  end

  # stderr bleibt beim Port unverbunden (geht an die Test-Konsole); stdout
  # liefert genau die JSON-RPC-Zeilen.
  defp start_relay(socket, token) do
    Port.open({:spawn_executable, System.find_executable("node")}, [
      :binary,
      {:line, 1_000_000},
      {:args, [@relay]},
      {:env,
       [
         {~c"KOMKI_MEDIATOR_SOCKET", String.to_charlist(socket)},
         {~c"KOMKI_MEDIATOR_TOKEN", String.to_charlist(token)},
         {~c"KOMKI_SESSION_ID", String.to_charlist(@session)}
       ]}
    ])
  end

  defp send_line(port, message), do: Port.command(port, JSON.encode!(message) <> "\n")

  defp read_line(port) do
    receive do
      {^port, {:data, {:eol, line}}} -> JSON.decode!(line)
    after
      10_000 -> flunk("keine Antwortzeile vom Relay")
    end
  end
end
