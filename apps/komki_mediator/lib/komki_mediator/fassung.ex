defmodule KomkiMediator.Fassung do
  @moduledoc """
  Feststehende, versionierte Verbindungsauflage (R.4.3): die Menge der vom
  Vermittler angebotenen MCP-Tools, als festgedrehte Fassung der
  Angriffsflaeche. `tools/0` ist die geordnete Liste; die vom MCP-Server
  advertised Tool-Namen muessen exakt dieser Liste entsprechen
  (Regressionssicherung D.9 gegen den Connector-Bypass).
  """

  @fassung_id "komki-mediator/3"

  # Feste Ordnung: die Tools des Vermittlers selbst (ping, seit #218
  # list_documents), dann die Connector-Tools sortiert
  # (= KomkiConnector.Manifest.tools/0, Connector-Vertrag §5.1; seit #169
  # gehoert admit_document dazu).
  @own_tools ["ping", "list_documents"]

  @tools @own_tools ++
           [
             "admit_document",
             "ris_search",
             "ris_show",
             "vault_read",
             "vault_search",
             "vault_write_test",
             "web_search"
           ]

  @doc "Versionskennung dieser Verbindungsauflage."
  @spec fassung_id() :: String.t()
  def fassung_id, do: @fassung_id

  @doc "Die Tools des Vermittlers selbst, ohne Connector (vor den Connector-Tools)."
  @spec own_tools() :: [String.t()]
  def own_tools, do: @own_tools

  @doc "Geordnete, festgedrehte Tool-Menge der Fassung."
  @spec tools() :: [String.t()]
  def tools, do: @tools
end
