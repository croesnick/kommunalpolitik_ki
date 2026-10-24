defmodule KomkiMediator.Tools.WebSearch do
  @moduledoc """
  MCP-Tool `web_search`: Websuche (Connector web, Operation search).
  Schema und Beschreibung aus dem Manifest, Ablauf emit → Vollzug → admit
  (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "web_search"
end
