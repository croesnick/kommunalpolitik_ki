defmodule Sidecar.Params do
  @moduledoc """
  Validation of operation parameters against a closed schema: unknown
  fields are an error, so are missing required ones; optional fields
  get their default. Field shape:

      %{type: :string, max: 200, required: true, pattern: ~r/.../}
      %{type: :integer, min: 1, max: 20, required: false, default: 10}

  Error texts come from the `texts` module (`Sidecar.Texts` by
  default), so a host can surface validation errors in its own
  language.
  """

  alias Sidecar.Texts

  @type field_spec :: %{required(:type) => :string | :integer, optional(atom()) => term()}
  @type schema :: %{String.t() => field_spec()}

  @doc """
  Checks `params` against `schema`; returns the normalized parameters.
  Error details are rendered by `texts` (default `Sidecar.Texts`).
  """
  @spec check(schema(), map(), module()) :: {:ok, map()} | {:error, {:params, String.t()}}
  def check(schema, params, texts \\ Texts)

  def check(schema, params, texts) when is_map(schema) and is_map(params) do
    unknown = Map.keys(params) -- Map.keys(schema)

    if unknown != [] do
      fail(texts.params_error(:unknown_fields, %{names: unknown}))
    else
      schema |> Enum.sort() |> Enum.reduce_while({:ok, %{}}, &step(&1, &2, params, texts))
    end
  end

  def check(_schema, _params, texts), do: fail(texts.params_error(:not_object, %{}))

  defp step({name, spec}, {:ok, acc}, params, texts) do
    case field(name, spec, Map.fetch(params, name), texts) do
      {:ok, :absent} -> {:cont, {:ok, acc}}
      {:ok, value} -> {:cont, {:ok, Map.put(acc, name, value)}}
      {:error, _} = e -> {:halt, e}
    end
  end

  defp field(name, spec, :error, texts) do
    cond do
      Map.get(spec, :required, true) -> fail(texts.params_error(:missing_required, %{name: name}))
      Map.has_key?(spec, :default) -> {:ok, spec.default}
      true -> {:ok, :absent}
    end
  end

  defp field(name, %{type: :string} = spec, {:ok, value}, texts) when is_binary(value) do
    max = Map.get(spec, :max, 1000)

    cond do
      not String.valid?(value) ->
        fail(texts.params_error(:invalid_utf8, %{name: name}))

      String.length(value) > max ->
        fail(texts.params_error(:too_long, %{name: name, max: max}))

      String.trim(value) == "" and Map.get(spec, :required, true) ->
        fail(texts.params_error(:blank, %{name: name}))

      spec[:pattern] && not Regex.match?(spec.pattern, value) ->
        fail(texts.params_error(:bad_format, %{name: name}))

      true ->
        {:ok, value}
    end
  end

  defp field(name, %{type: :integer} = spec, {:ok, value}, texts) when is_integer(value) do
    min = Map.get(spec, :min, value)
    max = Map.get(spec, :max, value)

    if value < min or value > max do
      fail(texts.params_error(:out_of_range, %{name: name, min: min, max: max}))
    else
      {:ok, value}
    end
  end

  defp field(name, %{type: type}, {:ok, _value}, texts),
    do: fail(texts.params_error(:wrong_type, %{name: name, type: type}))

  defp fail(detail), do: {:error, {:params, detail}}
end
