defmodule KomkiMediator.Tools.RisSessions do
  @moduledoc """
  MCP tool `ris_sessions`: list RIS meetings in a date window (connector ris, operation sessions, #516).
  Schema and description come from the manifest; the call runs as
  emit → transfer → execution → admit (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "ris_sessions"
end
