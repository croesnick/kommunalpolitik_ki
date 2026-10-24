defmodule KomkiConnector.Params do
  @moduledoc """
  Pruefung von Operations-Parametern gegen ein geschlossenes
  Manifest-Schema (CONTRACT.md §5): unbekannte Felder sind ein Fehler,
  fehlende Pflichtfelder auch; optionale Felder bekommen ihren Default.

  Schema-Form je Feld:

      %{type: :string, max: 200, required: true, pattern: ~r/.../}
      %{type: :integer, min: 1, max: 20, required: false, default: 10}
  """

  @type field_spec :: %{required(:type) => :string | :integer, optional(atom()) => term()}
  @type schema :: %{String.t() => field_spec()}

  @doc "Prueft `params` gegen `schema`; liefert die normalisierten Parameter."
  @spec check(schema(), map()) :: {:ok, map()} | {:error, {:params, String.t()}}
  def check(schema, params) when is_map(schema) and is_map(params) do
    unknown = Map.keys(params) -- Map.keys(schema)

    if unknown != [] do
      fail("unbekannte Felder: #{Enum.join(Enum.sort(unknown), ", ")}")
    else
      schema |> Enum.sort() |> Enum.reduce_while({:ok, %{}}, &step(&1, &2, params))
    end
  end

  def check(_schema, _params), do: fail("Parameter muessen ein Objekt sein")

  defp step({name, spec}, {:ok, acc}, params) do
    case field(name, spec, Map.fetch(params, name)) do
      {:ok, :absent} -> {:cont, {:ok, acc}}
      {:ok, value} -> {:cont, {:ok, Map.put(acc, name, value)}}
      {:error, _} = e -> {:halt, e}
    end
  end

  defp field(name, spec, :error) do
    cond do
      Map.get(spec, :required, true) -> fail("Pflichtfeld fehlt: #{name}")
      Map.has_key?(spec, :default) -> {:ok, spec.default}
      true -> {:ok, :absent}
    end
  end

  defp field(name, %{type: :string} = spec, {:ok, value}) when is_binary(value) do
    cond do
      not String.valid?(value) ->
        fail("#{name}: kein gueltiges UTF-8")

      String.length(value) > Map.get(spec, :max, 1000) ->
        fail("#{name}: laenger als #{spec.max} Zeichen")

      String.trim(value) == "" and Map.get(spec, :required, true) ->
        fail("#{name}: leer")

      spec[:pattern] && not Regex.match?(spec.pattern, value) ->
        fail("#{name}: unzulaessiges Format")

      true ->
        {:ok, value}
    end
  end

  defp field(name, %{type: :integer} = spec, {:ok, value}) when is_integer(value) do
    if value < Map.get(spec, :min, value) or value > Map.get(spec, :max, value),
      do: fail("#{name}: ausserhalb #{spec[:min]}..#{spec[:max]}"),
      else: {:ok, value}
  end

  defp field(name, %{type: type}, {:ok, _value}), do: fail("#{name}: erwartet #{type}")

  defp fail(detail), do: {:error, {:params, detail}}
end
