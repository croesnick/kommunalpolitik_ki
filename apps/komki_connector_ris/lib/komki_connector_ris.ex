defmodule KomkiConnectorRis do
  @moduledoc """
  RIS connector `komki-ris/2` (CONTRACT.md §5.1/§5.2): `search` and `show`
  over the public agenda items (TOPs) of the RIS API.

  Without credentials the connector only uses the guest endpoints
  (`guestmeetings`, `guestagendaitems`, see `KomkiConnectorRis.Api`), where
  the texts of the items are mostly missing.

  ## Signing in (#148)

  With the credential `RIS_ZUGANG` (JSON `{"login", "password"}`, sealed in
  the keychain, `komki secret set ris`) the connector signs in during
  `init/1`, before it binds the socket, and then reads meeting and item via
  the signed-in endpoints. The password lives only until the sign-in; the
  state keeps nothing but the token, and the log says until when it is
  valid. When it expires, the connector says so (`credential-missing`)
  instead of signing in again: every sign-in needs its own Touch ID
  approval, which means restarting komki.

  If the sign-in fails (rejected, RIS unreachable, incomplete credential),
  the connector starts anyway, so `komki up` does not take the rest of the
  workspace down with it, and answers every operation with
  `credential-missing`. The reason goes to the log at start, where `komki
  up` picks it up as a warning. It does not fall back to guest mode: whoever
  stored a credential expects texts and would silently get empty ones.
  Refusing the Touch ID approval is different: then `komki up` hands over no
  credential at all, says so, and the connector starts as a guest (the
  ticket's "starts without credentials").

  Signed in, the connector has a council member's view. It still delivers
  only public items: the filter (`KomkiConnectorRis.Top.public_items/1` and
  the detail check below) is the same as without signing in. Non-public
  items are #198.

  ## Search strategy

  The RIS API's full-text search (`fulltextsearch`) requires a sign-in. The
  connector therefore searches itself, with a fixed request budget
  (`max_requests`) and a fixed deadline (`budget_ms`):

  1. Load the meetings of a time window (`days_back` back, `days_ahead`
     ahead), newest first.
  2. Per meeting, load the agenda, drop non-public items, compare titles.
  3. With the remaining budget, load the text blocks of the public items
     whose title did not match, and compare (newest first).
  4. Stop once `limit` hits are found or budget or deadline are spent. The
     result may then be incomplete.

  Matching is a case-insensitive substring test (`String.downcase/1`).
  Since non-public items drop out before any comparison, they appear
  neither in the hits nor in their count.
  """

  @behaviour Sidecar.Server

  require Logger

  alias KomkiConnector.Manifest
  alias KomkiConnectorRis.{Api, Http, Top}

  @defaults %{
    base_url: "https://risapi3.komuna.net/web/",
    proxy: nil,
    # Einzelanfrage und Gesamtfrist bleiben unter den 15 s des Vermittlers.
    timeout_ms: 5_000,
    budget_ms: 12_000,
    max_requests: 40,
    days_back: 180,
    days_ahead: 60
  }

  @not_found {:error, "not-found", "TOP nicht gefunden"}

  @doc "Standardwerte der Konfiguration."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @impl true
  def manifest, do: Manifest.sidecar!("ris")

  @impl true
  def init(opts) do
    cfg = Map.merge(@defaults, Map.take(opts, Map.keys(@defaults)))

    with :ok <- start_http(cfg) do
      case sign_in(with_deadline(cfg), Map.get(opts, :credentials, %{})) do
        {:ok, nil} ->
          {:ok, Map.put(cfg, :token, nil)}

        {:ok, token} ->
          log_validity(token)
          {:ok, Map.put(cfg, :token, token)}

        {:error, message} ->
          Logger.warning(message)
          {:ok, Map.merge(cfg, %{token: nil, sign_in_error: message})}
      end
    end
  end

  defp start_http(cfg) do
    case Http.start(cfg.proxy) do
      :ok -> :ok
      {:error, reason} -> {:error, "HTTP-Start fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  # The message of a failed sign-in names no value.
  defp sign_in(cfg, %{"RIS_ZUGANG" => zugang}) do
    with {:ok, login, password} <- parse_zugang(zugang),
         {:ok, token} <- Api.login(cfg, login, password) do
      {:ok, token}
    else
      {:error, _code, message} -> {:error, "RIS-Anmeldung fehlgeschlagen: " <> message}
    end
  end

  # No credential: guest mode.
  defp sign_in(_cfg, _credentials), do: {:ok, nil}

  # How long a JWT lasts is not measured yet (#148); the first real run
  # tells, without the token itself ever reaching the log.
  defp log_validity(token) do
    case Api.expires_at(token) do
      nil -> Logger.info("RIS-Anmeldung erfolgreich, Ablauf unbekannt")
      at -> Logger.info("RIS-Anmeldung erfolgreich, gültig bis " <> DateTime.to_iso8601(at))
    end
  end

  defp parse_zugang(zugang) when is_binary(zugang) do
    case JSON.decode(zugang) do
      {:ok, %{"login" => login, "password" => password}}
      when is_binary(login) and login != "" and is_binary(password) and password != "" ->
        {:ok, login, password}

      _ ->
        {:error, "bad-request",
         "RIS_ZUGANG braucht login und password; neu setzen mit 'komki secret set ris'"}
    end
  end

  defp parse_zugang(_zugang), do: parse_zugang("")

  # A failed sign-in blocks every operation (see moduledoc).
  @impl true
  def handle_op(_op, _params, _context, %{sign_in_error: message}),
    do: {:error, "credential-missing", message}

  def handle_op("search", %{"text" => text, "limit" => limit}, _context, cfg),
    do: search(String.downcase(text), limit, with_deadline(cfg))

  def handle_op("show", %{"top_id" => top_id}, _context, cfg),
    do: show(top_id, with_deadline(cfg))

  defp with_deadline(cfg),
    do: Map.put(cfg, :deadline, System.monotonic_time(:millisecond) + cfg.budget_ms)

  # ---------------------------------------------------------------------------
  # search
  # ---------------------------------------------------------------------------

  defp search(needle, limit, cfg) do
    today = Date.utc_today()
    acc = %{hits: [], pending: [], left: cfg.max_requests - 1, limit: limit, needle: needle}

    with {:ok, items} <-
           Api.meetings(cfg, Date.add(today, -cfg.days_back), Date.add(today, cfg.days_ahead)),
         {:ok, acc} <- scan_meetings(newest_first(items), acc, cfg),
         {:ok, acc} <- scan_texts(Enum.reverse(acc.pending), acc, cfg) do
      {:ok, %{"results" => Enum.reverse(acc.hits), "abrufdatum" => abrufdatum()}}
    end
  end

  defp newest_first(items) do
    items
    |> Enum.filter(&match?(%{"id" => id} when is_integer(id) and id > 0, &1))
    |> Enum.sort_by(&Top.string(&1["meetingdate"]), :desc)
  end

  # Phase 1: Tagesordnungen laden, Titel vergleichen, Rest vormerken.
  defp scan_meetings([], acc, _cfg), do: {:ok, acc}

  defp scan_meetings([meeting | rest], acc, cfg) do
    if stop?(acc, cfg) do
      {:ok, acc}
    else
      with {:ok, acc} <- scan_meeting(meeting, spend(acc), cfg),
           do: scan_meetings(rest, acc, cfg)
    end
  end

  defp scan_meeting(meeting, acc, cfg) do
    case Api.meeting(cfg, meeting["id"]) do
      {:ok, detail} ->
        {:ok, Enum.reduce(Top.public_items(detail), acc, &title(&1, meeting, &2, cfg))}

      :not_found ->
        {:ok, acc}

      {:error, _, _} = e ->
        e
    end
  end

  defp title(top, meeting, acc, cfg) do
    cond do
      full?(acc) -> acc
      matches?(Top.string(top["name"]), acc.needle) -> hit(acc, top, meeting, cfg)
      true -> %{acc | pending: [{top, meeting} | acc.pending]}
    end
  end

  # Phase 2: Textbloecke der vorgemerkten TOPs mit dem Restbudget.
  defp scan_texts([], acc, _cfg), do: {:ok, acc}

  defp scan_texts([{top, meeting} | rest], acc, cfg) do
    if stop?(acc, cfg) do
      {:ok, acc}
    else
      with {:ok, acc} <- scan_text(top, meeting, spend(acc), cfg),
           do: scan_texts(rest, acc, cfg)
    end
  end

  defp scan_text(top, meeting, acc, cfg) do
    case Api.agendaitem(cfg, top["id"]) do
      {:ok, detail} ->
        if public_detail?(detail) and matches?(Top.text(detail), acc.needle),
          do: {:ok, hit(acc, top, meeting, cfg)},
          else: {:ok, acc}

      :not_found ->
        {:ok, acc}

      {:error, _, _} = e ->
        e
    end
  end

  defp full?(acc), do: length(acc.hits) >= acc.limit
  defp stop?(acc, cfg), do: full?(acc) or acc.left <= 0 or Api.remaining(cfg) == 0
  defp spend(acc), do: %{acc | left: acc.left - 1}

  defp matches?(haystack, needle), do: String.contains?(String.downcase(haystack), needle)

  defp hit(acc, top, meeting, cfg) do
    result = %{
      "top_id" => top["id"],
      "nummer" => Top.string(top["numbering"]),
      "titel" => Top.string(top["name"]),
      "sitzung" => Top.string(meeting["name"]),
      "datum" => Top.date(meeting["meetingdate"]),
      "url" => url(cfg, top["id"])
    }

    %{acc | hits: [result | acc.hits]}
  end

  # ---------------------------------------------------------------------------
  # show
  # ---------------------------------------------------------------------------

  # Jeder Grund, warum ein TOP nicht gezeigt wird (unbekannt, nicht-oeffentlich,
  # Sitzung fehlt, ID-Form falsch), ergibt denselben not-found-Fehler.
  defp show(top_id, cfg) do
    with {:ok, meeting_id} <- Top.meeting_id(top_id),
         {:ok, meeting} <- Api.meeting(cfg, meeting_id),
         {:ok, top} <- find_public(meeting, top_id),
         {:ok, detail} <- Api.agendaitem(cfg, top_id),
         true <- public_detail?(detail) do
      {:ok,
       %{
         "top_id" => top_id,
         "nummer" => Top.string(top["numbering"]),
         "titel" => Top.string(top["name"]),
         "sitzung" => Top.string(meeting["name"]),
         "datum" => Top.date(meeting["meetingdate"]),
         "text" => Top.text(detail),
         "url" => url(cfg, top_id),
         "abrufdatum" => abrufdatum()
       }}
    else
      {:error, _, _} = e -> e
      _ -> @not_found
    end
  end

  defp find_public(meeting, top_id) do
    case Enum.find(Top.public_items(meeting), &(&1["id"] == top_id)) do
      nil -> :not_found
      top -> {:ok, top}
    end
  end

  # The detail answer may only tighten the classification: it must carry
  # restricted false explicitly. Without the field the item counts as
  # non-public (fail-closed, since a council member's view may stand behind
  # it once signed in, #148).
  defp public_detail?(detail), do: Map.get(detail, "restricted") == false

  # ---------------------------------------------------------------------------

  # Link aus Basis-URL und gepruefter ID, nie aus Upstream-Freitext.
  defp url(cfg, top_id), do: cfg.base_url <> "guestagendaitems/" <> top_id

  defp abrufdatum do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
