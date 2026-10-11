defmodule KomkiPolicy.Context do
  @moduledoc """
  Geteilte Eingabe-Validierung für `derive` und `verify` (CONTRACT.md § 2.2, § 2.3).

  Beide dienstlichen Module prüfen denselben `ContextSnapshot`-/`Intent`-Datensatz
  mit denselben Fehlercodes — die Validierung ist die gemeinsame Wahrheit, damit
  kein Prüfer eine erlaubtere oder strengere Eingabemenge annimmt (RFC B.5
  Konsistenz). Die Funktionen sind rein und liefern strukturierte Fehler-Maps
  (gleiche Form wie `KomkiPolicy.JSON.parse/1`).

  * `validate_intent/1` — § 2.3: geschlossene Feldmenge, Schema-String,
    kebab-`intent_id`, `<object_id>@<version>`, `workspace` kebab, Operation
    in der geschlossenen Operationsmenge. Rückgabe: Auth-Map
    `%{operation:, intent_id:, object_ref:, workspace:}`.
  * `validate_snapshot/2` — § 2.2: geschlossene Feldmengen (auch `workspace`
    und `object`), `registry_ref`-Kohärenz zur kompilierten Registry,
    `identity` ∈ 𝒪, Referenz-Listen sortiert/eindeutig/existierend
    (`unknown_binding_reference`, `unknown_environment`), `facts` ⊆
    fact_fields ∪ Basisfakten mit Pflichtort `value`/`source`/`source_kind`
    und typgerechten Werten (Basisfakten unveränderlich boolesch, § 4.2). Rückgabe:
    ctx-map `%{registry_id:, snapshot_id:, identity:, workspace:, object:, facts:}`.
  * `ensure_coherence/2` — § 2.3: intent-workspace/object-Referenzen
    gleich dem Snapshot (`intent_snapshot_mismatch`).
  """

  alias KomkiPolicy.Registry

  @snapshot_fields [
    "schema",
    "snapshot_id",
    "registry_ref",
    "identity",
    "workspace",
    "object",
    "facts"
  ]
  @workspace_fields ["workspace_id", "bindings", "valid", "environment"]
  @object_fields ["object_id", "version", "classification", "labels"]
  @fact_entry_fields ["value", "source", "source_kind"]
  @source_kinds ["administered", "technical", "assumption", "test"]
  @classifications ["classified", "quarantine"]
  @intent_fields ["schema", "intent_id", "operation", "object", "workspace"]
  @known_operations ["start", "admit", "emit", "transfer", "store"]

  @basis_facts [
    "has_operation_right",
    "has_object_access_right",
    "audit_path_ready",
    "environment_observers_complete"
  ]

  @doc "Basisfakten nach § 4.2 (kann von Tests genutzt werden)."
  @spec basis_facts() :: [String.t()]
  def basis_facts, do: @basis_facts

  @type error() :: %{
          required(:code) => atom(),
          required(:path) => String.t(),
          required(:detail) => String.t()
        }
  @type auth() :: %{
          required(:operation) => String.t(),
          required(:intent_id) => String.t(),
          required(:object_ref) => String.t(),
          required(:workspace) => String.t()
        }
  @type ctx() :: %{
          required(:registry_id) => String.t(),
          required(:snapshot_id) => String.t(),
          required(:identity) => String.t(),
          required(:workspace) => map(),
          required(:object) => map(),
          required(:facts) => map()
        }

  # =========================================================================
  # Intent (§ 2.3)
  # =========================================================================

  @doc "Validiert den Intent und liefert die Auth-Referenzen."
  @spec validate_intent(term()) :: {:ok, auth()} | {:error, error()}
  def validate_intent(intent) do
    case validate_intent_reason(intent) do
      {:ok, auth} -> {:ok, auth}
      {:error, {code, path, detail}} -> {:error, %{code: code, path: path, detail: detail}}
    end
  end

  defp validate_intent_reason(intent) do
    with {:ok, _} <- require_map(intent, "$"),
         :ok <- require_schema(intent, "komki-intent/1"),
         :ok <- closed_fields(intent, @intent_fields, "$"),
         :ok <- require_kebab(intent["intent_id"], "$.intent_id"),
         :ok <- require_object_ref(intent["object"], "$.object"),
         :ok <- require_kebab(intent["workspace"], "$.workspace"),
         :ok <- require_operation(intent["operation"]) do
      {:ok,
       %{
         operation: intent["operation"],
         intent_id: intent["intent_id"],
         object_ref: intent["object"],
         workspace: intent["workspace"]
       }}
    end
  end

  # =========================================================================
  # Snapshot (§ 2.2)
  # =========================================================================

  @doc "Validiert den Snapshot gegen die kompilierte Registry und liefert den Entscheidungskontext."
  @spec validate_snapshot(term(), Registry.compiled()) :: {:ok, ctx()} | {:error, error()}
  def validate_snapshot(snapshot, registry) do
    case validate_snapshot_reason(snapshot, registry) do
      {:ok, ctx} -> {:ok, ctx}
      {:error, {code, path, detail}} -> {:error, %{code: code, path: path, detail: detail}}
    end
  end

  defp validate_snapshot_reason(snapshot, registry) do
    with {:ok, _} <- require_map(snapshot, "$"),
         :ok <- require_schema(snapshot, "komki-snapshot/1"),
         :ok <- closed_fields(snapshot, @snapshot_fields, "$"),
         :ok <- require_kebab(snapshot["snapshot_id"], "$.snapshot_id"),
         :ok <- require_registry_ref(snapshot, registry),
         :ok <- require_identity(snapshot, registry),
         {:ok, workspace} <- validate_workspace(snapshot["workspace"], registry),
         {:ok, object} <- validate_object(snapshot["object"], registry),
         :ok <- validate_facts(snapshot["facts"], registry) do
      {:ok,
       %{
         registry_id: registry.registry_id,
         snapshot_id: snapshot["snapshot_id"],
         identity: snapshot["identity"],
         workspace: workspace,
         object: object,
         facts: Map.fetch!(snapshot, "facts")
       }}
    end
  end

  # =========================================================================
  # Kohärenz (§ 2.3)
  # =========================================================================

  @doc "Intent-Referenzen müssen exakt dem Snapshot entsprechen."
  @spec ensure_coherence(ctx(), auth()) :: :ok | {:error, error()}
  def ensure_coherence(ctx, auth) do
    object_ref = ctx.object["object_id"] <> "@" <> ctx.object["version"]

    with :ok <- require_equal_workspace(auth.workspace, ctx.workspace["workspace_id"]) do
      require_equal_object(auth.object_ref, object_ref)
    end
  end

  defp require_equal_workspace(expected, actual) when expected == actual, do: :ok

  defp require_equal_workspace(expected, actual) do
    fail(
      :intent_snapshot_mismatch,
      "$.workspace",
      "intent workspace " <>
        Kernel.inspect(expected) <>
        " does not match snapshot workspace " <> Kernel.inspect(actual)
    )
  end

  defp require_equal_object(expected, actual) when expected == actual, do: :ok

  defp require_equal_object(expected, actual) do
    fail(
      :intent_snapshot_mismatch,
      "$.object",
      "intent object " <>
        Kernel.inspect(expected) <> " does not match snapshot object " <> Kernel.inspect(actual)
    )
  end

  defp fail(code, path, detail), do: {:error, {code, path, detail}}

  defp require_map(%{} = map, _path), do: {:ok, map}

  defp require_map(other, path),
    do: fail(:invalid_record, path, "expected an object, got " <> Kernel.inspect(other))

  defp require_schema(%{"schema" => schema} = _term, schema), do: :ok

  defp require_schema(term, schema),
    do:
      fail(
        :invalid_schema,
        "$.schema",
        "expected " <> schema <> ", got " <> Kernel.inspect(term["schema"])
      )

  defp closed_fields(map, allowed, path) do
    unknown = Enum.sort(Enum.reject(Map.keys(map), &(&1 in allowed)))

    case unknown do
      [] ->
        :ok

      [first | _] ->
        fail(:unknown_field, path <> "." <> first, "field not part of the closed schema")
    end
  end

  defp require_kebab(value, path) do
    if Registry.kebab_id?(value) do
      :ok
    else
      fail(:invalid_reference_id, path, "expected kebab-case id, got " <> Kernel.inspect(value))
    end
  end

  defp require_object_ref(value, path) do
    if object_ref_ok?(value) do
      :ok
    else
      fail(
        :invalid_reference_id,
        path,
        "expected <object_id>@<version>, got " <> Kernel.inspect(value)
      )
    end
  end

  defp object_ref_ok?(value) when is_binary(value) do
    case String.split(value, "@") do
      [object_id, version] -> Registry.kebab_id?(object_id) and Registry.kebab_id?(version)
      _ -> false
    end
  end

  defp object_ref_ok?(_other), do: false

  defp require_operation(operation) do
    if operation in @known_operations do
      :ok
    else
      fail(:invalid_operation, "$.operation", "unknown operation: " <> Kernel.inspect(operation))
    end
  end

  defp require_registry_ref(snapshot, registry) do
    if snapshot["registry_ref"] == registry.registry_id do
      :ok
    else
      fail(
        :registry_ref_mismatch,
        "$.registry_ref",
        "expected " <>
          registry.registry_id <> ", got " <> Kernel.inspect(snapshot["registry_ref"])
      )
    end
  end

  defp require_identity(snapshot, registry) do
    if snapshot["identity"] in registry.observers do
      :ok
    else
      fail(:unknown_observer, "$.identity", "identity not in the registry observer set")
    end
  end

  defp validate_workspace(ws, registry) do
    path = "$.workspace"

    with {:ok, _} <- require_map(ws, path),
         :ok <- closed_fields(ws, @workspace_fields, path),
         :ok <- require_kebab(ws["workspace_id"], path <> ".workspace_id"),
         :ok <- require_boolean(ws["valid"], path <> ".valid"),
         :ok <-
           member_of_registry(
             ws["bindings"],
             Map.keys(registry.bindings),
             path <> ".bindings",
             :unknown_binding_reference
           ),
         :ok <- require_environment(ws["environment"], registry) do
      {:ok, ws}
    end
  end

  defp require_environment(env_id, registry) do
    if Map.has_key?(registry.environments, env_id) do
      :ok
    else
      fail(
        :unknown_environment,
        "$.workspace.environment",
        "unknown environment: " <> Kernel.inspect(env_id)
      )
    end
  end

  defp validate_object(obj, registry) do
    path = "$.object"

    with {:ok, _} <- require_map(obj, path),
         :ok <- closed_fields(obj, @object_fields, path),
         :ok <- require_kebab(obj["object_id"], path <> ".object_id"),
         :ok <- require_kebab(obj["version"], path <> ".version"),
         :ok <- require_classification(obj, path),
         :ok <-
           member_of_registry(
             obj["labels"],
             Map.keys(registry.bindings),
             path <> ".labels",
             :unknown_binding_reference
           ) do
      {:ok, obj}
    end
  end

  defp require_classification(obj, path) do
    if obj["classification"] in @classifications do
      :ok
    else
      fail(
        :invalid_classification,
        path <> ".classification",
        "expected \"classified\" or \"quarantine\""
      )
    end
  end

  defp validate_facts(facts, registry) do
    case require_map(facts, "$.facts") do
      {:ok, _} -> validate_fact_entries(Map.to_list(facts), registry)
      {:error, reason} -> reason_to_finding(reason)
    end
  end

  defp reason_to_finding({code, path, detail}), do: fail(code, path, detail)

  defp validate_fact_entries(entries, registry) do
    entries
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn {name, entry}, :ok ->
      case validate_fact_entry({name, entry}, registry) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_fact_entry({name, entry}, registry) do
    path = "$.facts." <> name

    with {:ok, _} <- require_map(entry, path),
         :ok <- closed_fields(entry, @fact_entry_fields, path),
         :ok <- known_fact_field?(name, registry, path),
         :ok <- require_source(entry, path),
         :ok <- require_source_kind(entry, path) do
      require_fact_value(entry, name, registry, path)
    end
  end

  defp known_fact_field?(name, registry, path) do
    if Map.has_key?(registry.fact_fields, name) or name in @basis_facts do
      :ok
    else
      fail(:unknown_fact_field, path, "not a declared or basis fact: " <> name)
    end
  end

  defp require_source(entry, path) do
    if is_binary(entry["source"]) do
      :ok
    else
      fail(:invalid_source, path <> ".source", "expected a free-text source designation")
    end
  end

  defp require_source_kind(entry, path) do
    if entry["source_kind"] in @source_kinds do
      :ok
    else
      fail(
        :invalid_source_kind,
        path <> ".source_kind",
        "expected one of " <> Kernel.inspect(@source_kinds)
      )
    end
  end

  defp require_fact_value(entry, name, registry, path) do
    # Vertrags-Pin: Basisfakten sind boolesch; eine Registry-Redeclaration
    # desselben Namens in fact_fields darf den Typ nicht überschreiben (§ 4.2).
    type =
      if name in @basis_facts do
        "boolean"
      else
        Map.get(registry.fact_fields, name) || "boolean"
      end

    if fact_value_ok?(type, entry["value"]) do
      :ok
    else
      fail(:invalid_fact_value, path <> ".value", "value does not match fact type " <> type)
    end
  end

  defp fact_value_ok?("string", value), do: is_binary(value)
  defp fact_value_ok?("boolean", value), do: is_boolean(value)
  defp fact_value_ok?("integer", value), do: is_integer(value)
  defp fact_value_ok?("string_set", value), do: is_list(value) and Enum.all?(value, &is_binary/1)

  defp require_boolean(value, path) do
    if is_boolean(value) do
      :ok
    else
      fail(:invalid_flag, path, "expected a boolean, got " <> Kernel.inspect(value))
    end
  end

  defp sorted_unique_refs?(list) do
    is_list(list) and length(list) == length(Enum.uniq(list)) and list == Enum.sort(list)
  end

  defp require_strings(list, path) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      :ok
    else
      fail(:invalid_reference_list, path, "expected only strings")
    end
  end

  defp require_strings(_other, path),
    do: fail(:invalid_reference_list, path, "expected an array of strings")

  defp member_of_registry(ids, against, path, code) do
    with :ok <- require_strings(ids, path),
         :ok <- require_sorted_unique(ids, path) do
      case Enum.reject(ids, &(&1 in against)) do
        [] -> :ok
        [first | _] -> fail(code, path, "unknown reference: " <> first)
      end
    end
  end

  defp require_sorted_unique(list, path) do
    if sorted_unique_refs?(list) do
      :ok
    else
      fail(:unsorted_references, path, "expected a sorted, duplicate-free reference list")
    end
  end
end
