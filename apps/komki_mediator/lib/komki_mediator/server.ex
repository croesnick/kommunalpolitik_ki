defmodule KomkiMediator.Server do
  @moduledoc """
  MCP-Server `komki` (anubis_mcp, StreamableHTTP). pi erreicht den
  Vermittler ausschliesslich ueber die hier registrierten Tools — die
  advertised Tool-Namen muessen exakt `KomkiMediator.Fassung.tools/0`
  ergeben (D.9: angebotene Fassung gleich der Verbindungsaufflache).

  Die Tools entscheiden nichts selbst: jeder Aufruf laeuft durch das Gate
  (Gate 1: Policy-Entscheid vor dem Vollzug, Gate 2: Beweispruefung vor der
  Antwort), und jeder Ablauf geht mit einem PDR ins Journal. Die sechs
  Connector-Tools laufen ueber `KomkiMediator.ConnectorGate` (emit →
  Vollzug → admit, zwei PDR).
  """

  use Anubis.Server, name: "komki", version: "0.1.0", capabilities: [:tools]

  component(KomkiMediator.Tools.Ping)
  component(KomkiMediator.Tools.ListDocuments)
  component(KomkiMediator.Tools.AdmitDocument)
  component(KomkiMediator.Tools.RisSearch)
  component(KomkiMediator.Tools.RisShow)
  component(KomkiMediator.Tools.VaultRead)
  component(KomkiMediator.Tools.VaultSearch)
  component(KomkiMediator.Tools.VaultWriteTest)
  component(KomkiMediator.Tools.WebSearch)
end
