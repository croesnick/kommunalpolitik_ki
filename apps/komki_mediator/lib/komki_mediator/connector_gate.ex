defmodule KomkiMediator.ConnectorGate do
  @moduledoc """
  Ein Connector-Aufruf als emit → Vollzug → admit (Connector-Vertrag §6):
  zwei Entscheidungen der Engine, zwei PDR.

  * Vorpruefung: Parameter gegen das Manifest-Schema
    (`Sidecar.Params.check/3`) und B_W des Raums
    (`workspace_bindings`). Verstoss oder fehlendes B_W: `decision: error`,
    PDR, kein Vollzug (fail-closed).
  * Gate 1 (`emit`): die Anfrage ist eine Ausgabe an die Empfaenger der
    Manifest-Umgebung. Objekt `out-<digest12>`, Fakt
    `output_content_digest = intent_hash`. Kein Permit: Remedies, PDR,
    kein Vollzug. Permit: der emit-PDR wird geschrieben, **bevor** der
    Connector gerufen wird; seine `decision_id` ist die `call_id`.
  * Vollzug: `Sidecar.Client.call/6` gegen
    `<connectors_dir>/<id>.sock`. Bei schreibenden Operationen geht
    `context.assigned_label` (= B_W) mit.
  * Gate 2 (`admit`): Ergebnisform (§5.2), Labels allein aus dem Manifest
    (Vault: Labels der Notiz ⊆ Bindungen aus Γ, #211; `write_test`:
    zurueckgemeldete Labels = `assigned_label`), Objekt `in-<digest12>` in
    `room.environment`, `Derive.decide` und `Verify.check`. Danach der
    admit-PDR mit derselben `call_id`.

  Die Selbstauskunft des Connectors wird nie ueber das Manifest hinaus
  geglaubt. Connector-Fehler ergeben `admitted: false` mit PDR.

  GO (Ticket #98): Bietet der Katalog einer emit-Ablehnung eine
  Aktionsfreigabe fuer den exakten Call an und ist `env.go` gesetzt, fragt
  der Vermittler die nutzende Person, sofern eine Session zuhoert
  (`KomkiMediator.Go`). Eine vorgelegte
  Freigabe entscheidet der Freigabe-Zweig der Engine; nach einem Permit
  committet `KomkiMediator.GoStand` die Nonce und ein PDR
  (`outcome: released`) belegt das GO, beides vor dem Vollzug. Nein,
  keine Antwort oder eine ungueltige Freigabe lassen es beim deny.
  """

  alias KomkiConnector.{Manifest, Text}
  alias KomkiMediator.{Gamma, Gate, Go, GoStand, Hash, PDR, ResultShape, Room}
  alias KomkiMediator.Room.Object
  alias KomkiPolicy.{Derive, JSON, Verify}
  alias Sidecar.{Client, Params}

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

  # Die deutschen Parameter-Fehler erreichen das Modell (Gate-2-Texte).
  defp check_params(spec, rendered) do
    case Params.check(spec.params, rendered, Text) do
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
        response = not_permitted(env, call, "emit", nil, intent, snapshot, other)
        maybe_go(env, call, snapshot, intent, response)
    end
  end

  # -------------------------------------------------------------------------
  # GO: Aktionsfreigabe fuer den exakten Call (Ticket #98)
  # -------------------------------------------------------------------------

  defp maybe_go(%{go: %{} = go} = env, call, snapshot, intent, response) do
    case {Go.offered(response["remedies"]), Go.listening?(go.dir)} do
      {call_hash, true} when is_binary(call_hash) ->
        ask_go(env, go, call, snapshot, intent, response, call_hash)

      _no_offer_or_nobody_listening ->
        response
    end
  end

  defp maybe_go(_env, _call, _snapshot, _intent, response), do: response

  defp ask_go(env, go, call, snapshot, intent, response, call_hash) do
    request = %{
      "schema" => "komki-go-request/1",
      "call_hash" => call_hash,
      "decision_id" => response["decision_id"],
      "tool" => call.tool,
      "params" => call.params,
      "blockers" => Enum.map(response["remedies"], & &1["code"]),
      "object" => intent["object"],
      "workspace" => intent["workspace"],
      # Das Release-Schema verlangt reines Hex; die Engine rechnet den
      # Call-Hash ohnehin selbst aus dem Fakt nach.
      "content_digest" => String.replace_prefix(call.intent_hash, "sha256:", ""),
      "scope" => GoStand.current()["scope"],
      "authority" => Go.authority()
    }

    case Go.await(go, request) do
      {:release, release} -> released(env, call, snapshot, intent, release)
      :refused -> go_not_given(env, call, intent, response, "go_refused")
      :timeout -> go_not_given(env, call, intent, response, "go_timeout")
    end
  end

  defp released(env, call, snapshot, intent, release) do
    case Derive.decide_with_release(
           env.gamma.compiled,
           snapshot,
           intent,
           release,
           GoStand.current()
         ) do
      {:ok, %{"decision" => "permit", "release" => proposal} = decision} ->
        commit_release(env, call, snapshot, intent, decision, proposal)

      other ->
        not_permitted(env, call, "emit", nil, intent, snapshot, other)
    end
  end

  # Commit vor Wirkung (CONTRACT §4.6, B.8): erst die Nonce verbrauchen,
  # dann der PDR, dann der Vollzug. Faellt ein Schritt aus, folgt keiner
  # der spaeteren.
  defp commit_release(env, call, snapshot, intent, decision, proposal) do
    case GoStand.advance(proposal) do
      {:ok, _stand} ->
        PDR.append(env, %{
          "decision_id" => PDR.new_id(),
          "tool" => call.tool,
          "rule" => "emit",
          "decision" => "permit",
          "outcome" => "released",
          "intent_hash" => call.intent_hash,
          "payload_hash" => PDR.payload_hash(proposal),
          "intent_id" => intent["intent_id"],
          "snapshot_id" => snapshot["snapshot_id"],
          "assigned_label" => decision["assigned_label"]
        })

        execute(env, call, decision, snapshot, intent)

      {_refused_or_error, reason} ->
        refused(env, call.tool, call.intent_hash, "GO nicht committet: " <> inspect(reason))
    end
  end

  # Nein oder keine Antwort: es bleibt beim deny, der Katalog bleibt
  # sichtbar; das PDR haelt fest, dass gefragt wurde.
  defp go_not_given(env, call, intent, response, outcome) do
    PDR.append(env, %{
      "decision_id" => PDR.new_id(),
      "tool" => call.tool,
      "rule" => "emit",
      "decision" => "deny",
      "outcome" => outcome,
      "admitted" => false,
      "intent_hash" => call.intent_hash,
      "payload_hash" => PDR.payload_hash(response),
      "intent_id" => intent["intent_id"]
    })

    Map.put(response, "go", if(outcome == "go_refused", do: "abgelehnt", else: "keine Antwort"))
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
        Client.call(socket, call_id, call.op, call.params, context, texts: Text)

      _ ->
        {:error, %{"code" => "upstream-error", "detail" => "kein Connector-Verzeichnis"}}
    end
  end

  # -------------------------------------------------------------------------
  # Gate 2: admit
  # -------------------------------------------------------------------------

  defp admit(env, call, call_id, emit_decision, result) do
    with :ok <- shape(call, result),
         {:ok, _labels} <- labels(env, call, emit_decision, result),
         result = visible(call, env.room, result),
         {:ok, labels} <- labels(env, call, emit_decision, result) do
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

  # Suchtreffer ausserhalb von B_W fallen VOR Gate 2 still heraus
  # (Labbook L-109): sonst waere "deny" gegenueber "permit, 0 Treffer" ein
  # Existenz-Orakel fuer vertrauliche Inhalte. Die Antwort sieht dann aus
  # wie eine Suche ohne diese Treffer; ihre Anzahl verraet nichts.
  # Einzelzugriffe (`read`) bleiben eine Entscheidung mit Remedies.
  defp visible(%{manifest: %{id: "vault"}, op: "search"}, %Room{workspace_bindings: b_w}, result) do
    Map.update!(result, "results", fn hits ->
      Enum.filter(hits, fn hit -> Enum.all?(hit["labels"], &(&1 in b_w)) end)
    end)
  end

  defp visible(_call, _room, result), do: result

  defp shape(call, result) do
    case ResultShape.check(call.manifest.id, call.op, result) do
      :ok -> :ok
      {:error, detail} -> {:redact, "Antwort verletzt die Ergebnisform", [detail]}
    end
  end

  # Labels aus dem Manifest (RIS, Web) oder aus Γ (Vault, #211): §6.2.2, §6.3.
  defp labels(_env, %{kind: :write}, emit_decision, result) do
    assigned = emit_decision["assigned_label"]

    if Enum.sort(result["labels"]) == assigned,
      do: {:ok, assigned},
      else: {:redact, "zurueckgemeldete Labels weichen von assigned_label ab", ["label_mismatch"]}
  end

  # Vault-Notizen tragen ihre Labels selbst (Frontmatter). Seit Γ aus dem
  # Label-Store kommt (#208), gilt jede Bindung aus Γ; ein Label ausserhalb
  # haelt die Antwort zurueck (Ticket #211).
  defp labels(env, %{manifest: %{id: "vault"}, op: op}, _emit_decision, result) do
    notes =
      if op == "search", do: Enum.map(result["results"], & &1["labels"]), else: [result["labels"]]

    bindings = Map.keys(env.gamma.term["bindings"])

    if Enum.all?(notes, &note_labels_ok?(&1, bindings)),
      do: {:ok, notes |> List.flatten() |> Enum.uniq() |> Enum.sort()},
      else: {:redact, "Labels der Notiz ausserhalb von Γ", ["label_not_in_gamma"]}
  end

  defp labels(_env, %{manifest: manifest}, _emit_decision, _result),
    do: {:ok, Enum.sort(manifest.import_labels)}

  # Eine Notiz traegt mindestens ein Label, und alle sind Bindungen aus Γ.
  defp note_labels_ok?(labels, bindings),
    do: labels != [] and Enum.all?(labels, &(&1 in bindings))

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
