defmodule KomkiMediator.Tools.VaultWriteTest do
  @moduledoc """
  MCP-Tool `vault_write_test`: Testnotiz im Vault anlegen (Connector vault, Operation write_test).
  Schema und Beschreibung aus dem Manifest, Ablauf emit → Vollzug → admit
  (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "vault_write_test"
end
