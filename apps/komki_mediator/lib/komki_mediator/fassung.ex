defmodule KomkiMediator.Fassung do
  @moduledoc """
  Feststehende, versionierte Verbindungsauflage (R.4.3): die Menge der vom
  Vermittler angebotenen MCP-Tools, als festgedrehte Fassung der
  Angriffsflaeche. `tools/0` ist die geordnete Liste; die vom MCP-Server
  advertised Tool-Namen muessen exakt dieser Liste entsprechen
  (Regressionssicherung D.9 gegen den Connector-Bypass).
  """

  @fassung_id "komki-mediator/1"

  @tools ["ping", "admit_document"]

  # Exposure fuer das mcp.json-Rendering komki_clis: dieselbe Map wird
  # zusaetzlich via /healthz ausgegeben, damit komki_cli die Tools baumartig
  # ausliest und nie hartkodiert.
  @mcp_tool_exposure %{"ping" => "direct", "admit_document" => "direct"}

  @doc "Versionskennung dieser Verbindungsauflage."
  @spec fassung_id() :: String.t()
  def fassung_id, do: @fassung_id

  @doc "Geordnete, festgedrehte Tool-Menge der Fassung."
  @spec tools() :: [String.t()]
  def tools, do: @tools

  @doc "Exposure-Art je Tool (Layer-Abbildung fuer das mcp.json-Rendering komki_clis)."
  @spec mcp_tool_exposure() :: %{String.t() => String.t()}
  def mcp_tool_exposure, do: @mcp_tool_exposure
end
