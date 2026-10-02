defmodule KomkiPolicy.Evaluator do
  @moduledoc """
  Dreiwertiger Auswerter der B.4-Prädikatsausdrücke (CONTRACT.md § 3).

  Er erhält ausschließlich `(expression, facts)`: kein Prüflabel, kein
  Bindungskontext, keine anderen Bindungen (Monotonie, RFC 5.2). Ein
  fehlender Fakt ergibt `unknown` — niemals einen Default. Die Verknüpfungen
  folgen der festgelegten dreiwertigen Logik: bekanntes `false` schlägt in
  `all` das Unknown, bekanntes `true` in `any`; leere `all` → `true`,
  leere `any` → `false`.

  Der Auswerter nimmt nur *kompiliert-erlaubte* Ausdrücke an (siehe
  `KomkiPolicy.Registry`); unbekannte Formen werfen einen `ArgumentError`,
  da sie die Registry-Compile-Grenze nie überleben.
  """

  @type verdict() :: true | false | :unknown
  @type fact_map() :: %{String.t() => %{required(:value) => term()}}

  @spec evaluate(term(), fact_map()) :: verdict()
  def evaluate(expr, facts)

  def evaluate(true, _facts), do: true
  def evaluate(false, _facts), do: false

  def evaluate(%{"all" => clauses}, facts), do: all_verdict(clauses, facts)
  def evaluate(%{"any" => clauses}, facts), do: any_verdict(clauses, facts)
  def evaluate(%{"eq" => [field, literal]}, facts), do: compare(field, facts, literal)

  def evaluate(%{"member" => [field, literals]}, facts) do
    member_verdict(field, facts, literals)
  end

  def evaluate(%{"subset" => [field, literals]}, facts) do
    subset_verdict(field, facts, literals)
  end

  def evaluate(%{"at_most" => [field, bound]}, facts) do
    at_most_verdict(field, facts, bound)
  end

  def evaluate(other, _facts) do
    raise ArgumentError,
          "unsupported expression beyond the compile-checked language: #{Kernel.inspect(other)}"
  end

  defp compare(field, facts, literal) do
    case fact_value(facts, field) do
      :missing -> :unknown
      {:present, value} -> boolean_verdict(value == literal)
    end
  end

  defp member_verdict(field, facts, literals) do
    case fact_value(facts, field) do
      :missing -> :unknown
      {:present, value} -> boolean_verdict(value in literals)
    end
  end

  defp subset_verdict(field, facts, literals) do
    case fact_value(facts, field) do
      :missing -> :unknown
      {:present, value} -> boolean_verdict(Enum.all?(list_of(value), &(&1 in literals)))
    end
  end

  defp at_most_verdict(field, facts, bound) do
    case fact_value(facts, field) do
      :missing -> :unknown
      {:present, value} -> boolean_verdict(value <= bound)
    end
  end

  defp list_of(value) when is_list(value), do: value

  defp boolean_verdict(true), do: true
  defp boolean_verdict(false), do: false

  defp all_verdict(clauses, facts) do
    verdicts = Enum.map(clauses, &evaluate(&1, facts))

    cond do
      verdicts == [] -> true
      false in verdicts -> false
      :unknown in verdicts -> :unknown
      true -> true
    end
  end

  defp any_verdict(clauses, facts) do
    verdicts = Enum.map(clauses, &evaluate(&1, facts))

    cond do
      verdicts == [] -> false
      true in verdicts -> true
      :unknown in verdicts -> :unknown
      true -> false
    end
  end

  defp fact_value(facts, field) do
    case Map.get(facts, field) do
      %{"value" => value} -> {:present, value}
      _ -> :missing
    end
  end
end
