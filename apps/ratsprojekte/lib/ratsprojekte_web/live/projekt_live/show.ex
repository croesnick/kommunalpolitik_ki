defmodule RatsprojekteWeb.ProjektLive.Show do
  use RatsprojekteWeb, :live_view

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}
  alias RatsprojekteWeb.NavAssigns
  import Ecto.Query

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    projekt =
      Repo.one(
        from(p in Projekt,
          where: p.slug == ^slug,
          preload: [
            realisierungsstraenge: [:vorbedingungen, :schritte, :quellen],
            quellen: []
          ]
        )
      )

    case projekt do
      nil ->
        {:ok, socket |> put_flash(:error, "Projekt nicht gefunden") |> redirect(to: ~p"/")}

      projekt ->
        pending_count =
          Repo.aggregate(
            from(pp in PendingProposal,
              where: pp.projekt_id == ^projekt.id and pp.status == :pending
            ),
            :count
          )

        {:ok,
         socket
         |> NavAssigns.attach(:projekte)
         |> assign(projekt: projekt, pending_count: pending_count)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page">
      <div class="projekt-title-row">
        <h1 class="page-title">
          {@projekt.titel}
        </h1>
        <button
          type="button"
          class="copy-tag-btn"
          data-tag={"#ratsprojekt/#{@projekt.slug}"}
          aria-label={"Vault-Tag #ratsprojekt/#{@projekt.slug} kopieren"}
          phx-click={JS.dispatch("ratsprojekte:copy-tag")}
        >
          <span class="copy-tag-label">{@projekt.slug}</span>
          <span class="copy-tag-done" aria-hidden="true">✓ Kopiert</span>
        </button>
      </div>
      <p class="page-subtitle" style="margin-bottom: var(--space-3);">
        {@projekt.beschreibung}
      </p>
      <div class="badges" style="margin-bottom: var(--space-6);">
        <.badge kind={:status} value={@projekt.status} />
        <.badge kind={:priority} value={@projekt.prioritaet} />
        <.link
          navigate={~p"/projekte/#{@projekt.slug}/proposals"}
          class={"projekt-proposal-link #{if @pending_count > 0, do: "has-pending", else: "no-pending"}"}
        >
          🤖 {if @pending_count > 0, do: "Offene Vorschläge (#{@pending_count})", else: "Vorschläge"}
        </.link>
      </div>

      <div
        :if={@projekt.value_proposition || @projekt.success_metrics}
        class="projekt-kv"
        style="margin-bottom: var(--space-6);"
      >
        <div class="section-label flush">Ziel &amp; Messung</div>
        <.kv_row
          :if={@projekt.value_proposition}
          label="Value Proposition"
          value={@projekt.value_proposition}
        />
        <.kv_row
          :if={@projekt.success_metrics}
          label="Success Metrics"
          value={@projekt.success_metrics}
        />
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

        <div class="section-label spaced">Schritte auf diesem Weg</div>

        <div :for={schritt <- strang.schritte} class="schritt">
          <span class="schritt-arrow">→</span>
          <span>{schritt.text}</span>
          <span :if={schritt.frist} class="frist-badge">
            ⏰ {Calendar.strftime(schritt.frist, "%d.%m.%Y")}
          </span>
        </div>

        <div :if={strang.quellen != []} class="sources">
          <div class="section-label flush spaced">Quellen</div>
          <.quelle_item :for={q <- strang.quellen} quelle={q} />
        </div>
      </div>

      <div :if={@projekt.quellen != []} class="projekt-quellen">
        <div class="section-label flush spaced">Projekt-Quellen</div>
        <.quelle_item :for={q <- @projekt.quellen} quelle={q} />
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

  defp oder_separator(assigns) do
    ~H"""
    <div class="oder-separator">— ODER —</div>
    """
  end

  attr(:label, :string, required: true)
  attr(:value, :string, required: true)

  defp kv_row(assigns) do
    ~H"""
    <div class="payload-row">
      <span class="payload-row-label">
        {@label}:
      </span>
      <span class="payload-row-value">{@value}</span>
    </div>
    """
  end

  attr(:quelle, :map, required: true)

  defp quelle_item(assigns) do
    ~H"""
    <div class="source-item">
      📄 <a :if={@quelle.url} href={@quelle.url} target="_blank">{@quelle.titel}</a>
      <span :if={!@quelle.url}>{@quelle.titel}</span>
      <span :if={@quelle.paragraf} class="source-paragraf">{@quelle.paragraf}</span>
      <span :if={ris_referenz(@quelle)} class="source-ris">
        <a :if={@quelle.url} href={@quelle.url} target="_blank">{ris_referenz(@quelle)}</a>
        <span :if={!@quelle.url}>{ris_referenz(@quelle)}</span>
      </span>
    </div>
    """
  end

  # Strukturierte RIS-Referenz (#32): „welcher Beschluss gehört zu Projekt X?"
  # Der Link läuft über die URL der Quelle — ratsprojekte kennt nur die IDs
  # (Unix-Prinzip), keine URL-Schemata des RIS.
  defp ris_referenz(quelle) do
    teile =
      Enum.reject(
        [
          if(quelle.ris_sitzung_id, do: "Sitzung #{quelle.ris_sitzung_id}"),
          if(quelle.ris_top, do: "TOP #{quelle.ris_top}"),
          if(quelle.beschluss_nr, do: "Beschluss #{quelle.beschluss_nr}")
        ],
        &is_nil/1
      )

    if teile == [], do: nil, else: "🏛 RIS: " <> Enum.join(teile, " · ")
  end
end
