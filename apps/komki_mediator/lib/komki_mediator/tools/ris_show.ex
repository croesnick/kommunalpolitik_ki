defmodule KomkiMediator.Tools.RisShow do
  @moduledoc """
  MCP-Tool `ris_show`: Einen oeffentlichen TOP lesen (Connector ris, Operation show).
  Schema und Beschreibung aus dem Manifest, Ablauf emit → Vollzug → admit
  (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "ris_show"
end
