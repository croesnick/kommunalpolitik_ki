defmodule KomkiMediator.Tools.RisSearch do
  @moduledoc """
  MCP tool `ris_search`: search public agenda items in the RIS (connector ris, operation search).
  Schema and description come from the manifest; the call runs as
  emit → transfer → execution → admit (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "ris_search"
end
