defmodule KomkiMediator.Tools.VaultSearch do
  @moduledoc """
  MCP tool `vault_search`: search the vault (connector vault, operation search).
  Schema and description come from the manifest; the call runs as
  emit → transfer → execution → admit (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "vault_search"
end
