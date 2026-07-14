defmodule Ratsprojekte.MCP.Tools.ListPendingProposals do
  @moduledoc """
  Liste offene (oder alle) Vorschläge für ein Projekt.

  Proposals werden durch `propose_realisierungsstrang` in der
  Staging-Tabelle `pending_proposals` angelegt. Der Stadtrat
  entscheidet über Approve/Reject in der LiveView (GO-Prinzip) —
  dieses Tool ist rein lesend.

  Pro Eintrag werden id, typ, payload, begruendung, quellen,
  vorgeschlagen_am, status und eine review_url geliefert.

  Verwende show_pending_proposal für die vollen Details zu einem Vorschlag.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}
  import Ecto.Query

  schema do
    field(:projekt_slug, :string,
      required: true,
      description: "Projekt-Slug (von list_projekte / search_projekte)"
    )

    field(:status, :string,
      default: "pending",
      description: "Status-Filter: 'pending' (default), 'approved', 'rejected'"
    )
  end

  @impl true
  def execute(params, frame) do
    projekt_slug = params[:projekt_slug]

    projekt = Repo.one(from(p in Projekt, where: p.slug == ^projekt_slug))

    if projekt == nil do
      {:reply, Response.error(Response.tool(), "Projekt '#{projekt_slug}' nicht gefunden"), frame}
    else
      status =
        case params[:status] || "pending" do
          "pending" -> :pending
          "approved" -> :approved
          "rejected" -> :rejected
          other -> String.to_existing_atom(other)
        end

      proposals =
        Repo.all(
          from(pp in PendingProposal,
            where: pp.projekt_id == ^projekt.id and pp.status == ^status,
            order_by: [asc: pp.vorgeschlagen_am]
          )
        )

      formatted = Enum.map(proposals, &format(&1, projekt))
      {:reply, Response.json(Response.tool(), formatted), frame}
    end
  end

  defp format(proposal, projekt) do
    %{
      id: proposal.id,
      typ: proposal.typ,
      payload: proposal.payload,
      begruendung: proposal.begruendung,
      quellen: proposal.quellen,
      vorgeschlagen_am: DateTime.to_iso8601(proposal.vorgeschlagen_am),
      status: proposal.status,
      review_url: "http://localhost:4000/projekte/#{projekt.slug}/proposals/#{proposal.id}"
    }
  end
end
