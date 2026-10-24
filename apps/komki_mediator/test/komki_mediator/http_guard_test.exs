defmodule KomkiMediator.HTTPGuardTest do
  # Tickets #133/#143: Aufrufer-Pruefung vor jeder Route. Abgewiesene Aufrufe
  # enden im Guard, deshalb genuegt Plug.Test ohne laufenden Server.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test
  import Plug.Conn

  alias KomkiMediator.HTTP

  @body ~s({"jsonrpc":"2.0","id":1,"method":"tools/list"})
  @token String.duplicate("ab", 32)
  @auth {"authorization", "Bearer " <> String.duplicate("ab", 32)}
  @json {"content-type", "application/json"}

  defp request(method, path, host, headers, body \\ nil) do
    conn = put_private(%{conn(method, path, body) | host: host}, :komki_token, @token)
    Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
  end

  defp post(host, headers), do: request(:post, "/mcp", host, headers, @body)

  defp guard(conn), do: HTTP.guard_caller(conn, [])

  describe "Token" do
    test "ohne Authorization: 401" do
      log =
        capture_log(fn ->
          conn = guard(post("localhost", [@json]))
          assert conn.halted
          assert conn.status == 401
        end)

      assert log =~ "401"
    end

    test "falsches Token und falsches Schema: 401" do
      for header <- ["Bearer " <> String.duplicate("cd", 32), "Basic " <> @token, @token] do
        capture_log(fn ->
          conn = guard(post("localhost", [{"authorization", header}, @json]))
          assert conn.status == 401
        end)
      end
    end

    test "ohne Token im Prozess wird nichts durchgelassen (fail-closed)" do
      conn =
        put_req_header(%{conn(:get, "/healthz") | host: "localhost"}, "authorization", "Bearer ")

      capture_log(fn -> assert guard(conn).status == 401 end)
    end

    test "GET /healthz braucht das Token ebenfalls" do
      capture_log(fn ->
        assert guard(request(:get, "/healthz", "localhost", [])).status == 401
      end)

      refute guard(request(:get, "/healthz", "localhost", [@auth])).halted
    end
  end

  describe "Host, Origin, Content-Type (mit gueltigem Token)" do
    test "fremder Host wird mit 403 abgewiesen" do
      conn = guard(post("evil.example", [@auth, @json]))
      assert conn.halted
      assert conn.status == 403
    end

    test "gesetzter Origin wird abgewiesen" do
      conn = guard(post("localhost", [@auth, @json, {"origin", "http://localhost"}]))
      assert conn.status == 403
    end

    test "POST mit text/plain oder ohne Content-Type: 415" do
      assert guard(post("localhost", [@auth, {"content-type", "text/plain"}])).status == 415
      assert guard(post("localhost", [@auth])).status == 415
    end

    test "relay-foermiger Aufruf passiert den Guard" do
      for host <- ["localhost", "127.0.0.1"] do
        conn = guard(post(host, [@auth, {"content-type", "application/json; charset=utf-8"}]))
        refute conn.halted
      end
    end
  end

  describe "X-Komki-Session" do
    test "gueltige Session-ID landet in den Assigns" do
      conn = guard(post("localhost", [@auth, @json, {"x-komki-session", "ses-0123456789abcdef"}]))
      refute conn.halted
      assert conn.assigns.komki_session == "ses-0123456789abcdef"
    end

    test "ohne Header: nil in den Assigns" do
      conn = guard(post("localhost", [@auth, @json]))
      assert conn.assigns.komki_session == nil
    end

    test "ungueltiges Format: 400" do
      for bad <- ["kurz", "GROSS-0123456789", String.duplicate("a", 65), "ses_0123456789"] do
        conn = guard(post("localhost", [@auth, @json, {"x-komki-session", bad}]))
        assert conn.status == 400, bad
      end
    end
  end
end
