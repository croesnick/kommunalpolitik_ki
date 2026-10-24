defmodule KomkiMediator.ConnectorGate do
  @moduledoc """
  Ein Connector-Aufruf als emit → Vollzug → admit (Connector-Vertrag §6):
  zwei Entscheidungen der Engine, zwei PDR.

  * Vorpruefung: Parameter gegen das Manifest-Schema
    (`KomkiConnector.Params.check/2`) und B_W des Raums
    (`workspace_bindings`). Verstoss oder fehlendes B_W: `decision: error`,
    PDR, kein Vollzug (fail-closed).
  * Gate 1 (`emit`): die Anfrage ist eine Ausgabe an die Empfaenger der
    Manifest-Umgebung. Objekt `out-<digest12>`, Fakt
    `output_content_digest = intent_hash`. Kein Permit: Remedies, PDR,
    kein Vollzug. Permit: der emit-PDR wird geschrieben, **bevor** der
    Connector gerufen wird; seine `decision_id` ist die `call_id`.
  * Vollzug: `KomkiConnector.Client.call/6` gegen
    `<connectors_dir>/<id>.sock`. Bei schreibenden Operationen geht
    `context.assigned_label` (= B_W) mit.
  * Gate 2 (`admit`): Ergebnisform (§5.2), Labels allein aus dem Manifest
    (Vault: Labels der Notiz ⊆ `import_labels`; `write_test`:
    zurueckgemeldete Labels = `assigned_label`), Objekt `in-<digest12>` in
    `room.environment`, `Derive.decide` und `Verify.check`. Danach der
    admit-PDR mit derselben `call_id`.

  Die Selbstauskunft des Connectors wird nie ueber das Manifest hinaus
  geglaubt. Connector-Fehler ergeben `admitted: false` mit PDR.
  """

  alias KomkiConnector.{Client, Manifest, Params}
  alias KomkiMediator.{Gamma, Gate, Hash, PDR, ResultShape, Room}
  alias KomkiMediator.Room.Object
  alias KomkiPolicy.{Derive, JSON, Verify}

  @doc "Vermittelt einen Aufruf des Connector-Tools `tool` (z. B. `\"ris_search\"`)."
  @spec call(Gate.env(), String.t(), map()) :: map()
  def call(env, tool, params) do
    {:ok, manifest, op} = Manifest.by_tool(tool)
    spec = Map.fetch!(manifest.ops, op)
    rendered = params |> Gate.rendered_params() |> Map.reject(fn {_k, v} -> is_nil(v) end)

    with {:ok, checked} <- check_params(spec, rendered),
         :ok <- check_bindings(env.room) do
      call = %{
        tool: tool,
        manifest: manifest,
        op: op,
        kind: spec.kind,
        params: checked,
        intent_hash: intent_hash(tool, checked)
      }

      emit(env, call)
    else
      {:error, detail} -> refused(env, tool, intent_hash(tool, rendered), detail)
    end
  end

  # -------------------------------------------------------------------------
  # Vorpruefung
  # -------------------------------------------------------------------------

  defp check_params(spec, rendered) do
    case Params.check(spec.params, rendered) do
      {:ok, checked} -> {:ok, checked}
      {:error, {:params, detail}} -> {:error, "Parameter: " <> detail}
    end
  end

  defp check_bindings(%Room{workspace_bindings: bindings}) when is_list(bindings), do: :ok

  defp check_bindings(_room),
    do: {:error, "Raum ohne workspace_bindings: keine Connector-Operationen"}

  defp intent_hash(tool, params),
    do: Hash.sha256_hex(JSON.canonical(%{"tool" => tool, "params" => params}))

  # -------------------------------------------------------------------------
  # Gate 1: emit
  # -------------------------------------------------------------------------

  defp emit(env, call) do
    d12 = Hash.digest12(call.intent_hash)
    object = %Object{object_id: "out-" <> d12, version: "v1", labels: []}

    digest_fact = %{
      "value" => call.intent_hash,
      "source" => "komki-mediator",
      "source_kind" => "technical"
    }

    snapshot =
      Room.connector_snapshot(env.room, env.gamma, %{
        snapshot_id: "snap-emit-" <> d12,
        environment: call.manifest.environment,
        object: object,
        facts: Map.put(env.room.facts, "output_content_digest", digest_fact)
      })

    intent = intent(env.room, "emit", "intent-emit-" <> d12, object)

    case Derive.decide(env.gamma.compiled, snapshot, intent) do
      {:ok, %{"decision" => "permit"} = decision} ->
        execute(env, call, decision, snapshot, intent)

      other ->
        not_permitted(env, call, "emit", nil, intent, snapshot, other)
    end
  end

  # -------------------------------------------------------------------------
  # Vollzug
  # -------------------------------------------------------------------------

  defp execute(env, call, decision, snapshot, intent) do
    call_id = PDR.new_id()

    context =
      if call.kind == :write, do: %{"assigned_label" => decision["assigned_label"]}, else: %{}

    # Vorbeleg vor Wirkung (R.11): der emit-PDR liegt im Journal, bevor
    # die Anfrage den Vermittler verlaesst. payload_hash bindet die
    # ausgehende Anfrage (Operation, Parameter, Kontext).
    PDR.append(env, %{
      "decision_id" => call_id,
      "call_id" => call_id,
      "tool" => call.tool,
      "rule" => "emit",
      "decision" => "permit",
      "outcome" => "emitted",
      "admitted" => nil,
      "intent_hash" => call.intent_hash,
      "payload_hash" =>
        PDR.payload_hash(%{"op" => call.op, "params" => call.params, "context" => context}),
      "intent_id" => intent["intent_id"],
      "snapshot_id" => snapshot["snapshot_id"],
      "checked_label" => decision["checked_label"],
      "assigned_label" => decision["assigned_label"]
    })

    case connector_call(env, call, call_id, context) do
      {:ok, result} -> admit(env, call, call_id, decision, result)
      {:error, error} -> connector_failed(env, call, call_id, error)
    end
  end

  # Ohne konfiguriertes Connector-Verzeichnis ist kein Connector
  # erreichbar; der Aufruf faellt als Connector-Fehler aus.
  defp connector_call(env, call, call_id, context) do
    case Map.get(env, :connectors_dir) do
      dir when is_binary(dir) ->
        socket = Path.join(dir, call.manifest.id <> ".sock")
        Client.call(socket, call_id, call.op, call.params, context)

      _ ->
        {:error, %{"code" => "upstream-error", "detail" => "kein Connector-Verzeichnis"}}
    end
  end

  # -------------------------------------------------------------------------
  # Gate 2: admit
  # -------------------------------------------------------------------------

  defp admit(env, call, call_id, emit_decision, result) do
    with :ok <- shape(call, result),
         {:ok, labels} <- labels(call, emit_decision, result) do
      d12 = Hash.digest12(PDR.payload_hash(result))
      object = %Object{object_id: "in-" <> d12, version: "v1", labels: labels}

      snapshot =
        Room.connector_snapshot(env.room, env.gamma, %{
          snapshot_id: "snap-admit-" <> d12,
          environment: env.room.environment,
          object: object,
          facts: env.room.facts
        })

      intent = intent(env.room, "admit", "intent-admit-" <> d12, object)

      case Derive.decide(env.gamma.compiled, snapshot, intent) do
        {:ok, %{"decision" => "permit"} = decision} ->
          verify(env, call, call_id, result, labels, decision, snapshot, intent)

        other ->
          not_permitted(env, call, "admit", call_id, intent, snapshot, other)
      end
    else
      {:redact, reason, codes} -> redact(env, call, call_id, reason, codes)
    end
  end

  defp shape(call, result) do
    case ResultShape.check(call.manifest.id, call.op, result) do
      :ok -> :ok
      {:error, detail} -> {:redact, "Antwort verletzt die Ergebnisform", [detail]}
    end
  end

  # Labels allein aus dem Manifest (§6.2.2, §6.3).
  defp labels(%{kind: :write}, emit_decision, result) do
    assigned = emit_decision["assigned_label"]

    if Enum.sort(result["labels"]) == assigned,
      do: {:ok, assigned},
      else: {:redact, "zurueckgemeldete Labels weichen von assigned_label ab", ["label_mismatch"]}
  end

  defp labels(%{manifest: %{id: "vault"} = manifest, op: op}, _emit_decision, result) do
    notes =
      if op == "search", do: Enum.map(result["results"], & &1["labels"]), else: [result["labels"]]

    if Enum.all?(notes, &note_labels_ok?(&1, manifest.import_labels)),
      do: {:ok, notes |> List.flatten() |> Enum.uniq() |> Enum.sort()},
      else: {:redact, "Labels der Notiz ausserhalb der import_labels", ["label_not_importable"]}
  end

  defp labels(%{manifest: manifest}, _emit_decision, _result),
    do: {:ok, Enum.sort(manifest.import_labels)}

  # Eine Notiz traegt mindestens ein Label, und alle stammen aus den
  # import_labels des Manifests.
  defp note_labels_ok?(labels, import_labels),
    do: labels != [] and Enum.all?(labels, &(&1 in import_labels))

  defp verify(env, call, call_id, result, labels, decision, snapshot, intent) do
    case Verify.check(env.gamma.compiled, snapshot, intent, decision["proof"]) do
      {:ok, %{"result" => "valid"}} ->
        admitted(env, call, call_id, result, labels, decision, snapshot, intent)

      {:ok, %{"result" => "invalid", "reasons" => reasons}} ->
        redact(env, call, call_id, "unabhaengige Beweispruefung fehlgeschlagen", reasons)

      {:error, err} ->
        redact(env, call, call_id, "unabhaengige Beweispruefung fehlgeschlagen", [
          Gate.error_detail(err)
        ])
    end
  end

  # -------------------------------------------------------------------------
  # Ausgaenge (jeweils mit PDR)
  # -------------------------------------------------------------------------

  defp admitted(env, call, call_id, result, labels, decision, snapshot, intent) do
    decision_id = PDR.new_id()

    base =
      Map.merge(result, %{
        "decision" => "permit",
        "rule" => "admit",
        "decision_id" => decision_id,
        "emit_decision_id" => call_id,
        "labels" => labels
      })

    payload_hash = PDR.payload_hash(base)

    PDR.append(env, %{
      "decision_id" => decision_id,
      "call_id" => call_id,
      "tool" => call.tool,
      "rule" => "admit",
      "decision" => "permit",
      "outcome" => "admitted",
      "admitted" => true,
      "intent_hash" => call.intent_hash,
      "payload_hash" => payload_hash,
      "intent_id" => intent["intent_id"],
      "snapshot_id" => snapshot["snapshot_id"],
      "checked_label" => decision["checked_label"]
    })

    Map.put(base, "payload_hash", payload_hash)
  end

  # deny/indeterminate (Remedies) oder Entscheidungsfehler, in Gate 1
  # (call_id nil, kein Vollzug) oder Gate 2 (Inhalt bleibt zurueck).
  defp not_permitted(env, call, rule, call_id, intent, snapshot, outcome) do
    decision_id = PDR.new_id()

    {pdr_decision, response} =
      case outcome do
        {:ok, %{"decision" => kind, "remedies" => remedies}} ->
          {kind,
           %{
             "decision" => kind,
             "remedies" => remedies,
             "relaxation_authorities" => Gamma.relaxation_authorities_for(env.gamma, remedies)
           }}

        {:unsupported, info} ->
          {"unsupported", %{"decision" => "error", "detail" => info}}

        {:error, err} ->
          {"error", %{"decision" => "error", "detail" => Gate.error_detail(err)}}
      end

    response =
      response
      |> Map.merge(%{
        "rule" => rule,
        "decision_id" => decision_id,
        "registry_id" => env.gamma.registry_id
      })
      |> put_emit_id(call_id)

    PDR.append(env, %{
      "decision_id" => decision_id,
      "call_id" => call_id,
      "tool" => call.tool,
      "rule" => rule,
      "decision" => pdr_decision,
      "outcome" =>
        if(pdr_decision in ["deny", "indeterminate"], do: "not_admitted", else: "error"),
      "admitted" => false,
      "intent_hash" => call.intent_hash,
      "payload_hash" => PDR.payload_hash(response),
      "intent_id" => intent["intent_id"],
      "snapshot_id" => snapshot["snapshot_id"],
      "remedies" => response["remedies"]
    })

    response
  end

  defp redact(env, call, call_id, reason, details) do
    decision_id = PDR.new_id()

    core = %{
      "decision" => "permit",
      "rule" => "admit",
      "admitted" => "redacted",
      "decision_id" => decision_id,
      "emit_decision_id" => call_id,
      "reason" => reason,
      "verify" => details
    }

    payload_hash = PDR.payload_hash(core)

    PDR.append(env, %{
      "decision_id" => decision_id,
      "call_id" => call_id,
      "tool" => call.tool,
      "rule" => "admit",
      "decision" => "permit",
      "outcome" => "redacted",
      "admitted" => "redacted",
      "intent_hash" => call.intent_hash,
      "payload_hash" => payload_hash
    })

    Map.put(core, "payload_hash", payload_hash)
  end

  defp connector_failed(env, call, call_id, error) do
    decision_id = PDR.new_id()

    response = %{
      "decision" => "permit",
      "rule" => "admit",
      "admitted" => false,
      "decision_id" => decision_id,
      "emit_decision_id" => call_id,
      "error" => error
    }

    PDR.append(env, %{
      "decision_id" => decision_id,
      "call_id" => call_id,
      "tool" => call.tool,
      "rule" => "admit",
      "decision" => "permit",
      "outcome" => "error",
      "admitted" => false,
      "intent_hash" => call.intent_hash,
      "payload_hash" => PDR.payload_hash(response)
    })

    response
  end

  # Vorpruefung gescheitert (Schema, fehlendes B_W): keine Entscheidung
  # der Engine, kein Vollzug.
  defp refused(env, tool, intent_hash, detail) do
    decision_id = PDR.new_id()

    response = %{
      "decision" => "error",
      "rule" => "emit",
      "decision_id" => decision_id,
      "detail" => detail
    }

    PDR.append(env, %{
      "decision_id" => decision_id,
      "tool" => tool,
      "rule" => "emit",
      "decision" => "error",
      "outcome" => "error",
      "admitted" => false,
      "intent_hash" => intent_hash,
      "payload_hash" => PDR.payload_hash(response)
    })

    response
  end

  # -------------------------------------------------------------------------
  # Bausteine
  # -------------------------------------------------------------------------

  defp put_emit_id(response, nil), do: response
  defp put_emit_id(response, call_id), do: Map.put(response, "emit_decision_id", call_id)

  defp intent(room, operation, intent_id, object) do
    %{
      "schema" => "komki-intent/1",
      "intent_id" => intent_id,
      "operation" => operation,
      "object" => object.object_id <> "@" <> object.version,
      "workspace" => room.workspace_id
    }
  end
end
