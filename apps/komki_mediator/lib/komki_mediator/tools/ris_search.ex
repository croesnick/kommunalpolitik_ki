defmodule KomkiMediator.Tools.RisSearch do
  @moduledoc """
  MCP-Tool `ris_search`: Volltextsuche im RIS (Connector ris, Operation search).
  Schema und Beschreibung aus dem Manifest, Ablauf emit → Vollzug → admit
  (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "ris_search"
end
