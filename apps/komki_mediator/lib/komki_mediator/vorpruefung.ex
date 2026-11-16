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

  Rohe Argumente werden vor allem anderen auf Tiefe und Gesamtgroesse
  begrenzt (Ticket #473, Audit F1): Der Refusal-PDR bindet den gestellten
  Call per kanonischem Hash, und der kanonische Encoder ruckt pro Ebene
  ein - ohne Grenze trieb eine verschachtelte Map dort Θ(Tiefe²) Zellen
  und Bytes. Uebergrenzhafte Argumente enden als billige, strukturierte
  `decision: error`-Ablehnung mit PDR; der intent_hash bindet sie bis
  zur Grenze.
  """

  alias KomkiConnector.{Manifest, Text}
  alias KomkiMediator.{Fassung, Hash, PDR}
  alias KomkiPolicy.JSON
  alias Sidecar.Params

  # Grenzen der rohen Argumente (Ticket #473): Die Schemata der Fassung
  # sind flache Objekte mit Skalarfeldern (groesstes Feld: 1000 Zeichen,
  # apps/komki_connector/lib/komki_connector/manifest.ex) - beide Grenzen
  # liegen weit darueber und weit unter dem, was der Angriff braucht
  # (Audit: ~20 000 Ebenen bei ~150 KB Body).
  @max_depth 32
  @max_weight 256 * 1024

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
      {:ok, schema, rule} -> check_bounded(env, tool, schema, rule, args)
      :unknown_tool -> :ok
    end
  end

  def check(_tool, _arguments, _env), do: :ok

  # Grenzpruefung VOR Params.check und VOR dem Refusal-PDR (Ticket #473):
  # Uebergrenzhafte Argumente werden abgelehnt, bevor irgendetwas sie
  # kanonisiert; innerhalb der Grenzen bleibt der Ablauf unveraendert.
  defp check_bounded(env, tool, schema, rule, args) do
    with :ok <- bound(args),
         {:ok, _normalized} <- Params.check(schema, args, Text) do
      :ok
    else
      {:over, detail} -> {:refused, refused(env, tool, rule, bounded_view(args), detail)}
      {:error, {:params, detail}} -> {:refused, refused(env, tool, rule, args, detail)}
    end
  end

  # Schema und Regelzweig je Tool. Die eigenen Tools ohne Manifest
  # (ping, list_documents) nehmen keine Parameter: Jedes Argument waere
  # ein unbekanntes Feld. admit_document und die Connector-Tools lesen
  # ihr Schema aus dem Manifest (einzige Quelle, Connector-Vertrag
  # #5). Der Regelzweig ist der Fluss, dem der Aufruf ohne Verstoss
  # folgen wuerde: Connector-Tools ueber das ConnectorGate (`emit`),
  # admit_document, Nur-Aufnahme-Operationen (#419) und die eigenen Tools
  # ueber das Gate (`admit`).
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
        # #169) - daher Regelzweig `admit` statt `emit`. Ebenso
        # Nur-Aufnahme-Operationen (#419).
        spec = Map.fetch!(manifest.ops, op)

        rule =
          if manifest.id == "documents" or spec.kind == :admit_only, do: "admit", else: "emit"

        {:ok, spec.params, rule}

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

  # -------------------------------------------------------------------------
  # Tiefe- und Gewichtsgrenze der rohen Argumente (Ticket #473, Audit F1)
  # -------------------------------------------------------------------------

  # Der Walk stoppt bei der ersten Verletzung: Eine uebergrosse Eingabe
  # kostet O(Grenze), nicht O(Eingabe). byte_size/1 ist konstant, also
  # bricht auch eine einzige Riesen-Zeichenkette sofort ab. Das Gewicht
  # zaehlt Bytes plus einen Knoten je Struktur. bound/1 fasst das
  # Akkumulator-Ergebnis zu :ok zusammen.
  defp bound(term) do
    case bound(term, 0, 0) do
      {:ok, _weight} -> :ok
      {:over, _} = over -> over
    end
  end

  defp bound(_term, depth, _weight) when depth > @max_depth,
    do: {:over, "Argumente zu tief verschachtelt (max. #{@max_depth} Ebenen)"}

  defp bound(value, _depth, weight) when is_binary(value),
    do: bounded_weight(weight + byte_size(value) + 1)

  defp bound(%{} = value, depth, weight) do
    Enum.reduce_while(value, {:ok, weight + 1}, fn {key, item}, {:ok, acc} ->
      case bound(item, depth + 1, acc + key_weight(key)) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        {:over, _} = over -> {:halt, over}
      end
    end)
  end

  defp bound(values, depth, weight) when is_list(values) do
    Enum.reduce_while(values, {:ok, weight + 1}, fn item, {:ok, acc} ->
      case bound(item, depth + 1, acc + 1) do
        {:ok, acc} -> {:cont, {:ok, acc}}
        {:over, _} = over -> {:halt, over}
      end
    end)
  end

  defp bound(_leaf, _depth, weight), do: bounded_weight(weight + 1)

  defp bounded_weight(weight) when weight <= @max_weight, do: {:ok, weight}

  defp bounded_weight(_weight),
    do: {:over, "Argumente zu gross (max. #{div(@max_weight, 1024)} KB)"}

  defp key_weight(key) when is_binary(key), do: byte_size(key) + 1
  defp key_weight(_key), do: 1

  # Begrenzte Sicht auf die Argumente fuer den intent_hash einer
  # Grenz-Ablehnung: bindet den Aufruf bis zur Grenze deterministisch
  # (gleicher Aufruf, gleicher Hash, Zusammenspiel mit der Hash-Kette);
  # jenseits der Grenze steht der feste Marker "<begrenzt>". Kosten wie
  # bound/1: O(Grenze). Rueckgabe {sicht, gewicht}; das Gewicht klemmt
  # bei einem Groessenschnitt auf @max_weight + 1, damit Eltern die
  # Geschwister dahinter bestimmt abschneiden. Ein Groessenschnitt
  # mitten in einer Zeichenkette kann ein UTF-8-Zeichen teilen - das ist
  # unschaedlich, die Sicht dient nur als Hash-Primaereingabe und wird
  # nie geparst.
  defp bounded_view(term), do: elem(view(term, 0, 0), 0)

  defp view(_term, depth, _weight) when depth > @max_depth, do: {"<begrenzt>", 1}

  defp view(value, _depth, weight)
       when is_binary(value) and weight + byte_size(value) + 1 <= @max_weight,
       do: {value, weight + byte_size(value) + 1}

  defp view(value, _depth, weight) when is_binary(value) do
    keep = max(@max_weight - weight - 1, 0)
    {binary_part(value, 0, keep) <> "<begrenzt>", @max_weight + 1}
  end

  defp view(%{} = value, depth, weight) do
    {pairs, weight} =
      Enum.reduce_while(value, {[], weight + 1}, fn {key, item}, {acc, w} ->
        if w > @max_weight do
          {:halt, {[{"<begrenzt>", true} | acc], @max_weight + 1}}
        else
          {item_view, w} = view(item, depth + 1, w + key_weight(key))
          {:cont, {[{key, item_view} | acc], w}}
        end
      end)

    {Map.new(Enum.reverse(pairs)), weight}
  end

  defp view(values, depth, weight) when is_list(values) do
    {items, weight} =
      Enum.reduce_while(values, {[], weight + 1}, fn item, {acc, w} ->
        if w > @max_weight do
          {:halt, {["<begrenzt>" | acc], @max_weight + 1}}
        else
          {item_view, w} = view(item, depth + 1, w + 1)
          {:cont, {[item_view | acc], w}}
        end
      end)

    {Enum.reverse(items), weight}
  end

  defp view(leaf, _depth, weight), do: {leaf, weight + 1}
end
