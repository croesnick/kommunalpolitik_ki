defmodule Ratsprojekte.MCP.Server do
  @moduledoc """
  MCP-Server für ratsprojekte — read-only AI-Zugriff auf Stadtratsprojekte.

  GO-Prinzip: alle Tools sind rein lesend. Die AI kann Projekte und Stränge
  einsehen und Standortbestimmungen erstellen, aber nichts schreiben.
  Der Stadtrat entscheidet.
  """

  use Anubis.Server,
    name: "ratsprojekte",
    version: "0.1.0",
    capabilities: [:tools]

  component(Ratsprojekte.MCP.Tools.ListProjekte)
  component(Ratsprojekte.MCP.Tools.ShowProjekt)
  component(Ratsprojekte.MCP.Tools.SearchProjekte)
  component(Ratsprojekte.MCP.Tools.CheckAntragsreife)
end
