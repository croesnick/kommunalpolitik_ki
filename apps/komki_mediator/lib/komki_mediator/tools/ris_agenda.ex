defmodule KomkiMediator.Tools.RisAgenda do
  @moduledoc """
  MCP tool `ris_agenda`: the public agenda of one RIS meeting (connector ris, operation agenda, #516).
  Schema and description come from the manifest; the call runs as
  emit → transfer → execution → admit (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "ris_agenda"
end
