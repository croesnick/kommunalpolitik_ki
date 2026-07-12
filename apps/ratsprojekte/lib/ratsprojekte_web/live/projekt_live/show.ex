defmodule RatsprojekteWeb.ProjektLive.Show do
  use RatsprojekteWeb, :live_view

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  import Ecto.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    projekt =
      Repo.one(
        from p in Projekt,
          where: p.id == ^id,
          preload: [
            realisierungsstraenge: [:vorbedingungen, :schritte, :quellen],
            quellen: []
          ]
      )

    case projekt do
      nil ->
        {:ok, socket |> put_flash(:error, "Projekt nicht gefunden") |> redirect(to: ~p"/")}

      projekt ->
        {:ok, assign(socket, projekt: projekt)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 1000px; margin: 0 auto; padding: 24px;">
      <div class="show-back">
        <.link navigate={~p"/"}>← Zurück zur Übersicht</.link>
      </div>

      <h1 style="font-size: 22px; font-weight: 700; margin-bottom: 4px;">
        {@projekt.titel}
      </h1>
      <p style="font-size: 14px; color: #64748b; margin-bottom: 12px;">
        {@projekt.beschreibung}
      </p>
      <div class="badges" style="margin-bottom: 24px;">
        <.badge status={@projekt.status} />
        <.prio_badge prio={@projekt.prioritaet} />
      </div>

      <div :for={{strang, i} <- Enum.with_index(@projekt.realisierungsstraenge)} class="strang">
        <.oder_separator :if={i > 0} />

        <div class="strang-header">
          <.strang_label label={strang.label} />
          <span class="strang-title">{strang.titel}</span>
        </div>

        <div class="strang-desc">{strang.beschreibung}</div>

        <.strang_status strang={strang} />

        <div :if={strang.bedingung} class="strang-bedingung">
          <span class="bedingung-label">Strang-Bedingung:</span>
          <span>{strang.bedingung}</span>
          <span class={"bedingung-status #{if strang.bedingung_erfuellt, do: "status-met", else: "status-unmet"}"}>
            {if strang.bedingung_erfuellt, do: "✓ erfüllt", else: "⚠ offen"}
          </span>
        </div>

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
          <div class="section-label" style="padding-left: 0; margin-top: 12px;">Quellen</div>
          <div :for={q <- strang.quellen} class="source-item">
            📄 <a :if={q.url} href={q.url} target="_blank">{q.titel}</a>
            <span :if={!q.url}>{q.titel}</span>
            <span :if={q.paragraf} class="source-paragraf">{q.paragraf}</span>
          </div>
        </div>
      </div>

      <div :if={@projekt.quellen != []} class="projekt-quellen">
        <div class="section-label" style="padding-left: 0; margin-top: 24px;">Projekt-Quellen</div>
        <div :for={q <- @projekt.quellen} class="source-item">
          📄 <a :if={q.url} href={q.url} target="_blank">{q.titel}</a>
          <span :if={!q.url}>{q.titel}</span>
          <span :if={q.paragraf} class="source-paragraf">{q.paragraf}</span>
        </div>
      </div>
    </div>
    """
  end

  attr(:strang, :map, required: true)

  defp strang_status(assigns) do
    vorbedingungen = assigns.strang.vorbedingungen
    total = length(vorbedingungen)
    erfuellt = Enum.count(vorbedingungen, & &1.erfuellt)
    offen = total - erfuellt

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(:erfuellt, erfuellt)
      |> assign(:offen, offen)

    ~H"""
    <div class="strang-status">
      <span class="status-pill status-met">{@erfuellt} ✓</span>
      <span :if={@offen > 0} class="status-pill status-unmet">{@offen} ⚠</span>
      <span class="status-summary">
        {if @offen == 0,
          do: "Alle Vorbedingungen erfüllt",
          else: "#{@offen} von #{@total} Vorbedingungen offen"}
      </span>
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
