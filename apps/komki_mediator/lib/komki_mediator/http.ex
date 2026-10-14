defmodule KomkiMediator.HTTP do
  @moduledoc """
  HTTP-Oberflaeche (Bandit, NUR loopback — die Host-Bindung steht im
  Listener, der Plug haelt keine Bindungsmacht):

  * `GET /healthz` — Liveness plus Verbindungsauflage: Status, Fassung,
    angebotene Tools und Gamma-Stand. komki_cli liest genau diese Form
    (Schluessel sind bewusst fixiert) und muss die Tools nicht
    hartkodieren.
  * `/mcp` — der StreamableHTTP-Transport des anubis MCP-Servers.
  """

  use Plug.Router

  alias KomkiMediator.{Env, Fassung}
  alias KomkiPolicy.JSON

  plug(:match)
  plug(:dispatch)

  forward("/mcp",
    to: Anubis.Server.Transport.StreamableHTTP.Plug,
    init_opts: [server: KomkiMediator.Server]
  )

  get "/healthz" do
    env = Env.fetch()

    body =
      JSON.canonical(%{
        "status" => "ok",
        "fassung_id" => Fassung.fassung_id(),
        "tools" => Fassung.tools(),
        "registry_id" => env.gamma.registry_id,
        "gamma_hash" => env.gamma.gamma_hash
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
