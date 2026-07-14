defmodule Ratsprojekte.MCP.Tools.ShowPendingProposal do
  @moduledoc """
  Zeige die vollständigen Details eines Vorschlags inkl. Projekt-Titel,
  aller Payload-Felder, Begründung (Quellenpflicht), Quellen und
  Audit-Trail (vorgeschlagen von/am, status, entschieden am/von,
  entscheidungskommentar).

  Read-only. Für Approve/Reject siehe LiveView unter der `review_url`
  (GO-Prinzip — keine MCP-Tools für die Entscheidung).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}
  import Ecto.Query

  schema do
    field(:id, :integer,
      required: true,
      description: "Proposal-ID (von propose_realisierungsstrang oder list_pending_proposals)"
    )
  end

  @impl true
  def execute(%{id: id}, frame) do
    proposal =
      Repo.one(
        from(pp in PendingProposal,
          where: pp.id == ^id,
          preload: [:projekt]
        )
      )

    case proposal do
      nil ->
        {:reply, Response.error(Response.tool(), "Proposal #{id} nicht gefunden"), frame}

      proposal ->
        {:reply, Response.json(Response.tool(), format(proposal)), frame}
    end
  end

  defp format(%PendingProposal{projekt: %Projekt{} = projekt} = proposal) do
    %{
      id: proposal.id,
      projekt_id: projekt.id,
      projekt_titel: projekt.titel,
      typ: proposal.typ,
      payload: proposal.payload,
      begruendung: proposal.begruendung,
      quellen: proposal.quellen,
      vorgeschlagen_von: proposal.vorgeschlagen_von,
      vorgeschlagen_am: DateTime.to_iso8601(proposal.vorgeschlagen_am),
      status: proposal.status,
      entschieden_am: proposal.entschieden_am && DateTime.to_iso8601(proposal.entschieden_am),
      entschieden_von: proposal.entschieden_von,
      entscheidungskommentar: proposal.entscheidungskommentar,
      review_url: "http://localhost:4000/projekte/#{projekt.id}/proposals/#{proposal.id}"
    }
  end
end
