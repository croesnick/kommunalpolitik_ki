defmodule KomkiPolicy.Registry do
  @moduledoc """
  Registry-Compiler und -Validierer (CONTRACT.md § 2.1, § 3).

  Nimmt einen geparsten Registry-Term und validiert ihn als geschlossenes,
  versioniertes Schema `komki-registry/1`: geschlossene Feldmengen,
  Kennungsformate, Beobachterräume und die typgeprüfte Kompilierung aller
  Operations-Ausdrücke (B.4-Sprachumfang). Compile-Fehler sind Eingabefehler
  — die Sprachlücke wird nicht durch Annahmen verborgen.
  """

  @registry_fields [
    "schema",
    "registry_id",
    "observers",
    "fact_fields",
    "environments",
    "bindings"
  ]
  @binding_fields ["readers", "operations", "relaxation_authorities"]
  @environment_fields ["observers"]
  @fact_types ["string", "boolean", "integer", "string_set"]
  @known_operations ["start", "admit", "emit", "transfer", "store"]

  @kebab_re ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
  @ref_re ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*@(0|[1-9][0-9]*)\z/

  @type compiled :: %{
          required(:registry_id) => String.t(),
          required(:observers) => [String.t()],
          required(:fact_fields) => %{String.t() => String.t()},
          required(:environments) => %{String.t() => %{observers: [String.t()]}},
          required(:bindings) => %{String.t() => %{readers: [String.t()], operations: %{}}}
        }

  @type error() :: %{
          required(:code) => atom(),
          required(:path) => String.t(),
          required(:detail) => String.t()
        }

  @type reason :: {atom(), String.t(), String.t()}

  @spec compile(term()) :: {:ok, compiled()} | {:error, error()}
  def compile(term) when is_map(term) do
    case validate(term) do
      {:ok, parts} -> {:ok, build_compiled(parts)}
      {:error, reason} -> wrap_reason(reason)
    end
  end

  def compile(term) do
    wrap_reason({:invalid_record, "$", "expected an object, got " <> Kernel.inspect(term)})
  end

  @spec kebab_id?(term()) :: boolean()
  def kebab_id?(value), do: is_binary(value) and Regex.match?(@kebab_re, value)

  @spec reference_id?(term()) :: boolean()
  def reference_id?(value), do: is_binary(value) and Regex.match?(@ref_re, value)

  # ---------------------------------------------------------------------
  # Kernvalidierung
  # ---------------------------------------------------------------------

  defp validate(term) do
    with :ok <- require_schema(term),
         :ok <- closed_fields(term, @registry_fields, "$"),
         :ok <- validate_registry_id(term),
         {:ok, observers} <- validate_observers(term),
         {:ok, fact_fields} <- validate_fact_fields(term),
         {:ok, environments} <- validate_environments(term, observers),
         {:ok, bindings} <- validate_bindings(term, fact_fields, observers) do
      {:ok,
       %{
         registry_id: term["registry_id"],
         observers: Enum.sort(observers),
         fact_fields: fact_fields,
         environments: environments,
         bindings: bindings
       }}
    end
  end

  defp wrap_reason({code, path, detail}), do: {:error, %{code: code, path: path, detail: detail}}

  defp fail(code, path, detail), do: {:error, {code, path, detail}}

  defp require_schema(%{"schema" => "komki-registry/1"}), do: :ok

  defp require_schema(%{"schema" => other}),
    do: fail(:invalid_schema, "$.schema", "expected \"komki-registry/1\", got " <> inspect(other))

  defp require_schema(_term), do: fail(:invalid_schema, "$.schema", "missing field \"schema\"")

  defp closed_fields(map, allowed, path) do
    unknown = Enum.reject(Map.keys(map), fn key -> key in allowed end)

    case Enum.sort(unknown) do
      [] ->
        :ok

      [first | _] ->
        fail(:unknown_field, path <> "." <> first, "field not part of the closed schema")
    end
  end

  defp validate_registry_id(term) do
    if kebab_id?(term["registry_id"]) do
      :ok
    else
      fail(
        :invalid_registry_id,
        "$.registry_id",
        "expected kebab-case id, got " <> inspect(term["registry_id"])
      )
    end
  end

  defp validate_observers(term) do
    observers = term["observers"]
    path = "$.observers"

    with :ok <- nonempty_unique_strings(observers, path),
         :ok <- kebab_strings(observers, path) do
      {:ok, observers}
    end
  end

  defp validate_fact_fields(term) do
    fact_fields = term["fact_fields"]

    if is_map(fact_fields) and Enum.all?(Map.values(fact_fields), &(&1 in @fact_types)) do
      {:ok, fact_fields}
    else
      fail(
        :invalid_fact_type,
        "$.fact_fields",
        "expected a map with types in " <> inspect(@fact_types)
      )
    end
  end

  defp validate_environments(term, observers) do
    env_path = "$.environments"

    case term["environments"] do
      %{} = envs when map_size(envs) > 0 ->
        collect_environments(envs, observers, env_path)

      _ ->
        fail(:no_environments, env_path, "expected at least one environment")
    end
  end

  defp collect_environments(envs, observers, path) do
    entries = envs |> Map.to_list() |> Enum.sort()

    Enum.reduce_while(entries, {:ok, %{}}, fn {id, spec}, {:ok, acc} ->
      result = check_and_build_environment(id, spec, observers, path)

      case result do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, id, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp check_and_build_environment(id, spec, observers, path) do
    with :ok <- require_reference_id(id, path) do
      environment_part(spec, observers, path <> "." <> id)
    end
  end

  defp require_reference_id(id, path) do
    if reference_id?(id) do
      :ok
    else
      {:error,
       {:invalid_reference_id, path,
        "expected <kebab>@<non-negative-integer>, got " <> Kernel.inspect(id)}}
    end
  end

  defp environment_part(spec, observers, path) do
    with {:ok, _} <- require_map(spec, path),
         :ok <- closed_fields(spec, @environment_fields, path),
         :ok <- subset_observers(spec["observers"], observers, path <> ".observers") do
      {:ok, %{observers: Enum.sort(spec["observers"])}}
    else
      {:error, reason} -> reject_reason(reason)
    end
  end

  defp reject_reason(reason), do: {:error, reason}

  defp subset_observers(list, observers, path) do
    with :ok <- nonempty_unique_strings(list, path),
         :ok <- kebab_strings(list, path) do
      unknown = Enum.reject(list, &(&1 in observers))

      case unknown do
        [] ->
          :ok

        [first | _] ->
          fail(:unknown_observer, path, "observer not in the registry observer set: " <> first)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------
  # Bindungen
  # ---------------------------------------------------------------------

  defp validate_bindings(term, fact_fields, observers) do
    binding_path = "$.bindings"

    case term["bindings"] do
      %{} = bindings when map_size(bindings) > 0 ->
        collect_bindings(bindings, fact_fields, observers, binding_path)

      _ ->
        fail(:no_bindings, binding_path, "expected at least one binding")
    end
  end

  defp collect_bindings(bindings, fact_fields, observers, path) do
    entries = bindings |> Map.to_list() |> Enum.sort()

    Enum.reduce_while(entries, {:ok, %{}}, fn {id, spec}, {:ok, acc} ->
      result = check_and_build_binding(id, spec, fact_fields, observers, path)

      case result do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, id, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp check_and_build_binding(id, spec, fact_fields, observers, path) do
    with :ok <- require_reference_id(id, path) do
      binding_part(spec, fact_fields, observers, path <> "." <> id)
    end
  end

  defp binding_part(spec, fact_fields, observers, path) do
    with {:ok, _} <- require_map(spec, path),
         :ok <- closed_fields(spec, @binding_fields, path),
         :ok <- subset_observers(spec["readers"], observers, path <> ".readers"),
         :ok <- relaxations_list?(spec["relaxation_authorities"], path),
         {:ok, operations} <- validate_operations(spec["operations"], fact_fields, path) do
      {:ok, %{readers: Enum.sort(spec["readers"]), operations: operations}}
    else
      {:error, reason} -> reject_reason(reason)
    end
  end

  defp relaxations_list?(value, path) do
    if is_list(value) do
      :ok
    else
      fail(
        :invalid_relaxation_authorities,
        path <> ".relaxation_authorities",
        "expected an array"
      )
    end
  end

  defp validate_operations(operations, fact_fields, path) when is_map(operations) do
    unknown = operations |> Map.keys() |> Enum.reject(&(&1 in @known_operations))

    case Enum.sort(unknown) do
      [] ->
        collect_operations(operations, fact_fields, path <> ".operations")

      [first | _] ->
        fail(
          :unknown_operation,
          path <> ".operations." <> first,
          "operation not in the closed operation set"
        )
    end
  end

  defp validate_operations(_other, _fact_fields, path),
    do: fail(:invalid_operations, path <> ".operations", "expected an object")

  defp collect_operations(operations, fact_fields, path) do
    entries = operations |> Map.to_list() |> Enum.sort()

    Enum.reduce_while(entries, {:ok, %{}}, fn {name, expr}, {:ok, acc} ->
      case compile_expression(expr, fact_fields, path <> "." <> name) do
        :ok -> {:cont, {:ok, Map.put(acc, name, expr)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_compiled(parts) do
    %{
      registry_id: parts.registry_id,
      observers: parts.observers,
      fact_fields: parts.fact_fields,
      environments: parts.environments,
      bindings: parts.bindings
    }
  end

  # ---------------------------------------------------------------------
  # Zeichenketten-/Listenprüfungen
  # ---------------------------------------------------------------------

  defp require_map(%{} = map, _path), do: {:ok, map}

  defp require_map(other, path),
    do: fail(:invalid_record, path, "expected an object, got " <> inspect(other))

  defp nonempty_unique_strings(list, path) when is_list(list) do
    uniq = Enum.uniq(list)

    with :ok <- require_nonempty(list, path),
         :ok <- all_strings?(list, path),
         :ok <- require_unique(list, uniq, path) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp nonempty_unique_strings(_other, path),
    do: fail(:invalid_observers, path, "expected a non-empty array of strings")

  defp require_nonempty([], path), do: fail(:empty_list, path, "must not be empty")
  defp require_nonempty(_list, _path), do: :ok

  defp all_strings?(list, path) do
    if Enum.all?(list, &is_binary/1) do
      :ok
    else
      fail(:invalid_entry, path, "expected only strings")
    end
  end

  defp require_unique(list, uniq, path) do
    if length(list) == length(uniq) do
      :ok
    else
      [dup | _] = list -- uniq
      fail(:duplicate_entry, path, "duplicate entry: " <> dup)
    end
  end

  defp kebab_strings(list, path) do
    case Enum.reject(list, &kebab_id?/1) do
      [] -> :ok
      [first | _] -> fail(:invalid_entry, path, "not a kebab-case id: " <> Kernel.inspect(first))
    end
  end

  # ---------------------------------------------------------------------
  # Ausdrucks-Compile (B.4-Grammatik, exakt ein Schlüssel je Ausdrucksobjekt)
  # ---------------------------------------------------------------------

  defp compile_expression(expr, _fact_fields, _path) when is_boolean(expr), do: :ok

  defp compile_expression(%{} = expr, fact_fields, path) do
    case Map.keys(expr) do
      [key] ->
        compile_form(key, Map.fetch!(expr, key), fact_fields, path)

      _ ->
        fail(
          :unsupported_expression,
          path,
          "expression object must have exactly one key, got " <> Kernel.inspect(Map.keys(expr))
        )
    end
  end

  defp compile_expression(other, _fact_fields, path) do
    fail(:unsupported_expression, path, "unsupported expression shape: " <> Kernel.inspect(other))
  end

  defp compile_form(key, value, fact_fields, path)
       when key in ["all", "any"] and is_list(value) do
    sub_paths =
      value
      |> Enum.with_index()
      |> Enum.map(fn {_expr, i} -> path <> ".[" <> Integer.to_string(i) <> "]" end)

    sub_paths
    |> Enum.zip(value)
    |> Enum.reduce_while(:ok, fn {sub_path, sub_expr}, :ok ->
      case compile_expression(sub_expr, fact_fields, sub_path) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp compile_form(key, _value, _fact_fields, path) when key in ["all", "any"] do
    fail(:unsupported_expression, path, "expected an array of expressions for " <> key)
  end

  defp compile_form("eq", [field, literal], fact_fields, path) do
    compile_clause("eq", field, literal, fact_fields, path)
  end

  defp compile_form("eq", _value, _fact_fields, path) do
    fail(:unsupported_expression, path, "eq expects [field, literal]")
  end

  defp compile_form("member", [field, literals], fact_fields, path) do
    compile_clause("member", field, literals, fact_fields, path)
  end

  defp compile_form("member", _value, _fact_fields, path) do
    fail(:unsupported_expression, path, "member expects [field, [literal, ...]]")
  end

  defp compile_form("subset", [field, literals], fact_fields, path) do
    compile_clause("subset", field, literals, fact_fields, path)
  end

  defp compile_form("subset", _value, _fact_fields, path) do
    fail(:unsupported_expression, path, "subset expects [field, [literal, ...]]")
  end

  defp compile_form("at_most", [field, bound], fact_fields, path) do
    compile_clause("at_most", field, bound, fact_fields, path)
  end

  defp compile_form("at_most", _value, _fact_fields, path) do
    fail(:unsupported_expression, path, "at_most expects [field, integer]")
  end

  defp compile_form(key, _value, _fact_fields, path) do
    fail(:unsupported_expression, path, "unknown expression key: " <> Kernel.inspect(key))
  end

  defp compile_clause(op, field, literal, fact_fields, path)
       when op in ["eq", "member", "subset", "at_most"] and is_binary(field) do
    with :ok <- declared_field?(field, fact_fields, path),
         :ok <- op_type_check(op, field, literal, fact_fields, path) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp compile_clause(_op, field, _literal, _fact_fields, path) do
    fail(:unsupported_expression, path, "field must be a string, got " <> Kernel.inspect(field))
  end

  defp declared_field?(field, fact_fields, path) do
    if Map.has_key?(fact_fields, field) do
      :ok
    else
      fail(:unknown_fact_field, path <> " field", "field not declared in fact_fields: " <> field)
    end
  end

  defp op_type_check("eq", field, literal, fact_fields, path) do
    if type_compatible?(fact_fields[field], literal) do
      :ok
    else
      fail(:expression_type_mismatch, path, "literal type does not match field " <> field)
    end
  end

  defp op_type_check("member", field, literals, fact_fields, path) do
    if is_list(literals) and Enum.all?(literals, &type_compatible?(fact_fields[field], &1)) do
      :ok
    else
      fail(:expression_type_mismatch, path, "member literals must match field type " <> field)
    end
  end

  defp op_type_check("subset", field, literals, fact_fields, path) do
    if fact_fields[field] == "string_set" and is_list(literals) and
         Enum.all?(literals, &is_binary/1) do
      :ok
    else
      fail(
        :expression_type_mismatch,
        path,
        "subset needs a string_set field and string literals, field: " <> field
      )
    end
  end

  defp op_type_check("at_most", field, bound, fact_fields, path) do
    if fact_fields[field] == "integer" and is_integer(bound) and bound >= 0 do
      :ok
    else
      fail(
        :expression_type_mismatch,
        path,
        "at_most needs an integer field and a non-negative bound, field: " <> field
      )
    end
  end

  defp type_compatible?("string", literal), do: is_binary(literal)
  defp type_compatible?("boolean", literal), do: is_boolean(literal)
  defp type_compatible?("integer", literal), do: is_integer(literal)
  defp type_compatible?("string_set", _literal), do: false
  defp type_compatible?(_type, _literal), do: false

  # ------------------------------------------------------------------
  # Öffentlicher Helfer: im Ausdruck referenzierte Feldnamen (sortiert, eindeutig)
  # ------------------------------------------------------------------

  @spec expression_fact_refs(term()) :: [String.t()]
  def expression_fact_refs(expr) do
    refs = raw_fact_refs(expr)
    Enum.sort(Enum.uniq(refs))
  end

  defp raw_fact_refs(expr) when is_boolean(expr), do: []

  defp raw_fact_refs(%{} = expr) do
    case Map.keys(expr) do
      [key] -> field_refs(key, Map.fetch!(expr, key))
      _ -> []
    end
  end

  defp raw_fact_refs(_other), do: []

  defp field_refs(key, []) when key in ["all", "any"], do: []

  defp field_refs(key, clauses) when key in ["all", "any"],
    do: List.flatten(Enum.map(clauses, &expression_fact_refs/1))

  defp field_refs(key, [field | _]) when key in ["eq", "member", "subset", "at_most"], do: [field]

  defp field_refs(_key, clauses) when is_list(clauses), do: []

  defp field_refs(_key, _value), do: []
end
