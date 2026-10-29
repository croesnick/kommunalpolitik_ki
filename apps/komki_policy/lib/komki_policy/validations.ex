defmodule KomkiPolicy.Validations do
  @moduledoc """
  Geteilte Schema-Bausteine für die Datensatz-Validierer (CONTRACT.md § 2).

  `Release`, `Stand`, `Context`, `Verify` und `Registry` prüfen geschlossene,
  versionierte Schemas mit denselben Grundformen: Objekt-Form, geschlossene
  Feldmenge, Schema-String, Kebab- und `<object_id>@<version>`-Kennungen
  sowie nicht-negative Ganzzahl-Fenster. Die Grundformen existieren genau
  einmal hier; die Fehler bleiben Reason-Tupel `{code, path, detail}` in der
  Form, die die Aufrufer in ihre strukturierten Fehler-Maps verpacken.
  Modulspezifische Varianten bleiben bewusst lokal: `Context.require_schema/2`
  (zwei Schemas, eigene Fehlertexte) und `Verify.require_proof_schema/1`.
  """

  alias KomkiPolicy.Registry

  @hex_re ~r/\A[0-9a-f]{64}\z/

  @type reason() :: {atom(), String.t(), String.t()}

  @doc "Baut das Reason-Tupel im Fehlerfall (`{:error, {code, path, detail}}`)."
  @spec error(atom(), String.t(), String.t()) :: {:error, reason()}
  def error(code, path, detail), do: {:error, {code, path, detail}}

  @doc "Eingabe muss ein JSON-Objekt sein (`:invalid_record`)."
  @spec require_map(term(), String.t()) :: {:ok, map()} | {:error, reason()}
  def require_map(%{} = map, _path), do: {:ok, map}

  def require_map(other, path),
    do: error(:invalid_record, path, "expected an object, got " <> Kernel.inspect(other))

  @doc "Geschlossene Feldmenge: das erste unbekannte Feld ist der Befund (`:unknown_field`)."
  @spec closed_fields(map(), [String.t()], String.t()) :: :ok | {:error, reason()}
  def closed_fields(map, allowed, path) do
    case Enum.sort(Enum.reject(Map.keys(map), &(&1 in allowed))) do
      [] ->
        :ok

      [first | _] ->
        error(:unknown_field, path <> "." <> first, "field not part of the closed schema")
    end
  end

  @doc """
  Pflichtfeld `schema` muss exakt den erwarteten Vertragswert tragen. Der
  Fehlercode des fehlenden Felds ist Aufrufer-spezifisch: `:missing_field`
  (Release/Stand) bzw. `:invalid_schema` (Registry).
  """
  @spec require_schema(term(), String.t(), atom()) :: :ok | {:error, reason()}
  def require_schema(%{"schema" => schema}, schema, _missing_code), do: :ok

  def require_schema(%{"schema" => other}, schema, _missing_code),
    do:
      error(
        :invalid_schema,
        "$.schema",
        "expected \"" <> schema <> "\", got " <> Kernel.inspect(other)
      )

  def require_schema(_term, _schema, missing_code),
    do: error(missing_code, "$.schema", "missing field \"schema\"")

  @doc "Kebab-Case-Kennung wie `registry_id` (§ 2.1)."
  @spec require_kebab(term(), String.t()) :: :ok | {:error, reason()}
  def require_kebab(value, path) do
    if is_binary(value) and Registry.kebab_id?(value) do
      :ok
    else
      error(:invalid_reference_id, path, "expected kebab-case id, got " <> Kernel.inspect(value))
    end
  end

  @doc "Objektreferenz in der Form `<object_id>@<version>` (§ 2.2, § 2.3)."
  @spec require_object_ref(term(), String.t()) :: :ok | {:error, reason()}
  def require_object_ref(value, path) do
    if object_ref?(value) do
      :ok
    else
      error(
        :invalid_reference_id,
        path,
        "expected <object_id>@<version>, got " <> Kernel.inspect(value)
      )
    end
  end

  defp object_ref?(value) when is_binary(value) do
    case String.split(value, "@") do
      [object_id, version] -> Registry.kebab_id?(object_id) and Registry.kebab_id?(version)
      _ -> false
    end
  end

  defp object_ref?(_other), do: false

  @doc "Geschlossene Operationsmenge; der Wert muss ihr angehören."
  @spec require_operation(term(), [String.t()]) :: :ok | {:error, reason()}
  def require_operation(value, known) do
    if value in known do
      :ok
    else
      error(:invalid_operation, "$.operation", "unknown operation: " <> Kernel.inspect(value))
    end
  end

  @doc "SHA-256-Hex (64 Stellen, kleingeschrieben); der Fehlercode ist Aufrufer-spezifisch."
  @spec require_hex64(term(), String.t(), atom()) :: :ok | {:error, reason()}
  def require_hex64(value, path, code) do
    if is_binary(value) and Regex.match?(@hex_re, value) do
      :ok
    else
      error(
        code,
        path,
        "expected a lowercase sha256 hex string (64 hex digits), got " <> Kernel.inspect(value)
      )
    end
  end

  @doc "Nicht-negative Ganzzahl; der Fehlercode ist Aufrufer-spezifisch."
  @spec require_nonneg_integer(term(), String.t(), atom()) :: :ok | {:error, reason()}
  def require_nonneg_integer(value, _path, _code) when is_integer(value) and value >= 0, do: :ok

  def require_nonneg_integer(value, path, code),
    do: error(code, path, "expected a non-negative integer, got " <> Kernel.inspect(value))

  @doc "Beliebige Ganzzahl; der Fehlercode ist Aufrufer-spezifisch."
  @spec require_integer(term(), String.t(), atom()) :: :ok | {:error, reason()}
  def require_integer(value, _path, _code) when is_integer(value), do: :ok

  def require_integer(value, path, code),
    do: error(code, path, "expected an integer, got " <> Kernel.inspect(value))
end
