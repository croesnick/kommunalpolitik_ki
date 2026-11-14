defmodule KomkiMock.DataPlug do
  @moduledoc """
  The data port: what the system under test talks to. Hands every request
  to the server, waits out a `slow` scenario and sends the adapter's reply.
  """

  @behaviour Plug

  import Plug.Conn

  alias KomkiMock.Server

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :server)

  @impl true
  def call(conn, server) do
    {body, conn} = read_all(conn, [])

    request = %{
      method: conn.method,
      path: conn.request_path,
      query: conn.query_string,
      headers: conn.req_headers,
      body: body
    }

    {{status, headers, resp_body}, delay_ms} = Server.handle_request(server, request)
    if delay_ms > 0, do: Process.sleep(delay_ms)

    conn
    |> merge_resp_headers(headers)
    |> send_resp(status, resp_body)
  end

  defp read_all(conn, acc) do
    case read_body(conn) do
      {:ok, chunk, conn} -> {IO.iodata_to_binary([acc, chunk]), conn}
      {:more, chunk, conn} -> read_all(conn, [acc, chunk])
    end
  end
end
