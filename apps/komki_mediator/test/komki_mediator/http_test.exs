defmodule KomkiMediator.HTTPTest do
  # Ticket #143: Der Vermittler lauscht nur auf einem Unix-Socket und
  # verlangt das Bearer-Token. Die Tests laufen gegen einen echten
  # Vermittler-Baum (Bandit auf dem Socket).
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias KomkiMediator.TestHelpers

  @setup_headers [
    {"content-type", "application/json"},
    {"accept", "application/json"}
  ]
  @session "ses-0123456789abcdef"
  @canary "kanarienvogel-185-Bahnhofstrasse"

  setup do
    TestHelpers.stop_named(KomkiMediator.Env)
    TestHelpers.stop_named(KomkiMediator.Journal)

    start_supervised!({Finch, name: KomkiMediatorTestFinch})
    server = TestHelpers.start_socket_server!()
    on_exit(fn -> File.rm(server.socket) end)
    server
  end

  describe "Token (CONTRACT §8)" do
    test "ohne Token: 401 und Logzeile ohne Token-Wert", %{socket: socket, token: token} do
      log =
        capture_log(fn ->
          assert {:ok, %Finch.Response{status: 401}} =
                   mcp_post(socket, initialize(1), @setup_headers)
        end)

      assert log =~ "401"
      assert log =~ "ohne Token"
      refute log =~ token
    end

    test "falsches Token: 401, auch der Logeintrag nennt es nicht", %{socket: socket} do
      wrong = String.duplicate("0", 64)

      log =
        capture_log(fn ->
          assert {:ok, %Finch.Response{status: 401}} =
                   mcp_post(socket, initialize(1), [auth(wrong) | @setup_headers])
        end)

      assert log =~ "falsches Token"
      refute log =~ wrong
    end

    test "richtiges Token: initialize 200", %{socket: socket, token: token} do
      assert {:ok, %Finch.Response{status: 200, body: body}} =
               mcp_post(socket, initialize(1), [auth(token) | @setup_headers])

      assert JSON.decode!(body)["result"]["serverInfo"]["name"] == "komki"
    end

    test "/healthz: 401 ohne Token, 200 mit Token und fixierten Schluesseln", %{
      socket: socket,
      token: token
    } do
      capture_log(fn ->
        assert {:ok, %Finch.Response{status: 401}} = get(socket, "/healthz", [])
      end)

      assert {:ok, %Finch.Response{status: 200, body: body}} =
               get(socket, "/healthz", [auth(token)])

      health = JSON.decode!(body)
      assert health["status"] == "ok"
      assert health["fassung_id"] == "komki-mediator/2"
      assert health["tools"] == KomkiMediator.Fassung.tools()
      assert health["registry_id"] == "reg-komki-arbeitsraum"
      assert health["gamma_hash"] =~ "sha256:"
    end
  end

  describe "Listener" do
    test "Socket-Datei hat die Rechte 0600", %{socket: socket} do
      {:ok, stat} = File.lstat(socket)
      assert stat.type == :other
      assert Bitwise.band(stat.mode, 0o777) == 0o600
    end

    test "kein TCP-Listener: der Vermittler bindet keine IP-Adresse" do
      # Andere Teile der Test-VM duerfen IP-Sockets halten; entscheidend ist,
      # dass der Vermittler-Baum keinen beitraegt.
      with_mediator = ip_bound_tcp()
      :ok = stop_supervised(KomkiMediator.Supervisor)
      assert with_mediator == ip_bound_tcp()
    end

    test "zweiter Start auf demselben Socket wird verweigert", %{socket: socket} do
      assert {:error, %{"error" => "socket"}} = KomkiMediator.CLI.socket_free(socket)
      assert :ok = KomkiMediator.CLI.socket_free(socket <> ".frei")
    end
  end

  describe "MCP ueber den Socket" do
    test "initialize und tools/list liefern die Fassung", %{socket: socket, token: token} do
      mcp = handshake!(socket, token)

      assert {:ok, %Finch.Response{status: 200, body: body}} =
               mcp_post(socket, %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"}, mcp)

      names = Enum.map(JSON.decode!(body)["result"]["tools"], & &1["name"])
      assert Enum.sort(names) == Enum.sort(KomkiMediator.Fassung.tools())
    end

    test "X-Komki-Session landet als session_id im PDR", %{
      socket: socket,
      token: token,
      journal_path: journal_path
    } do
      mcp = handshake!(socket, token, [{"x-komki-session", @session}])

      assert {:ok, %Finch.Response{status: 200, body: body}} =
               mcp_post(socket, call_ping(3), mcp)

      assert JSON.decode!(body)["result"]["isError"] == false

      assert [_executing, record] = TestHelpers.journal_records(journal_path)
      assert record["tool"] == "ping"
      assert record["session_id"] == @session
    end

    test "ohne X-Komki-Session: session_id null im PDR", %{
      socket: socket,
      token: token,
      journal_path: journal_path
    } do
      mcp = handshake!(socket, token)
      assert {:ok, %Finch.Response{status: 200}} = mcp_post(socket, call_ping(3), mcp)

      assert [%{"session_id" => nil}, %{"session_id" => nil}] =
               TestHelpers.journal_records(journal_path)
    end

    test "ungueltige X-Komki-Session: 400", %{socket: socket, token: token} do
      headers = [auth(token), {"x-komki-session", "Ungueltig!"} | @setup_headers]

      assert {:ok, %Finch.Response{status: 400}} = mcp_post(socket, initialize(1), headers)
    end
  end

  describe "Log ohne Inhalte (Ticket #185)" do
    setup do
      level = Logger.level()
      anubis_log = Application.get_env(:anubis_mcp, :log, true)
      Logger.configure(level: :debug)

      on_exit(fn ->
        Application.put_env(:anubis_mcp, :log, anubis_log)
        Logger.configure(level: level)
      end)
    end

    test "Gegenprobe: ohne quiet_logging steht der Kanarienwert im Debug-Log", %{
      socket: socket,
      token: token
    } do
      Application.put_env(:anubis_mcp, :log, true)
      assert call_with_canary(socket, token) =~ @canary
    end

    test "mit quiet_logging steht der Kanarienwert nicht im Log", %{
      socket: socket,
      token: token
    } do
      :ok = KomkiMediator.CLI.quiet_logging()
      Logger.configure(level: :debug)

      refute call_with_canary(socket, token) =~ @canary
    end
  end

  defp call_with_canary(socket, token) do
    capture_log([level: :debug], fn ->
      mcp = handshake!(socket, token)
      call = put_in(call_ping(3), ["params", "arguments"], %{"notiz" => @canary})
      assert {:ok, %Finch.Response{status: 200}} = mcp_post(socket, call, mcp)
    end)
  end

  # -----------------------------------------------------------------------
  # Helfer
  # -----------------------------------------------------------------------

  defp ip_bound_tcp do
    for port <- Port.list(),
        Port.info(port, :name) == {:name, ~c"tcp_inet"},
        {:ok, {address, _}} <- [:inet.sockname(port)],
        is_tuple(address),
        into: MapSet.new(),
        do: port
  end

  defp auth(token), do: {"authorization", "Bearer " <> token}

  defp initialize(id) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-06-18",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "komki-mediator-test", "version" => "0"}
      }
    }
  end

  defp call_ping(id) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "tools/call",
      "params" => %{"name" => "ping", "arguments" => %{}}
    }
  end

  # MCP-Handschlag: initialize, Mcp-Session-Id lesen, dann die
  # initialized-Notification (202). Liefert die Header fuer Folgeanfragen.
  defp handshake!(socket, token, extra \\ []) do
    base = [auth(token) | extra] ++ @setup_headers

    {:ok, %Finch.Response{status: 200, headers: headers}} =
      mcp_post(socket, initialize(1), base)

    mcp_session = Enum.find_value(headers, fn {k, v} -> if k == "mcp-session-id", do: v end)
    assert is_binary(mcp_session)
    with_session = [{"mcp-session-id", mcp_session} | base]

    initialized = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
    {:ok, %Finch.Response{status: 202}} = mcp_post(socket, initialized, with_session)
    with_session
  end

  defp get(socket, path, headers) do
    :get
    |> Finch.build("http://localhost" <> path, headers, nil, unix_socket: socket)
    |> Finch.request(KomkiMediatorTestFinch, receive_timeout: 5000)
  end

  defp mcp_post(socket, body, headers) do
    :post
    |> Finch.build("http://localhost/mcp", headers, JSON.encode!(body), unix_socket: socket)
    |> Finch.request(KomkiMediatorTestFinch, receive_timeout: 5000)
  end
end
