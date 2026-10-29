defmodule KomkiMediator.Vorpruefung do
  @moduledoc """
  Parameter-Vorpruefung am MCP-Eingang (Ticket #165): Der Vermittler
  prueft die rohen Argumente jedes `tools/call` gegen das Schema des
  Tools (`Sidecar.Params.check/3` mit den deutschen Fehlertexten aus
  `KomkiConnector.Text`, wie die Vorpruefung im ConnectorGate), bevor
  die anubis-Schicht sie ablehnt oder Felder still verwirft. Jeder
  Verstoss — falscher Typ, ausserhalb des Bereichs, zu lang, leeres
  oder fehlendes Pflichtfeld, unzulaessiges Muster, unbekanntes Feld,
  Argumente ueberhaupt kein Objekt — endet als `decision: error` mit
  PDR und als normale Tool-Antwort ans Modell.

  Vorher (Labbook L-105, S-06): Typ, Laenge, Bereich und Pflichtfelder
  lehnte anubis vor dem Tool ab (`invalid_params`), ohne PDR; unbekannte
  Felder verwarf es stillschweigend (`web_search {"query": "...",
  "url": "..."}` lief als Suche ohne `url`). Jetzt ist der ausgefuehrte
  Call immer der gestellte Call, und jede Ablehnung steht mit
  `decision_id` im Journal.

  Die anubis-Schemas der Tools bleiben unveraendert: Die Werbung ans
  Modell nennt weiterhin Typ und Grenzen, ihre Validierung wirkt fuer
  bestandene Aufrufe als zweite Schicht. Tool-Namen ausserhalb der
  Fassung prueft die Vorpruefung nicht (D.9, kein Parameter-Thema): Sie
  erreichen die anubis-Schicht unveraendert (Tool not found, ohne PDR).
  """

  alias KomkiConnector.{Manifest, Text}
  alias KomkiMediator.{Fassung, Hash, PDR}
  alias KomkiPolicy.JSON
  alias Sidecar.Params

  @doc """
  Prueft die rohen `arguments` eines `tools/call` auf `tool` gegen das
  Schema des Tools.

      * `:ok` — die Argumente passen (oder der Name gehoert nicht zur
        Fassung): der Aufruf geht unveraendert an die anubis-Schicht.
      * `{:refused, response}` — Antwort ans Modell; der Ablehnungs-PDR
        ist bereits geschrieben.

  `env` ist die Aufruf-Umgebung (`KomkiMediator.Env.for_call/1`).
  """
  @spec check(term(), term(), map()) :: :ok | {:refused, map()}
  def check(tool, arguments, env) when is_binary(tool) do
    args = if is_nil(arguments), do: %{}, else: arguments

    case schema_for(tool) do
      {:ok, schema, rule} ->
        case Params.check(schema, args, Text) do
          {:ok, _normalized} -> :ok
          {:error, {:params, detail}} -> {:refused, refused(env, tool, rule, args, detail)}
        end

      :unknown_tool ->
        :ok
    end
  end

  def check(_tool, _arguments, _env), do: :ok

  # Schema und Regelzweig je Tool. Die eigenen Tools ohne Manifest
  # (ping, list_documents) nehmen keine Parameter: Jedes Argument waere
  # ein unbekanntes Feld. admit_document und die Connector-Tools lesen
  # ihr Schema aus dem Manifest (einzige Quelle, Connector-Vertrag
  # #5). Der Regelzweig ist der Fluss, dem der Aufruf ohne Verstoss
  # folgen wuerde: Connector-Tools ueber das ConnectorGate (`emit`),
  # admit_document und die eigenen Tools ueber das Gate (`admit`).
  defp schema_for(tool) do
    if tool in Fassung.own_tools() do
      {:ok, %{}, "admit"}
    else
      manifest_schema(tool)
    end
  end

  defp manifest_schema(tool) do
    case Manifest.by_tool(tool) do
      {:ok, manifest, op} ->
        # Das documents-Manifest dient nur dem Vollzug von admit_document;
        # die Entscheidung faellt im Gate (KomkiMediator.Gate, Ticket
        # #169) - daher Regelzweig `admit` statt `emit`.
        rule = if(manifest.id == "documents", do: "admit", else: "emit")
        {:ok, Map.fetch!(manifest.ops, op).params, rule}

      :error ->
        :unknown_tool
    end
  end

  # Ablehnung vor jeder Entscheidung der Engine: kein Vollzug. Der PDR
  # entspricht der Vorpruefung im ConnectorGate (decision error, outcome
  # error, admitted false); der intent_hash bindet den gestellten Call -
  # Tool samt rohen, ungefilterten Argumenten.
  defp refused(env, tool, rule, args, detail) do
    decision_id = PDR.new_id()

    response = %{
      "decision" => "error",
      "rule" => rule,
      "decision_id" => decision_id,
      "detail" => "Parameter: " <> detail
    }

    PDR.append(env, %{
      "decision_id" => decision_id,
      "tool" => tool,
      "rule" => rule,
      "decision" => "error",
      "outcome" => "error",
      "admitted" => false,
      "intent_hash" => Hash.sha256_hex(JSON.canonical(%{"tool" => tool, "params" => args})),
      "payload_hash" => PDR.payload_hash(response)
    })

    response
  end
end
