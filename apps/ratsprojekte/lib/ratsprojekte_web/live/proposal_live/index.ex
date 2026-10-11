defmodule RatsprojekteWeb.ProposalLive.Index do
  use RatsprojekteWeb, :live_view

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}
  alias RatsprojekteWeb.NavAssigns
  import Ecto.Query

  @impl true
  def mount(params, _session, socket) do
    projekt_slug = params["projekt_slug"]

    if projekt_slug do
      projekt = Repo.one(from(p in Projekt, where: p.slug == ^projekt_slug))

      case projekt do
        nil ->
          {:ok, socket |> put_flash(:error, "Projekt nicht gefunden") |> redirect(to: ~p"/")}

        projekt ->
          proposals =
            Repo.all(
              from(pp in PendingProposal,
                where: pp.projekt_id == ^projekt.id,
                order_by: [asc: pp.status, desc: pp.vorgeschlagen_am]
              )
            )

          {:ok,
           socket
           |> NavAssigns.attach(:projekte)
           |> assign(projekt: projekt, proposals: proposals)}
      end
    else
      # Top-level: add_projekt-Vorschlaege ohne Eltern-Projekt (projekt_id IS NULL)
      proposals =
        Repo.all(
          from(pp in PendingProposal,
            where: is_nil(pp.projekt_id),
            order_by: [asc: pp.status, desc: pp.vorgeschlagen_am]
          )
        )

      {:ok,
       socket
       |> NavAssigns.attach(:vorschlaege)
       |> assign(projekt: nil, proposals: proposals)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page">
      <h1 class="page-title">
        {heading(@projekt)}
      </h1>
      <p class="page-subtitle" style="margin-bottom: var(--space-1);">
        {subline(@projekt)}
      </p>
      <p style="font-size: var(--text-sm); color: var(--color-text-faint); margin-bottom: var(--space-6);">
        Approve/Reject nur hier in der LiveView — GO-Prinzip.
      </p>

      <div :if={@proposals == []} class="empty-state">
        {empty_message(@projekt)}
      </div>

      <.link
        :for={proposal <- @proposals}
        navigate={proposal_path(@projekt, proposal)}
        class="project-card-link"
      >
        <div class="project-card">
          <div class="project-header">
            <div>
              <h2>{payload_titel(proposal)}</h2>
              <div class="desc">{proposal.typ} · vorgeschlagen von {proposal.vorgeschlagen_von}</div>
            </div>
            <div class="badges">
              <.badge kind={:proposal} value={proposal.status} />
            </div>
          </div>
          <div class="proposal-preview">
            {String.slice(proposal.begruendung, 0, 140)}
            {if String.length(proposal.begruendung) > 140, do: "…", else: ""}
          </div>
        </div>
      </.link>
    </div>
    """
  end

  defp heading(nil), do: "Neue Projekte (Vorschläge)"
  defp heading(projekt), do: "Vorschläge für „#{projekt.titel}\""

  defp subline(nil),
    do:
      "AI-Vorschläge für neue Projekte. Status-Änderungen und Strang-Vorschläge findest du beim jeweiligen Projekt."

  defp subline(_projekt),
    do: "AI-Vorschläge für Realisierungsstränge und Status-Änderungen."

  defp empty_message(nil), do: "Keine Vorschläge."
  defp empty_message(_projekt), do: "Keine Vorschläge für dieses Projekt."

  defp proposal_path(nil, proposal), do: ~p"/proposals/#{proposal.id}"

  defp proposal_path(projekt, proposal),
    do: ~p"/projekte/#{projekt.slug}/proposals/#{proposal.id}"

  defp payload_titel(proposal) do
    case proposal.payload do
      %{"titel" => titel} when is_binary(titel) -> titel
      %{titel: titel} when is_binary(titel) -> titel
      _ -> "Vorschlag ##{proposal.id}"
    end
  end
end
