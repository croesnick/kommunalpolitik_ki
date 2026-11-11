defmodule WegwerfHub.HTTP do
  @moduledoc """
  DURCHSTICH #409 (Wegwerf): Die schmale Schnittstelle des Hubs — Bandit
  auf dem Unix-Socket `<dir>/hub.sock` (0600), genau EINE Operation für
  den Connector (#415: eigene Connector-Route, nicht der Browser-Port):

      POST /connector/fakt_vorschlagen  →  201 {"status":"vorgeschlagen"}

  Aufrufer-Prüfung in fester Reihenfolge:

  1. `Authorization: Bearer <token>`: Der Hub kennt nur den HASH des
     Tokens (Datei `token-hash` im Hub-Verzeichnis); verglichen wird
     SHA-256 des Präsentierten in konstanter Zeit. Ohne/falsches Token:
     401 — bevor irgendein Zustand sichtbar wird.
  2. Gesperrt (Datei `gesperrt` vorhanden): 503 {"status":"gesperrt"} —
     „Hub gesperrt“, gepuffert wird nichts.
  3. Rumpf muss JSON in der erwarteten Form sein (Titel, Teile mit
     Aussage und Quelle, Projekt-Hinweis, Labels), sonst 400.

  Die Antwort ist bewusst immer dieselbe: kein Schlüssel, keine Kennung,
  keine Fortnummer, nichts aus dem Bestand (Szene 11: enumeration). Was
  ankommt, landet im Bestand (`WegwerfHub.Store`); jede Anfrage als Zeile
  im Anfrage-Log, ohne Inhalte.
  """

  use Plug.Router

  require Logger

  alias KomkiPolicy.JSON
  alias WegwerfHub.Store

  @max_body 65_536

  plug(:guard_caller)
  plug(:match)
  plug(:dispatch)

  post "/connector/fakt_vorschlagen" do
    with {:ok, raw, _conn} <- Plug.Conn.read_body(conn, length: @max_body),
         {:ok, term} <- parse_json(raw),
         :ok <- validate(term) do
      {:ok, _id} = Store.annehmen(hub_dir(conn), term)

      log_and_respond(conn, 201, "{\"status\":\"vorgeschlagen\"}", "application/json")
    else
      {:error, :bad_json} ->
        conn |> bad_request("ungültiges JSON") |> halt()

      {:error, detail} ->
        conn |> bad_request(detail) |> halt()
    end
  end

  match _ do
    conn |> not_found() |> halt()
  end

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :dir)

  @impl Plug
  def call(conn, dir) do
    conn
    |> put_private(:hub_dir, dir)
    |> super(dir)
  end

  @doc false
  # Plug ruft Funktions-Plugs mit ihrem Optionswert auf (hier []) — das
  # Hub-Verzeichnis reist deshalb über conn.private (gesetzt in call/2),
  # nicht über den zweiten Parameter.
  def guard_caller(conn, _opts) do
    dir = hub_dir(conn)

    with :ok <- authorized?(conn, dir),
         :ok <- not_locked?(dir) do
      conn
    else
      {:error, :unauthorized} ->
        conn
        |> log_and_respond(401, "unauthorized")
        |> halt()

      {:error, :gesperrt} ->
        conn
        |> log_and_respond(503, "{\"status\":\"gesperrt\"}", "application/json")
        |> halt()
    end
  end

  # Token nur als Hash: sha256 des Praesentierten gegen die Datei, in
  # konstanter Zeit. Fehlt die Hash-Datei, bleibt der Hub zu (fail-closed).
  defp authorized?(conn, dir) do
    hash_file = Path.join(dir, "token-hash")

    with ["Bearer " <> presented] <- get_req_header(conn, "authorization"),
         {:ok, expected} when is_binary(expected) <- File.read(hash_file),
         true <- expected != "" do
      presented_hash =
        presented
        |> String.trim()
        |> then(&Base.encode16(:crypto.hash(:sha256, &1), case: :lower))

      if Plug.Crypto.secure_compare(presented_hash, String.trim_trailing(expected, "\n")),
        do: :ok,
        else: {:error, :unauthorized}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp not_locked?(dir) do
    if File.exists?(Path.join(dir, "gesperrt")),
      do: {:error, :gesperrt},
      else: :ok
  end

  defp parse_json(raw) do
    case JSON.parse(raw) do
      {:ok, term} when is_map(term) -> {:ok, term}
      _ -> {:error, :bad_json}
    end
  end

  # Geschlossene Form wie im Manifest des Connectors: Der Hub vertraut
  # dem Connector nicht blind (dessen Sandbox ist komki-Sache, nicht
  # seine). Unzulaessige Felder und Typen enden als 400, nichts wird
  # gespeichert.
  defp validate(term) do
    closed(term, ~w(labels projekt_hinweis teile titel))
  end

  defp closed(term, keys) do
    missing = for key <- keys, not Map.has_key?(term, key), do: key

    cond do
      missing != [] -> {:error, "Pflichtfeld fehlt: " <> Enum.join(missing, ", ")}
      Map.keys(term) -- keys != [] -> {:error, "unbekannte Felder"}
      true -> felder(term)
    end
  end

  defp felder(term) do
    cond do
      not is_binary(term["titel"]) ->
        {:error, "titel ist kein Text"}

      not (is_binary(term["projekt_hinweis"]) or is_nil(term["projekt_hinweis"])) ->
        {:error, "projekt_hinweis ist kein Text"}

      not (is_list(term["labels"]) and Enum.all?(term["labels"], &is_binary/1)) ->
        {:error, "labels ist keine Liste von Bindungen"}

      true ->
        teile(term["teile"])
    end
  end

  defp teile(teile) when is_list(teile) and teile != [] do
    Enum.find_value(teile, :ok, fn teil ->
      cond do
        not is_map(teil) ->
          {:error, "teil ist kein Objekt"}

        Map.keys(teil) -- ~w(aussage quelle fundstelle) != [] ->
          {:error, "unbekannte Felder im Teil"}

        not is_binary(teil["aussage"]) ->
          {:error, "aussage ist kein Text"}

        not is_binary(teil["quelle"]) ->
          {:error, "quelle ist kein Text"}

        not (is_binary(teil["fundstelle"]) or is_nil(teil["fundstelle"])) ->
          {:error, "fundstelle ist kein Text"}

        true ->
          nil
      end
    end)
  end

  defp teile(_), do: {:error, "teile fehlt oder ist leer"}

  defp bad_request(conn, detail) do
    log_and_respond(conn, 400, "ungültige Anfrage: " <> detail)
  end

  defp not_found(conn), do: log_and_respond(conn, 404, "not found")

  defp hub_dir(conn), do: conn.private[:hub_dir]

  defp log_and_respond(conn, status, body, content_type \\ "text/plain") do
    Store.anfrage_loggen(hub_dir(conn), conn.method, conn.request_path, status)
    Logger.info("wegwerf-hub: #{status} #{conn.method} #{conn.request_path}")

    conn
    |> put_resp_content_type(content_type)
    |> send_resp(status, body)
  end
end
