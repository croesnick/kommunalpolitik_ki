defmodule KomkiMediator.HTTP do
  @moduledoc """
  HTTP-Oberflaeche (Bandit auf dem Unix-Socket `<base>/run/mediator.sock`,
  Ticket #143 — kein TCP-Listener mehr; die Bindung steht im Listener, der
  Plug haelt keine Bindungsmacht):

  * `GET /healthz` — Liveness plus Verbindungsauflage: Status, Fassung,
    angebotene Tools und Gamma-Stand. komki_cli liest genau diese Form
    (Schluessel sind bewusst fixiert) und muss die Tools nicht
    hartkodieren.
  * `/mcp` — der StreamableHTTP-Transport des anubis MCP-Servers.

  Aufrufer-Pruefung vor jeder Route (`guard_caller/2`), in dieser Reihenfolge:

  1. `Authorization: Bearer <token>` (CONTRACT §8): das Token aus
     `--token-file`, Vergleich in konstanter Zeit
     (`Plug.Crypto.secure_compare/2`). Ohne oder mit falschem Token: 401
     und eine Logzeile ohne Token-Wert — auch fuer `/healthz`. Das haelt
     lokale Clients ohne Token fern (etwa eine zweite, nicht gesandboxte
     Agent-Session), die den Socket per Dateirecht erreichen koennten.
  2. `Host` ist `localhost` oder `127.0.0.1` (das Relay sendet
     `localhost`), ein `Origin`-Header wird abgelehnt und POST verlangt
     `application/json` (Ticket #133). Ein Browser erreicht den Unix-Socket
     nicht; die Pruefungen bleiben als billige Tiefenverteidigung.
  3. `X-Komki-Session` (optional, Format `^[a-z0-9-]{8,64}$`): die
     Session-ID von `komki run/session`. Ein ungueltiger Wert ergibt 400.
     Der gepruefte Wert (oder nil) geht nach `conn.assigns.komki_session`;
     anubis reicht die Assigns je Anfrage in `frame.assigns` weiter, wo
     `KomkiMediator.Env.for_call/1` ihn abholt. Die Session-ID dient der
     Zuordnung im PDR, nicht der Authentisierung.

  Das Token reist ueber `init/1` (`token: ...`) in `conn.private` — nicht in
  die Assigns, die anubis in den Frame uebernimmt.
  """

  use Plug.Router

  require Logger

  alias KomkiMediator.{Env, Fassung}
  alias KomkiPolicy.JSON

  @allowed_hosts ["localhost", "127.0.0.1"]
  @session_format ~r/\A[a-z0-9-]{8,64}\z/

  plug(:guard_caller)
  plug(:match)
  plug(:dispatch)

  forward("/mcp",
    to: Anubis.Server.Transport.StreamableHTTP.Plug,
    # Ein Aufruf kann auf ein GO warten (Ticket #98, bis 120 s); der
    # anubis-Standard von 30 s braeche ihn vorher ab.
    init_opts: [server: KomkiMediator.Server, request_timeout: 180_000]
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

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :token)

  @impl Plug
  def call(conn, token) do
    conn
    |> put_private(:komki_token, token)
    |> super(token)
  end

  @doc false
  def guard_caller(conn, _opts) do
    cond do
      not authorized?(conn) -> unauthorized(conn)
      conn.host not in @allowed_hosts -> reject(conn, 403, "host not allowed")
      get_req_header(conn, "origin") != [] -> reject(conn, 403, "origin not allowed")
      conn.method == "POST" and not json?(conn) -> reject(conn, 415, "application/json required")
      true -> assign_session(conn)
    end
  end

  # Fehlt das Token im Prozess (Fehlkonfiguration), wird nichts
  # durchgelassen (fail-closed).
  defp authorized?(conn) do
    with token when is_binary(token) <- conn.private[:komki_token],
         ["Bearer " <> presented] <- get_req_header(conn, "authorization") do
      Plug.Crypto.secure_compare(presented, token)
    else
      _ -> false
    end
  end

  defp unauthorized(conn) do
    reason =
      if get_req_header(conn, "authorization") == [], do: "ohne Token", else: "falsches Token"

    Logger.warning(
      "komki-mediator: 401 " <> conn.method <> " " <> conn.request_path <> " " <> reason
    )

    reject(conn, 401, "unauthorized")
  end

  defp assign_session(conn) do
    case get_req_header(conn, "x-komki-session") do
      [] ->
        assign(conn, :komki_session, nil)

      [session] ->
        if Regex.match?(@session_format, session),
          do: assign(conn, :komki_session, session),
          else: reject(conn, 400, "invalid x-komki-session")

      _ ->
        reject(conn, 400, "invalid x-komki-session")
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
