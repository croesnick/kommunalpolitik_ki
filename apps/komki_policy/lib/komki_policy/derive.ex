defmodule KomkiPolicy.Derive do
  @moduledoc """
  Regelkern `derive` Lieferung 1 — Regelzweig `admit` (CONTRACT.md § 1, § 2, § 4).

  `decide/3` validiert Snapshot und Intent als geschlossene Schemas,
  prüft die Referenzkohärenz und leitet dann in fester Prämissenordnung
  (§ 4.3). Nicht implementierte Regelzweige ergeben `{:unsupported, info}`
  — niemals ein `deny` (die fehlende Prüfung ist keine verbietende Prüfung).
  Struktur- und Validierungsfehler sind Eingabefehler, keine Decisions.

  Bekannt-falsch schlägt Unknown (deny); andernfalls führt Unknown zu
  `indeterminate`; nur bei vollständig bewiesenen Prämissen entsteht ein
  kanonischer Beweisbaum (§ 2.5).
  """

  alias KomkiPolicy.Calculus
  alias KomkiPolicy.{Context, Evaluator, Registry}

  @required_premises [
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

  @unsupported_operations ["start", "emit", "transfer", "store"]
  @unsupported_detail "rule branch not implemented in delivery 1"

  @doc "§ 4.3-Prämissennamen in fester Reihenfolge (gemeinsame Sollmenge für derive-Baum und verify)."
  @spec required_premises() :: [String.t()]
  def required_premises, do: @required_premises

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
  Leitet für den Regelzweig `admit` oder meldet `unsupported` (Lücke)
  bzw. einen strukturierten Eingabefehler.
  """
  @spec decide(Registry.compiled(), term(), term()) ::
          {:ok, decision()}
          | {:unsupported, %{required(String.t()) => String.t()}}
          | {:error, error()}
  def decide(registry, snapshot, intent) do
    case decide_validated?(registry, snapshot, intent) do
      {:ok, result} -> {:ok, result}
      {:unsupported, info} -> {:unsupported, info}
      {:error, %{} = error} -> {:error, error}
      {:error, reason} -> wrap_reason(reason)
    end
  end

  @doc "Ausgabeshape für nicht unterstützte Regelzweige (L1: alle außer `admit`)."
  def unsupported_info(operation) do
    %{"result" => "unsupported", "rule" => operation, "detail" => @unsupported_detail}
  end

  defp wrap_reason({code, path, detail}), do: {:error, %{code: code, path: path, detail: detail}}

  defp fail(code, path, detail), do: {:error, {code, path, detail}}

  defp decide_validated?(registry, snapshot, intent) do
    with {:ok, auth} <- Context.validate_intent(intent),
         :ok <- ensure_supported(auth.operation),
         {:ok, ctx} <- Context.validate_snapshot(snapshot, registry),
         :ok <- Context.ensure_coherence(ctx, auth) do
      run_admit(ctx, registry, auth)
    end
  end

  defp ensure_supported("admit"), do: :ok

  defp ensure_supported(operation) when operation in @unsupported_operations do
    {:unsupported, unsupported_info(operation)}
  end

  defp ensure_supported(other),
    do: fail(:invalid_operation, "$.operation", "unknown operation: " <> Kernel.inspect(other))

  # =========================================================================
  # admit-Kern (§ 4): Prämissen in fester Ordnung
  # =========================================================================

  defp run_admit(ctx, registry, auth) do
    workspace = ctx.workspace
    facts = ctx.facts
    rho = actual_recipients(workspace, registry)
    allowed = allowed_recipients(registry, workspace)

    state =
      ctx
      |> Map.merge(%{checked: workspace["bindings"], rho: rho, allowed: allowed})
      |> Map.merge(%{blockers: [], evidence: []})
      |> premise_quarantine()
      |> premise_workspace_valid()
      |> premise_basis_fact("has_operation_right")
      |> premise_basis_fact("has_object_access_right")
      |> premise_basis_fact("audit_path_ready")
      |> premise_env_flag()
      |> premise_label_inclusion()
      |> premise_recipient_inclusion()
      |> premise_binding_conditions(registry)

    conclude(state, ctx, registry, auth, facts)
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

  # P6: false/fehlt ist KEIN verbietender Befund, sondern fehlende Evidenz (§ 4.3).
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

  defp premise_binding_conditions(ctx, registry) do
    Enum.reduce(ctx.checked, ctx, fn binding_id, acc ->
      binding = Map.get(registry.bindings, binding_id)
      expr = binding && Map.get(binding.operations, "admit")

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
  # Empfängermengen (§ 4.3 Punkt 8) — Kalkül lebt in KomkiPolicy.Calculus,
  # damit verify (§ 5) dieselben Funktionen unabhaengig neu benutzt.
  # =========================================================================

  defp actual_recipients(workspace, registry) do
    Calculus.actual_recipients(registry, workspace["environment"])
  end

  defp allowed_recipients(registry, workspace) do
    Calculus.allowed_recipients(registry, workspace["bindings"])
  end

  # =========================================================================
  # Entscheidung (§ 4.4): bekannt-falsch > unknown > permit
  # =========================================================================

  defp conclude(state, ctx, registry, auth, facts) do
    cond do
      state.blockers != [] ->
        {:ok, decision(ctx, auth, state.checked, "blockers", state.blockers)}

      state.evidence != [] ->
        {:ok, decision(ctx, auth, state.checked, "missing_evidence", state.evidence)}

      true ->
        proof = build_proof(state, registry, auth, facts)
        {:ok, decision(ctx, auth, state.checked, "proof", proof)}
    end
  end

  defp decision(ctx, auth, checked, value_key, value) do
    %{
      "decision" => decision_value(value_key),
      "rule" => auth.operation,
      "registry_ref" => ctx.registry_id,
      "snapshot_ref" => ctx.snapshot_id,
      "intent_ref" => auth.intent_id,
      "identity" => ctx.identity,
      "workspace" => ctx.workspace["workspace_id"],
      "object" => %{"object_id" => ctx.object["object_id"], "version" => ctx.object["version"]},
      "checked_label" => checked,
      "blockers" => value_of(value_key, value, "blockers"),
      "missing_evidence" => value_of(value_key, value, "missing_evidence"),
      "proof" => value_of(value_key, value, "proof")
    }
  end

  defp decision_value("blockers"), do: "deny"
  defp decision_value("missing_evidence"), do: "indeterminate"
  defp decision_value("proof"), do: "permit"

  defp value_of(key, value, wanted) do
    if key == wanted, do: value, else: nil
  end

  # =========================================================================
  # Beweisbaum (§ 2.5, § 4.3 feste Prämissenordnung)
  # =========================================================================

  defp build_proof(state, registry, auth, facts) do
    %{
      "schema" => "komki-proof/1",
      "rule" => "admit",
      "conclusion" => "permit",
      "registry_ref" => state.registry_id,
      "snapshot_ref" => state.snapshot_id,
      "intent_ref" => auth.intent_id,
      "checked_label" => state.checked,
      "premises" => premises(state, registry, facts)
    }
  end

  defp premises(state, registry, facts) do
    premise_list = [
      quarantine_premise(state),
      workspace_premise(facts),
      basis_fact_premise(facts, "has_operation_right"),
      basis_fact_premise(facts, "has_object_access_right"),
      basis_fact_premise(facts, "audit_path_ready"),
      basis_fact_premise(facts, "environment_observers_complete"),
      label_inclusion_premise(state),
      recipient_premise(state),
      binding_condition_premises(state, registry, facts)
    ]

    List.flatten(premise_list)
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

  defp workspace_premise(_facts) do
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

  defp recipient_premise(ctx) do
    %{
      "name" => "recipient_inclusion",
      "kind" => "computed",
      "value" => true,
      "actual_recipients" => ctx.rho,
      "allowed_recipients" => ctx.allowed
    }
  end

  defp binding_condition_premises(ctx, registry, _facts) do
    Enum.map(ctx.checked, fn binding_id ->
      binding = Map.fetch!(registry.bindings, binding_id)
      expr = Map.fetch!(binding.operations, "admit")

      %{
        "name" => "binding_condition",
        "kind" => "condition",
        "binding" => binding_id,
        "expression" => expr,
        "value" => true,
        "fact_refs" => fact_refs_from_registry(registry, binding_id, expr)
      }
    end)
  end

  defp fact_refs_from_registry(_registry, _binding_id, expr) do
    Registry.expression_fact_refs(expr)
  end
end
