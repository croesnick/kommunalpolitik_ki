defmodule KomkiMediator.Tools.VaultSearch do
  @moduledoc """
  MCP-Tool `vault_search`: Vault-Notizen suchen (Connector vault, Operation search).
  Schema und Beschreibung aus dem Manifest, Ablauf emit → Vollzug → admit
  (`KomkiMediator.ConnectorGate`).
  """

  use KomkiMediator.Tools.Connector, tool: "vault_search"
end
