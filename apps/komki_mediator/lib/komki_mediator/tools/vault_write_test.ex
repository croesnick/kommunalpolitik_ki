defmodule KomkiMediator.Tools.VaultWriteTest do
  @moduledoc """
  MCP tool `vault_write_test`: create a test note in the vault (connector vault, operation write_test).
  Schema and description come from the manifest; the call runs as
  emit → store → execution → admit (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "vault_write_test"
end
