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
    `decision_id` is the `call_id` sent in the frame, `authorized_by` holds
    the decision_ids of the emit and Gate 1b decisions it relies on, and
    its `payload_hash` binds the outgoing request). The admit PDR follows the
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

  Admit-only operations (`kind: :admit_only`, contract §6.4, ticket #419)
  skip Gate 1: their request has no parameters, and the observers of the
  operation's environment lie within those of the room's, so the request
  is no output. The mediator checks both on every call and then decides
  only `admit` of the manifest's fixed object against B_W before the
  connector runs (`KomkiMediator.Gate`, as for `admit_document`). There is
  no GO on this path.

  GO (ticket #98): if the catalog of a Gate 1 denial offers an action
  release for the exact call and `env.go` is set, the mediator asks the
  person, provided a session is listening (`KomkiMediator.Go`). The
  engine's release branch decides a presented release; on permit
  `KomkiMediator.GoStand` commits the nonce and a PDR (`outcome:
  released`) records the GO right away, both before any effect. That PDR
  is the decision of the release branch, so no `permitted` PDR follows
  for the same gate. No, no answer or an invalid release leave the deny in
  place. If storing fails the recipient test, the catalog offers no GO
  (ticket #417) and nobody is asked. The answer then carries only the
  `hinweis` that nothing was transmitted and `recipients_outside` from the
  engine's blocker; the journal keeps the full catalog.
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
        environment: Manifest.environment(manifest, op),
        params: checked,
        intent_hash: intent_hash(tool, checked),
        call_id: PDR.new_id()
      }

      if spec.kind == :admit_only, do: admit_only(env, call), else: emit(env, call)
    else
      {:error, detail} -> refused(env, spec, tool, intent_hash(tool, rendered), detail)
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
  # Admit only (connector contract §6.4, ticket #419)
  # -------------------------------------------------------------------------

  # The request is a constant and nobody outside the room sees it, so it is
  # no output (the exception to R.4.3, decided in #419). The mediator checks
  # that criterion on every call; then it decides only `admit` of the
  # operation's fixed object against B_W, before the connector reads
  # anything (KomkiMediator.Gate, as for admit_document). No GO: a denial
  # stays a denial.
  defp admit_only(env, call) do
    case admit_only_criterion(env, call) do
      :ok ->
        Gate.call(env, call.tool, call.params, fn -> read_object(env, call) end)

      {:error, detail} ->
        error_out(env, call.tool, call.intent_hash, "admit", detail, %{})
    end
  end

  defp admit_only_criterion(env, call) do
    spec = Map.fetch!(call.manifest.ops, call.op)
    environments = env.gamma.compiled.environments

    with :ok <- no_params(spec),
         {:ok, op_observers} <- observers(environments, call.environment),
         {:ok, room_observers} <- observers(environments, env.room.environment) do
      case op_observers -- room_observers do
        [] ->
          :ok

        outside ->
          {:error,
           "Nur-Aufnahme-Operation mit Beobachtern ausserhalb des Raums: " <>
             Enum.join(outside, ", ")}
      end
    end
  end

  defp no_params(%{params: params}) when map_size(params) == 0, do: :ok

  defp no_params(_spec),
    do: {:error, "Nur-Aufnahme-Operation mit Parametern: die Anfrage waere eine Ausgabe"}

  defp observers(environments, id) do
    case environments[id] do
      %{observers: observers} -> {:ok, observers}
      _ -> {:error, "Umgebung " <> inspect(id) <> " fehlt in Γ"}
    end
  end

  # The executor runs only after the admit permit. The answer claims the
  # fixed object (Gate 2 binding in KomkiMediator.Gate); its shape is
  # closed like every connector answer (§5.2).
  defp read_object(env, call) do
    object_id = Map.fetch!(call.manifest.ops, call.op).object

    with {:ok, result} <- connector_call(env, call, PDR.new_id(), %{}),
         :ok <- ResultShape.check(call.manifest.id, call.op, result) do
      {:ok, Map.put(result, "object_id", object_id)}
    else
      {:error, %{"code" => code}} -> {:error, code}
      {:error, detail} -> {:error, "Antwort verletzt die Ergebnisform: " <> detail}
    end
  end

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

    # `decided` is the decision_id of the emit permit or GO record.
    to_handover = fn decision, decided ->
      emit = %{decision: decision, snapshot: snapshot, intent: intent, decided: decided}
      handover(env, call, emit)
    end

    case Derive.decide(env.gamma.compiled, snapshot, intent) do
      {:ok, %{"decision" => "permit"} = decision} ->
        decided = decision_pdr(env, call, {snapshot, intent}, decision, "permitted", decision)
        to_handover.(decision, decided)

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
        environment: call.environment,
        object: object,
        facts: Map.put(env.room.facts, "output_content_digest", digest_fact(call))
      })

    intent = intent(env.room, rule, "intent-" <> rule <> "-" <> d12, object)
    # `decided` is the decision_id of the Gate 1b permit or GO record.
    to_execution = fn _decision, decided -> execute(env, call, emit, decided) end

    case Derive.decide(env.gamma.compiled, snapshot, intent) do
      {:ok, %{"decision" => "permit"} = decision} ->
        decided = decision_pdr(env, call, {snapshot, intent}, decision, "permitted", decision)
        to_execution.(decision, decided)

      other ->
        response = not_permitted(env, call, rule, nil, intent, snapshot, other)
        maybe_go(env, call, snapshot, intent, response, to_execution)
    end
  end

  # A permit, journaled when it is made: `permitted` from the normal branch
  # (payload: the decision) or `released` from the release branch (payload:
  # the consumption proposal). For emit it carries the assigned λ(y). An
  # Offenlegungsfreigabe (#423) haelt im zusaetzlichen Feld `offenlegung`
  # fest, gegenueber wem offengelegt wurde: Ausgabeart, Ziellabel und alle
  # Empfaenger des Ziels (Szene 13).
  defp decision_pdr(env, call, {snapshot, intent}, decision, outcome, payload, extra \\ %{}) do
    decision_id = PDR.new_id()

    PDR.append(
      env,
      Map.merge(
        %{
          "decision_id" => decision_id,
          "call_id" => call.call_id,
          "tool" => call.tool,
          "rule" => intent["operation"],
          "decision" => "permit",
          "outcome" => outcome,
          "intent_hash" => call.intent_hash,
          "payload_hash" => PDR.payload_hash(payload),
          "intent_id" => intent["intent_id"],
          "snapshot_id" => snapshot["snapshot_id"],
          "checked_label" => decision["checked_label"],
          "assigned_label" => decision["assigned_label"]
        },
        extra
      )
    )

    decision_id
  end

  # -------------------------------------------------------------------------
  # GO: action release for the exact call (ticket #98, store #205,
  # transfer #298)
  # -------------------------------------------------------------------------

  # `then` continues after a permit of the release branch with the decision
  # and the decision_id of the released record: after emit like a normal
  # emit permit, after transfer or store with the execution. The
  # Offenlegungsfreigabe (#423) is the second offer a store denial can
  # carry: the window asks for the disclosure decision, the person
  # deselects parts before the GO, and the release is bound to the
  # (possibly reduced) event.
  defp maybe_go(%{go: %{} = go} = env, call, snapshot, intent, response, then) do
    case {Go.offered(response["remedies"]), Go.listening?(go.dir)} do
      {call_hash, true} when is_binary(call_hash) ->
        ask_go(env, go, call, {snapshot, intent, then}, response, call_hash)

      _no_aktion_offer ->
        offenlegung_or_response(env, call, snapshot, intent, response, then)
    end
  end

  defp maybe_go(_env, _call, _snapshot, _intent, response, _then), do: response

  defp offenlegung_or_response(%{go: %{} = go} = env, call, snapshot, intent, response, then) do
    case {Go.offered_offenlegung(response["remedies"]), Go.listening?(go.dir)} do
      {offer, true} when is_map(offer) ->
        ask_go_offenlegung(env, go, call, {snapshot, intent, then}, response, offer)

      _no_offer_or_nobody_listening ->
        response
    end
  end

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

  # -------------------------------------------------------------------------
  # GO: Offenlegungsfreigabe fuer den Store in den Hub (§ 4.9, Szene 13,
  # #423). Die Anfrage zeigt den genauen Text (Parameter), alle Empfaenger
  # des Ziels und den Hinweis auf die Offenlegung; die Teile waehlt die
  # nutzende Person hier ab, nicht erst im Hub. Eine Abwahl ergibt ein
  # neues Ereignis mit neuem Hash (R.6.2): Der Vermittler leitet den
  # reduzierten Call neu ab und baut die Freigabe darueber.
  # -------------------------------------------------------------------------

  defp ask_go_offenlegung(env, go, call, {snapshot, intent, then}, response, offer) do
    request =
      %{
        "schema" => "komki-go-request/1",
        "kind" => "offenlegungsfreigabe",
        "call_hash" => offer.call_hash,
        "decision_id" => response["decision_id"],
        "operation" => intent["operation"],
        "tool" => call.tool,
        "params" => call.params,
        "blockers" => response["remedies"] |> Enum.map(& &1["code"]) |> Enum.uniq(),
        "object" => intent["object"],
        "workspace" => intent["workspace"],
        "content_digest" => String.replace_prefix(call.intent_hash, "sha256:", ""),
        "scope" => GoStand.current()["scope"],
        "authority" => Go.authority(),
        "ausgabeart" => offer.ausgabeart,
        "ziellabel" => offer.ziellabel,
        "empfaenger" => ziel_empfaenger(env, call),
        "teile" => teile_choices(call)
      }

    case Go.await(go, request) do
      {:selection, ids} ->
        offenlegung_answered(env, call, {snapshot, intent, then}, request, ids)

      :refused ->
        go_not_given(env, call, {snapshot, intent}, response, "go_refused")

      :timeout ->
        go_not_given(env, call, {snapshot, intent}, response, "go_timeout")
    end
  end

  # Alle Empfaenger des Ziels (Szene 13: das Fenster zeigt alle Empfaenger):
  # die Beobachter der Zielumgebung des Manifests, sortiert.
  defp ziel_empfaenger(env, call) do
    case env.gamma.compiled.environments[call.environment] do
      %{observers: observers} -> observers
      _ -> []
    end
  end

  # Die Teile der Anfrage mit Kennung und Nummer; der genaue Text jedes
  # Teils steht in `params` (die Vorschau rendert ihn vollständig).
  defp teile_choices(call) do
    call.params
    |> Map.get("teile", [])
    |> List.wrap()
    |> Enum.with_index(1)
    |> Enum.map(fn {_teil, nummer} ->
      %{"id" => "teil-" <> Integer.to_string(nummer), "nummer" => nummer}
    end)
  end

  # Die Auswahl: Alle Teile bleiben — die Freigabe bindet den originalen
  # Call. Eine Abwahl leitet den reduzierten Call neu ab (emit und store
  # werden erneut entschieden und journalt), dann bindet die Freigabe
  # genau dieses neue Ereignis.
  defp offenlegung_answered(env, call, {snapshot, intent, then}, request, ids) do
    alle = Enum.map(request["teile"], & &1["id"])

    if Enum.sort(ids) == Enum.sort(alle) do
      offenlegung_commit(env, call, {snapshot, intent, then}, request)
    else
      offenlegung_reduced(env, call, request, ids)
    end
  end

  # Eine Abwahl ergibt ein neues Ereignis mit neuem Hash (R.6.2): Der
  # reduzierte Call durchlaeuft emit und store erneut — beide
  # Entscheidungen journalt der Vermittler wie jeden anderen Call — und
  # die Freigabe bindet genau dieses neue Ereignis. Fraglich wird hier
  # niemand mehr: Die nutzende Person hat im selben Fenster gewaehlt und
  # das GO gegeben.
  defp offenlegung_reduced(env, call, request, ids) do
    reduced_params = reduce_teile(call.params, request["teile"], ids)

    reduced_call = %{
      call
      | params: reduced_params,
        intent_hash: intent_hash(call.tool, reduced_params)
    }

    d12 = Hash.digest12(reduced_call.intent_hash)
    emit_object = %Object{object_id: "out-" <> d12, version: "v1", labels: []}

    emit_snapshot =
      Room.connector_snapshot(env.room, env.gamma, %{
        snapshot_id: "snap-emit-" <> d12,
        environment: env.room.environment,
        object: emit_object,
        facts: Map.put(env.room.facts, "output_content_digest", digest_fact(reduced_call))
      })

    emit_intent = intent(env.room, "emit", "intent-emit-" <> d12, emit_object)

    case Derive.decide(env.gamma.compiled, emit_snapshot, emit_intent) do
      {:ok, %{"decision" => "permit"} = emit_decision} ->
        emit_decided =
          decision_pdr(
            env,
            reduced_call,
            {emit_snapshot, emit_intent},
            emit_decision,
            "permitted",
            emit_decision
          )

        emit = %{
          decision: emit_decision,
          snapshot: emit_snapshot,
          intent: emit_intent,
          decided: emit_decided
        }

        store_reduced(env, reduced_call, emit, request)

      other ->
        not_permitted(env, reduced_call, "emit", nil, emit_intent, emit_snapshot, other)
    end
  end

  defp store_reduced(env, reduced_call, emit, request) do
    d12 = Hash.digest12(reduced_call.intent_hash)

    object = %Object{
      object_id: "out-" <> d12,
      version: "v1",
      labels: emit.decision["assigned_label"]
    }

    store_snapshot =
      Room.connector_snapshot(env.room, env.gamma, %{
        snapshot_id: "snap-store-" <> d12,
        environment: reduced_call.environment,
        object: object,
        facts: Map.put(env.room.facts, "output_content_digest", digest_fact(reduced_call))
      })

    store_intent = intent(env.room, "store", "intent-store-" <> d12, object)

    case Derive.decide(env.gamma.compiled, store_snapshot, store_intent) do
      {:ok, %{"decision" => "permit"} = store_decision} ->
        # Unerwarteter Fall: Der reduzierte Call bestünde den
        # Empfaengertest von selbst — dann brauchte es keine Offenlegung.
        # Fail-closed: weiter wie ein normales permit (journalt), ohne GO.
        decided =
          decision_pdr(
            env,
            reduced_call,
            {store_snapshot, store_intent},
            store_decision,
            "permitted",
            store_decision
          )

        execute(env, reduced_call, emit, decided)

      other ->
        reduced_store_denied(
          env,
          reduced_call,
          emit,
          {store_snapshot, store_intent},
          request,
          other
        )
    end
  end

  # Der reduzierte Call scheitert erwartbar am Empfaengertest: Die Auswahl
  # aus dem Fenster gilt — die Freigabe wird ueber den neuen Hash gebaut
  # und der Freigabe-Zweig entscheidet. Ohne Angebot bleibt die Ablehnung.
  defp reduced_store_denied(
         env,
         reduced_call,
         emit,
         {store_snapshot, store_intent},
         request,
         other
       ) do
    response = not_permitted(env, reduced_call, "store", nil, store_intent, store_snapshot, other)

    case Go.offered_offenlegung(response["remedies"]) do
      %{call_hash: call_hash} = offer ->
        reduced_store_release(
          env,
          reduced_call,
          emit,
          {store_snapshot, store_intent},
          request,
          offer,
          call_hash
        )

      _no_offer ->
        response
    end
  end

  defp reduced_store_release(
         env,
         reduced_call,
         emit,
         {store_snapshot, store_intent},
         request,
         offer,
         call_hash
       ) do
    release =
      Go.offenlegung_release_for(
        Map.merge(request, %{
          "call_hash" => call_hash,
          "ausgabeart" => offer.ausgabeart,
          "ziellabel" => offer.ziellabel
        }),
        %{
          call_hash: call_hash,
          content_digest: String.replace_prefix(reduced_call.intent_hash, "sha256:", "")
        },
        System.os_time(:second)
      )

    case Derive.decide_with_release(
           env.gamma.compiled,
           store_snapshot,
           store_intent,
           release,
           GoStand.current()
         ) do
      {:ok, %{"decision" => "permit", "release" => proposal} = decision} ->
        offenlegung_reduced_commit(
          env,
          reduced_call,
          emit,
          {store_snapshot, store_intent},
          decision,
          proposal,
          request
        )

      other_release ->
        not_permitted(
          env,
          reduced_call,
          "store",
          nil,
          store_intent,
          store_snapshot,
          other_release
        )
    end
  end

  defp offenlegung_reduced_commit(
         env,
         reduced_call,
         emit,
         {store_snapshot, store_intent},
         decision,
         proposal,
         request
       ) do
    case GoStand.advance(proposal) do
      {:ok, _stand} ->
        offenlegung = %{
          "offenlegung" => %{
            "ausgabeart" => request["ausgabeart"],
            "ziellabel" => request["ziellabel"],
            "empfaenger" => request["empfaenger"]
          }
        }

        decided =
          decision_pdr(
            env,
            reduced_call,
            {store_snapshot, store_intent},
            decision,
            "released",
            proposal,
            offenlegung
          )

        execute(env, reduced_call, emit, decided)

      {_refused_or_error, reason} ->
        go_not_committed(env, reduced_call, store_intent, store_snapshot, reason)
    end
  end

  # Die ausgewaehlten Teile behalten ihre Reihenfolge aus der Anfrage; alle
  # uebrigen Parameter bleiben unberuehrt.
  defp reduce_teile(params, choices, ids) do
    selected = choices |> Enum.filter(&(&1["id"] in ids)) |> Enum.map(& &1["nummer"])
    teile = params |> Map.get("teile", []) |> List.wrap()
    gewaehlte = for {teil, nummer} <- Enum.with_index(teile, 1), nummer in selected, do: teil
    Map.put(params, "teile", gewaehlte)
  end

  defp offenlegung_commit(env, call, {snapshot, intent, then}, request) do
    release =
      Go.offenlegung_release_for(
        request,
        %{call_hash: request["call_hash"], content_digest: request["content_digest"]},
        System.os_time(:second)
      )

    case Derive.decide_with_release(
           env.gamma.compiled,
           snapshot,
           intent,
           release,
           GoStand.current()
         ) do
      {:ok, %{"decision" => "permit", "release" => proposal} = decision} ->
        commit_offenlegung(env, call, {snapshot, intent, then}, decision, proposal, request)

      other ->
        not_permitted(env, call, intent["operation"], nil, intent, snapshot, other)
    end
  end

  # Commit vor Wirkung wie bei der Aktionsfreigabe (§ 4.6, B.8): erst den
  # Nonce committen, dann den PDR — er haelt die Offenlegung gegenueber
  # dem Vorstand fest (Szene 13: Ausgabeart, Ziellabel und alle Empfaenger)
  # —, dann erst die Ausfuehrung.
  defp commit_offenlegung(env, call, {snapshot, intent, then}, decision, proposal, request) do
    case GoStand.advance(proposal) do
      {:ok, _stand} ->
        offenlegung = %{
          "offenlegung" => %{
            "ausgabeart" => request["ausgabeart"],
            "ziellabel" => request["ziellabel"],
            "empfaenger" => request["empfaenger"]
          }
        }

        decided =
          decision_pdr(env, call, {snapshot, intent}, decision, "released", proposal, offenlegung)

        then.(decision, decided)

      {_refused_or_error, reason} ->
        go_not_committed(env, call, intent, snapshot, reason)
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
        decided = decision_pdr(env, call, {snapshot, intent}, decision, "released", proposal)
        then.(decision, decided)

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
  # effect and runs the connector. `authorized_by` names the two decision
  # records it relies on (R.11): the emit decision and the Gate 1b decision
  # with its recipient check, each `permitted` or `released`.
  defp execute(env, call, emit, gate1b_decided) do
    %{decision: decision, snapshot: snapshot, intent: intent} = emit
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
      "intent_id" => intent["intent_id"],
      "snapshot_id" => snapshot["snapshot_id"],
      "checked_label" => decision["checked_label"],
      "assigned_label" => decision["assigned_label"],
      "authorized_by" => [emit.decided, gate1b_decided]
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

    {checked_label, remedies} =
      case outcome do
        {:ok, decision} -> {decision["checked_label"], decision["remedies"]}
        _ -> {nil, nil}
      end

    {pdr_decision, response} =
      case outcome do
        {:ok, %{"decision" => kind}} ->
          {kind, denial(env, rule, kind, remedies)}

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
      # The journal keeps the engine's full catalog, also where the answer
      # leaves it out.
      "remedies" => remedies
    })

    response
  end

  # A store whose target lies outside the recipient circle has no GO way
  # (#417): the model gets only the note and who lies outside, which the
  # pi display needs for its sentence; no catalog and no relaxation
  # authorities (Gegenprobe 13.5). Every other denial keeps its form.
  defp denial(env, rule, kind, remedies) do
    if Hinweis.not_transmitted?(rule, remedies) do
      %{
        "decision" => kind,
        "hinweis" => Hinweis.text(:not_transmitted),
        "recipients_outside" =>
          Enum.find_value(
            remedies,
            &(&1["code"] == "recipient_not_allowed" && &1["recipients_outside"])
          )
      }
    else
      %{
        "decision" => kind,
        "remedies" => remedies,
        "relaxation_authorities" => Gamma.relaxation_authorities_for(env.gamma, remedies),
        "hinweis" => Hinweis.text(:deny)
      }
    end
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
  # decision, no execution. The rule is the branch the call would have
  # taken: `admit` for admit-only operations (§6.4), else `emit`.
  defp refused(env, spec, tool, intent_hash, detail) do
    rule = if spec.kind == :admit_only, do: "admit", else: "emit"
    error_out(env, tool, intent_hash, rule, detail, %{})
  end

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
