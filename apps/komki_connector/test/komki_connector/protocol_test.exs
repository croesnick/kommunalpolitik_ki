defmodule KomkiConnector.ProtocolTest do
  use ExUnit.Case, async: true

  alias KomkiConnector.{Client, Frame, Manifest, Params, Server}

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
    def handle_op("show", _params, _context, _state), do: {:error, "not-found", "nicht da"}
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "kc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "ris.sock")
    {:ok, listener} = Server.listen(path)
    pid = spawn(fn -> Server.accept_loop(listener, Echo, "zustand") end)
    _ = :gen_tcp.controlling_process(listener, pid)

    on_exit(fn ->
      Process.exit(pid, :kill)
      File.rm_rf!(dir)
    end)

    %{path: path}
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
    assert {:error, %{"code" => "not-found"}} = Client.call(path, "c", "show", %{"top_id" => "x"})

    assert {:error, %{"code" => "internal"}} =
             Client.call(path, "c", "show", %{"top_id" => "boom"})
  end

  test "nicht erreichbarer Socket ergibt upstream-error" do
    assert {:error, %{"code" => "upstream-error"}} =
             Client.call("/nonexistent/x.sock", "c", "ping", %{})
  end

  test "ungueltige Frames" do
    assert %{"ok" => false, "error" => %{"code" => "bad-request"}} =
             Server.handle_frame("kein json", Echo, nil)

    assert %{"ok" => false} = Server.handle_frame(~s({"v":2,"call_id":"a"}), Echo, nil)
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
    assert length(tools) == 6
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
