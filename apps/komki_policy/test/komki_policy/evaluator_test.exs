defmodule KomkiPolicy.EvaluatorTest do
  use ExUnit.Case, async: true

  alias KomkiPolicy.Evaluator
  alias KomkiPolicy.JSON

  @expectations_file Path.expand(
                       "../../priv/fixtures/expressions/evaluate_expectations.json",
                       __DIR__
                     )

  @expectations @expectations_file
                |> File.read!()
                |> JSON.parse()
                |> elem(1)
                |> Map.fetch!("cases")

  defp apply_case(%{"expression" => expr, "facts" => facts}) do
    Evaluator.evaluate(expr, facts)
  end

  describe "Auswerter-Orakel (evaluate_expectations.json)" do
    test "alle 20 Orakelfaelle ergeben das erwartete dreiwertige Resultat" do
      assert length(@expectations) == 20

      Enum.with_index(@expectations, fn case, i ->
        verdict = apply_case(case)
        want = String.to_existing_atom(case["expected"])

        assert verdict == want,
               "expectation ##{i} diverges: #{case["expected"]} wanted, got #{verdict} (#{JSON.canonical(case)})"
      end)
    end
  end

  describe "Basissemantik" do
    test "leere all werden true, leere any false" do
      assert Evaluator.evaluate(%{"all" => []}, %{}) == true
      assert Evaluator.evaluate(%{"any" => []}, %{}) == false
    end

    test "bekannt falsch schlaegt Unknown; bekannt wahr schlaegt Unknown" do
      facts = %{"a" => %{"value" => true}, "b" => %{"value" => false}, "c" => %{"value" => true}}

      both = [
        %{"eq" => ["a", true]},
        %{"eq" => ["b", true]},
        %{"eq" => ["c", true]},
        %{"eq" => ["x", 1]}
      ]

      assert Evaluator.evaluate(%{"all" => both}, facts) == false
      assert Evaluator.evaluate(%{"any" => both}, facts) == true
    end

    test "fehlender Fakt ist unknown, kein Default" do
      assert Evaluator.evaluate(%{"eq" => ["x", true]}, %{}) == :unknown
    end

    test "Auswerter wirft bei Formen jenseits der B.4-Grammatik" do
      assert_raise ArgumentError, fn -> Evaluator.evaluate(%{"not" => [true]}, %{}) end
    end
  end
end
