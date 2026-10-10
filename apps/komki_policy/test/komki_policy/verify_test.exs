defmodule KomkiPolicy.VerifyTest do
  use ExUnit.Case, async: true

  alias KomkiPolicy.{Derive, JSON, Registry, Verify}

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)
  @expectations_path "proofs/verify_expectations.json"

  defp fixture(path) do
    @fixtures_dir
    |> Path.join(path)
    |> File.read!()
    |> JSON.parse()
    |> elem(1)
  end

  defp registry do
    {:ok, compiled} = Registry.compile(fixture("registry.json"))
    compiled
  end

  defp check_case(reg, case_spec) do
    snapshot = fixture(case_spec["snapshot"])
    intent = fixture(case_spec["intent"])
    proof = fixture(case_spec["proof"])
    Verify.check(reg, snapshot, intent, proof)
  end

  defp reason_codes({:ok, %{"result" => "valid", "reasons" => []}}), do: []

  defp reason_codes({:ok, %{"result" => "invalid", "reasons" => reasons}}),
    do: Enum.map(reasons, &Map.fetch!(&1, "code"))

  defp reason_codes(_other), do: :input_error

  describe "Orakel-Schleife (verify_expectations.json, 10 Faelle)" do
    test "Praeufschritte produzieren exakt die erwartete result/Befundordnung" do
      expectations = fixture(@expectations_path)
      cases = Map.fetch!(expectations, "cases")
      assert length(cases) == 10

      reg = registry()

      Enum.with_index(cases, fn case_spec, index ->
        assert {:ok, outcome} = check_case(reg, case_spec)

        assert outcome["result"] == case_spec["expected"]["result"],
               "case ##{index} (#{Map.fetch!(case_spec, "proof")}): result diverges"

        assert reason_codes({:ok, outcome}) == case_spec["expected"]["reasons"],
               "case ##{index} (#{Map.fetch!(case_spec, "proof")}): reason sequence diverges"
      end)
    end

    test "reasons tragen die geschlossene Form {code, binding, fact}" do
      expectations = fixture(@expectations_path)
      cases = Map.fetch!(expectations, "cases")
      reg = registry()

      Enum.each(cases, fn case_spec ->
        case check_case(reg, case_spec) do
          {:ok, %{"result" => "invalid", "reasons" => reasons}} ->
            Enum.each(reasons, fn r ->
              assert MapSet.equal?(
                       MapSet.new(Map.keys(r)),
                       MapSet.new(["code", "binding", "fact"])
                     )

              assert is_binary(r["code"])
              assert Map.has_key?(r, "binding") and Map.has_key?(r, "fact")
            end)

          {:ok, %{"result" => "valid", "reasons" => []}} ->
            assert true

          _ ->
            flunk("unexpected outcome: #{Map.fetch!(case_spec, "proof")}")
        end
      end)
    end
  end

  describe "Eingabefehler (keine invalid-Urteile)" do
    test "falscher Schema-String -> {:error, invalid_schema}" do
      proof = Map.put(fixture("case_permit/proof_valid.json"), "schema", "komki-proof/9")

      assert {:error, %{code: :invalid_schema, path: "$.schema"}} =
               Verify.check(
                 registry(),
                 fixture("case_permit/snapshot.json"),
                 fixture("case_permit/intent.json"),
                 proof
               )
    end

    test "fehlendes premises-Feld -> {:error, missing_field}" do
      proof = Map.delete(fixture("case_permit/proof_valid.json"), "premises")

      assert {:error, %{code: :missing_field}} =
               Verify.check(
                 registry(),
                 fixture("case_permit/snapshot.json"),
                 fixture("case_permit/intent.json"),
                 proof
               )
    end

    test "unbekannte premise-kind -> {:error, invalid_premise_kind}" do
      proof = fixture("case_permit/proof_valid.json")
      forged = put_in(proof, ["premises", Access.at(0), "kind"], "vibes")

      assert {:error, %{code: :invalid_premise_kind}} =
               Verify.check(
                 registry(),
                 fixture("case_permit/snapshot.json"),
                 fixture("case_permit/intent.json"),
                 forged
               )
    end

    test "nicht-Objekt-Proof -> {:error, invalid_record}" do
      assert {:error, %{code: :invalid_record}} =
               Verify.check(
                 registry(),
                 fixture("case_permit/snapshot.json"),
                 fixture("case_permit/intent.json"),
                 ["nope"]
               )
    end

    test "Extra-Schluessel in Praemisse -> {:error, unknown_premise_field} (MIN-1)" do
      proof =
        put_in(fixture("case_permit/proof_valid.json"), ["premises", Access.at(0), "note"], "x")

      assert {:error, %{code: :unknown_premise_field, path: "$.premises.[0].note"}} =
               Verify.check(
                 registry(),
                 fixture("case_permit/snapshot.json"),
                 fixture("case_permit/intent.json"),
                 proof
               )
    end

    test "Faktpraemisse ohne source_kind -> {:error, missing_field} (MIN-1, § 2.5-Strenge)" do
      proof = fixture("case_permit/proof_valid.json")

      forged =
        put_in(
          proof,
          ["premises", Access.at(2)],
          Map.delete(Enum.at(proof["premises"], 2), "source_kind")
        )

      assert {:error, %{code: :missing_field}} =
               Verify.check(
                 registry(),
                 fixture("case_permit/snapshot.json"),
                 fixture("case_permit/intent.json"),
                 forged
               )
    end

    test "Art-Tarnung: binding_condition als fact-art ohne binding-Feld -> unknown_premise, kein Crash (BLOCKER)" do
      proof = fixture("case_permit/proof_valid.json")

      forged =
        put_in(proof, ["premises", Access.at(8)], %{
          "kind" => "fact",
          "name" => "binding_condition",
          "fact" => "has_operation_right",
          "source" => "fall-verwaltung",
          "source_kind" => "administered",
          "value" => true
        })

      assert {:ok, %{"result" => "invalid", "reasons" => reasons}} =
               Verify.check(
                 registry(),
                 fixture("case_permit/snapshot.json"),
                 fixture("case_permit/intent.json"),
                 forged
               )

      assert [
               %{
                 "binding" => "buergerfall-4711@1",
                 "code" => "missing_required_premise",
                 "fact" => nil
               }
             ] = Enum.filter(reasons, &(&1["code"] == "missing_required_premise"))

      assert Enum.any?(reasons, &(&1["code"] == "unknown_premise"))
    end

    test "MIN-2: condition-Befunde tragen die betroffene binding" do
      reg = registry()
      snapshot = fixture("case_deny/snapshot.json")
      intent = fixture("case_deny/intent.json")
      proof = fixture("proofs/proof_false_condition.json")

      assert {:ok, %{"result" => "invalid", "reasons" => reasons}} =
               Verify.check(reg, snapshot, intent, proof)

      condition_finding = Enum.find(reasons, &(&1["code"] == "condition_false"))
      assert condition_finding["binding"] == "buergerfall-4711@1"
      assert Enum.find(reasons, &(&1["code"] == "conclusion_mismatch"))
    end
  end

  describe "Determinismus und Rundtrip (§ 5 / § 6)" do
    test "zwei Aufrufe mit identischen Eingaben erzeugen byte-identische kanonische Ausgaben" do
      reg = registry()
      snapshot = fixture("case_deny/snapshot.json")
      intent = fixture("case_deny/intent.json")
      proof = fixture("proofs/proof_false_condition.json")

      first = Verify.check(reg, snapshot, intent, proof)
      second = Verify.check(reg, snapshot, intent, proof)

      assert first == second

      snap_bytes =
        Enum.map([first, second], fn
          {:ok, outcome} -> JSON.canonical(outcome)
          {:error, _error} -> flunk("unexpected error")
        end)

      assert length(Enum.uniq(snap_bytes)) == 1
    end

    test "derive(case_permit)-Beweis bestaetigt verify als valid (keine Datei-Magnetisierung)" do
      reg = registry()

      {:ok, snapshot} =
        JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/snapshot.json")))

      {:ok, intent} = JSON.parse(File.read!(Path.join(@fixtures_dir, "case_permit/intent.json")))
      {:ok, decision} = Derive.decide(reg, snapshot, intent)

      refute is_nil(decision["proof"])

      assert {:ok, %{"result" => "valid", "reasons" => []}} =
               Verify.check(reg, snapshot, intent, decision["proof"])
    end
  end
end
