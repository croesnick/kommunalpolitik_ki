defmodule KomkiConnectorRis do
  @moduledoc """
  RIS-Connector `komki-ris/2` (CONTRACT.md §5.1/§5.2): `search` und `show`
  ueber oeffentliche Tagesordnungspunkte (TOPs) der RIS-API.

  Der Connector nutzt nur die Gast-Endpunkte der API (`guestmeetings`,
  `guestagendaitems`, siehe `KomkiConnectorRis.Api`) und braucht deshalb
  keine Zugangsdaten.

  ## Suchstrategie

  Die Volltextsuche der RIS-API (`fulltextsearch`) verlangt eine Anmeldung.
  Der Connector sucht deshalb selbst, mit festem Anfragebudget
  (`max_requests`) und fester Frist (`budget_ms`):

  1. Sitzungen eines Zeitfensters laden (`days_back` zurueck, `days_ahead`
     voraus), neueste zuerst.
  2. Je Sitzung die Tagesordnung laden, nicht-oeffentliche TOPs verwerfen,
     Titel vergleichen.
  3. Mit dem Restbudget die Textbloecke der oeffentlichen TOPs laden, deren
     Titel nicht passte, und vergleichen (neueste zuerst).
  4. Schluss, sobald `limit` Treffer da sind oder Budget bzw. Frist
     verbraucht sind. Das Ergebnis kann dann unvollstaendig sein.

  Verglichen wird als Teilstring ohne Ruecksicht auf Gross- und
  Kleinschreibung (`String.downcase/1`). Weil nicht-oeffentliche TOPs vor
  jedem Vergleich wegfallen, tauchen sie weder in Treffern noch in der
  Anzahl auf.
  """

  @behaviour Sidecar.Server

  alias KomkiConnector.Manifest
  alias KomkiConnectorRis.{Api, Http, Top}

  @defaults %{
    base_url: "https://risapi1.komuna.net/web/",
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

    case Http.start(cfg.proxy) do
      :ok -> {:ok, cfg}
      {:error, reason} -> {:error, "HTTP-Start fehlgeschlagen: #{inspect(reason)}"}
    end
  end

  @impl true
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

  # Die Detailantwort darf die Einstufung nur verschaerfen: steht dort ein
  # restricted-Feld, muss es false sein.
  defp public_detail?(%{"restricted" => restricted}), do: restricted == false
  defp public_detail?(_), do: true

  # ---------------------------------------------------------------------------

  # Link aus Basis-URL und gepruefter ID, nie aus Upstream-Freitext.
  defp url(cfg, top_id), do: cfg.base_url <> "guestagendaitems/" <> top_id

  defp abrufdatum do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
