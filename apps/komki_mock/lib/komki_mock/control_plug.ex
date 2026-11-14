defmodule KomkiMock.ControlPlug do
  @moduledoc """
  The control port: how tests and agents drive a running mock. JSON in,
  JSON out.

      GET  /state                               seed, scenario, delay_ms, data
      POST /seed      {"name": "default"}       load a seed, scenario ok, empty log
      POST /reset                               reload the current seed
      PUT  /data      <any JSON value>          replace the data
      POST /scenario  {"name": "slow", "delay_ms": 500}
      GET  /log                                 the request log
  """

  @behaviour Plug

  import Plug.Conn

  alias KomkiMock.Server

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :server)

  @impl true
  def call(conn, server) do
    {status, body} = route(conn.method, conn.path_info, conn, server)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end

  defp route("GET", ["state"], _conn, server), do: {200, Server.state(server)}
  defp route("GET", ["log"], _conn, server), do: {200, Server.log(server)}
  defp route("POST", ["reset"], _conn, server), do: reply(Server.reset(server))

  defp route("PUT", ["data"], conn, server) do
    case json_body(conn) do
      {:ok, data} -> reply(Server.put_data(server, data))
      :error -> {400, %{"error" => "expected a JSON body"}}
    end
  end

  defp route("POST", ["seed"], conn, server) do
    case params(conn) do
      %{"name" => name} when is_binary(name) -> reply(Server.seed(server, name))
      _ -> {400, %{"error" => "expected {\"name\": <seed>}"}}
    end
  end

  defp route("POST", ["scenario"], conn, server) do
    case params(conn) do
      %{"name" => name} = params when is_binary(name) ->
        case Map.get(params, "delay_ms") do
          delay when is_nil(delay) or (is_integer(delay) and delay > 0) ->
            reply(Server.scenario(server, name, delay))

          _ ->
            {400, %{"error" => "delay_ms must be a positive integer"}}
        end

      _ ->
        {400, %{"error" => "expected {\"name\": <scenario>}"}}
    end
  end

  defp route(_method, _path, _conn, _server), do: {404, %{"error" => "not found"}}

  defp reply({:ok, state}), do: {200, state}
  defp reply({:error, :unknown_seed}), do: {404, %{"error" => "unknown seed"}}
  defp reply({:error, :unknown_scenario}), do: {400, %{"error" => "unknown scenario"}}

  defp params(conn) do
    case json_body(conn) do
      {:ok, %{} = params} -> params
      _ -> nil
    end
  end

  defp json_body(conn) do
    with {:ok, body, _conn} <- read_body(conn),
         {:ok, value} <- JSON.decode(body) do
      {:ok, value}
    else
      _ -> :error
    end
  end
end
