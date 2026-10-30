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
  transfer bzw. store → Vollzug → admit, drei PDR).

  Jedem `tools/call` stellt `handle_request/2` die Parameter-Vorpruefung
  `KomkiMediator.Vorpruefung` voran (Ticket #165): Schemaverstoesse und
  unbekannte Felder enden als `decision: error` mit PDR, bevor die
  anubis-Schicht sie ohne PDR ablehnt (`invalid_params`) oder Felder
  still verwirft. Alle anderen Methoden bedient der injizierte anubis-
  Default.
  """

  use Anubis.Server, name: "komki", version: "0.1.0", capabilities: [:tools]

  alias Anubis.Server.{Handlers, Response}
  alias KomkiMediator.{Env, Vorpruefung}

  component(KomkiMediator.Tools.Ping)
  component(KomkiMediator.Tools.ListDocuments)
  component(KomkiMediator.Tools.AdmitDocument)
  component(KomkiMediator.Tools.RisSearch)
  component(KomkiMediator.Tools.RisShow)
  component(KomkiMediator.Tools.VaultRead)
  component(KomkiMediator.Tools.VaultSearch)
  component(KomkiMediator.Tools.VaultWriteTest)
  component(KomkiMediator.Tools.WebSearch)

  # Ticket #165: Die Vorpruefung sieht die rohen Argumente - inklusive
  # unbekannter Felder und falscher Typen, welche die anubis-Schicht
  # sonst ohne PDR ablehnt bzw. still verwirft. Bestandene Aufrufe
  # laufen unveraendert weiter; die anubis-Validierung bleibt fuer sie
  # als zweite Schicht wirksam. Der Klauselkopf verlangt `params` als
  # Objekt mit `name`: Alles Unparsbare (etwa `params` als Liste) faellt
  # unveraendert an den injizierten Default zurueck, und `get_in/2` im
  # Rumpf kann auf einer Map nicht raisen. `Handlers.handle/3` ist der
  # Rumpf des injizierten Defaults (`super` steht vor dem before_compile
  # nicht bereit); alle Methoden ausser `tools/call` erreicht der
  # Default direkt.
  @impl Anubis.Server
  def handle_request(%{"method" => "tools/call", "params" => %{"name" => name}} = request, frame) do
    arguments = get_in(request, ["params", "arguments"])

    case Vorpruefung.check(name, arguments, Env.for_call(frame)) do
      :ok ->
        Handlers.handle(request, __MODULE__, frame)

      {:refused, response} ->
        {:reply, Response.to_protocol(Response.json(Response.tool(), response)), frame}
    end
  end
end
