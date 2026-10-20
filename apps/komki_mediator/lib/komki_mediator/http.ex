defmodule KomkiMediator.HTTP do
  @moduledoc """
  HTTP-Oberflaeche (Bandit, NUR loopback — die Host-Bindung steht im
  Listener, der Plug haelt keine Bindungsmacht):

  * `GET /healthz` — Liveness plus Verbindungsauflage: Status, Fassung,
    angebotene Tools und Gamma-Stand. komki_cli liest genau diese Form
    (Schluessel sind bewusst fixiert) und muss die Tools nicht
    hartkodieren.
  * `/mcp` — der StreamableHTTP-Transport des anubis MCP-Servers.

  Aufrufer-Pruefung vor jeder Route (Ticket #133): Die Loopback-Bindung
  haelt fremde Rechner fern, aber nicht den Browser der Nutzerin oder des
  Nutzers. Eine Website kann per DNS-Rebinding (fremder `Host`) oder per
  Cross-Origin-POST mit `text/plain` (kein CORS-Preflight) an den Port
  gelangen. Deshalb gilt: `Host` ist `127.0.0.1` oder `localhost`, ein
  `Origin`-Header wird abgelehnt (pi sendet keinen, Browser immer bei
  POST), und POST verlangt `application/json`. Abweisung mit 403 bzw.
  415, bevor ein Tool oder die Policy-Engine erreicht wird.
  """

  use Plug.Router

  alias KomkiMediator.{Env, Fassung}
  alias KomkiPolicy.JSON

  @loopback_hosts ["127.0.0.1", "localhost"]

  plug(:guard_caller)
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

  @doc false
  def guard_caller(conn, _opts) do
    cond do
      conn.host not in @loopback_hosts -> reject(conn, 403, "host not allowed")
      get_req_header(conn, "origin") != [] -> reject(conn, 403, "origin not allowed")
      conn.method == "POST" and not json?(conn) -> reject(conn, 415, "application/json required")
      true -> conn
    end
  end

  defp json?(conn) do
    case get_req_header(conn, "content-type") do
      [type | _] -> type |> String.downcase() |> String.starts_with?("application/json")
      [] -> false
    end
  end

  defp reject(conn, status, reason), do: conn |> send_resp(status, reason) |> halt()
end
