defmodule Sidecar.ProtocolTest do
  @moduledoc """
  Protocol-level tests against a fixture sidecar (no host code, no
  host manifest): framing, capability token, parameter validation,
  error-code closure, and the optional peer-uid check.
  """

  use ExUnit.Case, async: true

  alias Sidecar.{Client, Frame, Params, Peer, Server, Token}

  defmodule Echo do
    @behaviour Sidecar.Server

    @impl true
    def manifest do
      %{
        version: "sidecar-test/1",
        ops: %{
          "search" => %{
            kind: :read,
            params: %{
              "text" => %{type: :string, max: 200, required: true},
              "limit" => %{type: :integer, min: 1, max: 20, required: false, default: 10}
            }
          },
          "show" => %{
            kind: :read,
            params: %{
              "top_id" => %{type: :string, max: 64, required: true, pattern: ~r/^[A-Za-z0-9_-]+$/}
            }
          }
        }
      }
    end

    @impl true
    def init(arg), do: {:ok, arg}

    @impl true
    def handle_op("search", params, context, state),
      do: {:ok, %{"params" => params, "context" => context, "state" => state}}

    def handle_op("show", %{"top_id" => "boom"}, _context, _state), do: raise("kaputt")

    def handle_op("show", %{"top_id" => "leck" <> _} = params, _context, _state),
      do: raise(MatchError, term: params)

    def handle_op("show", _params, _context, _state), do: {:error, "not-found", "DETAIL-CANARY"}
  end

  # A host with its own user-facing language, injected via the texts: option.
  defmodule HostTexts do
    @behaviour Sidecar.Texts

    @impl true
    def describe("not-found"), do: "nicht gefunden"
    def describe(code), do: Sidecar.Texts.describe(code)

    @impl true
    def transport(:no_token, _reason), do: "sidecar token missing"
    def transport(kind, reason), do: Sidecar.Texts.transport(kind, reason)

    @impl true
    def params_error(:missing_required, %{name: name}), do: "Pflichtfeld fehlt: #{name}"
    def params_error(kind, info), do: Sidecar.Texts.params_error(kind, info)
  end

  defp harness(path, peer \\ false) do
    {:ok, listener} = Server.listen(path)
    token = Token.provision!(path)
    pid = spawn(fn -> Server.accept_loop(listener, Echo, "state", token, peer: peer) end)
    _ = :socket.setopt(listener, {:otp, :controlling_process}, pid)

    on_exit(fn ->
      Process.exit(pid, :kill)
      File.rm_rf!(Path.dirname(path))
    end)

    token
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "sc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sidecar.sock")
    token = harness(path)
    %{path: path, token: token}
  end

  # run/5 binds asynchronously in its own process. The chmod to 0600 comes
  # after listen, so a 0600 socket file is one that accepts connections.
  defp wait_for_socket(path, tries \\ 100) do
    cond do
      match?({:ok, %File.Stat{mode: m}} when Bitwise.band(m, 0o777) == 0o600, File.stat(path)) ->
        :ok

      tries == 0 ->
        flunk("socket #{path} never appeared")

      true ->
        Process.sleep(10) && wait_for_socket(path, tries - 1)
    end
  end

  # The test process's uid as the OS reports it, independent of Sidecar.Peer.
  defp own_uid do
    {out, 0} = System.cmd("id", ["-u"])
    out |> String.trim() |> String.to_integer()
  end

  # Raw request to the socket, bypassing the client (like a foreign process).
  defp raw(path, frame) do
    {:ok, sock} = :gen_tcp.connect({:local, String.to_charlist(path)}, 0, Frame.socket_opts())
    {:ok, bin} = Frame.encode(frame)
    :ok = :gen_tcp.send(sock, bin)
    {:ok, reply} = :gen_tcp.recv(sock, 0, 5_000)
    :gen_tcp.close(sock)
    {:ok, map} = Frame.decode(reply)
    map
  end

  test "socket file has mode 0600", %{path: path} do
    assert {:ok, %File.Stat{mode: mode}} = File.stat(path)
    assert Bitwise.band(mode, 0o777) == 0o600
  end

  test "call with default parameter and context", %{path: path} do
    assert {:ok, result} =
             Client.call(path, "pdr-1", "search", %{"text" => "station"}, %{"x" => 1})

    assert result["params"] == %{"text" => "station", "limit" => 10}
    assert result["context"] == %{"x" => 1}
    assert result["state"] == "state"
  end

  test "ping is answered by the server from the manifest", %{path: path} do
    assert {:ok, %{"version" => "sidecar-test/1", "ops" => ["search", "show"]}} =
             Client.call(path, "pdr-2", "ping", %{})
  end

  test "unknown fields, operations and format violations are rejected", %{path: path} do
    assert {:error, %{"code" => "bad-request"}} =
             Client.call(path, "c", "search", %{"text" => "a", "url" => "http://x"})

    assert {:error, %{"code" => "unknown-op"}} = Client.call(path, "c", "delete", %{})

    assert {:error, %{"code" => "bad-request"}} =
             Client.call(path, "c", "show", %{"top_id" => "../etc/passwd"})

    assert {:error, %{"code" => "bad-request"}} =
             Client.call(path, "c", "search", %{"text" => "a", "limit" => 99})
  end

  test "sidecar errors and crashes stay inside the closed code set", %{path: path} do
    # The sidecar's free text never reaches the caller, only the fixed text.
    assert {:error, %{"code" => "not-found", "detail" => "not found"}} =
             Client.call(path, "c", "show", %{"top_id" => "x"})

    assert {:error, %{"code" => "internal"}} =
             Client.call(path, "c", "show", %{"top_id" => "boom"})
  end

  test "crash log line names the exception type, not the parameters", %{path: path} do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, %{"code" => "internal"}} =
                 Client.call(path, "c", "show", %{"top_id" => "leck-canary"})
      end)

    assert log =~ "MatchError"
    refute log =~ "leck-canary"
  end

  test "the sidecar's own error detail appears in its log, not in the reply", %{path: path} do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, %{"code" => "not-found"}} =
                 Client.call(path, "c", "show", %{"top_id" => "x"})
      end)

    assert log =~ "DETAIL-CANARY"
  end

  test "unreachable socket gives upstream-error" do
    assert {:error, %{"code" => "upstream-error"}} =
             Client.call("/nonexistent/x.sock", "c", "ping", %{})
  end

  test "invalid frames" do
    assert %{"ok" => false, "error" => %{"code" => "bad-request"}} =
             Server.handle_frame("kein json", Echo, nil, Token.generate())

    assert %{"ok" => false} =
             Server.handle_frame(~s({"v":2,"call_id":"a"}), Echo, nil, Token.generate())
  end

  test "transport error details come from the default English texts", %{path: path} do
    File.rm!(Token.for_socket(path))

    assert {:error, %{"code" => "unauthorized", "detail" => "sidecar token missing"}} =
             Client.call(path, "c", "ping", %{})

    assert {:error, %{"code" => "upstream-error", "detail" => "sidecar unreachable: :enoent"}} =
             Client.call("/nonexistent/x.sock", "c", "ping", %{})
  end

  test "texts: injects the host's language", %{path: path} do
    assert {:error, %{"code" => "not-found", "detail" => "nicht gefunden"}} =
             Client.call(path, "c", "show", %{"top_id" => "x"}, %{}, texts: HostTexts)

    schema = Echo.manifest().ops["show"].params
    assert {:error, {:params, "Pflichtfeld fehlt: top_id"}} = Params.check(schema, %{}, HostTexts)
    assert {:error, {:params, "required field missing: top_id"}} = Params.check(schema, %{})
  end

  describe "capability token" do
    test "request without a token is rejected, even ping", %{path: path} do
      for op <- ["ping", "search"] do
        reply = raw(path, %{"v" => 1, "call_id" => "x", "op" => op, "params" => %{"text" => "a"}})

        assert %{"ok" => false, "call_id" => "", "error" => %{"code" => "unauthorized"}} =
                 reply
      end
    end

    test "wrong token is rejected and reveals no results", %{path: path} do
      frame = Frame.request(Token.generate(), "x", "search", %{"text" => "a"})
      reply = raw(path, frame)
      assert reply["error"]["code"] == "unauthorized"
      refute Map.has_key?(reply, "result")
    end

    test "the correct token at the raw socket is accepted", %{path: path, token: token} do
      assert %{"ok" => true} = raw(path, Frame.request(token, "x", "ping", %{}))
    end

    test "missing token file: the client refuses to call", %{path: path} do
      File.rm!(Token.for_socket(path))

      assert {:error, %{"code" => "unauthorized"}} = Client.call(path, "c", "ping", %{})
    end

    test "the server does not start without a valid token" do
      assert {:error, :invalid_token} = Server.run(Echo, "/tmp/never.sock", nil, %{})

      assert {:error, :invalid_token} =
               Server.run(Echo, "/tmp/never.sock", nil, %{"SIDECAR_TOKEN" => "short"})

      refute File.exists?("/tmp/never.sock")
    end

    test "credential_key: names the stdin key that carries the token" do
      token = Token.generate()
      assert {:ok, ^token} = Server.fetch_token(%{"MY_TOKEN" => token}, "MY_TOKEN")
      assert {:error, :invalid_token} = Server.fetch_token(%{"MY_TOKEN" => token}, "OTHER")
      assert {:error, :invalid_token} = Server.fetch_token(%{}, "MY_TOKEN")
    end

    test "token file has mode 0600", %{path: path} do
      assert {:ok, %File.Stat{mode: mode}} = File.stat(Token.for_socket(path))
      assert Bitwise.band(mode, 0o777) == 0o600
    end
  end

  describe "framing" do
    test "a declared length beyond the 1 MiB cap closes the connection", %{path: path} do
      {:ok, sock} =
        :gen_tcp.connect({:local, String.to_charlist(path)}, 0, [:binary, active: false])

      :ok = :gen_tcp.send(sock, <<2_000_000::big-32, "x">>)
      assert {:error, :closed} = :gen_tcp.recv(sock, 0, 5_000)
      :gen_tcp.close(sock)
    end

    test "Frame.encode refuses > 1 MiB" do
      assert {:error, :too_large} =
               Frame.encode(%{"v" => 1, "x" => String.duplicate("a", 1_100_000)})
    end
  end

  describe "peer credentials" do
    @describetag :peer

    test "peer_uid/1 decodes the caller's real uid from the kernel" do
      dir = Path.join(System.tmp_dir!(), "sc-peer-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "sidecar.sock")
      on_exit(fn -> File.rm_rf!(dir) end)

      {:ok, listener} = Server.listen(path)
      {:ok, caller} = :gen_tcp.connect({:local, String.to_charlist(path)}, 0, Frame.socket_opts())
      {:ok, accepted} = :socket.accept(listener, 5_000)

      # Without this, a decoder that returns zeros or garbage would still
      # make the mismatch test below pass.
      assert Peer.peer_uid(accepted) == {:ok, own_uid()}

      :gen_tcp.close(caller)
      :socket.close(accepted)
      :socket.close(listener)
    end

    test "a caller of the sidecar's own uid is served" do
      dir = Path.join(System.tmp_dir!(), "sc-peer-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "sidecar.sock")
      harness(path, own_uid())

      assert {:ok, %{"version" => "sidecar-test/1"}} = Client.call(path, "c", "ping", %{})
    end

    test "a caller with a different uid is rejected before any reply" do
      dir = Path.join(System.tmp_dir!(), "sc-peer-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "sidecar.sock")
      harness(path, 99_999)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:error, %{"code" => "upstream-error"}} = Client.call(path, "c", "ping", %{})
        end)

      assert log =~ "peer_uid_mismatch"
    end

    test "run/5 with peer_credentials: true serves a caller of its own uid" do
      dir = Path.join(System.tmp_dir!(), "sc-peer-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "sidecar.sock")
      token = Token.provision!(path)
      creds = %{"SIDECAR_TOKEN" => token}

      pid = spawn(fn -> Server.run(Echo, path, "state", creds, peer_credentials: true) end)

      on_exit(fn ->
        Process.exit(pid, :kill)
        File.rm_rf!(dir)
      end)

      wait_for_socket(path)
      assert {:ok, %{"version" => "sidecar-test/1"}} = Client.call(path, "c", "ping", %{})
    end

    test "an invalid peer_credentials option fails before the socket is bound" do
      path = Path.join(System.tmp_dir!(), "sc-peer-#{System.unique_integer([:positive])}.sock")
      creds = %{"SIDECAR_TOKEN" => Token.generate()}

      assert {:error, {:invalid_peer_credentials, "yes"}} =
               Server.run(Echo, path, nil, creds, peer_credentials: "yes")

      refute File.exists?(path)
    end

    test "Peer.supported?/0 matches the platform's ability to report credentials" do
      assert Peer.supported?() == match?({:unix, os} when os in [:darwin, :linux], :os.type())
    end
  end

  test "credentials from stdin" do
    {:ok, dev} = StringIO.open(~s({"API_KEY":"secret"}\n))
    assert {:ok, %{"API_KEY" => "secret"}} = Server.read_credentials(dev)
    {:ok, empty} = StringIO.open("")
    assert {:ok, %{}} = Server.read_credentials(empty)
    {:ok, bad} = StringIO.open(~s({"A":1}))
    assert {:error, _} = Server.read_credentials(bad)
  end

  test "Params.check against the fixture schema" do
    schema = Echo.manifest().ops["show"].params
    assert {:ok, %{"top_id" => "a-b_1"}} = Params.check(schema, %{"top_id" => "a-b_1"})
    assert {:error, _} = Params.check(schema, %{"top_id" => "x.txt"})
    assert {:error, _} = Params.check(schema, %{})
    assert {:error, _} = Params.check(schema, %{"top_id" => 5})
  end
end
