defmodule KomkiConnectorRis.Api do
  @moduledoc """
  The endpoints of the RIS API (`risapi3.komuna.net/web/`) the connector
  uses. Headers and tenant as in `apps/ratsinfo` (`Ratsinfo.Config`). Address
  and `x-orgkey` come from `https://ris.komuna.net/52/webconfig.json`, the
  configuration of the web front end (`serviceUrl`, `org_key`, fetched
  2026-11-13, #515; before that `risapi1`/`RIS51`):

  - `GET guestmeetings?client=32&from=YYYY-MM-DD&until=YYYY-MM-DD`
    → `{"items": [{"id", "name", "meetingdate", "committeename", ...}]}`
  - `GET guestmeetings/{id}`
    → `{"id", "name", "meetingdate", "parts": [{"protectedpart", "agendaitems": [{"id", "numbering", "name", "restricted"}]}]}`
  - `GET guestagendaitems/{meetingId-agendaItemId}`
    → `{"id", "name", "restricted", "textsanddocsvisible", "textblocks": [{"caption", "content"}], ...}`

  Signed in (#148): `POST auth` (`{"login", "password"}` → `{"token"}`, a
  JWT), then meeting and agenda item come from the signed-in counterparts
  `meetings/{id}` and `agendaitems/{id}` with `authorization: Bearer
  <token>`, in the same shape. Only there does the RIS serve the text blocks
  of public items; for guests they are mostly empty (structure profile of
  the 2026-11-01 recording, and L-104). The meeting list stays the guest
  endpoint. The login goes out only over a transport that may carry a
  secret (`KomkiConnector.Transport.secret_ok?/1`).

  A 401 on a signed-in call means the token is no longer valid; that is
  `credential-missing`, since the mediator only ever sees the code, not the
  text. The connector does not sign in again by itself: every sign-in needs
  its own Touch ID approval (decision of 2026-10-25 in #148).

  Every call keeps the deadline of the running connector call
  (`cfg.deadline`, monotonic milliseconds). Errors map onto the closed
  codes; a 404 on a meeting or an item stays `:not_found`, so the caller
  decides what it means. The meeting list, by contrast, always exists: a
  404 there means the upstream does not know the tenant (`Tenant unknown`,
  e.g. after a move) and is `upstream-error` instead of "no meetings"
  (#515). Messages never carry upstream text, credentials or the token.
  """

  alias KomkiConnectorRis.Http

  # Wie Ratsinfo.Config: Mandant und Kopfzeilen der VG Buchloe.
  @client_id 32
  @headers [
    {"x-orgkey", "RIS52"},
    {"x-customname", "vgbuchloe"},
    {"x-uniqueid", "ris.komuna.net/vgbuchloe"},
    {"accept", "application/json"}
  ]

  @typedoc "The token as a function, so it never shows up in an `inspect` of the state."
  @type token :: (-> String.t()) | nil

  @type cfg :: %{
          required(:base_url) => String.t(),
          required(:timeout_ms) => pos_integer(),
          required(:deadline) => integer(),
          optional(:token) => token(),
          optional(atom()) => term()
        }
  @type failure :: {:error, String.t(), String.t()}

  @doc """
  Signs in and returns the token. Rejected credentials (401, 403) are
  `unauthorized`; no message names the login or the password.
  """
  @spec login(cfg(), String.t(), String.t()) :: {:ok, token()} | failure()
  def login(cfg, login, password) do
    if KomkiConnector.Transport.secret_ok?(cfg.base_url) do
      post_login(cfg, JSON.encode!(%{"login" => login, "password" => password}))
    else
      {:error, "bad-request", "RIS-Anmeldung nur über https; Adresse in --base-url prüfen"}
    end
  end

  defp post_login(cfg, body) do
    with_time(cfg, fn timeout_ms ->
      case Http.post_json(cfg.base_url <> "auth", @headers, body, timeout_ms) do
        {:ok, %{} = response} -> token(response)
        {:ok, _} -> bad_response()
        {:error, {:status, status}} when status in [401, 403] -> rejected()
        {:error, error} -> failure(error)
      end
    end)
  end

  # Field name as in Ratsinfo.ApiClient.login/2, which works against the real
  # RIS; the recordings redact all three, so which one it sends is unrecorded.
  defp token(response) do
    case response["token"] || response["access_token"] || response["jwt"] do
      jwt when is_binary(jwt) and jwt != "" -> {:ok, fn -> jwt end}
      _ -> bad_response()
    end
  end

  @doc """
  When the token expires, from the JWT's `exp` claim, or `nil` if it carries
  none. Read without verifying the signature: it only tells the user how
  long the sign-in lasts, nothing is decided on it.
  """
  @spec expires_at(token()) :: DateTime.t() | nil
  def expires_at(token) when is_function(token, 0) do
    with [_header, payload | _] <- String.split(token.(), "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => exp}} when is_integer(exp) <- JSON.decode(json),
         {:ok, at} <- DateTime.from_unix(exp) do
      at
    else
      _ -> nil
    end
  end

  @doc "Meetings in a time window (guest endpoint)."
  @spec meetings(cfg(), Date.t(), Date.t()) :: {:ok, [map()]} | failure()
  def meetings(cfg, from, until) do
    query =
      URI.encode_query(
        client: @client_id,
        from: Date.to_iso8601(from),
        until: Date.to_iso8601(until)
      )

    case get(cfg, "guestmeetings?" <> query, nil) do
      {:ok, %{"items" => items}} when is_list(items) -> {:ok, items}
      {:ok, _} -> bad_response()
      :not_found -> {:error, "upstream-error", "RIS kennt die Sitzungsliste nicht (HTTP 404)"}
      {:error, _, _} = e -> e
    end
  end

  @doc "Meeting with its agenda; signed in when `cfg` carries a token."
  @spec meeting(cfg(), pos_integer()) :: {:ok, map()} | :not_found | failure()
  def meeting(cfg, id) when is_integer(id),
    do: object(get(cfg, path(cfg, "meetings/") <> Integer.to_string(id), cfg[:token]))

  @doc """
  Agenda item with its text blocks; signed in when `cfg` carries a token.
  `top_id` has already been checked against the ID pattern.
  """
  @spec agendaitem(cfg(), String.t()) :: {:ok, map()} | :not_found | failure()
  def agendaitem(cfg, top_id),
    do: object(get(cfg, path(cfg, "agendaitems/") <> top_id, cfg[:token]))

  @doc "Time left until the deadline in milliseconds (never negative)."
  @spec remaining(cfg()) :: non_neg_integer()
  def remaining(%{deadline: deadline}),
    do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp path(cfg, resource), do: if(cfg[:token], do: resource, else: "guest" <> resource)

  defp object({:ok, map}) when is_map(map), do: {:ok, map}
  defp object({:ok, _}), do: bad_response()
  defp object(other), do: other

  defp get(cfg, path, token) do
    with_time(cfg, fn timeout_ms ->
      case Http.get_json(cfg.base_url <> path, headers(token), timeout_ms) do
        {:ok, body} -> {:ok, body}
        {:error, :not_found} -> :not_found
        {:error, {:status, 401}} when token != nil -> expired()
        {:error, error} -> failure(error)
      end
    end)
  end

  defp headers(nil), do: @headers
  defp headers(token), do: [{"authorization", "Bearer " <> token.()} | @headers]

  defp with_time(cfg, fun) do
    case min(cfg.timeout_ms, remaining(cfg)) do
      0 -> timeout()
      timeout_ms -> fun.(timeout_ms)
    end
  end

  defp failure(:timeout), do: timeout()

  defp failure({:status, status}),
    do: {:error, "upstream-error", "RIS antwortet mit HTTP #{status}"}

  defp failure(:bad_json), do: bad_response()
  defp failure(:not_found), do: {:error, "upstream-error", "RIS antwortet mit HTTP 404"}
  defp failure(:unreachable), do: {:error, "upstream-error", "RIS nicht erreichbar"}

  defp rejected,
    do:
      {:error, "unauthorized",
       "RIS lehnt die Anmeldung ab; Zugang pruefen mit 'komki secret set ris'"}

  defp expired,
    do:
      {:error, "credential-missing",
       "RIS-Anmeldung abgelaufen; komki neu starten, dann fragt komki per Touch ID neu"}

  defp timeout, do: {:error, "upstream-timeout", "RIS antwortet nicht rechtzeitig"}
  defp bad_response, do: {:error, "upstream-error", "RIS liefert eine unerwartete Antwort"}
end
