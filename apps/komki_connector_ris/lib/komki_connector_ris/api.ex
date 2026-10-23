defmodule KomkiConnectorRis.Api do
  @moduledoc """
  Die drei Gast-Endpunkte der RIS-API (`risapi1.komuna.net/web/`), die
  ohne Anmeldung erreichbar sind (geprueft 2026-10-23). Kopfzeilen und
  Mandant wie in `apps/ratsinfo` (`Ratsinfo.Config`):

  - `GET guestmeetings?client=32&from=YYYY-MM-DD&until=YYYY-MM-DD`
    → `{"items": [{"id", "name", "meetingdate", "committeename", ...}]}`
  - `GET guestmeetings/{id}`
    → `{"id", "name", "meetingdate", "parts": [{"protectedpart", "agendaitems": [{"id", "numbering", "name", "restricted"}]}]}`
  - `GET guestagendaitems/{meetingId-agendaItemId}`
    → `{"id", "name", "restricted", "textsanddocsvisible", "textblocks": [{"caption", "content"}], ...}`

  Die angemeldeten Gegenstuecke (`meetings/{id}`, `agendaitems/{id}`,
  `fulltextsearch`), die `ratsinfo` nutzt, antworten ohne Token mit 401.

  Jeder Aufruf haelt die Frist des laufenden Connector-Aufrufs ein
  (`cfg.deadline`, monotone Millisekunden). Fehler werden auf die
  geschlossenen Codes abgebildet; ein 404 bleibt `:not_found`, damit
  der Aufrufer entscheidet, was das heisst. Fehlermeldungen enthalten
  nie Upstream-Text.
  """

  alias KomkiConnectorRis.Http

  # Wie Ratsinfo.Config: Mandant und Kopfzeilen der VG Buchloe.
  @client_id 32
  @headers [
    {"x-orgkey", "RIS51"},
    {"x-customname", "vgbuchloe"},
    {"x-uniqueid", "ris.komuna.net/vgbuchloe"},
    {"accept", "application/json"}
  ]

  @type cfg :: %{
          required(:base_url) => String.t(),
          required(:timeout_ms) => pos_integer(),
          required(:deadline) => integer(),
          optional(atom()) => term()
        }
  @type failure :: {:error, String.t(), String.t()}

  @doc "Sitzungen eines Zeitfensters (Gast-Endpunkt)."
  @spec meetings(cfg(), Date.t(), Date.t()) :: {:ok, [map()]} | failure()
  def meetings(cfg, from, until) do
    query =
      URI.encode_query(
        client: @client_id,
        from: Date.to_iso8601(from),
        until: Date.to_iso8601(until)
      )

    case get(cfg, "guestmeetings?" <> query) do
      {:ok, %{"items" => items}} when is_list(items) -> {:ok, items}
      {:ok, _} -> bad_response()
      :not_found -> {:ok, []}
      {:error, _, _} = e -> e
    end
  end

  @doc "Sitzung mit Tagesordnung."
  @spec meeting(cfg(), pos_integer()) :: {:ok, map()} | :not_found | failure()
  def meeting(cfg, id) when is_integer(id), do: object(get(cfg, "guestmeetings/#{id}"))

  @doc "TOP-Details samt Textbloecken. `top_id` ist bereits gegen das ID-Muster geprueft."
  @spec agendaitem(cfg(), String.t()) :: {:ok, map()} | :not_found | failure()
  def agendaitem(cfg, top_id), do: object(get(cfg, "guestagendaitems/" <> top_id))

  @doc "Restzeit bis zur Frist in Millisekunden (nie negativ)."
  @spec remaining(cfg()) :: non_neg_integer()
  def remaining(%{deadline: deadline}),
    do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp object({:ok, map}) when is_map(map), do: {:ok, map}
  defp object({:ok, _}), do: bad_response()
  defp object(other), do: other

  defp get(cfg, path) do
    case min(cfg.timeout_ms, remaining(cfg)) do
      0 ->
        timeout()

      timeout_ms ->
        case Http.get_json(cfg.base_url <> path, @headers, timeout_ms) do
          {:ok, body} ->
            {:ok, body}

          {:error, :not_found} ->
            :not_found

          {:error, :timeout} ->
            timeout()

          {:error, {:status, status}} ->
            {:error, "upstream-error", "RIS antwortet mit HTTP #{status}"}

          {:error, :bad_json} ->
            bad_response()

          {:error, :unreachable} ->
            {:error, "upstream-error", "RIS nicht erreichbar"}
        end
    end
  end

  defp timeout, do: {:error, "upstream-timeout", "RIS antwortet nicht rechtzeitig"}
  defp bad_response, do: {:error, "upstream-error", "RIS liefert eine unerwartete Antwort"}
end
