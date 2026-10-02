defmodule KomkiPolicy.Verify do
  @moduledoc """
  Unabhaengiger Ableitungspruefer `verify` (CONTRACT.md § 5).

  Prueft einen vorgelegten Beweisbaum `komki-proof/1` gegen genau die
  mitgefuehrte Registry, den Snapshot und den Intent. Er ruft `derive`
  NIEMALS auf und glaubt kein `permit` — die Prueflabel-, Praemissen-,
  Fakt-, Mengen- und Bedingungspraemissen werden neu berechnet:

  * Sollmenge: `KomkiPolicy.Derive.required_premises/0` (§ 4.3) plus je
    `binding_condition` fuer jedes Element von `workspace.bindings`.
  * Mengen: `KomkiPolicy.Calculus` (R_G / rho_G / l-Subset, § 4.3 Punkt 8).
  * Neu-Auswertung der Bedingungen: `KomkiPolicy.Evaluator.evaluate/2`.
  * Expression und `fact_refs` muessen exakt und strukturell dem
    Registry-AST entsprechen (`KomkiPolicy.Registry.expression_fact_refs/1`);
    dem Baum wird nicht getraut.

  Pruefschritte laufen in fester Ordnung § 5; Befund-Reihenfolge ist die
  Pruefordnung. Struktur-Befunde aus Schritt 1–3 beenden die Pruefung
  sofort (genau dieser Befund, spaetere Schritte laufen nicht mehr).
  Befunde aus den praedikatsbezogenen Schritten 4–8 ziehen zusaetzlich
  `conclusion_mismatch` nach sich. Strukturfehler in den Eingabedaten
  sind Eingabefehler (`{:error, …}`), kein `invalid`-Urteil.

  Deterministisch und rein: gleiche Eingaben -> byte-identische
  kanonische Ausgaben; kein I/O, kein Zustand, keine Uhr.
  """

  alias KomkiPolicy.{Calculus, Context, Derive, Evaluator, Registry}

  @proof_fields [
    "schema",
    "rule",
    "conclusion",
    "registry_ref",
    "snapshot_ref",
    "intent_ref",
    "checked_label",
    "premises"
  ]
  @required_proof_values [
    "rule",
    "conclusion",
    "registry_ref",
    "snapshot_ref",
    "intent_ref",
    "checked_label",
    "premises"
  ]
  @premise_kinds ["object_check", "fact", "computed", "condition"]

  # Name↔Art-Tabelle § 2.5: jeder feste Prämissenname trägt genau eine Art;
  # Art-Tarnung (richtiger Name, falsche Art) ist eine unbekannte Prämisse.
  @premise_kinds_by_name %{
    "not_quarantine" => "object_check",
    "workspace_contract_valid" => "fact",
    "has_operation_right" => "fact",
    "has_object_access_right" => "fact",
    "audit_path_ready" => "fact",
    "environment_observers_complete" => "fact",
    "label_inclusion" => "computed",
    "recipient_inclusion" => "computed",
    "binding_condition" => "condition"
  }

  # Kind-generische Schluesselformen für (Name, Art)-Paare außerhalb der
  # Tabelle (schließen Extra-Keys aus,MIN-1).
  @premise_shape_keys %{
    {"not_quarantine", "object_check"} => ["classification", "kind", "name", "object", "value"],
    {"workspace_contract_valid", "fact"} => ["fact", "kind", "name", "source", "value"],
    {"has_operation_right", "fact"} => ["fact", "kind", "name", "source", "source_kind", "value"],
    {"has_object_access_right", "fact"} => [
      "fact",
      "kind",
      "name",
      "source",
      "source_kind",
      "value"
    ],
    {"audit_path_ready", "fact"} => ["fact", "kind", "name", "source", "source_kind", "value"],
    {"environment_observers_complete", "fact"} => [
      "fact",
      "kind",
      "name",
      "source",
      "source_kind",
      "value"
    ],
    {"label_inclusion", "computed"} => ["checked_label", "kind", "name", "object_labels", "value"],
    {"recipient_inclusion", "computed"} => [
      "actual_recipients",
      "allowed_recipients",
      "kind",
      "name",
      "value"
    ],
    {"binding_condition", "condition"} => [
      "binding",
      "expression",
      "fact_refs",
      "kind",
      "name",
      "value"
    ]
  }

  @generic_premise_shape_keys %{
    "object_check" => ["classification", "kind", "name", "object", "value"],
    "fact" => ["fact", "kind", "name", "source", "source_kind", "value"],
    "computed" => ["kind", "name", "value"],
    "condition" => ["binding", "expression", "kind", "name", "value"]
  }
  @premise_required_keys %{
    "object_check" => ["classification", "object", "value"],
    "fact" => ["fact", "source", "source_kind", "value"],
    "computed" => ["value"],
    "condition" => ["binding", "expression", "value"]
  }

  @type evidence() :: %{
          required(String.t()) => String.t() | nil
        }

  @type error() :: %{
          required(:code) => atom(),
          required(:path) => String.t(),
          required(:detail) => String.t()
        }
  @type outcome() :: %{required(String.t()) => term()}

  @doc "Prueft den Beweisbaum unabhaengig gegen Registry/Snapshot/Intent (§ 5)."
  @spec check(KomkiPolicy.Registry.compiled(), term(), term(), term()) ::
          {:ok, outcome()} | {:error, error()}
  def check(registry, snapshot, intent, proof) do
    outcome =
      with {:ok, auth} <- Context.validate_intent(intent),
           {:ok, ctx} <- Context.validate_snapshot(snapshot, registry),
           :ok <- Context.ensure_coherence(ctx, auth),
           {:ok, proof} <- validate_proof(proof) do
        {:ok, run_checks(ctx, registry, auth, proof)}
      else
        {:error, error} -> {:error, error_shape(error)}
      end

    outcome
  end

  defp error_shape(%{} = map), do: map
  defp error_shape({code, path, detail}), do: %{code: code, path: path, detail: detail}

  # =========================================================================
  # Proof-Eingabevalidierung (Eingabefehler, kein invalid-Urteil)
  # =========================================================================

  defp validate_proof(proof) when is_map(proof) do
    case validate_proof_reason(proof) do
      {:ok, value} -> {:ok, value}
      {:error, {code, path, detail}} -> {:error, %{code: code, path: path, detail: detail}}
    end
  end

  defp validate_proof(proof),
    do:
      input_error(
        :invalid_record,
        "$",
        "expected a komki-proof/1 object, got " <> Kernel.inspect(proof)
      )

  defp input_error(code, path, detail), do: {:error, {code, path, detail}}

  defp validate_proof_reason(proof) do
    with {:ok, _} <- require_map(proof, "$"),
         :ok <- require_proof_schema(proof),
         :ok <- closed_fields(proof, @proof_fields, "$"),
         :ok <- require_present(proof, @required_proof_values, "$"),
         :ok <- require_binary(proof["rule"], "$.rule"),
         :ok <- require_binary(proof["conclusion"], "$.conclusion"),
         :ok <- require_binary(proof["registry_ref"], "$.registry_ref"),
         :ok <- require_binary(proof["snapshot_ref"], "$.snapshot_ref"),
         :ok <- require_binary(proof["intent_ref"], "$.intent_ref"),
         :ok <- require_string_list(proof["checked_label"], "$.checked_label"),
         :ok <- validate_premises(proof["premises"], "$.premises") do
      {:ok, proof}
    end
  end

  defp require_proof_schema(%{"schema" => "komki-proof/1"} = _proof), do: :ok

  defp require_proof_schema(%{"schema" => other}),
    do:
      input_error(
        :invalid_schema,
        "$.schema",
        "expected \"komki-proof/1\", got " <> Kernel.inspect(other)
      )

  defp require_proof_schema(_other),
    do: input_error(:missing_field, "$.schema", "missing field \"schema\"")

  defp closed_fields(map, allowed, path) do
    unknown = Enum.sort(Enum.reject(Map.keys(map), &(&1 in allowed)))

    case unknown do
      [] ->
        :ok

      [first | _] ->
        input_error(:unknown_field, path <> "." <> first, "field not part of the closed schema")
    end
  end

  defp require_present(map, keys, root) do
    missing = Enum.reject(keys, &Map.has_key?(map, &1))
    if_present(missing, root)
  end

  defp if_present([], _root), do: :ok

  defp if_present(missing, root),
    do:
      input_error(
        :missing_field,
        root,
        "missing required fields: " <> Enum.join(missing, ", ")
      )

  defp require_binary(value, _path) when is_binary(value), do: :ok

  defp require_binary(value, path),
    do: input_error(:invalid_entry, path, "expected a string, got " <> Kernel.inspect(value))

  defp require_string_list(list, path) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      :ok
    else
      input_error(:invalid_entry, path, "expected an array of strings")
    end
  end

  defp require_string_list(value, path),
    do:
      input_error(
        :invalid_entry,
        path,
        "expected an array of strings, got " <> Kernel.inspect(value)
      )

  defp require_map(%{} = map, _path), do: {:ok, map}

  defp validate_premises(premises, path) when is_list(premises) do
    premises
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {premise, index}, :ok ->
      case premise_entry(premise, path <> ".[" <> Integer.to_string(index) <> "]") do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_premises(_other, path),
    do: input_error(:invalid_entry, path, "expected an array of premises")

  defp premise_entry(%{} = premise, path) do
    with {:ok, kind} <- require_premise_kind(premise, path),
         :ok <- require_premise_name(premise, path),
         :ok <- premise_shape_keys(premise, kind, path),
         :ok <- required_premise_keys(premise, kind, path),
         :ok <- required_premise_value(premise, path),
         :ok <- require_binary_values(premise, path, "binding") do
      require_binary_values(premise, path, "fact")
    end
  end

  defp premise_entry(_other, path),
    do: input_error(:invalid_premise, path, "expected a premise object")

  # Geschlossene Feldmenge pro (name, kind), geknüpftes kind-generisches
  # Form für (Name, Art)-Paare außerhalb der §2.5-Tabelle. Extra-Schlüssel
  # sind Eingabefehler (MIN-1).
  defp premise_shape_keys(premise, kind, path) do
    name = Map.get(premise, "name")

    closed =
      Map.get(@premise_shape_keys, {name, kind}) || Map.fetch!(@generic_premise_shape_keys, kind)

    case unknown_premise_keys(Map.keys(premise), closed) do
      [] ->
        :ok

      extras ->
        input_error(
          :unknown_premise_field,
          path <> "." <> List.first(extras),
          "field not part of the premise shape"
        )
    end
  end

  defp unknown_premise_keys(present, allowed) do
    present
    |> Enum.reject(&(&1 in allowed))
    |> Enum.sort()
  end

  defp require_premise_kind(%{"kind" => kind} = _p, _path) when kind in @premise_kinds,
    do: {:ok, kind}

  defp require_premise_kind(%{"kind" => kind}, path) do
    input_error(
      :invalid_premise_kind,
      path <> ".kind",
      "unknown premise kind " <> Kernel.inspect(kind)
    )
  end

  defp require_premise_kind(_other, path),
    do: input_error(:missing_field, path <> ".kind", "missing field \"kind\"")

  defp require_premise_name(%{"name" => name} = _p, _path) when is_binary(name), do: :ok

  defp require_premise_name(_other, path),
    do: input_error(:missing_field, path <> ".name", "missing field \"name\"")

  @pair_required_keys %{
    {"workspace_contract_valid", "fact"} => ["fact", "source", "value"],
    {"binding_condition", "condition"} => ["binding", "expression", "fact_refs", "value"]
  }

  defp required_premise_keys(premise, kind, path) do
    pair = {Map.get(premise, "name"), kind}
    base = Map.get(@pair_required_keys, pair) || Map.fetch!(@premise_required_keys, kind)
    missing = missing_keys(premise, base)

    case missing do
      [] ->
        :ok

      missing_entries ->
        input_error(
          :missing_field,
          path,
          "missing required fields: " <> Enum.join(missing_entries, ", ")
        )
    end
  end

  defp missing_keys(premise, required) do
    Enum.reject(required, fn key -> Map.has_key?(premise, key) end)
  end

  defp required_premise_value(premise, path) do
    case Map.get(premise, "value") do
      value when is_boolean(value) ->
        :ok

      other ->
        input_error(
          :invalid_entry,
          path <> ".value",
          "premise value must be a boolean, got " <> Kernel.inspect(other)
        )
    end
  end

  defp require_binary_values(premise, path, key) do
    case Map.get(premise, key) do
      nil ->
        :ok

      value when is_binary(value) ->
        :ok

      other ->
        input_error(
          :invalid_entry,
          path <> "." <> key,
          "expected a string, got " <> Kernel.inspect(other)
        )
    end
  end

  # =========================================================================
  # Prüfschritte § 5 — fester Ordnung; erster Befund-Schritt unter 1–3
  # beendet sofort; Schritte 4–8 sammeln; Schritt 9 hängt conclusion_mismatch an.
  # =========================================================================

  defp run_checks(ctx, registry, auth, proof) do
    case structural_reasons(ctx, registry, auth, proof) do
      [] -> predicate_reasons(ctx, registry, proof)
      reasons -> invalid_outcome(reasons)
    end
  end

  # Schritte 1–3
  defp structural_reasons(ctx, registry, auth, proof) do
    step1 = reference_reasons(ctx, registry, auth, proof)

    if step1 != [] do
      step1
    else
      case label_mismatch_reasons(ctx, proof) do
        [] -> required_set_reasons(ctx, proof)
        reasons -> reasons
      end
    end
  end

  defp reference_reasons(ctx, registry, auth, proof) do
    findings = [
      mismatch_if(proof["snapshot_ref"] != ctx.snapshot_id, "snapshot_mismatch"),
      mismatch_if(proof["registry_ref"] != registry.registry_id, "registry_mismatch"),
      mismatch_if(proof["intent_ref"] != auth.intent_id, "intent_mismatch"),
      mismatch_if(proof["rule"] != "admit", "unsupported_rule")
    ]

    Enum.reject(findings, &is_nil/1)
  end

  defp mismatch_if(true, code), do: reason(code, nil, nil)
  defp mismatch_if(false, _code), do: nil

  defp label_mismatch_reasons(ctx, proof) do
    if Enum.sort(proof["checked_label"]) == ctx.workspace["bindings"] do
      []
    else
      [reason("checked_label_mismatch", nil, nil)]
    end
  end

  defp reason(code, binding, fact), do: %{"code" => code, "binding" => binding, "fact" => fact}

  defp invalid_outcome(reasons), do: %{"result" => "invalid", "reasons" => reasons}

  # Schritt 3: Required-Set — Name↔Art-Tabelle (§ 2.5): eine Prämisse erfüllt
  # ihren Namens-Slot nur mit der zugeordneten Art; jede Tarnung (richtiger
  # Name, falsche Art) ist eine unbekannte, strukturelle Prämisse und stoppt
  # die Prüfung sofort. Bindungen für binding_condition-Slots kommen nur aus
  # tatsächlich `kind: "condition"`-Prämissen.
  defp required_set_reasons(ctx, proof) do
    fixed = Derive.required_premises() -- ["binding_condition"]
    bindings = ctx.workspace["bindings"]
    premises = proof["premises"]
    present_names = Enum.uniq(Enum.map(premises, &Map.fetch!(&1, "name")))

    condition_bindings =
      for %{"kind" => "condition"} = premise <- premises,
          Map.fetch!(premise, "name") == "binding_condition",
          do: Map.fetch!(premise, "binding")

    # missing nur bei gaenzlich fehlendem Namen; eine art-getarnte Ersetzung
    # wird als unknown_premise gemeldet (der SLOT ist praesent, die
    # Verfaelschung sichtbar — kein doppelter Befund).
    missing_fixed =
      for name <- fixed,
          name not in present_names,
          do: reason("missing_required_premise", nil, nil)

    missing_conditions =
      for b <- bindings,
          b not in condition_bindings,
          do: reason("missing_required_premise", b, nil)

    slippery = Enum.reject(premises, &fits_slot?/1)
    unknown = Enum.map(slippery, &unexpected_reason/1)

    missing_fixed ++ missing_conditions ++ unknown
  end

  defp expected_kind(name) do
    Map.get(@premise_kinds_by_name, name)
  end

  defp fits_slot?(premise) do
    Map.fetch!(premise, "kind") == expected_kind(Map.fetch!(premise, "name"))
  end

  defp unexpected_reason(premise) do
    binding = premise["binding"]

    if is_binary(binding) do
      reason("unknown_premise", binding, nil)
    else
      reason("unknown_premise", nil, nil)
    end
  end

  # Steps 4–8: alles sammeln.
  defp predicate_reasons(ctx, registry, proof) do
    premise_findings =
      List.flatten([
        fact_premise_reasons(ctx, proof),
        quarantine_reasons(ctx, proof),
        label_inclusion_reasons(ctx, proof),
        recipient_inclusion_reasons(ctx, registry, proof),
        condition_reasons(ctx, registry, proof)
      ])

    conclusion_findings = conclusion_reasons(premise_findings != [], proof)

    case premise_findings ++ conclusion_findings do
      [] -> %{"result" => "valid", "reasons" => []}
      reasons -> invalid_outcome(reasons)
    end
  end

  defp conclusion_reasons(has_premise_findings, proof) do
    base = if has_premise_findings, do: [reason("conclusion_mismatch", nil, nil)], else: []

    unsupported =
      if proof["conclusion"] != "permit",
        do: [reason("conclusion_unsupported", nil, nil)],
        else: []

    base ++ unsupported
  end

  defp fact_premise_reasons(ctx, proof) do
    fact_premises = Enum.filter(proof["premises"], fn p -> p["kind"] == "fact" end)

    fact_premises
    |> Enum.map(fn premise -> fact_premise_finding(ctx, premise) end)
    |> Enum.reject(&is_nil/1)
  end

  defp fact_premise_finding(ctx, premise) do
    fact_name = Map.fetch!(premise, "fact")

    if fact_name == "workspace_contract_valid" do
      mismatch_if(premise["value"] != ctx.workspace["valid"], "fact_value_mismatch")
    else
      fact_entry_finding(ctx.facts, fact_name, premise)
    end
  end

  defp fact_entry_finding(facts, fact_name, premise) do
    case Map.get(facts, fact_name) do
      nil -> reason("fact_missing", nil, fact_name)
      entry -> mismatch_if(premise["value"] != Map.fetch!(entry, "value"), "fact_value_mismatch")
    end
  end

  defp quarantine_reasons(ctx, proof) do
    for %{"kind" => "object_check"} = _p <- proof["premises"],
        ctx.object["classification"] != "classified" do
      reason("object_quarantine", nil, nil)
    end
  end

  defp label_inclusion_reasons(ctx, proof) do
    for %{"kind" => "computed", "name" => "label_inclusion"} = premise <- proof["premises"] do
      ok =
        Calculus.labels_subset?(ctx.object["labels"], ctx.workspace["bindings"]) and
          premise["value"] == true and
          premise["object_labels"] == Enum.sort(ctx.object["labels"]) and
          premise["checked_label"] == ctx.workspace["bindings"]

      if ok, do: nil, else: reason("label_inclusion_false", nil, nil)
    end
    |> Enum.reject(&is_nil/1)
  end

  defp recipient_inclusion_reasons(ctx, registry, proof) do
    for %{"kind" => "computed", "name" => "recipient_inclusion"} = premise <- proof["premises"] do
      rho = Calculus.actual_recipients(registry, ctx.workspace["environment"])
      allowed = Calculus.allowed_recipients(registry, ctx.workspace["bindings"])

      ok =
        MapSet.subset?(MapSet.new(rho), MapSet.new(allowed)) and
          premise["value"] == true and
          premise["actual_recipients"] == rho and
          premise["allowed_recipients"] == allowed

      if ok, do: nil, else: reason("recipient_inclusion_false", nil, nil)
    end
    |> Enum.reject(&is_nil/1)
  end

  defp condition_reasons(ctx, registry, proof) do
    for %{"kind" => "condition"} = premise <- proof["premises"] do
      binding = Map.fetch!(premise, "binding")
      registry_expr = registry_admit_expression(registry, binding)

      ([expression_check(premise, registry_expr, binding)] ++
         [fact_refs_check(premise, registry_expr, binding)] ++
         [verdict_check(registry_expr, ctx.facts, binding)] ++
         [claimed_value_check(premise, binding)])
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
    end
    |> List.flatten()
  end

  defp registry_admit_expression(registry, binding) do
    entry = Map.get(registry.bindings, binding)
    entry && Map.get(entry.operations, "admit")
  end

  defp expression_check(premise, registry_expr, binding) do
    if premise["expression"] != registry_expr,
      do: reason("expression_mismatch", binding, nil),
      else: nil
  end

  # Kein Registry-Ausdruck (Bindung ohne admit-Regel): Die strukturelle
  # Assertion (expression_mismatch) uebernimmt die Verwerfung; Neuauswertung
  # und fact_refs-Vergleich werden uebersprungen (nichts zu vergleichen —
  # kein Crash, keine weiteren Befunde).
  defp fact_refs_check(_premise, nil, _binding), do: nil

  defp fact_refs_check(premise, registry_expr, binding) do
    if premise["fact_refs"] != Registry.expression_fact_refs(registry_expr),
      do: reason("fact_refs_mismatch", binding, nil),
      else: nil
  end

  defp verdict_check(nil, _facts, _binding), do: nil

  defp verdict_check(registry_expr, facts, binding) do
    case Evaluator.evaluate(registry_expr, facts) do
      true -> nil
      false -> reason("condition_false", binding, nil)
      :unknown -> reason("condition_unknown", binding, nil)
    end
  end

  defp claimed_value_check(premise, binding) do
    if premise["value"] != true,
      do: reason("condition_false", binding, nil),
      else: nil
  end
end
