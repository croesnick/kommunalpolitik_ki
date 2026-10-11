defmodule KomkiPolicy.RegistryTest do
  use ExUnit.Case, async: true

  alias KomkiPolicy.{JSON, Registry}

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)

  defp fixture(path) do
    @fixtures_dir
    |> Path.join(path)
    |> File.read!()
    |> JSON.parse()
    |> elem(1)
  end

  defp compile_error(fixture_path) do
    term = fixture(fixture_path)

    case Registry.compile(term) do
      {:error, error} -> error
      {:ok, _} -> flunk("expected a compile error for #{fixture_path}")
    end
  end

  defp compile_term!(term) do
    case Registry.compile(term) do
      {:ok, compiled} -> compiled
      {:error, error} -> flunk("unexpected compile error: #{inspect(error)}")
    end
  end

  defp compile_term_error(term) do
    case Registry.compile(term) do
      {:error, error} -> error
      {:ok, _} -> flunk("expected a compile error")
    end
  end

  defp base_registry do
    %{
      "schema" => "komki-registry/1",
      "registry_id" => "reg-test",
      "observers" => ["carsten"],
      "fact_fields" => %{"purpose" => "string", "count" => "integer", "labels" => "string_set"},
      "environments" => %{"lokale@1" => %{"observers" => ["carsten"]}},
      "bindings" => %{
        "test@1" => %{
          "readers" => ["carsten"],
          "operations" => %{"admit" => true},
          "relaxation_authorities" => []
        }
      }
    }
  end

  describe "Registry-Orakel" do
    test "priv/fixtures/registry.json kompiliert" do
      compiled = compile_term!(fixture("registry.json"))

      assert compiled.registry_id == "reg-fall-4711-test"

      assert compiled.observers == [
               "carsten",
               "eigene-rz-analyse",
               "lokale-fallverarbeitung",
               "webdienst-x"
             ]

      assert Map.has_key?(compiled.fact_fields, "purpose")

      assert Map.keys(compiled.environments) == [
               "lokale-fallverarbeitung@1",
               "recherche-webdienst@1"
             ]

      assert Map.keys(compiled.bindings) == [
               "buergerfall-4711@1",
               "lizenz-namensnennung@1",
               "nur-start-test@1"
             ]
    end

    test "invalid/registry_unknown_field.json -> unknown_field (Bindungsebene)" do
      error = compile_error("invalid/registry_unknown_field.json")

      assert %{
               code: :unknown_field,
               path: "$.bindings.buergerfall-4711@1.beschreibung",
               detail: _
             } = error
    end

    test "invalid/registry_unknown_expression.json -> unsupported_expression" do
      error = compile_error("invalid/registry_unknown_expression.json")
      assert %{code: :unsupported_expression, path: path} = error
      assert String.contains?(path, "operations.admit")
    end
  end

  describe "Schema-Schließung und Kennungsformate (§ 2.1)" do
    test "registry_id muss kebab-case sein" do
      term = Map.put(base_registry(), "registry_id", "Reg Test")
      assert %{code: :invalid_registry_id, path: "$.registry_id"} = compile_term_error(term)
    end

    test "observers duerfen nicht leer sein und muessen eindeutig sein" do
      assert %{code: :empty_list, path: "$.observers"} =
               compile_term_error(Map.put(base_registry(), "observers", []))

      two_x = Map.put(base_registry(), "observers", ["x", "x"])
      assert %{code: :duplicate_entry} = compile_term_error(two_x)
    end

    test "observers muessen kebab-case sein" do
      bad = Map.put(base_registry(), "observers", ["X"])
      assert %{code: :invalid_entry} = compile_term_error(bad)
    end

    test "fact_fields-Typen sind geschlossen" do
      term = put_in(base_registry(), ["fact_fields", "purpose"], "integer_set")
      assert %{code: :invalid_fact_type} = compile_term_error(term)
    end

    test "Umgebungs- und Bindungskennungen folgen <kebab>@<nichtnegativ-Integer> ohne fuehrende Nullen (MIN-4)" do
      bad_env =
        Map.put(base_registry(), "environments", %{"Lokale@1" => %{"observers" => ["carsten"]}})

      assert %{code: :invalid_reference_id} = compile_term_error(bad_env)

      binding = get_in(base_registry(), ["bindings", "test@1"])

      bad_binding = put_in(base_registry(), ["bindings"], %{"test@-1" => binding})
      assert %{code: :invalid_reference_id} = compile_term_error(bad_binding)

      leading_zero = put_in(base_registry(), ["bindings"], %{"test@007" => binding})
      assert %{code: :invalid_reference_id} = compile_term_error(leading_zero)

      zero_version = put_in(base_registry(), ["bindings"], %{"test@0" => binding})
      compile_term!(zero_version)
    end

    test "readers muessen Teilmenge der observers sein" do
      term = put_in(base_registry(), ["bindings", "test@1", "readers"], ["carsten", "fremd"])
      assert %{code: :unknown_observer} = compile_term_error(term)
    end

    test "Operationsnamen sind geschlossen" do
      term = put_in(base_registry(), ["bindings", "test@1", "operations"], %{"reject" => true})
      assert %{code: :unknown_operation} = compile_term_error(term)
    end
  end

  describe "Ausdrucks-Compile (§ 3)" do
    test "unbekannte Ausdrucksform wird abgewiesen (Sprachluecke nicht versteckt)" do
      term =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{"not" => [true]})

      assert %{code: :unsupported_expression} = compile_term_error(term)
    end

    test "undefiniertes Feld in eq" do
      term =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "eq" => ["fehlt", 1]
        })

      assert %{code: :unknown_fact_field} = compile_term_error(term)
    end

    test "Literaltyp muss dem Feldtyp gleichen (eq/member)" do
      term =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "eq" => ["purpose", 1]
        })

      assert %{code: :expression_type_mismatch} = compile_term_error(term)

      term2 =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "member" => ["count", ["x"]]
        })

      assert %{code: :expression_type_mismatch} = compile_term_error(term2)
    end

    test "subset nur auf string_set, Literalmenge strings" do
      term =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "subset" => ["purpose", ["a"]]
        })

      assert %{code: :expression_type_mismatch} = compile_term_error(term)

      ok =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "subset" => ["labels", ["a", "b"]]
        })

      compile_term!(ok)
    end

    test "at_most nur auf integer mit nicht-negativer Schranke" do
      term =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "at_most" => ["purpose", 3]
        })

      assert %{code: :expression_type_mismatch} = compile_term_error(term)

      term2 =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "at_most" => ["count", -1]
        })

      assert %{code: :expression_type_mismatch} = compile_term_error(term2)
    end

    test "Ausdrucksobjekt braucht exakt einen Schluessel; true/false erlaubt" do
      term =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "all" => [],
          "any" => []
        })

      assert %{code: :unsupported_expression} = compile_term_error(term)

      ok =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{
          "all" => [true, false]
        })

      compile_term!(ok)
    end

    test "all/any mit Nicht-Array-Argument bekommt eigenen Detailtext (MIN-3)" do
      term =
        put_in(base_registry(), ["bindings", "test@1", "operations", "admit"], %{"all" => true})

      assert %{code: :unsupported_expression, detail: detail} = compile_term_error(term)
      assert String.contains?(detail, "array of expressions")
    end

    test "expression_fact_refs liefert die Menge sortiert und duplikatfrei (MIN-2)" do
      expr = %{"all" => [%{"eq" => ["b", 1]}, %{"eq" => ["a", true]}, %{"eq" => ["b", 2]}]}
      assert ["a", "b"] == Registry.expression_fact_refs(expr)

      assert Registry.expression_fact_refs(true) == []
    end
  end
end
