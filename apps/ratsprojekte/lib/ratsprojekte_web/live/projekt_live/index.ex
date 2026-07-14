defmodule RatsprojekteWeb.ProjektLive.Index do
  use RatsprojekteWeb, :live_view

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  alias RatsprojekteWeb.NavAssigns
  import Ecto.Query

  @status_optionen [
    {"", "alle"},
    {"idee", "idee"},
    {"aktiv", "aktiv"},
    {"abgeschlossen", "abgeschlossen"},
    {"verworfen", "verworfen"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> NavAssigns.attach(:projekte)
     |> assign(:status_optionen, @status_optionen)
     |> stream(:projekte, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = parse_filter(params)

    projekte =
      base_query()
      |> apply_status(filter.status)
      |> apply_seit(filter.status, filter.seit)
      |> Repo.all()
      |> then(fn projekte ->
        if filter.blockiert do
          Enum.filter(projekte, &blockiert?/1)
        else
          projekte
        end
      end)

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> stream(:projekte, projekte, reset: true)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filter_params = params["filter"] || params
    {:noreply, push_patch(socket, to: ~p"/?#{cleaned_filter(filter_params)}")}
  end

  defp base_query do
    from(p in Projekt,
      order_by: [desc: p.prioritaet, desc: p.inserted_at],
      preload: [realisierungsstraenge: [:vorbedingungen, :schritte, :quellen]]
    )
  end

  defp parse_filter(params) do
    %{
      status: blank_to_nil(params["status"]),
      seit: parse_date(params["seit"]),
      blockiert: params["blockiert"] == "true"
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value

  defp parse_date(""), do: nil
  defp parse_date(nil), do: nil

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp cleaned_filter(params) when is_map(params) do
    %{}
    |> maybe_put(:status, Map.get(params, "status"))
    |> maybe_put(:seit, Map.get(params, "seit"))
    |> maybe_put(:blockiert, if(Map.get(params, "blockiert") == "true", do: "true", else: nil))
  end

  defp cleaned_filter(_), do: %{}

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp apply_status(query, nil), do: query

  defp apply_status(query, status) do
    from(p in query, where: p.status == ^status)
  end

  defp apply_seit(query, _status, nil), do: query

  defp apply_seit(query, "abgeschlossen", seit) do
    from(p in query, where: p.abgeschlossen_am >= ^seit)
  end

  defp apply_seit(query, "verworfen", seit) do
    from(p in query, where: p.verworfen_am >= ^seit)
  end

  defp apply_seit(query, _status, seit) do
    from(p in query,
      where: p.abgeschlossen_am >= ^seit or p.verworfen_am >= ^seit
    )
  end

  defp blockiert?(projekt) do
    not Enum.any?(projekt.realisierungsstraenge, & &1.bedingung_erfuellt)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page">
      <h1 class="page-title">Stadtrats-Projekte Buchloe</h1>
      <p class="page-subtitle">
        Rechtlich-inhaltliche Standortbestimmung — welche Realisierungsstränge gibt es und stehen die Vorbedingungen?
      </p>

      <.filter_form filter={@filter} status_optionen={@status_optionen} />

      <div :for={{_dom_id, projekt} <- @streams.projekte} class="project-card">
        <.link navigate={~p"/projekte/#{projekt.slug}"} class="project-card-link">
          <div class="project-header">
            <div>
              <h2>{projekt.titel}</h2>
              <div class="desc">{projekt.beschreibung}</div>
            </div>
            <div class="badges">
              <.badge kind={:status} value={projekt.status} />
              <.badge kind={:priority} value={projekt.prioritaet} />
            </div>
          </div>
        </.link>

        <div
          :for={{strang, i} <- Enum.with_index(projekt.realisierungsstraenge)}
          class="strang"
          id={"strang-#{projekt.id}-#{strang.label}"}
        >
          <.oder_separator :if={i > 0} />

          <div
            class="strang-header"
            role="button"
            tabindex="0"
            aria-expanded="false"
            phx-click={
              JS.toggle(to: "#strang-details-#{projekt.id}-#{strang.label}")
              |> JS.toggle_class("strang-open", to: "#strang-#{projekt.id}-#{strang.label}")
            }
          >
            <.strang_label label={strang.label} />
            <span class="strang-title">{strang.titel}</span>
            <span class="chevron" aria-hidden="true">▶</span>
          </div>

          <div
            id={"strang-details-#{projekt.id}-#{strang.label}"}
            class="strang-details"
            style="display: none;"
          >
            <div class="strang-desc">{strang.beschreibung}</div>

            <div class="section-label">Rechtliche Vorbedingungen</div>

            <div
              :for={vorb <- strang.vorbedingungen}
              class={"vorbedingung #{if vorb.erfuellt, do: "vorb-met", else: "vorb-unmet"}"}
            >
              <span class="vorb-icon">{if vorb.erfuellt, do: "✓", else: "⚠"}</span>
              <span class="vorb-text">{vorb.text}</span>
              <span
                :if={vorb.rechtliche_grundlage}
                class={"legal-badge #{if vorb.erfuellt, do: "legal-met", else: "legal-unmet"}"}
              >
                {vorb.rechtliche_grundlage}
              </span>
            </div>

            <div class="section-label spaced">Schritte auf diesem Weg</div>

            <div :for={schritt <- strang.schritte} class="schritt">
              <span class="schritt-arrow">→</span>
              <span>{schritt.text}</span>
              <span :if={schritt.frist} class="frist-badge">
                ⏰ {Calendar.strftime(schritt.frist, "%d.%m.%Y")}
              </span>
            </div>

            <div :if={strang.quellen != []} class="sources">
              <div :for={q <- strang.quellen} class="source-item">
                📄 <a :if={q.url} href={q.url} target="_blank">{q.titel}</a>
                <span :if={!q.url}>{q.titel}</span>
                <span :if={q.paragraf} class="source-paragraf">{q.paragraf}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:filter, :map, required: true)
  attr(:status_optionen, :list, required: true)

  defp filter_form(assigns) do
    ~H"""
    <form id="filter-form" phx-change="filter" class="filter-form">
      <label class="filter-field">
        <span class="filter-field-label">Status</span>
        <select name="filter[status]" class="filter-input">
          <option
            :for={{value, label} <- @status_optionen}
            value={value}
            selected={value == (@filter.status || "")}
          >
            {label}
          </option>
        </select>
      </label>

      <label class="filter-field">
        <span class="filter-field-label">Seit</span>
        <input
          type="date"
          name="filter[seit]"
          value={if @filter.seit, do: Date.to_iso8601(@filter.seit), else: ""}
          class="filter-input"
        />
      </label>

      <label class="filter-checkbox-field">
        <input
          type="checkbox"
          name="filter[blockiert]"
          value="true"
          checked={@filter.blockiert}
          class="filter-checkbox"
        />
        <span class="filter-checkbox-label">Nur blockierte</span>
      </label>
    </form>
    """
  end

  defp oder_separator(assigns) do
    ~H"""
    <div class="oder-separator">— ODER —</div>
    """
  end
end
