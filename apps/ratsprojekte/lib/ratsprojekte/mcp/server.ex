defmodule Ratsprojekte.MCP.Server do
  @moduledoc """
  MCP-Server für ratsprojekte — AI-Zugriff auf Stadtratsprojekte.

  ## Lese-Tools (read-only)

  Die folgenden Tools sind rein lesend: list_projekte, list_blockierte_projekte,
  show_projekt, search_projekte, check_antragsreife, list_pending_proposals,
  show_pending_proposal.

  ## Schreib-Tools (Staging only)

  `propose_realisierungsstrang`, `propose_projekt`, `propose_status_change`,
  `propose_projekt_update` und `propose_strang_update` schreiben ausschließlich
  in die Staging-Tabelle `pending_proposals` — nicht in `realisierungsstraenge`,
  `projekte`, den Projekt-Status bzw. in die Projektfelder. Die KI kann
  Vorschläge machen, aber nicht bestätigen oder ablehnen.

  ## GO-Execution

  `decide_proposal` führt ein GO aus, das der Stadtrat im Chat gegeben hat
  (Accept/Reject). Die KI darf dieses Tool NIEMALS ohne explizites,
  unmissverständliches GO des Stadtrats aufrufen — kein stillschweigendes
  Accept. `entschieden_von` wird auf `"stadtrat-via-ai"` gesetzt, damit im
  Audit-Trail klar bleibt, welches GO aus dem Chat und welches aus der
  LiveView kam. Die Apply-Logik teilt sich dieses Tool mit der LiveView
  (`Ratsprojekte.ProposalApplier`) — Single Source of Truth.

  ## GO-Prinzip

  Approve/Reject eines Vorschlags geht über die LiveView *oder* über das
  `decide_proposal`-MCP-Tool (wenn der Stadtrat GO im Chat gegeben hat).
  Beide Wege nutzen `Ratsprojekte.ProposalApplier` als Single Source of Truth.
  Die KI ruft `decide_proposal` NIEMALS ohne explizites GO auf — das GO muss
  vom Menschen kommen, nicht von der KI. `entschieden_von` unterscheidet:
  `"stadtrat"` (Browser) vs. `"stadtrat-via-ai"` (Chat).
  Realisierungsstrang- und Statusänderungs-Vorschläge unter
  `/projekte/:projekt_id/proposals/:id`, Projekt-Vorschläge unter
  `/proposals/:id`.
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

  # Propose-Confirm-Pattern: KI schreibt in Staging-Tabelle, GO-Gate über LiveView
  component(Ratsprojekte.MCP.Tools.ProposeRealisierungsstrang)
  component(Ratsprojekte.MCP.Tools.ProposeProjekt)
  component(Ratsprojekte.MCP.Tools.ProposeStatusChange)
  component(Ratsprojekte.MCP.Tools.ProposeProjektUpdate)
  component(Ratsprojekte.MCP.Tools.ProposeStrangUpdate)
  component(Ratsprojekte.MCP.Tools.ListPendingProposals)
  component(Ratsprojekte.MCP.Tools.ShowPendingProposal)

  # GO-Execution: führt GO aus dem Chat aus. Nur mit explizitem GO des Stadtrats.
  component(Ratsprojekte.MCP.Tools.DecideProposal)
end
