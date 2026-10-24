defmodule KomkiMediator.Tools.VaultRead do
  @moduledoc """
  MCP-Tool `vault_read`: Eine Vault-Notiz lesen (Connector vault, Operation read).
  Schema und Beschreibung aus dem Manifest, Ablauf emit → Vollzug → admit
  (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "vault_read"
end
