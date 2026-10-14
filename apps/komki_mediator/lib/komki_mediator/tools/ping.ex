defmodule KomkiMediator.Tools.Ping do
  @moduledoc """
  MCP-Tool `ping`: Liveness-Pruefung durch das Gate. Die Antwort traegt
  Fassung, Gamma-Stand-Hash und die angebotene Tool-Menge — nach Tor 1
  entschied und mit PDR belegt.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias KomkiMediator.{Env, Fassung, Gate}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    env = Env.fetch()
    gamma = env.gamma

    executor = fn ->
      {:ok,
       %{
         "fassung_id" => Fassung.fassung_id(),
         "registry_id" => gamma.registry_id,
         "gamma_hash" => gamma.gamma_hash,
         "tools" => Fassung.tools()
       }}
    end

    response = Gate.call(env, "ping", %{}, executor)
    {:reply, Response.json(Response.tool(), response), frame}
  end
end
