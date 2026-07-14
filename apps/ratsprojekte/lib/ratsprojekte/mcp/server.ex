defmodule Ratsprojekte.MCP.Server do
  @moduledoc """
  MCP-Server für ratsprojekte — AI-Zugriff auf Stadtratsprojekte.

  ## Lese-Tools (read-only)

  Die folgenden Tools sind rein lesend: list_projekte, list_blockierte_projekte,
  show_projekt, search_projekte, check_antragsreife, list_pending_proposals,
  show_pending_proposal.

  ## Schreib-Tools (Staging only)

  `propose_realisierungsstrang`, `propose_projekt` und `propose_status_change`
  schreiben ausschließlich in die Staging-Tabelle `pending_proposals` — nicht
  in `realisierungsstraenge`, `projekte` bzw. in den Projekt-Status. Die AI kann
  Vorschläge machen, aber nicht bestätigen oder ablehnen.

  ## GO-Prinzip

  Approve/Reject eines Vorschlags geht NUR über die LiveView — bewusst KEIN
  MCP-Tool dafür. Realisierungsstrang- und Statusänderungs-Vorschläge unter
  `/projekte/:projekt_id/proposals/:id`, Projekt-Vorschläge unter
  `/proposals/:id`. Der Stadtrat entscheidet, nicht die AI. Das ist das
  disziplinarische GO-Gate für demokratische Verantwortung.
  """

  use Anubis.Server,
    name: "ratsprojekte",
    version: "0.1.0",
    capabilities: [:tools]

  component(Ratsprojekte.MCP.Tools.ListProjekte)
  component(Ratsprojekte.MCP.Tools.ListBlockierteProjekte)
  component(Ratsprojekte.MCP.Tools.ShowProjekt)
  component(Ratsprojekte.MCP.Tools.SearchProjekte)
  component(Ratsprojekte.MCP.Tools.CheckAntragsreife)

  # Propose-Confirm-Pattern: AI schreibt in Staging-Tabelle, GO-Gate über LiveView
  component(Ratsprojekte.MCP.Tools.ProposeRealisierungsstrang)
  component(Ratsprojekte.MCP.Tools.ProposeProjekt)
  component(Ratsprojekte.MCP.Tools.ProposeStatusChange)
  component(Ratsprojekte.MCP.Tools.ListPendingProposals)
  component(Ratsprojekte.MCP.Tools.ShowPendingProposal)
end
