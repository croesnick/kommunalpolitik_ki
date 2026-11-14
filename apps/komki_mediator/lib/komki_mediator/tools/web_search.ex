defmodule KomkiMediator.Tools.WebSearch do
  @moduledoc """
  MCP tool `web_search`: web search (connector web, operation search).
  Schema and description come from the manifest; the call runs as
  emit → transfer → execution → admit (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "web_search"
end
