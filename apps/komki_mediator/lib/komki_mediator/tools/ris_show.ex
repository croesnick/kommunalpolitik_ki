defmodule KomkiMediator.Tools.RisShow do
  @moduledoc """
  MCP tool `ris_show`: show one public agenda item from the RIS (connector ris, operation show).
  Schema and description come from the manifest; the call runs as
  emit → transfer → execution → admit (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "ris_show"
end
