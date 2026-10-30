defmodule KomkiPolicy.Derive do
  @moduledoc """
  Regelkern `derive` — Regelzweige `admit` (§ 4), `emit` (§ 4.5),
  `store` (§ 4.7) und `transfer` (§ 4.8), Freigabe-Zweig
  `decide_with_release/5` (§ 4.6), Remedy-Katalog via
  `KomkiPolicy.Remedies` (§ 2.8) (CONTRACT.md Lieferung 2 bis 4).

  `decide/3` validiert Snapshot und Intent als geschlossene Schemas,
  prüft die Referenzkohärenz und leitet in fester Prämissenordnung.
  Nicht implementierte Regelzweige ergeben `{:unsupported, info}` —
  niemals ein `deny` (die fehlende Prüfung ist keine verbietende
  Prüfung). Struktur- und Validierungsfehler sind Eingabefehler, keine
  Decisions.

  `emit` ordnet λ(y) := B_W zu (Vermittler-Zuordnung, R.5.5): keine
  Eingabe kann `assigned_label` beeinflussen — der Intent trägt keine
  Labels und der Kern liest `object.labels` für `emit` nicht. Fehlt der
  technische Fakt `output_content_digest`, ist der Call nicht
  identifizierbar: Eingabefehler `emit_digest_missing` (Exit 2).

  `store` (RFC 0003 R.5.6) legt ein erzeugtes Objekt y in einen
  dauerhaften Speicher (die Umgebung des Snapshots). Entschieden wird
  unter λ(y) = `object.labels`, nicht unter B_W: Prüflabel, Empfängerkreis
  und `store`-Regeln stammen aus den Bindungen des Objekts. B_W ⊆ λ(y)
  ist eine eigene Prämisse (`label_preservation`), denn ein Speichern
  entfernt keine Bindung. Digest- und Klassifikationspflicht wie `emit`.

  `transfer` (RFC 0003 R.5.6) übergibt ein erzeugtes Objekt y an ein
  Ziel (die Umgebung des Snapshots, etwa einen externen Dienst). Form
  wie `store`: Prüflabel λ(y), `label_preservation`, Empfängerkreis des
  Ziels, `transfer`-Regeln der Bindungen von λ(y).

  Urteil und Vollzug getrennt (B.8): der Kern verbraucht keine
  Freigabe — `decide_with_release/5` plant den Verbrauch als
  deklaratives `release`-Objekt, der atomare Übergang liegt in
  `KomkiPolicy.Stand.advance/2`.
  """

  alias KomkiPolicy.Calculus
  alias KomkiPolicy.{Context, Evaluator, Registry, Release, Remedies, Stand}

  @admit_premises [
    "not_quarantine",
    "workspace_contract_valid",
    "has_operation_right",
    "has_object_access_right",
    "audit_path_ready",
    "environment_observers_complete",
    "label_inclusion",
    "recipient_inclusion",
    "binding_condition"
  ]

  @emit_premises [
    "workspace_contract_valid",
    "has_operation_right",
    "audit_path_ready",
    "environment_observers_complete",
    "recipient_inclusion",
    "label_assignment",
    "binding_condition"
  ]

  # store (§ 4.7) und transfer (§ 4.8): ein erzeugtes Objekt verlässt den
  # Raum unter λ(y).
  @handover_premises [
    "workspace_contract_valid",
    "has_operation_right",
    "audit_path_ready",
    "environment_observers_complete",
    "label_preservation",
    "recipient_inclusion",
    "binding_condition"
  ]

  @handover_operations ["transfer", "store"]

  # Regelzweige mit Ausgabeobjekt: Digest-Pflicht, call-GO im Katalog,
  # Freigabe-Zweig.
  @output_operations ["emit" | @handover_operations]

  @unsupported_operations ["start"]
  @unsupported_detail "rule branch not implemented"

  @doc "§ 4.3-Prämissennamen in fester Reihenfolge (gemeinsame Sollmenge für derive-Baum und verify)."
  @spec required_premises() :: [String.t()]
  def required_premises, do: @admit_premises

  @doc "Regelabhängige Sollmengen (§ 4.3 `admit`, § 4.5 `emit`, § 4.7 `store`, § 4.8 `transfer`)."
  @spec required_premises(String.t()) :: [String.t()]
  def required_premises("admit"), do: @admit_premises
  def required_premises("emit"), do: @emit_premises
  def required_premises(rule) when rule in @handover_operations, do: @handover_premises

  @doc """
  Prüflabel einer Entscheidung: B_W für `admit` und `emit`, λ(y) (die
  Objekt-Labels, sortiert) für `store` und `transfer` (§ 4.7, § 4.8).
  Gemeinsam für derive und verify.
  """
  @spec checked_label(String.t(), map(), map()) :: [String.t()]
  def checked_label(rule, _workspace, object) when rule in @handover_operations,
    do: Enum.sort(Enum.uniq(object["labels"]))

  def checked_label(_rule, workspace, _object), do: workspace["bindings"]

  @type decision() :: %{required(String.t()) => term()}
  @type error() :: %{
          required(:code) => atom(),
          required(:path) => String.t(),
          required(:detail) => String.t()
        }

  # =========================================================================
  # Öffentliche API
  # =========================================================================

  @doc """
  Leitet für den Regelzweig `admit`, `emit`, `store` oder `transfer` und meldet `unsupported`
  bzw. einen strukturierten Eingabefehler.
  """
  @spec decide(Registry.compiled(), term(), term()) ::
          {:ok, decision()}
          | {:unsupported, %{required(String.t()) => String.t()}}
          | {:error, error()}
  def decide(registry, snapshot, intent) do
    decide_dispatched?(registry, snapshot, intent, &run_normal/2)
  end

  @doc """
  Ausgabeshape für nicht unterstützte Regelzweige (alle außer `admit`,
  `emit`, `store`, `transfer` und dem Freigabe-Zweig).
  """
  def unsupported_info(operation) do
    %{"result" => "unsupported", "rule" => operation, "detail" => @unsupported_detail}
  end

  @doc """
  Aktionsfreigabe-Zweig (§ 4.6, B.5 Schritt 6): eigener Regelzweig mit
  vorgelegter Aktionsfreigabe und Offenlegungsstand — nie ein stiller
  Fallback der normalen Entscheidung. Nur `kind: aktionsfreigabe` mit
  Operation `emit`, `store` oder `transfer` ist entscheidbar; `offenlegungsfreigabe`
  und andere Operationen ergeben `unsupported` (Exit 3).
  """
  @spec decide_with_release(Registry.compiled(), term(), term(), term(), term()) ::
          {:ok, decision()}
          | {:unsupported, %{required(String.t()) => String.t()}}
          | {:error, error()}
  def decide_with_release(registry, snapshot, intent, release_term, stand_term) do
    with_release_validated?(registry, snapshot, intent, release_term, stand_term)
  end

  # =========================================================================
  # Gemeinsame Validierung front-matter
  # =========================================================================

  defp decide_dispatched?(registry, snapshot, intent, continuation) do
    case decide_validated?(registry, snapshot, intent, continuation) do
      {:ok, result} -> {:ok, result}
      {:unsupported, info} -> {:unsupported, info}
      {:error, %{} = error} -> {:error, error}
      {:error, reason} -> wrap_reason(reason)
    end
  end

  defp with_release_validated?(registry, snapshot, intent, release_term, stand_term) do
    case release_validated?(registry, snapshot, intent, release_term, stand_term) do
      {:ok, result} -> {:ok, result}
      {:unsupported, info} -> {:unsupported, info}
      {:error, %{} = error} -> {:error, error}
      {:error, reason} -> wrap_reason(reason)
    end
  end

  defp wrap_reason({code, path, detail}), do: {:error, %{code: code, path: path, detail: detail}}

  defp fail(code, path, detail), do: {:error, {code, path, detail}}

  defp decide_validated?(registry, snapshot, intent, continuation) do
    with {:ok, auth} <- Context.validate_intent(intent),
         :ok <- ensure_supported(auth.operation),
         {:ok, ctx} <- Context.validate_snapshot(snapshot, registry),
         :ok <- Context.ensure_coherence(ctx, auth) do
      continuation.(ctx, {registry, auth})
    end
  end

  defp run_normal(ctx, {registry, auth}) do
    case auth.operation do
      "admit" -> run_admit(ctx, registry, auth)
      "emit" -> run_emit(ctx, registry, auth)
      handover -> run_handover(ctx, registry, auth, handover)
    end
  end

  defp ensure_supported(operation) when operation in ["admit" | @output_operations], do: :ok

  defp ensure_supported(operation) when operation in @unsupported_operations do
    {:unsupported, unsupported_info(operation)}
  end

  defp ensure_supported(other),
    do: fail(:invalid_operation, "$.operation", "unknown operation: " <> Kernel.inspect(other))

  # =========================================================================
  # Freigabe-Zweig (§ 4.6)
  # =========================================================================

  defp release_validated?(registry, snapshot, intent, release_term, stand_term) do
    with {:ok, auth} <- Context.validate_intent(intent),
         {:ok, ctx} <- Context.validate_snapshot(snapshot, registry),
         :ok <- Context.ensure_coherence(ctx, auth),
         {:ok, release} <- Release.validate(release_term),
         {:ok, stand} <- Stand.validate(stand_term),
         :ok <- require_supportable(auth, release) do
      # § 4.6-Reihenfolge: erst die Freigabe-Entscheidung (kind/operation),
      # dann die Digest-Pflicht (emit, store, transfer) — ein nicht-unterstützter Zweig ist
      # unsupported (Exit 3), auch wenn der Snapshot bereits den Digest
      # vermissen lassen würde.
      case require_emit_input(ctx) do
        :ok -> run_release_branch(ctx, registry, auth, release, stand)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # § 4.6: nur `aktionsfreigabe` ist entscheidbar; `offenlegungsfreigabe`
  # und Operationen ohne Ausgabeobjekt ergeben `unsupported` (Exit 3) — kein deny.
  defp require_supportable(auth, release) do
    cond do
      auth.operation not in @output_operations ->
        {:unsupported, unsupported_info(auth.operation)}

      release.kind != "aktionsfreigabe" ->
        {:unsupported, unsupported_info(release.kind)}

      true ->
        :ok
    end
  end

  defp run_release_branch(ctx, registry, auth, release, stand) do
    call_hash = output_call_hash(ctx, auth.operation)

    state =
      ctx
      |> shared_premises(registry, auth.operation)
      |> premise_workspace_valid()
      |> release_check_call_hash(release, call_hash)
      |> release_check_window(release, stand)
      |> release_check_nonce(release, stand)
      |> release_check_scope(release, stand)
      |> release_check_authority(registry, release)

    conclude_release(state, ctx, registry, auth, release, stand, call_hash)
  end

  # Release-Prüfungen in fester Ordnung (§ 4.6 Schritt 3); jede Verletzung
  # ein Blocker (binding: null, condition: null, § 2.4).
  defp release_check_call_hash(state, release, correct) do
    if release.call_hash == correct do
      state
    else
      add_blocker(state, binder("release_call_mismatch", nil, nil))
    end
  end

  defp release_check_window(state, release, stand) do
    cond do
      stand.as_of < release.valid_from ->
        add_blocker(state, binder("release_not_yet_valid", nil, nil))

      stand.as_of > release.valid_until ->
        add_blocker(state, binder("release_expired", nil, nil))

      true ->
        state
    end
  end

  defp release_check_nonce(state, release, stand) do
    if Map.has_key?(stand.consumed, release.nonce) do
      add_blocker(state, binder("release_nonce_consumed", nil, nil))
    else
      state
    end
  end

  defp release_check_scope(state, release, stand) do
    if release.scope == stand.scope do
      state
    else
      add_blocker(state, binder("release_scope_mismatch", nil, nil))
    end
  end

  defp release_check_authority(state, registry, release) do
    if release.authority in registry.observers do
      state
    else
      add_blocker(state, binder("release_authority_unknown", nil, nil))
    end
  end

  defp conclude_release(state, ctx, registry, auth, release, stand, call_hash) do
    if state.blockers == [] do
      {:ok,
       release_decision(ctx, auth, state.checked, state.checked, %{
         "decision" => "permit",
         "blockers" => nil,
         "missing_evidence" => nil,
         "proof" => nil,
         "remedies" => nil,
         "content_digest" => digest_value(ctx),
         "release" => %{
           "release_id" => release.release_id,
           "nonce" => release.nonce,
           "stand_ref" => stand.stand_id <> "@" <> Integer.to_string(stand.version),
           "stand_version_after" => stand.version + 1,
           "call_hash" => call_hash
         }
       })}
    else
      remedy_ctx = release_remedies_context(state, registry, call_hash)
      findings = Remedies.catalog(registry, remedy_ctx, state.blockers)

      {:ok,
       release_decision(ctx, auth, state.checked, nil, %{
         "decision" => "deny",
         "blockers" => state.blockers,
         "missing_evidence" => nil,
         "proof" => nil,
         "remedies" => findings,
         "content_digest" => digest_value(ctx),
         "release" => nil
       })}
    end
  end

  # Nur `emit` ordnet ein Label zu; `store` und `transfer` erhalten λ(y)
  # und tragen kein `assigned_label`.
  defp release_label_fields("emit", label), do: %{"assigned_label" => label}
  defp release_label_fields(_handover, _label), do: %{}

  defp release_decision(ctx, auth, checked, label, fields) do
    ctx
    |> base_decision(auth, checked)
    |> Map.merge(fields)
    |> Map.merge(release_label_fields(auth.operation, label))
  end

  defp release_remedies_context(ctx, _registry, call_hash) do
    %{
      rule: :release,
      object_labels: [],
      checked: ctx.workspace["bindings"],
      rho: ctx.rho,
      object_ref: ctx.object["object_id"] <> "@" <> ctx.object["version"],
      call_hash: call_hash
    }
  end

  # =========================================================================
  # Eingabepflichten für emit, store und transfer (§ 4.5, § 4.7, § 4.8): Digest-Pflicht,
  # Klassifikationszustand
  # =========================================================================

  defp require_emit_input(ctx) do
    with :ok <- require_emit_digest(ctx) do
      require_emit_classification(ctx)
    end
  end

  defp require_emit_digest(ctx) do
    if Map.has_key?(ctx.facts, "output_content_digest") do
      :ok
    else
      fail(
        :emit_digest_missing,
        "$.facts.output_content_digest",
        "emit requires the technical fact output_content_digest (§ 4.5)"
      )
    end
  end

  defp require_emit_classification(ctx) do
    if ctx.object["classification"] == "classified" do
      :ok
    else
      fail(
        :emit_object_not_classified,
        "$.object.classification",
        "emit requires classification \"classified\"; quarantine is an input state, not an output state"
      )
    end
  end

  # =========================================================================
  # admit-Kern (§ 4): Prämissen in fester Ordnung
  # =========================================================================

  defp run_admit(ctx, registry, auth) do
    state =
      ctx
      |> shared_premises(registry, "admit")
      |> premise_quarantine()
      |> premise_workspace_valid()
      |> premise_basis_fact("has_operation_right")
      |> premise_basis_fact("has_object_access_right")
      |> premise_basis_fact("audit_path_ready")
      |> premise_env_flag()
      |> premise_label_inclusion()
      |> premise_recipient_inclusion()
      |> premise_binding_conditions(registry, "admit")

    conclude(state, ctx, registry, auth, "admit")
  end

  # =========================================================================
  # emit-Kern (§ 4.5): Prämissen in fester Ordnung
  # =========================================================================

  defp run_emit(ctx, registry, auth) do
    with :ok <- require_emit_input(ctx) do
      state =
        ctx
        |> shared_premises(registry, "emit")
        |> premise_workspace_valid()
        |> premise_basis_fact("has_operation_right")
        |> premise_basis_fact("audit_path_ready")
        |> premise_env_flag()
        |> premise_recipient_inclusion()
        |> premise_binding_conditions(registry, "emit")

      conclude(state, ctx, registry, auth, "emit")
    end
  end

  # =========================================================================
  # store- und transfer-Kern (§ 4.7, § 4.8): Prämissen in fester Ordnung,
  # entschieden unter λ(y)
  # =========================================================================

  defp run_handover(ctx, registry, auth, rule) do
    with :ok <- require_emit_input(ctx) do
      state =
        ctx
        |> shared_premises(registry, rule)
        |> premise_workspace_valid()
        |> premise_basis_fact("has_operation_right")
        |> premise_basis_fact("audit_path_ready")
        |> premise_env_flag()
        |> premise_label_preservation()
        |> premise_recipient_inclusion()
        |> premise_binding_conditions(registry, rule)

      conclude(state, ctx, registry, auth, rule)
    end
  end

  defp shared_premises(ctx, registry, rule) do
    workspace = ctx.workspace
    checked = checked_label(rule, workspace, ctx.object)

    Map.merge(ctx, %{
      checked: checked,
      rho: Calculus.actual_recipients(registry, workspace["environment"]),
      allowed: Calculus.allowed_recipients(registry, checked),
      blockers: [],
      evidence: []
    })
  end

  defp binder(code, binding, condition),
    do: %{"code" => code, "binding" => binding, "condition" => condition}

  defp evidence(code, fact, binding), do: %{"code" => code, "fact" => fact, "binding" => binding}

  defp add_blocker(state, blocker), do: Map.update!(state, :blockers, &(&1 ++ [blocker]))
  defp add_evidence(state, ev), do: Map.update!(state, :evidence, &(&1 ++ [ev]))

  defp fact_state(facts, name) do
    case Map.get(facts, name) do
      %{"value" => value} -> if value, do: true, else: false
      _ -> :unknown
    end
  end

  defp premise_quarantine(ctx) do
    if ctx.object["classification"] == "quarantine" do
      add_blocker(ctx, binder("object_quarantine", nil, nil))
    else
      ctx
    end
  end

  defp premise_workspace_valid(ctx) do
    if ctx.workspace["valid"] != true do
      add_blocker(ctx, binder("workspace_invalid", nil, nil))
    else
      ctx
    end
  end

  defp premise_basis_fact(ctx, "audit_path_ready") do
    case fact_state(ctx.facts, "audit_path_ready") do
      true -> ctx
      false -> add_blocker(ctx, binder("audit_path_not_ready", nil, "audit_path_ready"))
      :unknown -> add_evidence(ctx, evidence("missing_fact", "audit_path_ready", nil))
    end
  end

  defp premise_basis_fact(ctx, name) do
    case fact_state(ctx.facts, name) do
      true -> ctx
      false -> add_blocker(ctx, binder("basis_right_false", nil, name))
      :unknown -> add_evidence(ctx, evidence("missing_fact", name, nil))
    end
  end

  # P4 (admit P6): false/fehlt ist KEIN verbietender Befund, sondern
  # fehlende Belege (§ 4.3, § 4.5 — Empfänger-Beweisbarkeit).
  defp premise_env_flag(ctx) do
    if fact_state(ctx.facts, "environment_observers_complete") == true do
      ctx
    else
      add_evidence(ctx, evidence("recipients_unproven", "environment_observers_complete", nil))
    end
  end

  defp premise_label_inclusion(ctx) do
    if Calculus.labels_subset?(ctx.object["labels"], ctx.checked) do
      ctx
    else
      add_blocker(ctx, binder("label_not_included", nil, nil))
    end
  end

  # store/transfer P5: B_W ⊆ λ(y) — Speichern und Übergeben entfernen keine
  # Bindung (R.5.6).
  defp premise_label_preservation(ctx) do
    if Calculus.labels_subset?(ctx.workspace["bindings"], ctx.checked) do
      ctx
    else
      add_blocker(ctx, binder("label_not_preserved", nil, nil))
    end
  end

  # P8: ρ_Γ(c) ⊆ R_Γ(B_W); bei B_W = ∅ ist R_Γ(∅) = 𝒪. Ist der Mengentest
  # bekannt falsch, vereitelt dies - unabhaengig vom env-Flag - den Zugriff.
  defp premise_recipient_inclusion(ctx) do
    rho = MapSet.new(ctx.rho)
    allowed = MapSet.new(ctx.allowed)

    if MapSet.subset?(rho, allowed) do
      ctx
    else
      add_blocker(ctx, binder("recipient_not_allowed", nil, nil))
    end
  end

  defp premise_binding_conditions(ctx, registry, rule_name) do
    Enum.reduce(ctx.checked, ctx, fn binding_id, acc ->
      binding = Map.get(registry.bindings, binding_id)
      expr = binding && Map.get(binding.operations, rule_name)

      case expr do
        nil -> add_blocker(acc, binder("missing_operation_rule", binding_id, nil))
        expr -> condition_value(acc, binding_id, expr)
      end
    end)
  end

  defp condition_value(acc, binding_id, expr) do
    case Evaluator.evaluate(expr, acc.facts) do
      true ->
        acc

      false ->
        cond_field = locate_field(expr, acc.facts, false)
        add_blocker(acc, binder("binding_condition_false", binding_id, cond_field))

      :unknown ->
        missing_field = locate_field(expr, acc.facts, :unknown)
        add_evidence(acc, evidence("missing_fact", missing_field, binding_id))
    end
  end

  # --------------------------------------------------------------------
  # Locate: erstes Feld mit bekannt falschem/unknowbarem Ergebnis
  # --------------------------------------------------------------------

  defp locate_field(expr, _facts, _kind) when is_boolean(expr), do: nil

  defp locate_field(%{} = expr, facts, kind) do
    case Map.keys(expr) do
      [key] when key in ["all", "any"] ->
        find_locate(Map.fetch!(expr, key), facts, kind)

      [key] when key in ["eq", "member", "subset", "at_most"] ->
        [field | _] = Map.fetch!(expr, key)
        field

      _ ->
        nil
    end
  end

  defp find_locate(clauses, facts, kind)
  defp find_locate([], _facts, _kind), do: nil

  defp find_locate([clause | rest], facts, kind) do
    if Evaluator.evaluate(clause, facts) == kind do
      locate_field(clause, facts, kind) || find_locate(rest, facts, kind)
    else
      find_locate(rest, facts, kind)
    end
  end

  # =========================================================================
  # Remedy-Kontext (§ 2.8): reine Funktion der Entscheidungslage
  # =========================================================================

  defp remedies_context(ctx, rule_kind) do
    object_labels = if rule_kind == "admit", do: ctx.object["labels"], else: []

    %{
      rule: string_to_kind(rule_kind),
      object_labels: object_labels,
      checked: ctx.checked,
      rho: ctx.rho,
      object_ref: ctx.object["object_id"] <> "@" <> ctx.object["version"],
      call_hash:
        if(rule_kind in @output_operations, do: output_call_hash(ctx, rule_kind), else: nil)
    }
  end

  # Die Operation geht in den Hash ein: ein GO für `emit` passt nie auf
  # `store` oder `transfer` desselben Objekts und umgekehrt.
  defp output_call_hash(ctx, operation) do
    Release.call_hash(
      digest_value(ctx),
      ctx.object["object_id"] <> "@" <> ctx.object["version"],
      operation,
      ctx.workspace["workspace_id"]
    )
  end

  defp digest_value(ctx) do
    case Map.get(ctx.facts, "output_content_digest") do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  # =========================================================================
  # Entscheidung (§ 4.4): bekannt-falsch > unknown > permit
  # =========================================================================

  defp conclude(state, ctx, registry, auth, rule_kind) do
    cond do
      state.blockers != [] ->
        payload =
          Remedies.catalog(registry, remedies_context(state, rule_kind), state.blockers)

        decision =
          Map.merge(base_decision(ctx, auth, state.checked), %{
            "decision" => "deny",
            "blockers" => state.blockers,
            "missing_evidence" => nil,
            "proof" => nil,
            "remedies" => payload
          })

        {:ok, Map.merge(decision, emit_rule_fields(rule_kind, state, :deny))}

      state.evidence != [] ->
        payload =
          Remedies.catalog(registry, remedies_context(state, rule_kind), state.evidence)

        decision =
          Map.merge(base_decision(ctx, auth, state.checked), %{
            "decision" => "indeterminate",
            "blockers" => nil,
            "missing_evidence" => state.evidence,
            "proof" => nil,
            "remedies" => payload
          })

        {:ok, Map.merge(decision, emit_rule_fields(rule_kind, state, :not_permit))}

      true ->
        proof = build_proof(state, registry, auth, rule_kind)

        decision =
          Map.merge(base_decision(ctx, auth, state.checked), %{
            "decision" => "permit",
            "blockers" => nil,
            "missing_evidence" => nil,
            "proof" => proof,
            "remedies" => nil
          })

        {:ok, Map.merge(decision, emit_rule_fields(rule_kind, state, :permit))}
    end
  end

  defp string_to_kind("admit"), do: :admit
  defp string_to_kind("emit"), do: :emit
  defp string_to_kind("store"), do: :store
  defp string_to_kind("transfer"), do: :transfer

  defp emit_rule_fields("emit", state, :permit) do
    %{"assigned_label" => state.checked, "content_digest" => digest_value(state)}
  end

  defp emit_rule_fields("emit", state, _not_permit) do
    %{"assigned_label" => nil, "content_digest" => digest_value(state)}
  end

  defp emit_rule_fields("admit", _state, _value), do: %{}
  defp emit_rule_fields(_handover, state, _value), do: %{"content_digest" => digest_value(state)}

  defp base_decision(ctx, auth, checked) do
    %{
      "rule" => auth.operation,
      "registry_ref" => ctx.registry_id,
      "snapshot_ref" => ctx.snapshot_id,
      "intent_ref" => auth.intent_id,
      "identity" => ctx.identity,
      "workspace" => ctx.workspace["workspace_id"],
      "object" => %{"object_id" => ctx.object["object_id"], "version" => ctx.object["version"]},
      "checked_label" => checked
    }
  end

  # =========================================================================
  # Beweisbaum (§ 2.5): § 4.3 (admit), § 4.5 (emit), § 4.7/§ 4.8 (store,
  # transfer) feste Prämissenordnung
  # =========================================================================

  defp build_proof(state, registry, auth, rule_kind) do
    premises =
      case rule_kind do
        "admit" ->
          [
            quarantine_premise(state),
            workspace_premise(),
            basis_fact_premise(state.facts, "has_operation_right"),
            basis_fact_premise(state.facts, "has_object_access_right"),
            basis_fact_premise(state.facts, "audit_path_ready"),
            basis_fact_premise(state.facts, "environment_observers_complete"),
            label_inclusion_premise(state),
            recipient_premise(state),
            binding_condition_premises(state, registry, "admit")
          ]

        "emit" ->
          [
            workspace_premise(),
            basis_fact_premise(state.facts, "has_operation_right"),
            basis_fact_premise(state.facts, "audit_path_ready"),
            basis_fact_premise(state.facts, "environment_observers_complete"),
            recipient_premise(state),
            binding_condition_premises(state, registry, "emit"),
            label_assignment_premise(state)
          ]

        handover ->
          [
            workspace_premise(),
            basis_fact_premise(state.facts, "has_operation_right"),
            basis_fact_premise(state.facts, "audit_path_ready"),
            basis_fact_premise(state.facts, "environment_observers_complete"),
            label_preservation_premise(state),
            recipient_premise(state),
            binding_condition_premises(state, registry, handover)
          ]
      end

    %{
      "schema" => "komki-proof/1",
      "rule" => rule_kind,
      "conclusion" => "permit",
      "registry_ref" => state.registry_id,
      "snapshot_ref" => state.snapshot_id,
      "intent_ref" => auth.intent_id,
      "checked_label" => state.checked,
      "premises" => List.flatten(premises)
    }
  end

  defp quarantine_premise(ctx) do
    %{
      "name" => "not_quarantine",
      "kind" => "object_check",
      "value" => true,
      "object" => ctx.object["object_id"] <> "@" <> ctx.object["version"],
      "classification" => "classified"
    }
  end

  defp workspace_premise do
    %{
      "name" => "workspace_contract_valid",
      "kind" => "fact",
      "fact" => "workspace_contract_valid",
      "value" => true,
      "source" => "workspace.valid"
    }
  end

  defp basis_fact_premise(facts, name) do
    entry = Map.fetch!(facts, name)

    %{
      "name" => name,
      "kind" => "fact",
      "fact" => name,
      "value" => true,
      "source" => entry["source"],
      "source_kind" => entry["source_kind"]
    }
  end

  defp label_inclusion_premise(ctx) do
    %{
      "name" => "label_inclusion",
      "kind" => "computed",
      "value" => true,
      "object_labels" => ctx.object["labels"],
      "checked_label" => ctx.checked
    }
  end

  defp label_assignment_premise(ctx) do
    %{
      "name" => "label_assignment",
      "kind" => "computed",
      "value" => true,
      "assigned_label" => ctx.checked,
      "checked_label" => ctx.checked
    }
  end

  defp label_preservation_premise(ctx) do
    %{
      "name" => "label_preservation",
      "kind" => "computed",
      "value" => true,
      "workspace_bindings" => ctx.workspace["bindings"],
      "checked_label" => ctx.checked
    }
  end

  defp recipient_premise(ctx) do
    %{
      "name" => "recipient_inclusion",
      "kind" => "computed",
      "value" => true,
      "actual_recipients" => ctx.rho,
      "allowed_recipients" => ctx.allowed
    }
  end

  defp binding_condition_premises(ctx, registry, rule_name) do
    Enum.map(ctx.checked, fn binding_id ->
      binding = Map.fetch!(registry.bindings, binding_id)
      expr = Map.fetch!(binding.operations, rule_name)

      %{
        "name" => "binding_condition",
        "kind" => "condition",
        "binding" => binding_id,
        "expression" => expr,
        "value" => true,
        "fact_refs" => Registry.expression_fact_refs(expr)
      }
    end)
  end
end
