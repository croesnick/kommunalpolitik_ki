defmodule KomkiConnector.ProtocolTest do
  use ExUnit.Case, async: true

  alias KomkiConnector.{Client, Frame, Manifest, Params, Server, Token}

  defmodule Echo do
    @behaviour KomkiConnector.Server

    @impl true
    def manifest_id, do: "ris"

    @impl true
    def init(arg), do: {:ok, arg}

    @impl true
    def handle_op("search", params, context, state),
      do: {:ok, %{"params" => params, "context" => context, "state" => state}}

    def handle_op("show", %{"top_id" => "boom"}, _context, _state), do: raise("kaputt")

    def handle_op("show", %{"top_id" => "leck" <> _} = params, _context, _state),
      do: raise(MatchError, term: params)

    def handle_op("show", _params, _context, _state), do: {:error, "not-found", "DETAIL-KANARIE"}
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "kc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "ris.sock")
    {:ok, listener} = Server.listen(path)
    token = Token.provision!(path)
    pid = spawn(fn -> Server.accept_loop(listener, Echo, "zustand", token) end)
    _ = :gen_tcp.controlling_process(listener, pid)

    on_exit(fn ->
      Process.exit(pid, :kill)
      File.rm_rf!(dir)
    end)

    %{path: path, token: token}
  end

  # Roh-Anfrage an den Socket, am Client vorbei (wie ein fremder Prozess).
  defp raw(path, frame) do
    {:ok, sock} = :gen_tcp.connect({:local, String.to_charlist(path)}, 0, Frame.socket_opts())
    {:ok, bin} = Frame.encode(frame)
    :ok = :gen_tcp.send(sock, bin)
    {:ok, reply} = :gen_tcp.recv(sock, 0, 5_000)
    :gen_tcp.close(sock)
    {:ok, map} = Frame.decode(reply)
    map
  end

  test "Socket-Datei hat Rechte 0600", %{path: path} do
    assert {:ok, %File.Stat{mode: mode}} = File.stat(path)
    assert Bitwise.band(mode, 0o777) == 0o600
  end

  test "Aufruf mit Default-Parameter und Kontext", %{path: path} do
    assert {:ok, result} =
             Client.call(path, "pdr-1", "search", %{"text" => "Bahnhof"}, %{"x" => 1})

    assert result["params"] == %{"text" => "Bahnhof", "limit" => 10}
    assert result["context"] == %{"x" => 1}
    assert result["state"] == "zustand"
  end

  test "ping beantwortet der Server aus dem Manifest", %{path: path} do
    assert {:ok, %{"fassung" => "komki-ris/1", "ops" => ["search", "show"]}} =
             Client.call(path, "pdr-2", "ping", %{})
  end

  test "unbekannte Felder, Operationen und Formatverstoesse werden abgewiesen", %{path: path} do
    assert {:error, %{"code" => "bad-request"}} =
             Client.call(path, "c", "search", %{"text" => "a", "url" => "http://x"})

    assert {:error, %{"code" => "unknown-op"}} = Client.call(path, "c", "delete", %{})

    assert {:error, %{"code" => "bad-request"}} =
             Client.call(path, "c", "show", %{"top_id" => "../etc/passwd"})

    assert {:error, %{"code" => "bad-request"}} =
             Client.call(path, "c", "search", %{"text" => "a", "limit" => 99})
  end

  test "Connector-Fehler und Absturz bleiben geschlossene Codes", %{path: path} do
    # Der Freitext des Connectors erreicht den Vermittler nicht, nur der feste Text.
    assert {:error, %{"code" => "not-found", "detail" => "nicht gefunden"}} =
             Client.call(path, "c", "show", %{"top_id" => "x"})

    assert {:error, %{"code" => "internal"}} =
             Client.call(path, "c", "show", %{"top_id" => "boom"})
  end

  test "Absturz-Logzeile nennt den Fehlertyp, nicht die Parameter (Ticket #185)", %{path: path} do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, %{"code" => "internal"}} =
                 Client.call(path, "c", "show", %{"top_id" => "leck185kanarie"})
      end)

    assert log =~ "MatchError"
    refute log =~ "leck185kanarie"
  end

  test "nicht erreichbarer Socket ergibt upstream-error" do
    assert {:error, %{"code" => "upstream-error"}} =
             Client.call("/nonexistent/x.sock", "c", "ping", %{})
  end

  test "ungueltige Frames" do
    assert %{"ok" => false, "error" => %{"code" => "bad-request"}} =
             Server.handle_frame("kein json", Echo, nil, Token.generate())

    assert %{"ok" => false} =
             Server.handle_frame(~s({"v":2,"call_id":"a"}), Echo, nil, Token.generate())
  end

  describe "Capability-Token (Negativtests Steuerebene)" do
    test "Anfrage ohne Token wird abgewiesen, auch ping", %{path: path} do
      for op <- ["ping", "search"] do
        reply = raw(path, %{"v" => 1, "call_id" => "x", "op" => op, "params" => %{"text" => "a"}})

        assert %{"ok" => false, "call_id" => "", "error" => %{"code" => "unauthorized"}} =
                 reply
      end
    end

    test "falsches Token wird abgewiesen und verraet keine Ergebnisse", %{path: path} do
      frame = Frame.request(Token.generate(), "x", "search", %{"text" => "a"})
      reply = raw(path, frame)
      assert reply["error"]["code"] == "unauthorized"
      refute Map.has_key?(reply, "result")
    end

    test "richtiges Token direkt am Socket wird angenommen", %{path: path, token: token} do
      assert %{"ok" => true} = raw(path, Frame.request(token, "x", "ping", %{}))
    end

    test "fehlende Tokendatei: der Client ruft nicht ohne Token", %{path: path} do
      File.rm!(Token.for_socket(path))

      assert {:error, %{"code" => "unauthorized"}} = Client.call(path, "c", "ping", %{})
    end

    test "Server startet nicht ohne gueltiges Token" do
      assert {:error, "kein gueltiges Connector-Token"} =
               Server.run(Echo, "/tmp/nie.sock", nil, %{})

      assert {:error, _} =
               Server.run(Echo, "/tmp/nie.sock", nil, %{Token.credential_key() => "kurz"})

      refute File.exists?("/tmp/nie.sock")
    end

    test "Tokendatei hat Rechte 0600", %{path: path} do
      assert {:ok, %File.Stat{mode: mode}} = File.stat(Token.for_socket(path))
      assert Bitwise.band(mode, 0o777) == 0o600
    end
  end

  test "Credentials von stdin" do
    {:ok, dev} = StringIO.open(~s({"BRAVE_API_KEY":"geheim"}\n))
    assert {:ok, %{"BRAVE_API_KEY" => "geheim"}} = Server.read_credentials(dev)
    {:ok, empty} = StringIO.open("")
    assert {:ok, %{}} = Server.read_credentials(empty)
    {:ok, bad} = StringIO.open(~s({"A":1}))
    assert {:error, _} = Server.read_credentials(bad)
  end

  test "Manifeste: Tools eindeutig, by_tool, keine URL- oder Host-Parameter" do
    tools = Manifest.tools()
    assert tools == Enum.uniq(tools)
    assert length(tools) == 7
    assert {:ok, %{id: "documents"}, "read"} = Manifest.by_tool("admit_document")
    assert {:ok, %{id: "vault"}, "write_test"} = Manifest.by_tool("vault_write_test")
    assert :error = Manifest.by_tool("exec")

    for m <- Manifest.all(), {_op, spec} <- m.ops, name <- Map.keys(spec.params) do
      refute name in ["url", "host", "path", "command"]
    end
  end

  test "Params.check" do
    schema = Manifest.fetch!("vault").ops["read"].params
    assert {:ok, _} = Params.check(schema, %{"note_id" => "projekte/Bahnhof.md"})
    assert {:error, _} = Params.check(schema, %{"note_id" => "x.txt"})
    assert {:error, _} = Params.check(schema, %{})
    assert {:error, _} = Params.check(schema, %{"note_id" => 5})
  end

  test "Frame.encode verweigert > 1 MiB" do
    assert {:error, :too_large} =
             Frame.encode(%{"v" => 1, "x" => String.duplicate("a", 1_100_000)})
  end
end
