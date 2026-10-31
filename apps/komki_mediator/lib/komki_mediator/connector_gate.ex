defmodule KomkiMediator.ConnectorGate do
  @moduledoc """
  A connector call as emit → transfer or store → execution → admit
  (connector contract §6): three engine decisions, each recorded in the
  journal when it is made, plus a record before the effect. All PDRs of a
  call share one `call_id`.

  * Pre-check: parameters against the manifest schema
    (`Sidecar.Params.check/3`) and the room's B_W (`workspace_bindings`).
    A violation or a missing B_W yields `decision: error`, a PDR and no
    execution (fail-closed). There is no call yet, so this PDR carries no
    `call_id`.
  * Gate 1a (`emit`, CONTRACT §4.5): the room produces the request y. The
    environment is the room's (`room.environment`); the engine assigns
    λ(y) = B_W. Object `out-<digest12>`, fact
    `output_content_digest = intent_hash`. No permit: remedies, PDR, no
    execution.
  * Gate 1b: y leaves the room, decided under λ(y) = `assigned_label` in
    the manifest environment. Read operations hand the request to the
    connector (`transfer`, CONTRACT §4.8, ticket #298); write operations
    (`kind: :write`) put y into its store (`store`, CONTRACT §4.7, ticket
    #205). This is where the recipient check against RIS, web search or
    vault happens. Without a `store` rule in Γ, writing is a deny with an
    action release for the exact call.
  * PDRs per call: every engine decision is journaled when it is made —
    `permitted`, a denial, or `released` after a GO — so the journal holds
    the complete derivation even when nothing is executed. Right before
    execution follows the record before effect (rule `emit`, `outcome:
    emitted`, `decision: null` because it decides nothing; its
    `decision_id` is the `call_id` sent in the frame, its
    `intent_id`/`snapshot_id` name the transfer or store decision it relies
    on, and its `payload_hash` binds the outgoing request). The admit PDR follows the
    execution. Every PDR after the pre-check carries the call's `call_id`.
  * Execution: `Sidecar.Client.call/6` against
    `<connectors_dir>/<id>.sock`. Write operations send
    `context.assigned_label` (= B_W).
  * Gate 2 (`admit`): result shape (§5.2), labels from the manifest only
    (vault: note labels ⊆ bindings in Γ, #211; `write_test`: returned
    labels = `assigned_label`), object `in-<digest12>` in
    `room.environment`, `Derive.decide` and `Verify.check`.

  The connector's self-report is never trusted beyond the manifest.
  Connector errors yield `admitted: false` with a PDR.

  GO (ticket #98): if the catalog of a Gate 1 denial offers an action
  release for the exact call and `env.go` is set, the mediator asks the
  person, provided a session is listening (`KomkiMediator.Go`). The
  engine's release branch decides a presented release; on permit
  `KomkiMediator.GoStand` commits the nonce and a PDR (`outcome:
  released`) records the GO right away, both before any effect. That PDR
  is the decision of the release branch, so no `permitted` PDR follows
  for the same gate. No, no answer or an invalid release leave the deny in
  place.
  """

  alias KomkiConnector.{Manifest, Text}
  alias KomkiMediator.{Gamma, Gate, Go, GoStand, Hash, Hinweis, PDR, ResultShape, Room}
  alias KomkiMediator.Room.Object
  alias KomkiPolicy.{Derive, JSON, Verify}
  alias Sidecar.{Client, Params}

  @doc "Mediates a call of the connector tool `tool` (e.g. `\"ris_search\"`)."
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
        intent_hash: intent_hash(tool, checked),
        call_id: PDR.new_id()
      }

      emit(env, call)
    else
      {:error, detail} -> refused(env, tool, intent_hash(tool, rendered), detail)
    end
  end

  # -------------------------------------------------------------------------
  # Pre-check
  # -------------------------------------------------------------------------

  # The German parameter errors reach the model (Gate 2 texts).
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
  # Gate 1a: emit inside the room
  # -------------------------------------------------------------------------

  defp emit(env, call) do
    d12 = Hash.digest12(call.intent_hash)
    object = %Object{object_id: "out-" <> d12, version: "v1", labels: []}

    snapshot =
      Room.connector_snapshot(env.room, env.gamma, %{
        snapshot_id: "snap-emit-" <> d12,
        environment: env.room.environment,
        object: object,
        facts: Map.put(env.room.facts, "output_content_digest", digest_fact(call))
      })

    intent = intent(env.room, "emit", "intent-emit-" <> d12, object)

    to_handover = fn decision ->
      handover(env, call, %{decision: decision, snapshot: snapshot, intent: intent})
    end

    case Derive.decide(env.gamma.compiled, snapshot, intent) do
      {:ok, %{"decision" => "permit"} = decision} ->
        permitted(env, call, decision, snapshot, intent)
        to_handover.(decision)

      other ->
        response = not_permitted(env, call, "emit", nil, intent, snapshot, other)
        maybe_go(env, call, snapshot, intent, response, to_handover)
    end
  end

  defp digest_fact(call) do
    %{"value" => call.intent_hash, "source" => "komki-mediator", "source_kind" => "technical"}
  end

  # -------------------------------------------------------------------------
  # Gate 1b: transfer to the connector (§4.8) or store into its store
  # (§4.7), both under λ(y) in the manifest environment
  # -------------------------------------------------------------------------

  defp handover(env, call, emit) do
    rule = if call.kind == :write, do: "store", else: "transfer"
    d12 = Hash.digest12(call.intent_hash)

    object = %Object{
      object_id: "out-" <> d12,
      version: "v1",
      labels: emit.decision["assigned_label"]
    }

    snapshot =
      Room.connector_snapshot(env.room, env.gamma, %{
        snapshot_id: "snap-" <> rule <> "-" <> d12,
        environment: call.manifest.environment,
        object: object,
        facts: Map.put(env.room.facts, "output_content_digest", digest_fact(call))
      })

    intent = intent(env.room, rule, "intent-" <> rule <> "-" <> d12, object)
    # After a GO the released PDR already records the Gate 1b decision.
    gate1b = %{snapshot: snapshot, intent: intent}
    executed = fn _decision -> execute(env, call, emit, gate1b) end

    case Derive.decide(env.gamma.compiled, snapshot, intent) do
      {:ok, %{"decision" => "permit"} = decision} ->
        permitted(env, call, decision, snapshot, intent)
        execute(env, call, emit, gate1b)

      other ->
        response = not_permitted(env, call, rule, nil, intent, snapshot, other)
        maybe_go(env, call, snapshot, intent, response, executed)
    end
  end

  # A permit of the normal branch, journaled when it is made (emit, transfer
  # or store). For emit it carries the assigned λ(y).
  defp permitted(env, call, decision, snapshot, intent) do
    PDR.append(env, %{
      "decision_id" => PDR.new_id(),
      "call_id" => call.call_id,
      "tool" => call.tool,
      "rule" => intent["operation"],
      "decision" => "permit",
      "outcome" => "permitted",
      "intent_hash" => call.intent_hash,
      "payload_hash" => PDR.payload_hash(decision),
      "intent_id" => intent["intent_id"],
      "snapshot_id" => snapshot["snapshot_id"],
      "checked_label" => decision["checked_label"],
      "assigned_label" => decision["assigned_label"]
    })
  end

  # -------------------------------------------------------------------------
  # GO: action release for the exact call (ticket #98, store #205,
  # transfer #298)
  # -------------------------------------------------------------------------

  # `then` continues after a permit of the release branch: after emit like a
  # normal emit permit, after transfer or store with the execution.
  defp maybe_go(%{go: %{} = go} = env, call, snapshot, intent, response, then) do
    case {Go.offered(response["remedies"]), Go.listening?(go.dir)} do
      {call_hash, true} when is_binary(call_hash) ->
        ask_go(env, go, call, {snapshot, intent, then}, response, call_hash)

      _no_offer_or_nobody_listening ->
        response
    end
  end

  defp maybe_go(_env, _call, _snapshot, _intent, response, _then), do: response

  defp ask_go(env, go, call, {snapshot, intent, then}, response, call_hash) do
    request = %{
      "schema" => "komki-go-request/1",
      "call_hash" => call_hash,
      "decision_id" => response["decision_id"],
      "operation" => intent["operation"],
      "tool" => call.tool,
      "params" => call.params,
      # One entry per code for the preview (store, transfer: one blocker per binding).
      "blockers" => response["remedies"] |> Enum.map(& &1["code"]) |> Enum.uniq(),
      "object" => intent["object"],
      "workspace" => intent["workspace"],
      # The release schema wants plain hex; the engine recomputes the call
      # hash from the fact anyway.
      "content_digest" => String.replace_prefix(call.intent_hash, "sha256:", ""),
      "scope" => GoStand.current()["scope"],
      "authority" => Go.authority()
    }

    case Go.await(go, request) do
      {:release, release} -> released(env, call, {snapshot, intent, then}, release)
      :refused -> go_not_given(env, call, {snapshot, intent}, response, "go_refused")
      :timeout -> go_not_given(env, call, {snapshot, intent}, response, "go_timeout")
    end
  end

  defp released(env, call, {snapshot, intent, then}, release) do
    case Derive.decide_with_release(
           env.gamma.compiled,
           snapshot,
           intent,
           release,
           GoStand.current()
         ) do
      {:ok, %{"decision" => "permit", "release" => proposal} = decision} ->
        commit_release(env, call, {snapshot, intent, then}, decision, proposal)

      other ->
        not_permitted(env, call, intent["operation"], nil, intent, snapshot, other)
    end
  end

  # Commit before effect (CONTRACT §4.6, B.8): consume the nonce first,
  # then the PDR, then the execution. If a step fails, none of the later
  # ones follows.
  defp commit_release(env, call, {snapshot, intent, then}, decision, proposal) do
    case GoStand.advance(proposal) do
      {:ok, _stand} ->
        PDR.append(env, %{
          "decision_id" => PDR.new_id(),
          "call_id" => call.call_id,
          "tool" => call.tool,
          "rule" => intent["operation"],
          "decision" => "permit",
          "outcome" => "released",
          "intent_hash" => call.intent_hash,
          "payload_hash" => PDR.payload_hash(proposal),
          "intent_id" => intent["intent_id"],
          "snapshot_id" => snapshot["snapshot_id"],
          "checked_label" => decision["checked_label"],
          "assigned_label" => decision["assigned_label"]
        })

        then.(decision)

      {_refused_or_error, reason} ->
        go_not_committed(env, call, intent, snapshot, reason)
    end
  end

  # The nonce could not be consumed (e.g. a second terminal was faster):
  # no effect, and the PDR stays linked to the call.
  defp go_not_committed(env, call, intent, snapshot, reason) do
    error_out(
      env,
      call.tool,
      call.intent_hash,
      intent["operation"],
      "GO nicht committet: " <> inspect(reason),
      %{
        "call_id" => call.call_id,
        "intent_id" => intent["intent_id"],
        "snapshot_id" => snapshot["snapshot_id"]
      }
    )
  end

  # No or no answer: the deny stands and the catalog stays visible; the
  # PDR records that the person was asked.
  defp go_not_given(env, call, {snapshot, intent}, response, outcome) do
    hinweis = if outcome == "go_refused", do: :go_refused, else: :go_timeout
    response = Map.put(response, "hinweis", Hinweis.text(hinweis))

    PDR.append(env, %{
      "decision_id" => PDR.new_id(),
      "call_id" => call.call_id,
      "tool" => call.tool,
      "rule" => intent["operation"],
      "decision" => "deny",
      "outcome" => outcome,
      "admitted" => false,
      "intent_hash" => call.intent_hash,
      "payload_hash" => PDR.payload_hash(response),
      "intent_id" => intent["intent_id"],
      "snapshot_id" => snapshot["snapshot_id"]
    })

    Map.put(response, "go", if(outcome == "go_refused", do: "abgelehnt", else: "keine Antwort"))
  end

  # -------------------------------------------------------------------------
  # Execution
  # -------------------------------------------------------------------------

  # All decisions are in the journal by now; this adds the record before
  # effect and runs the connector. The record names the Gate 1b decision
  # (`gate1b`) that let the request leave the room, i.e. the recipient
  # check it relies on (R.11); λ(y) comes from the emit decision.
  defp execute(env, call, emit, gate1b) do
    %{decision: decision} = emit
    call_id = call.call_id

    context =
      if call.kind == :write, do: %{"assigned_label" => decision["assigned_label"]}, else: %{}

    # Record before effect (R.11): it is in the journal before the request
    # leaves the mediator. payload_hash binds the outgoing request
    # (operation, parameters, context). It is no decision — those are
    # journaled already — so `decision` stays null.
    PDR.append(env, %{
      "decision_id" => call_id,
      "call_id" => call_id,
      "tool" => call.tool,
      "rule" => "emit",
      "decision" => nil,
      "outcome" => "emitted",
      "admitted" => nil,
      "intent_hash" => call.intent_hash,
      "payload_hash" =>
        PDR.payload_hash(%{"op" => call.op, "params" => call.params, "context" => context}),
      "intent_id" => gate1b.intent["intent_id"],
      "snapshot_id" => gate1b.snapshot["snapshot_id"],
      "checked_label" => decision["checked_label"],
      "assigned_label" => decision["assigned_label"]
    })

    case connector_call(env, call, call_id, context) do
      {:ok, result} -> admit(env, call, call_id, decision, result)
      {:error, error} -> connector_failed(env, call, call_id, error)
    end
  end

  # Without a configured connector directory no connector is reachable;
  # the call fails as a connector error.
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

  # Search hits outside B_W are dropped silently BEFORE Gate 2 (labbook
  # L-109): otherwise "deny" versus "permit, 0 hits" would be an existence
  # oracle for confidential content. The answer then looks like a search
  # without those hits; their number reveals nothing. Single reads
  # (`read`) stay a decision with remedies.
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

  # Labels from the manifest (RIS, web) or from Γ (vault, #211): §6.2.2, §6.3.
  defp labels(_env, %{kind: :write}, emit_decision, result) do
    assigned = emit_decision["assigned_label"]

    if Enum.sort(result["labels"]) == assigned,
      do: {:ok, assigned},
      else: {:redact, "zurueckgemeldete Labels weichen von assigned_label ab", ["label_mismatch"]}
  end

  # Vault notes carry their own labels (front matter). Since Γ comes from
  # the label store (#208), any binding in Γ is accepted; a label outside
  # it withholds the answer (ticket #211).
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

  # A note carries at least one label, and all of them are bindings in Γ.
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
  # Outcomes (each with a PDR)
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

  # deny/indeterminate (remedies) or a decision error, in Gate 1 (no
  # execution, `executed` is nil) or Gate 2 (content withheld, `executed`
  # is the call_id, i.e. the decision_id of the record before effect). The
  # PDR always carries the call_id; the answer names a record before effect
  # only if there is one.
  defp not_permitted(env, call, rule, executed, intent, snapshot, outcome) do
    decision_id = PDR.new_id()

    checked_label =
      case outcome do
        {:ok, decision} -> decision["checked_label"]
        _ -> nil
      end

    {pdr_decision, response} =
      case outcome do
        {:ok, %{"decision" => kind, "remedies" => remedies}} ->
          {kind,
           %{
             "decision" => kind,
             "remedies" => remedies,
             "relaxation_authorities" => Gamma.relaxation_authorities_for(env.gamma, remedies),
             "hinweis" => Hinweis.text(:deny)
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
      |> put_emit_id(executed)

    PDR.append(env, %{
      "decision_id" => decision_id,
      "call_id" => call.call_id,
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
      "checked_label" => checked_label,
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

  # Pre-check failed (schema, missing B_W): no call yet, no engine
  # decision, no execution.
  defp refused(env, tool, intent_hash, detail),
    do: error_out(env, tool, intent_hash, "emit", detail, %{})

  # An error without an engine decision: error answer plus PDR. `link`
  # adds the call's identifiers once there is a call.
  defp error_out(env, tool, intent_hash, rule, detail, link) do
    decision_id = PDR.new_id()

    response = %{
      "decision" => "error",
      "rule" => rule,
      "decision_id" => decision_id,
      "detail" => detail
    }

    PDR.append(
      env,
      Map.merge(link, %{
        "decision_id" => decision_id,
        "tool" => tool,
        "rule" => rule,
        "decision" => "error",
        "outcome" => "error",
        "admitted" => false,
        "intent_hash" => intent_hash,
        "payload_hash" => PDR.payload_hash(response)
      })
    )

    response
  end

  # -------------------------------------------------------------------------
  # Building blocks
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
