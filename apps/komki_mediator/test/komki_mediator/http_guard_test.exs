defmodule KomkiMediator.HTTPGuardTest do
  # Ticket #133: Aufrufer-Pruefung vor jeder Route. Abgewiesene Aufrufe
  # enden im Guard, deshalb genuegt Plug.Test ohne laufenden Server.
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias KomkiMediator.HTTP

  @body ~s({"jsonrpc":"2.0","id":1,"method":"tools/list"})

  defp post(host, headers) do
    conn = Map.put(conn(:post, "/mcp", @body), :host, host)
    Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
  end

  defp guard(conn), do: HTTP.guard_caller(conn, [])

  test "fremder Host (DNS-Rebinding) wird mit 403 abgewiesen" do
    conn = guard(post("evil.example", [{"content-type", "application/json"}]))
    assert conn.halted
    assert conn.status == 403
  end

  test "gesetzter Origin wird abgewiesen, auch bei Loopback-Host" do
    headers = [{"content-type", "application/json"}, {"origin", "http://127.0.0.1:49525"}]
    conn = guard(post("127.0.0.1", headers))
    assert conn.halted
    assert conn.status == 403
  end

  test "POST mit text/plain (CORS-simple request) wird mit 415 abgewiesen" do
    conn = guard(post("localhost", [{"content-type", "text/plain"}]))
    assert conn.halted
    assert conn.status == 415
  end

  test "POST ohne Content-Type wird mit 415 abgewiesen" do
    conn = guard(post("127.0.0.1", []))
    assert conn.status == 415
  end

  test "pi-foermiger Aufruf passiert den Guard" do
    for host <- ["127.0.0.1", "localhost"] do
      conn = guard(post(host, [{"content-type", "application/json; charset=utf-8"}]))
      refute conn.halted
    end
  end

  test "GET /healthz ohne Content-Type passiert, mit fremdem Host nicht" do
    refute guard(Map.put(conn(:get, "/healthz"), :host, "127.0.0.1")).halted
    assert guard(Map.put(conn(:get, "/healthz"), :host, "evil.example")).status == 403
  end
end
