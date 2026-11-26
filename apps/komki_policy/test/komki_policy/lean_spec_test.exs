defmodule KomkiPolicy.LeanSpecTest do
  @moduledoc false

  # Differential tests of `Verify.check/4` and `Derive.decide/3` against the
  # proven Lean model (#625, #629, lean/README.md). Needs the binary from
  # `cd lean && lake build`; excluded by default, run with
  # `mix test --only lean_spec`.
  #
  # Only cases inside the validated domain are compared: Elixir has to
  # return a verdict, a decision or one of the modelled input errors (the
  # snapshot prerequisites of the output rules, #628; for `derive` also
  # `unknown_environment`); any other input error drops the case. Within
  # that domain, everything compared has to match. KOMKI_SPEC_SEED and
  # KOMKI_SPEC_RUNS widen the search; a mismatch writes its cases to a JSONL
  # file for replay with `komki-spec verify-batch` or `derive-batch`.

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias KomkiPolicy.{Calculus, Derive, Evaluator, Registry, Release, Stand, Verify}

  @moduletag :lean_spec
  @moduletag timeout: 600_000

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)
  @default_bin Path.expand("../../lean/.lake/build/bin/komki-spec", __DIR__)

  @observers ~w(o-a o-b o-c o-d o-e)
  @bindings ~w(b-drei@1 b-eins@1 b-vier@1 b-zwei@1 ratsprojekte@1)
  @environments ~w(env-drei@1 env-eins@1 env-zwei@1 ratsprojekte-bestand@1)
  @hex String.duplicate("ab", 32)
  @base_facts ~w(has_operation_right has_object_access_right audit_path_ready environment_observers_complete)
  @fact_fields %{
    "count" => "integer",
    "output_content_digest" => "string",
    "purpose" => "string",
    "scope" => "boolean",
    "tags" => "string_set"
  }
  @purposes ~w(antwort mandat recherche)
  @tags ~w(x y z)
  @claim_fields ~w(object_labels checked_label actual_recipients allowed_recipients fact_refs
                   assigned_label workspace_bindings)
  @modelled_input_errors [:emit_digest_missing, :emit_object_not_classified]
  @derive_input_errors [:unknown_environment | @modelled_input_errors]
  @decision_fields ~w(decision rule checked_label blockers missing_evidence proof
                      assigned_label content_digest remedies)
  @release_fields ~w(decision rule checked_label blockers release content_digest assigned_label
                     remedies)
  # Release variants: one wrong field each, or a window on its edge. Both
  # ends belong to the window (§ 4.6 step 3: valid_from ≤ as_of ≤ valid_until).
  @release_changes %{
    base: %{},
    wrong_hash: %{"call_hash" => String.duplicate("ab", 32)},
    foreign_scope: %{"scope" => "scope-fremd"},
    not_yet: %{"valid_from" => 51, "valid_until" => 60},
    expired: %{"valid_from" => 10, "valid_until" => 49},
    edge_from: %{"valid_from" => 50, "valid_until" => 60},
    edge_until: %{"valid_from" => 40, "valid_until" => 50},
    consumed: %{"nonce" => "n-alt"},
    foreign_authority: %{"authority" => "o-fremd"}
  }
  @stand %{
    "schema" => "komki-stand/1",
    "stand_id" => "stand-drt",
    "version" => 3,
    "scope" => "scope-drt",
    "as_of" => 50,
    "consumed" => %{"n-alt" => "go-alt"}
  }

  # Corruptions for the input-check test: each breaks one check of
  # Registry.compile/1 or Context.validate_snapshot/2 (CONTRACT § 2.1, § 2.2, § 3).
  @registry_corruptions [
    {:reader, "o-fremd"},
    {:authority, "o-fremd"},
    {:environment, "o-fremd"},
    :empty_readers,
    :duplicate_reader,
    :unknown_transformation_label,
    :unknown_transformation_output,
    :empty_transformation_input,
    :base_fact_redeclared,
    {:expression, %{"eq" => ["unbekannt", 1]}},
    {:expression, %{"eq" => ["count", "drei"]}},
    {:expression, %{"eq" => ["count", 1.5]}},
    {:expression, %{"eq" => ["tags", "x"]}},
    {:expression, %{"at_most" => ["count", -1]}},
    {:expression, %{"at_most" => ["purpose", 1]}},
    {:expression, %{"subset" => ["purpose", ["a"]]}},
    {:expression, %{"subset" => ["tags", [1]]}},
    {:expression, %{"member" => ["scope", [1]]}},
    {:expression, %{"member" => ["tags", ["x"]]}},
    {:expression, %{"member" => ["tags", []]}},
    {:expression, %{"not" => true}},
    {:expression, %{"eq" => ["count", 1], "any" => []}},
    {:expression, %{"all" => true}},
    {:expression, %{"eq" => [1, 1]}},
    {:expression, %{"any" => [%{"eq" => ["count", "x"]}]}}
  ]

  @snapshot_corruptions [
    :unsorted_bindings,
    :duplicate_binding,
    :unknown_binding,
    :unknown_environment,
    :string_base_fact,
    :non_string_element,
    :wrong_fact_type,
    :undeclared_fact,
    :unknown_classification,
    :unsorted_labels,
    :duplicate_label
  ]

  test "Lean-Tabellen entsprechen Derive" do
    {out, 0} = System.cmd(spec_bin(), ["constants"])
    {:ok, constants} = KomkiPolicy.JSON.parse(String.trim(out))

    assert constants["proof_rules"] == Derive.proof_rules()
    assert constants["output_operations"] == Derive.output_operations()
    assert constants["handover_operations"] == Derive.handover_operations()

    for rule <- Derive.proof_rules() do
      assert constants["required_premises"][rule] == Derive.required_premises(rule)
    end

    # Verify.lean takes B_W as the checked label of admit and emit, λ(y) of
    # store and transfer.
    workspace = %{"bindings" => ["b-eins@1"]}
    object = %{"labels" => ["b-eins@1", "b-zwei@1"]}

    for rule <- Derive.proof_rules() do
      expected = if rule in Derive.handover_operations(), do: object["labels"], else: ["b-eins@1"]
      assert Derive.checked_label(rule, workspace, object) == expected
    end
  end

  test "Fixture-Korpus: Elixir und Lean urteilen gleich" do
    raw = fixture("registry.json")
    {:ok, registry} = Registry.compile(raw)
    worlds = fixture_worlds()

    proofs =
      fixture_proofs() ++
        for {snapshot, intent} <- worlds,
            proof = derived_proof(registry, snapshot, intent),
            do: proof

    cases =
      for {snapshot, intent, proof} <-
            audit_attacks() ++ for({s, i} <- worlds, p <- proofs, do: {s, i, p}) do
        {raw, registry, snapshot, intent, proof}
      end

    stats = compare!(cases, "korpus")

    assert stats.valid >= 6
    assert stats.invalid >= 500
    assert stats.input_error >= 6
  end

  test "Generierte Welten und geschmiedete Bäume: Elixir und Lean urteilen gleich" do
    seed = env_int("KOMKI_SPEC_SEED", 20_261_123)
    runs = env_int("KOMKI_SPEC_RUNS", 8_000)

    # `seeded` fixes one draw, so the whole list is that one draw; `resize`
    # keeps expressions and mutation lists from staying at size 1.
    cases =
      world_gen()
      |> StreamData.resize(30)
      |> StreamData.list_of(length: runs)
      |> StreamData.seeded(seed)
      |> Enum.at(0)
      |> Enum.flat_map(&world_cases/1)

    stats = compare!(cases, "generator")
    IO.puts("\nlean_spec seed=#{seed} runs=#{runs}: #{inspect(stats)}")

    assert stats.input_error >= 200

    for rule <- Derive.proof_rules() do
      assert stats.valid_by_rule[rule] >= 150, "zu wenige gültige #{rule}-Bäume"
    end
  end

  test "Fixture-Korpus: Derive und das Lean-Modell entscheiden gleich" do
    raw = fixture("registry.json")
    {:ok, registry} = Registry.compile(raw)

    cases =
      for {snapshot, intent} <-
            fixture_worlds() ++ unsupported_fixture_worlds() ++ input_error_worlds(),
          do: {raw, registry, snapshot, intent}

    stats = compare_decisions!(cases, "derive-korpus")

    for decision <- ~w(permit deny indeterminate unsupported input_error) do
      assert Enum.any?(stats, fn {{_, d}, n} -> d == decision and n > 0 end),
             "kein Fixture-Fall mit #{decision}"
    end
  end

  test "Generierte Welten: Derive und das Lean-Modell entscheiden gleich" do
    seed = env_int("KOMKI_SPEC_SEED", 20_261_123)
    runs = env_int("KOMKI_SPEC_RUNS", 8_000)

    cases =
      world_gen()
      |> StreamData.resize(30)
      |> StreamData.list_of(length: runs)
      |> StreamData.seeded(seed)
      |> Enum.at(0)
      |> Enum.flat_map(&decision_cases/1)

    stats = compare_decisions!(cases, "derive-generator")
    IO.puts("\nlean_spec derive seed=#{seed} runs=#{runs}: #{inspect(stats)}")

    for rule <- Derive.proof_rules(), decision <- ~w(permit deny indeterminate) do
      assert Map.get(stats, {rule, decision}, 0) >= 150, "zu wenige #{rule}/#{decision}"
    end
  end

  test "Freigabe-Zweige: Derive und das Lean-Modell entscheiden gleich" do
    worlds = seeded_list(release_world_gen())

    cases = fixture_release_cases() ++ Enum.flat_map(worlds, &release_cases/1)
    pairs = Enum.map(cases, &release_pair/1)

    stats =
      compare_json!(
        pairs,
        "release-batch",
        "release",
        "Derive.decide_with_release/5 und dem Lean-Modell"
      )

    IO.puts("\nlean_spec release: #{inspect(stats)}")

    offenlegung_permits =
      Enum.count(pairs, fn {line, result} ->
        line["release"]["kind"] == "offenlegungsfreigabe" and is_map(result) and
          result["decision"] == "permit"
      end)

    assert offenlegung_permits >= 20

    for op <- Derive.output_operations(), decision <- ~w(permit deny) do
      assert Map.get(stats, {op, decision}, 0) >= 100, "zu wenige #{op}/#{decision}"
    end
  end

  test "advance: Stand und das Lean-Modell gehen gleich über" do
    cases = seeded_list(advance_gen())

    chained =
      for {stand, proposal} <- cases,
          {:ok, next} <- [Stand.advance(stand, proposal)],
          do: replay_on(Stand.to_record(next), proposal)

    stats =
      (cases ++ chained)
      |> Enum.map(fn {stand, proposal} ->
        line = %{
          "stand" => stand,
          "proposal" => proposal,
          "intent" => %{"operation" => "advance"}
        }

        {line, elixir_advance(stand, proposal)}
      end)
      |> compare_json!("advance-batch", "advance", "Stand.advance/2 und dem Lean-Modell")

    IO.puts("\nlean_spec advance: #{inspect(stats)}")
    assert Map.get(stats, {"advance", "ok"}, 0) >= 200
    assert Map.get(stats, {"advance", "refused"}, 0) >= 200
  end

  test "Auswerter: Evaluator und das Lean-Modell werten gleich aus" do
    corpus =
      for c <- fixture("expressions/evaluate_expectations.json")["cases"],
          do: {c["expression"], c["facts"]}

    generated = seeded_list(StreamData.tuple({expr_gen(), facts_gen()}))

    pairs =
      for {expression, facts} <- corpus ++ generated do
        line = %{
          "expression" => expression,
          "facts" => facts,
          "intent" => %{"operation" => "eval"}
        }

        {line, %{"verdict" => to_string(Evaluator.evaluate(expression, facts))}}
      end

    compare_json!(pairs, "eval-batch", "eval", "Evaluator.evaluate/2 und dem Lean-Auswerter")
    verdicts = Enum.frequencies_by(pairs, fn {_, result} -> result["verdict"] end)
    IO.puts("\nlean_spec eval: #{inspect(verdicts)}")

    for verdict <- ~w(true false unknown), do: assert(Map.get(verdicts, verdict, 0) >= 500)
  end

  # The theorems assume what Registry.compile/1 and Context guarantee
  # (`Registry.compiledOk`, `Snapshot.validated`). Corrupted inputs go to
  # Elixir; whatever it accepts has to pass the Lean checks.
  test "Eingabeprüfung: was Registry.compile und Context annehmen, liegt im Wertebereich" do
    cases = domain_gen() |> seeded_list() |> Enum.map(&domain_case/1)

    pairs = for {line, expected} <- cases, expected != :dropped, do: {line, expected}

    compare_json!(
      pairs,
      "domain-batch",
      "domain",
      "Registry.compile/Context und dem Wertebereich"
    )

    snapshots = Enum.count(pairs, fn {_, e} -> e["snapshot"] end)

    IO.puts(
      "\nlean_spec domain: registries #{length(pairs)}, snapshots #{snapshots}, rejected #{length(cases) - length(pairs)}"
    )

    assert length(pairs) >= 3_000
    assert snapshots >= 1_000
  end

  # Not a comparison with Lean, but the property the Lean theorem states
  # for the model (#631): a GO the catalog offers takes effect. Each offer
  # becomes a release with a fresh nonce; the release branch has to permit.
  # The object-scope GO (quarantine) is an Erstklassifikation (R.2.5), no
  # call of the release branch.
  test "Katalog: jedes angebotene GO wirkt" do
    raw = fixture("registry.json")
    {:ok, registry} = Registry.compile(raw)

    normal =
      for({snapshot, intent} <- fixture_worlds(), do: {raw, registry, snapshot, intent}) ++
        Enum.flat_map(seeded_list(world_gen()), &decision_cases/1)

    released =
      for {r, compiled, snapshot, intent, release, stand} <-
            fixture_release_cases() ++
              Enum.flat_map(seeded_list(release_world_gen()), &release_cases/1),
          do:
            {r, compiled, snapshot, intent,
             Derive.decide_with_release(compiled, snapshot, intent, release, stand)}

    offers =
      (for(
         {_, compiled, snapshot, intent} <- normal,
         do: {compiled, snapshot, intent, Derive.decide(compiled, snapshot, intent)}
       ) ++
         for(
           {_, compiled, snapshot, intent, result} <- released,
           do: {compiled, snapshot, intent, result}
         ))
      |> Enum.flat_map(fn
        {compiled, snapshot, intent, {:ok, %{"decision" => "deny", "remedies" => remedies}}} ->
          for entry <- remedies,
              go <- entry["transitions"],
              go["type"] in ~w(aktionsfreigabe offenlegungsfreigabe),
              go["scope"] == "call",
              do: {compiled, snapshot, intent, go}

        _ ->
          []
      end)
      |> Enum.uniq()

    failing =
      for {compiled, snapshot, intent, go} <- offers,
          release = release_from_offer(compiled, snapshot, intent, go),
          result = Derive.decide_with_release(compiled, snapshot, intent, release, @stand),
          not match?({:ok, %{"decision" => "permit"}}, result),
          do: {go, snapshot, intent, result}

    counts = Enum.frequencies_by(offers, fn {_, _, _, go} -> go["type"] end)
    IO.puts("\nlean_spec GO-Angebote: #{inspect(counts)}")

    assert failing == [], "Angebot wirkt nicht: #{inspect(Enum.take(failing, 2), limit: 8)}"
    assert Map.get(counts, "aktionsfreigabe", 0) >= 200
    assert Map.get(counts, "offenlegungsfreigabe", 0) >= 5
  end

  # ---------------------------------------------------------------------
  # Comparison
  # ---------------------------------------------------------------------

  defp compare!(cases, label) do
    judged =
      cases
      |> Enum.map(fn {raw, registry, snapshot, intent, proof} ->
        line = %{"registry" => raw, "snapshot" => snapshot, "intent" => intent, "proof" => proof}
        {line, elixir_verdict(registry, snapshot, intent, proof)}
      end)
      |> Enum.reject(fn {_, verdict} -> verdict == :dropped end)
      |> Enum.with_index()

    lean = run_lean("verify-batch", judged)

    mismatches =
      for {{line, verdict}, id} <- judged,
          Map.get(lean, id) != verdict,
          do: {id, verdict, Map.get(lean, id), line}

    report_mismatches!(mismatches, label, "Verify.check/4 und dem Lean-Prüfer")

    count = fn verdict -> Enum.count(judged, fn {{_, v}, _} -> v == verdict end) end

    %{
      compared: length(judged),
      dropped: length(cases) - length(judged),
      valid: count.("valid"),
      invalid: count.("invalid"),
      input_error: count.("input_error"),
      valid_by_rule:
        judged
        |> Enum.filter(fn {{_, v}, _} -> v == "valid" end)
        |> Enum.frequencies_by(fn {{line, _}, _} -> line["proof"]["rule"] end)
    }
  end

  defp elixir_verdict(registry, snapshot, intent, proof) do
    case Verify.check(registry, snapshot, intent, proof) do
      {:ok, %{"result" => result}} -> result
      {:error, %{code: code}} when code in @modelled_input_errors -> "input_error"
      {:error, _} -> :dropped
    end
  end

  defp compare_decisions!(cases, label) do
    cases
    |> Enum.map(fn {raw, registry, snapshot, intent} ->
      line = %{
        "registry" => raw,
        "snapshot" => snapshot,
        "intent" => intent,
        "call_hash" => call_hash(snapshot, intent)
      }

      {line, elixir_decision(registry, snapshot, intent)}
    end)
    |> compare_json!("derive-batch", label, "Derive.decide/3 und dem Lean-Modell")
  end

  # Pairs {case line, Elixir result} against the Lean batch `command`;
  # returns the results counted by operation and kind.
  defp compare_json!(pairs, command, label, what) do
    judged =
      pairs
      |> Enum.reject(fn {_, result} -> result == :dropped end)
      |> Enum.with_index()

    lean = run_lean(command, judged)

    mismatches =
      for {{line, result}, id} <- judged,
          parse_decision(Map.get(lean, id)) != result,
          do: {id, result, parse_decision(Map.get(lean, id)), line}

    report_mismatches!(mismatches, label, what)

    Enum.frequencies_by(judged, fn {{line, result}, _} ->
      {line["intent"]["operation"], result["decision"] || Enum.at(Map.keys(result), 0)}
    end)
  end

  defp release_pair({raw, registry, snapshot, intent, release, stand}) do
    line = %{
      "registry" => raw,
      "snapshot" => snapshot,
      "intent" => intent,
      "release" => release,
      "stand" => stand,
      "call_hash" => call_hash(snapshot, intent)
    }

    {line, elixir_release(registry, snapshot, intent, release, stand)}
  end

  defp elixir_release(registry, snapshot, intent, release, stand) do
    case Derive.decide_with_release(registry, snapshot, intent, release, stand) do
      {:ok, decision} ->
        decision |> Map.take(@release_fields) |> Map.put("gos", gos(decision["remedies"]))

      {:unsupported, _} ->
        %{"unsupported" => true}

      {:error, %{code: code}} when code in @derive_input_errors ->
        %{"input_error" => to_string(code)}

      {:error, _} ->
        :dropped
    end
  end

  defp elixir_advance(stand, proposal) do
    case Stand.advance(stand, proposal) do
      {:ok, next} -> %{"ok" => next |> Stand.to_record() |> Map.delete("schema")}
      {:refused, %{code: code}} -> %{"refused" => to_string(code)}
      {:error, _} -> :dropped
    end
  end

  defp call_hash(snapshot, intent) do
    case get_in(snapshot, ["facts", "output_content_digest", "value"]) do
      nil ->
        ""

      digest ->
        Release.call_hash(digest, intent["object"], intent["operation"], intent["workspace"])
    end
  end

  # The GO offers of a catalog, per finding (§ 2.8): `catalogGos`, which the
  # Lean theorems are about. The whole catalog is compared as `remedies`.
  defp gos(nil), do: nil

  defp gos(remedies) do
    for entry <- remedies do
      Enum.filter(entry["transitions"], &(&1["type"] in ~w(aktionsfreigabe offenlegungsfreigabe)))
    end
  end

  # The fields of a decision the Lean model decides: everything but the
  # echoes of the input.
  defp elixir_decision(registry, snapshot, intent) do
    case Derive.decide(registry, snapshot, intent) do
      {:ok, decision} ->
        decision |> Map.take(@decision_fields) |> Map.put("gos", gos(decision["remedies"]))

      {:unsupported, _} ->
        %{"unsupported" => true}

      {:error, %{code: code}} when code in @derive_input_errors ->
        %{"input_error" => to_string(code)}

      {:error, _} ->
        :dropped
    end
  end

  defp parse_decision(nil), do: nil

  defp parse_decision(out) do
    case KomkiPolicy.JSON.parse(out) do
      {:ok, decision} -> decision
      {:error, _} -> out
    end
  end

  defp run_lean(command, judged) do
    path = Path.join(System.tmp_dir!(), "komki-spec-#{System.unique_integer([:positive])}.jsonl")
    File.write!(path, for({{line, _}, id} <- judged, do: case_line(id, line)))

    try do
      {out, 0} = System.cmd(spec_bin(), [command, path])

      for line <- String.split(out, "\n", trim: true), into: %{} do
        [id, result] = String.split(line, " ", parts: 2)
        {String.to_integer(id), result}
      end
    after
      File.rm(path)
    end
  end

  defp case_line(id, line), do: JSON.encode!(Map.put(line, "id", id)) <> "\n"

  defp report_mismatches!([], _label, _what), do: :ok

  defp report_mismatches!(mismatches, label, what) do
    path = Path.join(System.tmp_dir!(), "komki-spec-mismatch-#{label}.jsonl")
    File.write!(path, for({id, _, _, line} <- mismatches, do: case_line(id, line)))

    shown =
      mismatches
      |> Enum.take(5)
      |> Enum.map_join("\n", fn {id, elixir, lean, _} ->
        "  Fall #{id}: Elixir #{inspect(elixir)}, Lean #{inspect(lean)}"
      end)

    flunk("""
    #{length(mismatches)} Abweichungen zwischen #{what}:
    #{shown}
    Fälle: #{path}
    """)
  end

  defp spec_bin do
    path = Path.expand(System.get_env("KOMKI_SPEC_BIN", @default_bin))

    if File.exists?(path),
      do: path,
      else: flunk("komki-spec fehlt unter #{path}: erst `cd lean && lake build` (lean/README.md)")
  end

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  # ---------------------------------------------------------------------
  # Fixture corpus
  # ---------------------------------------------------------------------

  defp fixture(path) do
    {:ok, term} = @fixtures_dir |> Path.join(path) |> File.read!() |> KomkiPolicy.JSON.parse()
    term
  end

  defp fixture_worlds do
    for dir <- File.ls!(@fixtures_dir),
        File.exists?(Path.join([@fixtures_dir, dir, "snapshot.json"])),
        File.exists?(Path.join([@fixtures_dir, dir, "intent.json"])),
        intent = fixture(Path.join(dir, "intent.json")),
        intent["operation"] in Derive.proof_rules() do
      {fixture(Path.join(dir, "snapshot.json")), intent}
    end
  end

  defp input_error_worlds do
    [
      {fixture("invalid/emit_digest_missing_snapshot.json"),
       fixture("invalid/emit_digest_missing_intent.json")},
      {put_in(
         fixture("case_permit/snapshot.json"),
         ["workspace", "environment"],
         "env-unbekannt@1"
       ), fixture("case_permit/intent.json")}
    ]
  end

  defp unsupported_fixture_worlds do
    for {snapshot, intent} <- fixture_worlds(),
        do: {snapshot, Map.put(intent, "operation", "start")}
  end

  defp fixture_proofs do
    proof_files =
      for name <- File.ls!(Path.join(@fixtures_dir, "proofs")),
          name != "verify_expectations.json",
          do: Path.join("proofs", name)

    case_files =
      for dir <- File.ls!(@fixtures_dir),
          File.exists?(Path.join([@fixtures_dir, dir, "proof_valid.json"])),
          do: Path.join(dir, "proof_valid.json")

    Enum.map(proof_files ++ case_files, &fixture/1)
  end

  # The forged trees of the audit, built as in verify_test.exs. verify.ex
  # before ed7c4574 accepts them; the Lean verifier never does. Then the
  # output trees on a snapshot outside the rule's domain (#628).
  defp audit_attacks do
    forged_trees() ++ off_domain_trees()
  end

  defp off_domain_trees do
    {:ok, registry} = Registry.compile(fixture("registry.json"))

    for dir <- ~w(case_emit_permit case_store_permit case_transfer_permit),
        snapshot = fixture(dir <> "/snapshot.json"),
        intent = fixture(dir <> "/intent.json"),
        broken <- off_domain(snapshot) do
      {broken, intent, derived_proof(registry, snapshot, intent)}
    end
  end

  defp off_domain(snapshot) do
    [
      put_in(snapshot, ["object", "classification"], "quarantine"),
      update_in(snapshot, ["facts"], &Map.delete(&1, "output_content_digest"))
    ]
  end

  defp forged_trees do
    permit = fixture("case_permit/snapshot.json")
    permit_intent = fixture("case_permit/intent.json")
    permit_proof = fixture("case_permit/proof_valid.json")
    no_basis = fixture("case_deny_no_basis/snapshot.json")
    no_basis_intent = fixture("case_deny_no_basis/intent.json")
    false_fact = fixture("proofs/proof_false_fact_value.json")
    admitless = fixture("proofs/proof_admitless_condition.json")

    [
      # #477: expression null hides the missing admit rule.
      {fixture("case_deny_missing_rule/snapshot.json"),
       fixture("case_deny_missing_rule/intent.json"),
       put_in(admitless, ["premises", Access.at(8), "expression"], nil)},
      # #479: the has_operation_right slot checks another, true fact.
      {no_basis, no_basis_intent,
       put_named(false_fact, "has_operation_right", "fact", "has_object_access_right")},
      # #480: faithfully mirrored false values.
      {no_basis, no_basis_intent, put_named(false_fact, "has_operation_right", "value", false)},
      {put_in(permit, ["workspace", "valid"], false), permit_intent,
       put_named(permit_proof, "workspace_contract_valid", "value", false)},
      {permit, permit_intent, put_named(permit_proof, "not_quarantine", "value", false)}
    ]
  end

  defp put_named(proof, name, key, value) do
    index = Enum.find_index(proof["premises"], &(&1["name"] == name))
    put_in(proof, ["premises", Access.at(index), key], value)
  end

  defp derived_proof(registry, snapshot, intent) do
    case Derive.decide(registry, snapshot, intent) do
      {:ok, %{"decision" => "permit", "proof" => proof}} when is_map(proof) -> proof
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------
  # Generated worlds: a registry, two snapshots over it, tree mutations
  # ---------------------------------------------------------------------

  # Cases per world: every tree in the world it comes from, in a second
  # snapshot (a proof from another world), mutated, with float literals
  # (#626), off its rule's domain (#628) and, for store and transfer, under
  # the other handover rule. Trees come from the snapshot, from a repaired
  # snapshot (base facts true, labels fitting the rule, #480) and from a
  # registry where every binding has every rule (#477).
  defp world_cases({raw, op, snapshot, other, mutations}) do
    with {:ok, registry} <- Registry.compile(raw),
         {:ok, ruled} <- Registry.compile(with_all_rules(raw)) do
      fixed = repaired(snapshot, op)

      sources =
        [
          {snapshot, derived_proof(registry, snapshot, intent(op))},
          {fixed, derived_proof(registry, fixed, intent(op))},
          {fixed, derived_proof(ruled, fixed, intent(op))}
        ]
        |> Enum.reject(fn {_, tree} -> is_nil(tree) end)
        |> Enum.uniq()

      cases =
        for {source, tree} <- sources,
            {target, target_intent, proof} <- tree_cases(tree, op, source, other, mutations),
            do: {raw, registry, target, target_intent, proof}

      mirrored =
        for target <- [snapshot, other, fixed],
            do: {raw, registry, target, intent(op), mirrored_tree(registry, target, op)}

      cases ++ mirrored
    else
      {:error, _} -> []
    end
  end

  # Decisions per world: the snapshot, the second snapshot and the repaired
  # one, each under the registry and under the one with every rule, plus
  # `start`, which no snapshot decides.
  defp decision_cases({raw, op, snapshot, other, _mutations}) do
    ruled_raw = with_all_rules(raw)

    with {:ok, registry} <- Registry.compile(raw),
         {:ok, ruled} <- Registry.compile(ruled_raw) do
      worlds =
        for {r, compiled} <- [{raw, registry}, {ruled_raw, ruled}],
            s <- [snapshot, other, repaired(snapshot, op)],
            do: {r, compiled, s, intent(op)}

      worlds ++ [{raw, registry, snapshot, intent("start")}]
    else
      {:error, _} -> []
    end
  end

  # The float variant only where it differs (strictly: `3.0 != 3` is false
  # in Elixir); a tree without integer literals would count twice as valid.
  defp tree_cases(tree, op, source, other, mutations) do
    floated = mutate(:floatify, tree)

    [
      {source, intent(op), tree},
      {other, intent(op), tree},
      {source, intent(op), Enum.reduce(mutations, tree, &mutate/2)}
    ] ++
      if(floated !== tree, do: [{source, intent(op), floated}], else: []) ++
      if(op in Derive.output_operations(),
        do: for(broken <- off_domain(source), do: {broken, intent(op), tree}),
        else: []
      ) ++ handover_swap(tree, op, source) ++ claim_variants(tree, op, source)
  end

  # One claim field at a time, every premise that carries it: reversed with
  # a duplicate (a set for assigned_label, exact everywhere else) and
  # replaced by a foreign value. A random mutation rarely hits exactly one
  # field of an otherwise valid tree.
  defp claim_variants(tree, op, source) do
    for key <- @claim_fields,
        change <- [&scramble/1, &foreign/1],
        variant = map_claims(tree, key, change),
        variant != tree,
        do: {source, intent(op), variant}
  end

  defp map_claims(tree, key, change) do
    Map.update!(tree, "premises", fn premises ->
      Enum.map(premises, &Map.replace_lazy(&1, key, change))
    end)
  end

  defp foreign([]), do: ["b-eins@1"]
  defp foreign(_list), do: []

  # The strongest forger (#480): every premise of the rule present, every
  # claimed value mirrored from the target world, a false fact as false.
  # Valid exactly where the world itself is derivable.
  defp mirrored_tree(registry, snapshot, op) do
    workspace = snapshot["workspace"]
    object = snapshot["object"]
    checked = Derive.checked_label(op, workspace, object)

    premises =
      for name <- Derive.required_premises(op),
          premise <- mirrored_premises(name, registry, snapshot, checked, op),
          do: premise

    %{
      "schema" => "komki-proof/1",
      "rule" => op,
      "conclusion" => "permit",
      "registry_ref" => registry.registry_id,
      "snapshot_ref" => snapshot["snapshot_id"],
      "intent_ref" => "intent-drt",
      "checked_label" => checked,
      "premises" => premises
    }
  end

  defp mirrored_premises("binding_condition", registry, _snapshot, checked, op) do
    for binding <- checked do
      expr = Map.get(Map.fetch!(registry.bindings, binding).operations, op, true)

      %{
        "name" => "binding_condition",
        "kind" => "condition",
        "binding" => binding,
        "expression" => expr,
        "fact_refs" => Registry.expression_fact_refs(expr),
        "value" => true
      }
    end
  end

  defp mirrored_premises(name, registry, snapshot, checked, _op) do
    workspace = snapshot["workspace"]
    computed = %{"name" => name, "kind" => "computed", "value" => true}

    premise =
      case name do
        "not_quarantine" ->
          %{
            "name" => name,
            "kind" => "object_check",
            "value" => true,
            "object" => "obj-drt@v1",
            "classification" => "classified"
          }

        "workspace_contract_valid" ->
          %{
            "name" => name,
            "kind" => "fact",
            "fact" => name,
            "value" => workspace["valid"],
            "source" => "drt"
          }

        "label_inclusion" ->
          Map.merge(computed, %{
            "object_labels" => snapshot["object"]["labels"],
            "checked_label" => checked
          })

        "label_assignment" ->
          Map.merge(computed, %{"assigned_label" => checked, "checked_label" => checked})

        "label_preservation" ->
          Map.merge(computed, %{
            "workspace_bindings" => workspace["bindings"],
            "checked_label" => checked
          })

        "recipient_inclusion" ->
          Map.merge(computed, %{
            "actual_recipients" => Calculus.actual_recipients(registry, workspace["environment"]),
            "allowed_recipients" => Calculus.allowed_recipients(registry, checked)
          })

        base_fact ->
          %{
            "name" => base_fact,
            "kind" => "fact",
            "fact" => base_fact,
            "value" => get_in(snapshot, ["facts", base_fact, "value"]) != false,
            "source" => "drt",
            "source_kind" => "test"
          }
      end

    [premise]
  end

  # store and transfer trees share one shape; a tree proves only its own rule.
  defp handover_swap(tree, "store", source),
    do: [{source, intent("transfer"), Map.put(tree, "rule", "transfer")}]

  defp handover_swap(tree, "transfer", source),
    do: [{source, intent("store"), Map.put(tree, "rule", "store")}]

  defp handover_swap(_tree, _op, _source), do: []

  defp intent(op) do
    %{
      "schema" => "komki-intent/1",
      "intent_id" => "intent-drt",
      "operation" => op,
      "object" => "obj-drt@v1",
      "workspace" => "ws-drt"
    }
  end

  defp with_all_rules(raw) do
    Map.update!(raw, "bindings", fn bindings ->
      Map.new(bindings, fn {id, binding} ->
        {id,
         update_in(binding, ["operations"], fn rules ->
           Enum.reduce(Derive.proof_rules(), rules, &Map.put_new(&2, &1, true))
         end)}
      end)
    end)
  end

  # λ(x) ⊆ B_W for admit, B_W ⊆ λ(y) for store and transfer; emit reads no labels.
  defp repaired(snapshot, op) do
    bindings = snapshot["workspace"]["bindings"]
    labels = snapshot["object"]["labels"]

    fitting =
      cond do
        op == "admit" -> Enum.filter(labels, &(&1 in bindings))
        op in Derive.handover_operations() -> Enum.sort(Enum.uniq(labels ++ bindings))
        true -> labels
      end

    facts =
      @base_facts
      |> Enum.reduce(snapshot["facts"], fn name, acc -> Map.put(acc, name, entry(true)) end)
      |> Map.put_new("output_content_digest", entry("digest-drt"))

    snapshot
    |> put_in(["workspace", "valid"], true)
    |> put_in(["object", "classification"], "classified")
    |> put_in(["object", "labels"], fitting)
    |> Map.put("facts", facts)
  end

  # Half the cases stay uncorrupted, so enough inputs get through.
  defp corruption_gen(corruptions),
    do: StreamData.one_of([StreamData.constant(:none), StreamData.member_of(corruptions)])

  # A redeclared base fact gets a string value in half the snapshots, so
  # Context has to hold the base fact to boolean against fact_fields (§ 4.2).
  defp domain_gen do
    gen all(
          {raw, _op, snapshot, _other, _} <- world_gen(),
          registry_corruption <- corruption_gen(@registry_corruptions),
          snapshot_corruption <-
            if(registry_corruption == :base_fact_redeclared,
              do:
                StreamData.one_of([
                  StreamData.constant(:string_base_fact),
                  corruption_gen(@snapshot_corruptions)
                ]),
              else: corruption_gen(@snapshot_corruptions)
            )
        ) do
      {corrupt_registry(raw, registry_corruption),
       corrupt_snapshot(snapshot, snapshot_corruption)}
    end
  end

  defp domain_case({raw, snapshot}) do
    case Registry.compile(raw) do
      {:ok, compiled} ->
        case KomkiPolicy.Context.validate_snapshot(snapshot, compiled) do
          {:ok, _} ->
            {%{"registry" => raw, "snapshot" => snapshot, "intent" => %{"operation" => "domain"}},
             %{"registry" => true, "snapshot" => true}}

          {:error, _} ->
            {%{"registry" => raw, "intent" => %{"operation" => "domain"}},
             %{"registry" => true, "snapshot" => nil}}
        end

      {:error, _} ->
        {nil, :dropped}
    end
  end

  defp corrupt_registry(raw, :none), do: raw

  defp corrupt_registry(raw, {:reader, o}),
    do: update_first_binding(raw, &Map.update!(&1, "readers", fn rs -> Enum.sort([o | rs]) end))

  defp corrupt_registry(raw, {:authority, o}),
    do:
      update_first_binding(raw, fn b ->
        Map.update!(b, "relaxation_authorities", fn rs ->
          [
            %{"authority" => o, "restriction" => "readers", "output" => "ratsprojekte-essenz"}
            | rs
          ]
        end)
      end)

  defp corrupt_registry(raw, {:environment, o}) do
    Map.update!(raw, "environments", fn envs ->
      [{id, env} | rest] = Enum.sort(envs)
      Map.new([{id, Map.update!(env, "observers", &Enum.sort([o | &1]))} | rest])
    end)
  end

  defp corrupt_registry(raw, :empty_readers),
    do: update_first_binding(raw, &Map.put(&1, "readers", []))

  defp corrupt_registry(raw, :duplicate_reader),
    do: update_first_binding(raw, &Map.update!(&1, "readers", fn [r | _] = rs -> rs ++ [r] end))

  defp corrupt_registry(raw, :unknown_transformation_label),
    do:
      Map.put(raw, "transformations", %{
        "t-x@1" => %{"input_labels" => ["b-fremd@1"], "output_labels" => []}
      })

  defp corrupt_registry(raw, :unknown_transformation_output) do
    [first | _] = raw["bindings"] |> Map.keys() |> Enum.sort()

    Map.put(raw, "transformations", %{
      "t-x@1" => %{"input_labels" => [first], "output_labels" => ["b-fremd@1"]}
    })
  end

  defp corrupt_registry(raw, :empty_transformation_input),
    do:
      Map.put(raw, "transformations", %{
        "t-x@1" => %{"input_labels" => [], "output_labels" => []}
      })

  defp corrupt_registry(raw, :base_fact_redeclared),
    do: put_in(raw, ["fact_fields", "has_operation_right"], "string")

  defp corrupt_registry(raw, {:expression, expr}),
    do: update_first_binding(raw, &put_in(&1, ["operations", "admit"], expr))

  defp update_first_binding(raw, fun) do
    Map.update!(raw, "bindings", fn bindings ->
      [{id, b} | rest] = Enum.sort(bindings)
      Map.new([{id, fun.(b)} | rest])
    end)
  end

  defp corrupt_snapshot(snapshot, :none), do: snapshot

  defp corrupt_snapshot(snapshot, :unsorted_bindings),
    do: update_in(snapshot, ["workspace", "bindings"], &Enum.reverse/1)

  defp corrupt_snapshot(snapshot, :duplicate_binding),
    do: update_in(snapshot, ["workspace", "bindings"], fn bs -> bs ++ Enum.take(bs, 1) end)

  defp corrupt_snapshot(snapshot, :unknown_binding),
    do: update_in(snapshot, ["workspace", "bindings"], &Enum.sort(["b-fremd@1" | &1]))

  defp corrupt_snapshot(snapshot, :unknown_environment),
    do: put_in(snapshot, ["workspace", "environment"], "env-fremd@1")

  defp corrupt_snapshot(snapshot, :string_base_fact),
    do: put_in(snapshot, ["facts", "has_operation_right"], entry("ja"))

  defp corrupt_snapshot(snapshot, :non_string_element),
    do: put_in(snapshot, ["facts", "tags"], entry(["x", 1]))

  defp corrupt_snapshot(snapshot, :wrong_fact_type),
    do: put_in(snapshot, ["facts", "count"], entry("viele"))

  defp corrupt_snapshot(snapshot, :undeclared_fact),
    do: put_in(snapshot, ["facts", "fremd"], entry(true))

  defp corrupt_snapshot(snapshot, :unknown_classification),
    do: put_in(snapshot, ["object", "classification"], "geheim")

  defp corrupt_snapshot(snapshot, :unsorted_labels),
    do: update_in(snapshot, ["object", "labels"], &Enum.reverse/1)

  defp corrupt_snapshot(snapshot, :duplicate_label),
    do: update_in(snapshot, ["object", "labels"], fn ls -> ls ++ Enum.take(ls, 1) end)

  defp seeded_list(generator) do
    generator
    |> StreamData.resize(30)
    |> StreamData.list_of(length: env_int("KOMKI_SPEC_RUNS", 8_000))
    |> StreamData.seeded(env_int("KOMKI_SPEC_SEED", 20_261_123))
    |> Enum.at(0)
  end

  # ---------------------------------------------------------------------
  # Releases (§ 4.6, § 4.9) and the stand (§ 2.7)
  # ---------------------------------------------------------------------

  defp release_world_gen do
    gen all(
          world <- world_gen(),
          variants <- StreamData.list_of(release_variant_gen(), length: 3)
        ) do
      {world, variants}
    end
  end

  # One or two wrong fields at once, so the fixed order of the release
  # checks shows (§ 4.6 step 3); an Offenlegungsfreigabe with or without one.
  defp release_variant_gen do
    simple = StreamData.member_of(Map.keys(@release_changes))

    StreamData.one_of([
      StreamData.map(StreamData.list_of(simple, min_length: 1, max_length: 2), &{:simple, &1}),
      StreamData.tuple(
        {StreamData.constant(:offenlegung),
         StreamData.frequency([
           {4, StreamData.constant(:matching)},
           {1, StreamData.constant("freigabe-notiz")}
         ]),
         StreamData.frequency([
           {4, StreamData.constant(["ratsprojekte@1"])},
           {1, StreamData.constant(["b-eins@1"])},
           {1, StreamData.constant(["b-unbekannt@1"])}
         ]), StreamData.integer(0..4), StreamData.list_of(simple, max_length: 1)}
      )
    ])
  end

  # Each variant against the snapshot and the repaired one; a release only
  # exists for the output rules.
  defp release_cases({{raw, op, snapshot, _other, _mutations}, variants}) do
    with true <- op in Derive.output_operations(),
         {:ok, registry} <- Registry.compile(raw) do
      for target <- [snapshot, repaired(snapshot, op)],
          variant <- variants,
          do:
            {raw, registry, target, intent(op), release_variant(raw, target, op, variant), @stand}
    else
      _ -> []
    end
  end

  defp fixture_release_cases do
    raw = fixture("registry.json")
    {:ok, registry} = Registry.compile(raw)

    for dir <- File.ls!(@fixtures_dir),
        File.exists?(Path.join([@fixtures_dir, dir, "release.json"])),
        do:
          {raw, registry, fixture(dir <> "/snapshot.json"), fixture(dir <> "/intent.json"),
           fixture(dir <> "/release.json"), fixture(dir <> "/stand.json")}
  end

  defp base_release(target, op, authority) do
    hash =
      case call_hash(target, intent(op)) do
        "" -> @hex
        hash -> hash
      end

    %{
      "schema" => "komki-release/1",
      "release_id" => "go-drt",
      "kind" => "aktionsfreigabe",
      "operation" => op,
      "object" => "obj-drt@v1",
      "workspace" => "ws-drt",
      "content_digest" => @hex,
      "call_hash" => hash,
      "scope" => "scope-drt",
      "authority" => authority,
      "valid_from" => 40,
      "valid_until" => 60,
      "nonce" => "n-neu"
    }
  end

  defp release_variant(raw, target, op, variant) do
    base = base_release(target, op, hd(raw["observers"]))

    case variant do
      {:offenlegung, art, ziellabel, index, changes} ->
        base |> offenlegung(raw, target, art, ziellabel, index) |> apply_changes(changes)

      {:simple, changes} ->
        apply_changes(base, changes)
    end
  end

  defp apply_changes(release, changes),
    do: Enum.reduce(changes, release, &Map.merge(&2, Map.fetch!(@release_changes, &1)))

  defp offenlegung(base, raw, target, art, ziellabel, index) do
    ausgabeart =
      if art == :matching,
        do: Derive.ziel_ausgabeart(target["workspace"]["environment"]) || "ratsprojekte-essenz",
        else: art

    observers = raw["observers"]

    Map.merge(base, %{
      "schema" => "komki-release/2",
      "kind" => "offenlegungsfreigabe",
      "ausgabeart" => ausgabeart,
      "ziellabel" => ziellabel,
      "authority" => Enum.at(observers, rem(index, length(observers)))
    })
  end

  # A release exactly as the offer reads, fresh nonce and valid window; for
  # the Offenlegungsfreigabe an authority holding every needed Befugnis.
  defp release_from_offer(registry, snapshot, intent, go) do
    op = intent["operation"]
    base = base_release(snapshot, op, hd(registry.observers))
    base = Map.merge(base, %{"call_hash" => go["call_hash"], "nonce" => "n-frisch"})

    case go["type"] do
      "aktionsfreigabe" ->
        base

      "offenlegungsfreigabe" ->
        checked = Derive.checked_label(op, snapshot["workspace"], snapshot["object"])
        rho = Calculus.actual_recipients(registry, snapshot["workspace"]["environment"])

        [authority | _] =
          Calculus.lockerungsbefugte(registry, checked, rho, go["ausgabeart"]) ++
            [base["authority"]]

        Map.merge(base, %{
          "schema" => "komki-release/2",
          "kind" => "offenlegungsfreigabe",
          "ausgabeart" => go["ausgabeart"],
          "ziellabel" => go["ziellabel"],
          "authority" => authority
        })
    end
  end

  defp advance_gen do
    gen all(
          version <- StreamData.integer(0..4),
          consumed <- subset_gen(~w(n-a n-b n-c), 0),
          nonce <- StreamData.member_of(~w(n-a n-b n-c n-d)),
          ref <- StreamData.member_of([0, 0, 0, -1, 1]),
          after_delta <- StreamData.member_of([1, 1, 1, 0, 2])
        ) do
      stand = %{
        @stand
        | "version" => version,
          "consumed" => Map.new(consumed, &{&1, "go-" <> &1})
      }

      {stand, proposal(nonce, max(version + ref, 0), version + after_delta)}
    end
  end

  defp proposal(nonce, ref_version, version_after) do
    %{
      "release_id" => "go-neu",
      "nonce" => nonce,
      "stand_ref" => "stand-drt@#{ref_version}",
      "stand_version_after" => version_after,
      "call_hash" => @hex
    }
  end

  # After a commit: the same nonce, addressed correctly to the next stand.
  defp replay_on(next, used) do
    {next, proposal(used["nonce"], next["version"], next["version"] + 1)}
  end

  defp world_gen do
    gen all(
          raw <- registry_gen(),
          op <- StreamData.member_of(Derive.proof_rules()),
          snapshot <- snapshot_gen(raw),
          other <- snapshot_gen(raw),
          mutations <- StreamData.list_of(mutation_gen(raw), min_length: 1, max_length: 3)
        ) do
      {raw, op, snapshot, other, mutations}
    end
  end

  defp registry_gen do
    gen all(
          observers <- subset_gen(@observers, 1),
          environments <- keyed_gen(@environments, fn -> subset_gen(observers, 1) end),
          bindings <- keyed_gen(@bindings, fn -> binding_gen(observers) end),
          transformations <- transformations_gen(Enum.map(bindings, &elem(&1, 0)))
        ) do
      %{
        "schema" => "komki-registry/2",
        "registry_id" => "reg-drt",
        "observers" => observers,
        "fact_fields" => @fact_fields,
        "environments" => Map.new(environments, fn {id, obs} -> {id, %{"observers" => obs}} end),
        "bindings" => Map.new(bindings),
        "transformations" => Map.new(transformations)
      }
    end
  end

  # Registered label transitions (§ 2.1): inputs non-empty, outputs may be empty.
  defp transformations_gen(binding_ids) do
    ids = Enum.sort(binding_ids)

    transformation =
      StreamData.tuple(
        {StreamData.member_of(~w(t-a@1 t-b@1 t-c@1)), subset_gen(ids, 1), subset_gen(ids, 0)}
      )

    StreamData.map(StreamData.list_of(transformation, max_length: 2), fn ts ->
      for {id, input, output} <- Enum.uniq_by(ts, &elem(&1, 0)),
          do: {id, %{"input_labels" => input, "output_labels" => output}}
    end)
  end

  # A non-empty subset of `ids`, each paired with its own generated value.
  defp keyed_gen(ids, value_gen) do
    StreamData.bind(subset_gen(ids, 1), fn chosen ->
      chosen
      |> Enum.map(fn id -> StreamData.map(value_gen.(), &{id, &1}) end)
      |> StreamData.fixed_list()
    end)
  end

  # Readers are often all observers, so the recipient test passes often enough.
  defp binding_gen(observers) do
    gen all(
          readers <-
            StreamData.frequency([
              {2, StreamData.constant(observers)},
              {1, subset_gen(observers, 1)}
            ]),
          operations <- rules_gen(),
          befugnisse <- StreamData.list_of(befugnis_gen(observers), max_length: 2)
        ) do
      %{
        "readers" => readers,
        "operations" => operations,
        "relaxation_authorities" => Enum.uniq(befugnisse)
      }
    end
  end

  # Mostly the one combination § 4.9 decides, sometimes another (R.2.2).
  defp befugnis_gen(observers) do
    gen all(
          authority <- StreamData.member_of(observers),
          {restriction, output} <-
            StreamData.frequency([
              {4, StreamData.constant({"readers", "ratsprojekte-essenz"})},
              {1, StreamData.constant({"operations", "ratsprojekte-essenz"})},
              {1, StreamData.constant({"readers", "freigabe-notiz"})}
            ])
        ) do
      %{"authority" => authority, "restriction" => restriction, "output" => output}
    end
  end

  # Each rule with its own expression, or absent (B.4: no rule, no permit).
  defp rules_gen do
    Derive.proof_rules()
    |> Enum.map(&{&1, maybe(expr_gen())})
    |> StreamData.fixed_map()
    |> StreamData.map(fn rules ->
      for {rule, expr} <- rules, expr != :absent, into: %{}, do: {rule, expr}
    end)
  end

  defp snapshot_gen(raw) do
    binding_ids = raw["bindings"] |> Map.keys() |> Enum.sort()

    gen all(
          bindings <- subset_gen(binding_ids, 0),
          labels <-
            StreamData.frequency([
              {3, subset_gen(bindings, 0)},
              {1, subset_gen(binding_ids, 0)},
              {2,
               StreamData.map(subset_gen(binding_ids, 0), &Enum.sort(Enum.uniq(&1 ++ bindings)))}
            ]),
          environment <- StreamData.member_of(Map.keys(raw["environments"])),
          valid <-
            StreamData.frequency([
              {9, StreamData.constant(true)},
              {1, StreamData.constant(false)}
            ]),
          classification <-
            StreamData.frequency([
              {9, StreamData.constant("classified")},
              {1, StreamData.constant("quarantine")}
            ]),
          identity <- StreamData.member_of(raw["observers"]),
          facts <- facts_gen()
        ) do
      %{
        "schema" => "komki-snapshot/1",
        "snapshot_id" => "snap-drt",
        "registry_ref" => "reg-drt",
        "identity" => identity,
        "workspace" => %{
          "workspace_id" => "ws-drt",
          "bindings" => bindings,
          "valid" => valid,
          "environment" => environment
        },
        "object" => %{
          "object_id" => "obj-drt",
          "version" => "v1",
          "classification" => classification,
          "labels" => labels
        },
        "facts" => facts
      }
    end
  end

  defp facts_gen do
    base = Enum.map(@base_facts, &{&1, maybe(weighted_bool())})

    domain = [
      {"purpose", maybe(StreamData.member_of(@purposes))},
      {"scope", maybe(StreamData.boolean())},
      {"count", maybe(StreamData.integer(0..5))},
      {"tags", maybe(subset_gen(@tags, 0))},
      {"output_content_digest", maybe(StreamData.member_of(~w(digest-a digest-b)))}
    ]

    StreamData.map(StreamData.fixed_map(base ++ domain), fn facts ->
      for {name, value} <- facts, value != :absent, into: %{}, do: {name, entry(value)}
    end)
  end

  defp entry(value), do: %{"value" => value, "source" => "drt", "source_kind" => "test"}

  defp weighted_bool,
    do: StreamData.frequency([{6, StreamData.constant(true)}, {1, StreamData.constant(false)}])

  defp maybe(gen), do: StreamData.frequency([{5, gen}, {1, StreamData.constant(:absent)}])

  defp subset_gen(list, min) do
    list
    |> Enum.map(fn _ -> StreamData.boolean() end)
    |> StreamData.fixed_list()
    |> StreamData.map(fn bits -> for {item, true} <- Enum.zip(list, bits), do: item end)
    |> StreamData.filter(&(length(&1) >= min))
  end

  defp expr_gen do
    leaf =
      StreamData.one_of([
        StreamData.boolean(),
        StreamData.map(StreamData.member_of(@purposes), &%{"eq" => ["purpose", &1]}),
        StreamData.map(StreamData.boolean(), &%{"eq" => ["scope", &1]}),
        StreamData.map(StreamData.integer(0..5), &%{"eq" => ["count", &1]}),
        StreamData.map(subset_gen(@purposes, 1), &%{"member" => ["purpose", &1]}),
        StreamData.map(subset_gen(@tags, 0), &%{"subset" => ["tags", &1]}),
        StreamData.map(StreamData.integer(0..5), &%{"at_most" => ["count", &1]})
      ])

    StreamData.tree(leaf, fn child ->
      StreamData.one_of([
        StreamData.map(StreamData.list_of(child, max_length: 3), &%{"all" => &1}),
        StreamData.map(StreamData.list_of(child, max_length: 3), &%{"any" => &1})
      ])
    end)
  end

  # ---------------------------------------------------------------------
  # Tree mutations: the forgery classes of the audit and beyond
  # ---------------------------------------------------------------------

  defp mutation_gen(raw) do
    index = StreamData.integer(0..12)
    binding_ids = Map.keys(raw["bindings"])
    names = Derive.proof_rules() |> Enum.flat_map(&Derive.required_premises/1) |> Enum.uniq()

    StreamData.one_of([
      StreamData.tuple({StreamData.constant(:flip_value), index}),
      # Unsorted, duplicated claims: assigned_label counts as a set, the rest exactly.
      StreamData.tuple(
        {StreamData.constant(:scramble), index, StreamData.member_of(@claim_fields)}
      ),
      # Same number, other JSON type: CONTRACT § 5 step 8 demands structural equality (#626).
      StreamData.constant(:floatify),
      StreamData.tuple({StreamData.constant(:drop), index}),
      StreamData.tuple({StreamData.constant(:duplicate), index}),
      StreamData.tuple(
        {StreamData.constant(:put), index, StreamData.constant("kind"),
         StreamData.member_of(["object_check", "fact", "computed", "condition"])}
      ),
      StreamData.tuple(
        {StreamData.constant(:put), index, StreamData.constant("name"),
         StreamData.member_of(names)}
      ),
      StreamData.tuple(
        {StreamData.constant(:put), index, StreamData.constant("fact"),
         StreamData.member_of(@base_facts ++ ["workspace_contract_valid", "scope"])}
      ),
      StreamData.tuple(
        {StreamData.constant(:put), index, StreamData.constant("binding"),
         StreamData.member_of(binding_ids ++ ["b-fremd@1"])}
      ),
      # null is an input error since #477; against older code it is the attack.
      StreamData.tuple(
        {StreamData.constant(:put), index, StreamData.constant("expression"),
         StreamData.one_of([expr_gen(), StreamData.constant(nil)])}
      ),
      StreamData.tuple(
        {StreamData.constant(:put), index, StreamData.member_of(@claim_fields),
         subset_gen(@observers ++ @bindings, 0)}
      ),
      StreamData.tuple(
        {StreamData.constant(:top), StreamData.constant("conclusion"),
         StreamData.member_of(["permit", "deny"])}
      ),
      StreamData.tuple(
        {StreamData.constant(:top), StreamData.constant("rule"),
         StreamData.member_of(Derive.proof_rules() ++ ["start"])}
      ),
      StreamData.tuple(
        {StreamData.constant(:top), StreamData.constant("checked_label"),
         subset_gen(@bindings, 0)}
      )
    ])
  end

  defp mutate({:flip_value, i}, proof),
    do: update_premise(proof, i, &Map.put(&1, "value", not Map.get(&1, "value", true)))

  defp mutate({:scramble, i, key}, proof),
    do: update_premise(proof, i, &Map.replace_lazy(&1, key, fn value -> scramble(value) end))

  defp mutate(:floatify, proof) do
    Map.update!(proof, "premises", fn premises -> Enum.map(premises, &floatify_expression/1) end)
  end

  defp mutate({:drop, i}, proof), do: Map.update!(proof, "premises", &List.delete_at(&1, i))

  defp mutate({:duplicate, i}, proof) do
    case Enum.at(proof["premises"], i) do
      nil -> proof
      premise -> Map.update!(proof, "premises", &(&1 ++ [premise]))
    end
  end

  defp mutate({:put, i, key, value}, proof),
    do: update_premise(proof, i, &Map.put(&1, key, value))

  defp mutate({:top, key, value}, proof), do: Map.put(proof, key, value)

  defp floatify_expression(%{"expression" => expression} = premise),
    do: Map.put(premise, "expression", floatify(expression))

  defp floatify_expression(premise), do: premise

  defp scramble([first | _] = list), do: Enum.reverse(list) ++ [first]
  defp scramble(value), do: value

  defp floatify(value) when is_integer(value), do: value * 1.0
  defp floatify(value) when is_list(value), do: Enum.map(value, &floatify/1)
  defp floatify(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, floatify(v)} end)
  defp floatify(value), do: value

  defp update_premise(proof, i, fun) do
    if i < length(proof["premises"]),
      do: Map.update!(proof, "premises", &List.update_at(&1, i, fun)),
      else: proof
  end
end
