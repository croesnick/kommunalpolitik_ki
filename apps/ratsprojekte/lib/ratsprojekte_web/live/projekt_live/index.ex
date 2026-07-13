defmodule RatsprojekteWeb.ProjektLive.Index do
  use RatsprojekteWeb, :live_view

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    projekte =
      Repo.all(
        from(p in Projekt,
          order_by: [desc: p.prioritaet, desc: p.inserted_at],
          preload: [realisierungsstraenge: [:vorbedingungen, :schritte, :quellen]]
        )
      )

    {:ok, assign(socket, projekte: projekte)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 1000px; margin: 0 auto; padding: 24px;">
      <h1 style="font-size: 22px; font-weight: 700; margin-bottom: 4px;">
        Stadtrats-Projekte Buchloe
      </h1>
      <p style="font-size: 14px; color: #64748b; margin-bottom: 24px;">
        Rechtlich-inhaltliche Standortbestimmung — welche Realisierungsstränge gibt es und stehen die Vorbedingungen?
      </p>

      <.link
        :for={projekt <- @projekte}
        navigate={~p"/projekte/#{projekt.id}"}
        class="project-card-link"
      >
        <div class="project-card">
          <div class="project-header">
            <div>
              <h2>{projekt.titel}</h2>
              <div class="desc">{projekt.beschreibung}</div>
            </div>
            <div class="badges">
              <.badge status={projekt.status} />
              <.prio_badge prio={projekt.prioritaet} />
            </div>
          </div>

          <div :for={{strang, i} <- Enum.with_index(projekt.realisierungsstraenge)} class="strang">
            <.oder_separator :if={i > 0} />

            <div class="strang-header">
              <.strang_label label={strang.label} />
              <span class="strang-title">{strang.titel}</span>
            </div>

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

            <div class="section-label" style="margin-top: 12px;">Schritte auf diesem Weg</div>

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
      </.link>
    </div>
    """
  end

  attr(:status, :atom, required: true)

  defp badge(assigns) do
    colors = %{idee: "#dbeafe", aktiv: "#dcfce7", abgeschlossen: "#f3f4f6"}
    text_colors = %{idee: "#1e40af", aktiv: "#166534", abgeschlossen: "#374151"}

    assigns =
      assigns
      |> assign(:bg, Map.get(colors, assigns.status, "#f3f4f6"))
      |> assign(:fg, Map.get(text_colors, assigns.status, "#374151"))

    ~H"""
    <span class="badge" style={"background: #{@bg}; color: #{@fg};"}>
      {@status}
    </span>
    """
  end

  attr(:prio, :atom, required: true)

  defp prio_badge(assigns) do
    colors = %{hoch: "#fee2e2", mittel: "#fef9c3", niedrig: "#f3f4f6"}
    text_colors = %{hoch: "#991b1b", mittel: "#854d0e", niedrig: "#374151"}

    assigns =
      assigns
      |> assign(:bg, Map.get(colors, assigns.prio, "#f3f4f6"))
      |> assign(:fg, Map.get(text_colors, assigns.prio, "#374151"))

    ~H"""
    <span class="badge" style={"background: #{@bg}; color: #{@fg};"}>
      {@prio}
    </span>
    """
  end

  attr(:label, :string, required: true)

  defp strang_label(assigns) do
    colors = %{"A" => "#16a34a", "B" => "#ca8a04", "C" => "#2563eb"}
    assigns = assign(assigns, :bg, Map.get(colors, assigns.label, "#6b7280"))

    ~H"""
    <span class="strang-label" style={"background: #{@bg};"}>
      {@label}
    </span>
    """
  end

  defp oder_separator(assigns) do
    ~H"""
    <div class="oder-separator">— ODER —</div>
    """
  end
end
