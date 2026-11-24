defmodule KomkiPolicy.LeanSpecTest do
  @moduledoc false

  # Differential test of `Verify.check/4` against the proven Lean verifier
  # (#625, lean/README.md). Needs the binary from `cd lean && lake build`;
  # excluded by default, run with `mix test --only lean_spec`.
  #
  # Only cases inside the validated domain are compared: Elixir has to
  # return a verdict, an input error drops the case. Within that domain,
  # every verdict has to match. KOMKI_SPEC_SEED and KOMKI_SPEC_RUNS widen
  # the search; a mismatch writes its cases to a JSONL file for replay with
  # `komki-spec verify-batch`.

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias KomkiPolicy.{Derive, Registry, Verify}

  @moduletag :lean_spec
  @moduletag timeout: 600_000

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)
  @default_bin Path.expand("../../lean/.lake/build/bin/komki-spec", __DIR__)

  @observers ~w(o-a o-b o-c o-d o-e)
  @bindings ~w(b-drei@1 b-eins@1 b-vier@1 b-zwei@1)
  @environments ~w(env-drei@1 env-eins@1 env-zwei@1)
  @base_facts ~w(has_operation_right has_object_access_right audit_path_ready environment_observers_complete)
  @fact_fields %{
    "count" => "integer",
    "purpose" => "string",
    "scope" => "boolean",
    "tags" => "string_set"
  }
  @purposes ~w(antwort mandat recherche)
  @tags ~w(x y z)
  @claim_fields ~w(object_labels checked_label actual_recipients allowed_recipients fact_refs)

  @intent %{
    "schema" => "komki-intent/1",
    "intent_id" => "intent-drt",
    "operation" => "admit",
    "object" => "obj-drt@v1",
    "workspace" => "ws-drt"
  }

  test "Lean-Tabellen entsprechen Derive" do
    {out, 0} = System.cmd(spec_bin(), ["constants"])
    {:ok, constants} = KomkiPolicy.JSON.parse(String.trim(out))

    assert constants["admit_premises"] == Derive.required_premises("admit")
    assert constants["proof_rules"] == Derive.proof_rules()

    # Verify.lean takes B_W as the checked label of admit, never λ(x).
    assert Derive.checked_label("admit", %{"bindings" => ["b-eins@1"]}, %{
             "labels" => ["b-zwei@1"]
           }) ==
             ["b-eins@1"]
  end

  test "Fixture-Korpus: Elixir und Lean urteilen gleich" do
    raw = fixture("registry.json")
    {:ok, registry} = Registry.compile(raw)
    worlds = admit_fixture_worlds()

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

    assert stats.valid >= 2
    assert stats.invalid >= 100
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

    assert stats.valid >= 600
    assert stats.invalid >= 7_000
  end

  # ---------------------------------------------------------------------
  # Comparison
  # ---------------------------------------------------------------------

  defp compare!(cases, label) do
    judged =
      cases
      |> Enum.map(fn {raw, registry, snapshot, intent, proof} ->
        {raw, snapshot, intent, proof, elixir_verdict(registry, snapshot, intent, proof)}
      end)
      |> Enum.reject(fn {_, _, _, _, verdict} -> verdict == :input_error end)
      |> Enum.with_index()

    lean = lean_verdicts(judged)

    mismatches =
      for {{raw, snapshot, intent, proof, verdict}, id} <- judged,
          Map.get(lean, id) != verdict,
          do: {id, verdict, Map.get(lean, id), raw, snapshot, intent, proof}

    report_mismatches!(mismatches, label)

    %{
      compared: length(judged),
      dropped: length(cases) - length(judged),
      valid: Enum.count(judged, fn {{_, _, _, _, v}, _} -> v == "valid" end),
      invalid: Enum.count(judged, fn {{_, _, _, _, v}, _} -> v == "invalid" end)
    }
  end

  defp elixir_verdict(registry, snapshot, intent, proof) do
    case Verify.check(registry, snapshot, intent, proof) do
      {:ok, %{"result" => result}} -> result
      {:error, _} -> :input_error
    end
  end

  defp lean_verdicts(judged) do
    path = Path.join(System.tmp_dir!(), "komki-spec-#{System.unique_integer([:positive])}.jsonl")

    lines =
      for {{raw, snapshot, intent, proof, _}, id} <- judged do
        case_line(id, raw, snapshot, intent, proof)
      end

    File.write!(path, lines)

    try do
      {out, 0} = System.cmd(spec_bin(), ["verify-batch", path])

      for line <- String.split(out, "\n", trim: true), into: %{} do
        [id, result] = String.split(line, " ", parts: 2)
        {String.to_integer(id), result}
      end
    after
      File.rm(path)
    end
  end

  defp case_line(id, raw, snapshot, intent, proof) do
    JSON.encode!(%{
      "id" => id,
      "registry" => raw,
      "snapshot" => snapshot,
      "intent" => intent,
      "proof" => proof
    }) <> "\n"
  end

  defp report_mismatches!([], _label), do: :ok

  defp report_mismatches!(mismatches, label) do
    path = Path.join(System.tmp_dir!(), "komki-spec-mismatch-#{label}.jsonl")

    File.write!(
      path,
      for {id, _, _, raw, snapshot, intent, proof} <- mismatches do
        case_line(id, raw, snapshot, intent, proof)
      end
    )

    shown =
      mismatches
      |> Enum.take(5)
      |> Enum.map_join("\n", fn {id, elixir, lean, _, _, _, _} ->
        "  Fall #{id}: Elixir #{elixir}, Lean #{inspect(lean)}"
      end)

    flunk("""
    #{length(mismatches)} Abweichungen zwischen Verify.check/4 und dem Lean-Prüfer:
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

  defp admit_fixture_worlds do
    for dir <- File.ls!(@fixtures_dir),
        File.exists?(Path.join([@fixtures_dir, dir, "snapshot.json"])),
        File.exists?(Path.join([@fixtures_dir, dir, "intent.json"])),
        intent = fixture(Path.join(dir, "intent.json")),
        intent["operation"] == "admit" do
      {fixture(Path.join(dir, "snapshot.json")), intent}
    end
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
  # before ed7c4574 accepts them; the Lean verifier never does.
  defp audit_attacks do
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

  # Cases per world: the honest tree, the same tree against the second
  # snapshot (a proof from another world), trees from a repaired snapshot
  # (all base facts true, #480) and from a registry where every binding has
  # an admit rule (#477); each tree also with float literals (#626) and
  # mutated.
  defp world_cases({raw, snapshot, other, mutations}) do
    with {:ok, registry} <- Registry.compile(raw),
         {:ok, ruled} <- Registry.compile(with_admit_rules(raw)) do
      trees =
        [
          derived_proof(registry, snapshot, @intent),
          derived_proof(registry, repaired(snapshot), @intent),
          derived_proof(ruled, repaired(snapshot), @intent)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      for tree <- trees,
          {target, proof} <- [
            {snapshot, tree},
            {other, tree},
            {snapshot, mutate(:floatify, tree)},
            {snapshot, Enum.reduce(mutations, tree, &mutate/2)}
          ],
          do: {raw, registry, target, @intent, proof}
    else
      {:error, _} -> []
    end
  end

  defp with_admit_rules(raw) do
    Map.update!(raw, "bindings", fn bindings ->
      Map.new(bindings, fn {id, binding} ->
        {id, update_in(binding, ["operations"], &Map.put_new(&1, "admit", true))}
      end)
    end)
  end

  defp repaired(snapshot) do
    workspace = snapshot["workspace"]
    labels = Enum.filter(snapshot["object"]["labels"], &(&1 in workspace["bindings"]))

    facts =
      Enum.reduce(@base_facts, snapshot["facts"], fn name, acc ->
        Map.put(acc, name, entry(true))
      end)

    snapshot
    |> put_in(["workspace", "valid"], true)
    |> put_in(["object", "classification"], "classified")
    |> put_in(["object", "labels"], labels)
    |> Map.put("facts", facts)
  end

  defp world_gen do
    gen all(
          raw <- registry_gen(),
          snapshot <- snapshot_gen(raw),
          other <- snapshot_gen(raw),
          mutations <- StreamData.list_of(mutation_gen(raw), min_length: 1, max_length: 3)
        ) do
      {raw, snapshot, other, mutations}
    end
  end

  defp registry_gen do
    gen all(
          observers <- subset_gen(@observers, 1),
          environments <- keyed_gen(@environments, fn -> subset_gen(observers, 1) end),
          bindings <- keyed_gen(@bindings, fn -> binding_gen(observers) end)
        ) do
      %{
        "schema" => "komki-registry/2",
        "registry_id" => "reg-drt",
        "observers" => observers,
        "fact_fields" => @fact_fields,
        "environments" => Map.new(environments, fn {id, obs} -> {id, %{"observers" => obs}} end),
        "bindings" => Map.new(bindings)
      }
    end
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
          operations <-
            StreamData.frequency([
              {6, StreamData.map(expr_gen(), &%{"admit" => &1})},
              {1, StreamData.constant(%{})},
              {1, StreamData.constant(%{"emit" => true})}
            ])
        ) do
      %{"readers" => readers, "operations" => operations, "relaxation_authorities" => []}
    end
  end

  defp snapshot_gen(raw) do
    binding_ids = raw["bindings"] |> Map.keys() |> Enum.sort()

    gen all(
          bindings <- subset_gen(binding_ids, 0),
          labels <-
            StreamData.frequency([
              {4, subset_gen(bindings, 0)},
              {1, subset_gen(binding_ids, 0)}
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
      {"tags", maybe(subset_gen(@tags, 0))}
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

    StreamData.one_of([
      StreamData.tuple({StreamData.constant(:flip_value), index}),
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
         StreamData.member_of(Derive.required_premises("admit") ++ ["label_assignment"])}
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
         StreamData.member_of(["admit", "emit", "store"])}
      ),
      StreamData.tuple(
        {StreamData.constant(:top), StreamData.constant("checked_label"),
         subset_gen(@bindings, 0)}
      )
    ])
  end

  defp mutate({:flip_value, i}, proof),
    do: update_premise(proof, i, &Map.put(&1, "value", not Map.get(&1, "value", true)))

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
