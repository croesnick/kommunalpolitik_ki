defmodule Ratsinfo.ApiClient do
  @moduledoc """
  API-Client für das Ratsinformationssystem der VGem Buchloe.

  Die API liefert JSON direkt — kein HTML-Scraping nötig.
  Gast-Zugang reicht für Sitzungslisten; authentifizierter Zugang
  (JWT via POST /web/auth) für TOP-Details, Volltextsuche und Downloads.
  """

  alias Ratsinfo.Config

  @doc """
  Einloggen und JWT-Token zurückbekommen.

  POST /web/auth mit username/password → JSON mit Token.
  """
  @spec login(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def login(username, password) do
    body = URI.encode_query(%{"username" => username, "password" => password})

    case Req.post(Config.base_url() <> "auth",
           body: body,
           headers: [{"content-type", "application/x-www-form-urlencoded"} | Config.headers()],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        token = body["token"] || body["access_token"] || body["jwt"]
        if token, do: {:ok, token}, else: {:error, :no_token_in_response}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sitzungsliste abrufen (Gast-Zugang, kein Login nötig).

  GET /web/guestmeetings?client=32&from=2025-01-01&until=2025-12-31
  """
  @spec list_sitzungen(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_sitzungen(opts \\ []) do
    client_id = Keyword.get(opts, :client_id, Config.client_stadt_buchloe())
    from = Keyword.get(opts, :from, default_from())
    until = Keyword.get(opts, :until, default_until())

    params = %{client: client_id, from: from, until: until}

    case Req.get(Config.base_url() <> "guestmeetings",
           params: params,
           headers: Config.headers(),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body["items"] || []}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sitzungsdetails mit TOPs abrufen (authentifiziert).

  GET /web/meetings/{id}
  """
  @spec get_sitzung(integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_sitzung(meeting_id, token) do
    case Req.get(Config.base_url() <> "meetings/#{meeting_id}",
           headers: Config.auth_headers(token),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  TOP-Details abrufen (authentifiziert).

  GET /web/agendaitems/{meetingId}-{agendaId}

  Die agenda_id hat das Format "meetingId-agendaItemId" (z.B. "116135092-116135132").
  """
  @spec get_top(integer(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_top(meeting_id, agenda_item_id, token) do
    full_id = "#{meeting_id}-#{agenda_item_id}"

    case Req.get(Config.base_url() <> "agendaitems/#{full_id}",
           headers: Config.auth_headers(token),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Volltextsuche im RIS (authentifiziert).

  GET /web/fulltextsearch?searchterm=Bahnhofstraße&committee=0&client=32
  """
  @spec fulltext_search(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fulltext_search(searchterm, opts \\ []) do
    token = Keyword.fetch!(opts, :token)
    client_id = Keyword.get(opts, :client_id, Config.client_stadt_buchloe())
    committee = Keyword.get(opts, :committee, 0)

    params = %{searchterm: searchterm, committee: committee, client: client_id}

    case Req.get(Config.base_url() <> "fulltextsearch",
           params: params,
           headers: Config.auth_headers(token),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Dokument herunterladen (authentifiziert).

  GET /web/agendaitems/documents/{docId}

  Liefert binary (application/octet-stream).
  """
  @spec download_dokument(String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def download_dokument(doc_id, token) do
    case Req.get(Config.base_url() <> "agendaitems/documents/#{doc_id}",
           headers: Config.auth_headers(token),
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gremien-Liste abrufen (authentifiziert).

  GET /web/committees?client=32
  """
  @spec list_gremien(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_gremien(token, opts \\ []) do
    client_id = Keyword.get(opts, :client_id, Config.client_stadt_buchloe())

    case Req.get(Config.base_url() <> "committees",
           params: [client: client_id],
           headers: Config.auth_headers(token),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body["items"] || body}

      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_from, do: "#{Date.utc_today().year}-01-01"
  defp default_until, do: "#{Date.utc_today().year}-12-31"
end
