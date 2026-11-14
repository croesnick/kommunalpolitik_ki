defmodule Sidecar.Params do
  @moduledoc """
  Validation of operation parameters against a closed schema: unknown
  fields are an error, so are missing required ones; optional fields
  get their default. Field shape:

      %{type: :string, max: 200, required: true, pattern: ~r/.../}
      %{type: :integer, min: 1, max: 20, required: false, default: 10}
      %{type: :list, min_items: 1, max_items: 8, items: %{...}}

  A `:list` field holds closed objects (Durchstich #409: one proposal
  with parts). `items` is a schema of the same string/integer fields,
  applied to every element; unknown keys inside an element are an error.
  Error texts come from the `texts` module (`Sidecar.Texts` by
  default), so a host can surface validation errors in its own
  language.
  """

  alias Sidecar.Texts

  @type field_spec :: %{required(:type) => :string | :integer | :list, optional(atom()) => term()}
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

  # A closed list of objects (Durchstich #409): every element is checked
  # against the same `items` schema, unknown keys inside an element are an
  # error. Item fields reuse the string/integer clauses, so blank and
  # pattern rules hold per element. Errors name the element, e.g.
  # "teile[2].quelle", so the caller can point at the part that failed.
  defp field(name, %{type: :list} = spec, {:ok, value}, texts) when is_list(value) do
    items = Map.get(spec, :items, %{})
    min_items = Map.get(spec, :min_items, 1)
    max_items = Map.get(spec, :max_items, 8)

    cond do
      length(value) > max_items ->
        fail(texts.params_error(:too_many_items, %{name: name, max: max_items}))

      length(value) < min_items ->
        fail(texts.params_error(:too_few_items, %{name: name, min: min_items}))

      true ->
        check_items(name, items, value, texts)
    end
  end

  # Any other value against any other type (also a non-list against
  # :list): wrong type, before defaults or patterns apply.
  defp field(name, %{type: type}, {:ok, _value}, texts),
    do: fail(texts.params_error(:wrong_type, %{name: name, type: type}))

  defp check_items(name, items, values, texts) do
    values
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, acc} ->
      case item(name, index, items, value, texts) do
        {:ok, checked} -> {:cont, {:ok, acc ++ [checked]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  defp item(name, index, items, value, texts) do
    if is_map(value) do
      unknown = Map.keys(value) -- Map.keys(items)

      if unknown != [] do
        fail(
          texts.params_error(:item_unknown_fields, %{name: "#{name}[#{index}]", names: unknown})
        )
      else
        item_fields(name, index, items, value, texts)
      end
    else
      fail(texts.params_error(:item_not_object, %{name: "#{name}[#{index}]"}))
    end
  end

  defp item_fields(name, index, items, value, texts) do
    items
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, fn {key, spec}, {:ok, acc} ->
      case field("#{name}[#{index}].#{key}", spec, Map.fetch(value, key), texts) do
        {:ok, :absent} -> {:cont, {:ok, acc}}
        {:ok, checked} -> {:cont, {:ok, Map.put(acc, key, checked)}}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  defp fail(detail), do: {:error, {:params, detail}}
end
