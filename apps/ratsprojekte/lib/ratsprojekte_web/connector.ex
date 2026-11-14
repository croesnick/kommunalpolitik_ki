defmodule RatsprojekteWeb.Connector do
  @moduledoc """
  The connector's own way into the hub (ADR 0004): Bandit on the Unix
  socket `Ort.connector/1` (mode 0600), connector operations only, nothing
  of the interface. The browser port never sees these routes.

  Every request is checked in this order, before anything else:

  1. `Authorization: Bearer <token>`. The hub knows only the SHA-256 of the
     token (`Ort.token_hash/1`, written by `ratsprojekte connector-token`);
     compared in constant time. No hash file, no access (fail closed). 401.
  2. Locked hub: 503 `{"status":"gesperrt"}`; nothing is buffered.

  Connector calls are no action in the interface: they never postpone the
  lock. The write path itself („Fakt vorschlagen“) is built by #277.
  """

  use Plug.Router

  alias Ratsprojekte.{Ort, Sperre}

  plug(:pruefen)
  plug(:match)
  plug(:dispatch)

  post "/connector/fakt_vorschlagen" do
    antworten(conn, 501, ~s({"status":"noch nicht gebaut"}))
  end

  match _ do
    antworten(conn, 404, ~s({"status":"unbekannt"}))
  end

  @doc "Child spec: Bandit on the socket, mode 0600 once it listens."
  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    home = Keyword.fetch!(opts, :home)
    pfad = Ort.connector(home)
    _ = File.rm(pfad)

    bandit = [
      plug: {__MODULE__, home: home, sperre: Keyword.get(opts, :sperre, Sperre)},
      scheme: :http,
      ip: {:local, pfad},
      port: 0,
      thousand_island_options: [num_acceptors: 2]
    ]

    with {:ok, pid} <- Bandit.start_link(bandit) do
      File.chmod!(pfad, 0o600)
      {:ok, pid}
    end
  end

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts), do: conn |> put_private(:connector, opts) |> super(opts)

  @doc false
  def pruefen(conn, _opts) do
    opts = conn.private.connector

    cond do
      not berechtigt?(conn, Keyword.fetch!(opts, :home)) ->
        conn |> antworten(401, ~s({"status":"abgelehnt"})) |> halt()

      Sperre.status(Keyword.fetch!(opts, :sperre)) != :offen ->
        conn |> antworten(503, ~s({"status":"gesperrt"})) |> halt()

      true ->
        conn
    end
  end

  defp berechtigt?(conn, home) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, erwartet} <- File.read(Ort.token_hash(home)),
         erwartet = String.trim(erwartet),
         true <- erwartet != "" do
      vorgelegt = :sha256 |> :crypto.hash(String.trim(token)) |> Base.encode16(case: :lower)
      Plug.Crypto.secure_compare(vorgelegt, erwartet)
    else
      _ -> false
    end
  end

  defp antworten(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, body)
  end
end
