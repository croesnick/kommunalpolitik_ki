defmodule KomkiMediator.Tools.VaultRead do
  @moduledoc """
  MCP tool `vault_read`: read one vault note (connector vault, operation read).
  Schema and description come from the manifest; the call runs as
  emit → transfer → execution → admit (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "vault_read"
end
