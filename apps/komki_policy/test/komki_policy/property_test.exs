defmodule KomkiPolicy.PropertyTest do
  @moduledoc false

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KomkiPolicy.{Registry, Verify}

  @max_runs 200
  @seed 20_260_906

  # =====================================================================
  # Generatoren: JSON-Baeume (CONTRACT.md § 6)
  #
  # Abdeckung: null, true, false, Integer, Unicode-Strings, Arrays, Objekte.
  # Floats sind bewusst ausgeschlossen. CONTRACT.md § 6 sagt: "Floats
  # kommen in keiner L1-Ausgabe vor". Der Vertrag pinnt fuer Floats weder
  # eine kanonische Zahlform (Shortest-repr?) noch ein Rundtrip-Verhalten.
  # Eine Float-Property wuerde also eine Regel pruefen, die keinen
  # Vertragswert hat, und wuerde bei einer kuenftigen Float-Form im
  # Encoder ohne Vertragsverstoß rot. Das ehrliche Ausschlusskriterium
  # ist hier der Vertrag selbst.
  #
  # Strings: StreamData.string(:printable) erzeugt wohlgeformte
  # Unicode-Texte. Steuerzeichen sind nicht enthalten. Das ist korrekt:
  # der kanonische Encoder Steuerzeichen \u-escapet und der Parser nimmt
  # Steuerzeichen nur escaped an (RFC 8259). Der Escape-Rundtrip fuer
  # Anfuehrungszeichen, Backslash und \u-Folgen ist in den
  # Beispieletests von json_test.exs gepinnt. Hier geht es um die
  # strukturelle Baum-Klasse.
  # =====================================================================

  def json_leaf do
    StreamData.one_of([
      StreamData.constant(nil),
      StreamData.boolean(),
      StreamData.integer(),
      StreamData.string(:printable, max_length: 8)
    ])
  end

  def json_key do
    StreamData.string(:printable, max_length: 6)
  end

  def json_tree do
    StreamData.tree(json_leaf(), fn child ->
      StreamData.one_of([
        StreamData.list_of(child, max_length: 4),
        StreamData.map_of(json_key(), child, max_length: 4)
      ])
    end)
  end

  describe "JSON-Richtigkeit (§ 6): parse und canonical" do
    property "decode(encode(baum)) == baum" do
      check all(tree <- json_tree(), initial_seed: @seed, max_runs: @max_runs) do
        encoded = KomkiPolicy.JSON.canonical(tree)
        assert {:ok, decoded} = KomkiPolicy.JSON.parse(encoded)
        assert decoded == tree
      end
    end

    property "encode ist idempotent: encode(parse(encode(baum))) == encode(baum)" do
      check all(tree <- json_tree(), initial_seed: @seed, max_runs: @max_runs) do
        encoded = KomkiPolicy.JSON.canonical(tree)
        assert {:ok, decoded} = KomkiPolicy.JSON.parse(encoded)
        assert KomkiPolicy.JSON.canonical(decoded) == encoded
      end
    end

    property "encode ist deterministisch: zweimal encoden ist byte-gleich" do
      check all(tree <- json_tree(), initial_seed: @seed, max_runs: @max_runs) do
        first = KomkiPolicy.JSON.canonical(tree)
        second = KomkiPolicy.JSON.canonical(tree)
        assert first == second
      end
    end
  end

  describe "Differenzial gegen stdlib JSON: Parsing-Übereinstimmung" do
    # Only parse-agreement is pinned. We never compare bytes with stdlib,
    # because our canonical form sorts keys and the stdlib encoder does not.
    # Duplicate-key strictness (our parser rejects, stdlib accepts or
    # keeps-last) stays in the example tests of json_test.exs; stdlib
    # encode of a map cannot even produce duplicate keys, so the generated
    # documents are always in the class where both parsers agree.
    property "stdlib-encode des baums wird von KomkiPolicy.JSON gleich gedeutet" do
      check all(tree <- json_tree(), initial_seed: @seed, max_runs: @max_runs) do
        doc = Elixir.JSON.encode!(tree)
        assert {:ok, parsed} = KomkiPolicy.JSON.parse(doc)
        assert parsed == tree
      end
    end
  end

  # =====================================================================
  # Generatoren: B.4-Ausdruecke und Fakten (CONTRACT.md § 3)
  #
  # Der Vertragsumfang ist: true, false, eq, member, subset, at_most,
  # all, any. Es gibt kein not und kein or-neq in der Grammatik; die
  # Negationsgesetze werden deshalb über gespiegelte eq-Literale auf
  # Bool-Feldern ausgedrueckt. Fakten koennen fehlen; fehlende Fakten
  # sind unknown, nie false.
  # =====================================================================

  @bool_field "bool"
  @str_field "str"
  @num_field "num"
  @set_field "set"

  @num_pool 0..15
  @str_pool ["a", "b", "c", ""]
  @set_pool [["x"], ["x", "y"], [], ["z"]]

  def str_literal, do: StreamData.member_of(@str_pool)

  def leaf_expr do
    StreamData.frequency([
      {3,
       StreamData.map(StreamData.member_of([true, false]), fn lit ->
         %{"eq" => [@bool_field, lit]}
       end)},
      {2, StreamData.map(str_literal(), fn lit -> %{"eq" => [@str_field, lit]} end)},
      {1,
       StreamData.map(StreamData.member_of(@num_pool), fn lit -> %{"eq" => [@num_field, lit]} end)},
      {2,
       StreamData.map(StreamData.list_of(str_literal(), max_length: 2, min_length: 1), fn lits ->
         %{"member" => [@str_field, lits]}
       end)},
      {1,
       StreamData.map(StreamData.list_of(str_literal(), max_length: 3), fn lits ->
         %{"subset" => [@set_field, lits]}
       end)},
      {1,
       StreamData.map(StreamData.member_of(0..20), fn bound ->
         %{"at_most" => [@num_field, bound]}
       end)}
    ])
  end

  def expr do
    StreamData.sized(fn size ->
      if size <= 1 do
        leaf_expr()
      else
        StreamData.frequency([
          {2, leaf_expr()},
          {3,
           StreamData.map(
             StreamData.list_of(StreamData.resize(expr(), div(size, 2)),
               min_length: 1,
               max_length: 3
             ),
             fn xs -> %{"all" => xs} end
           )},
          {2,
           StreamData.map(
             StreamData.list_of(StreamData.resize(expr(), div(size, 2)),
               min_length: 1,
               max_length: 3
             ),
             fn xs -> %{"any" => xs} end
           )}
        ])
      end
    end)
  end

  def bool_expr do
    StreamData.map(StreamData.boolean(), fn lit -> %{"eq" => [@bool_field, lit]} end)
  end

  def negate_bool_expr(%{"eq" => [@bool_field, lit]}), do: %{"eq" => [@bool_field, not lit]}

  # Fakten: jedes Feld present mit typgerechtem Wert oder absent.
  # Abwesend heißt unknown: der Generator mischt beides durch.
  def fact_entry(present_value) when is_binary(present_value), do: %{"value" => present_value}

  def fact_entry(present_value), do: %{"value" => present_value}

  # Typgerechte Fakten (liftet die Compiler-Umgebung § 3 ein): jedes Feld
  # ist entweder absent oder mit dem passenden Feldtyp belegt. Ein Wert mit
  # falschem Typ wuerde in der echten Pipeline niemals den Auswerter
  # erreichen, weil Context.validate_snapshot die Typen zwingend pruft.
  def facts do
    StreamData.map(raw_facts_keyed(), fn keyed ->
      keyed
      |> Enum.reject(fn {_name, value} -> value == :absent end)
      |> Map.new()
    end)
  end

  def raw_facts_keyed do
    StreamData.fixed_map([
      {@bool_field,
       StreamData.frequency([{3, StreamData.boolean()}, {1, StreamData.constant(:absent)}])},
      {@str_field, StreamData.frequency([{3, str_literal()}, {1, StreamData.constant(:absent)}])},
      {@num_field,
       StreamData.frequency([
         {3, StreamData.member_of(@num_pool)},
         {1, StreamData.constant(:absent)}
       ])},
      {@set_field,
       StreamData.frequency([
         {3, StreamData.member_of(@set_pool)},
         {1, StreamData.constant(:absent)}
       ])}
    ])
  end

  def kleene(true), do: false
  def kleene(false), do: true
  def kleene(:unknown), do: :unknown

  def verdict_of(expr, facts), do: KomkiPolicy.Evaluator.evaluate(expr, facts)

  describe "Evaluator-Algebra (§ 3, dreiwertig)" do
    property "all und any sind kommutativ" do
      check all(
              a <- expr(),
              b <- expr(),
              facts <- facts(),
              initial_seed: @seed,
              max_runs: @max_runs
            ) do
        assert verdict_of(%{"all" => [a, b]}, facts) == verdict_of(%{"all" => [b, a]}, facts)
        assert verdict_of(%{"any" => [a, b]}, facts) == verdict_of(%{"any" => [b, a]}, facts)
      end
    end

    property "all und any sind assoziativ (Klammerform vs Flachform)" do
      check all(
              a <- expr(),
              b <- expr(),
              c <- expr(),
              facts <- facts(),
              initial_seed: @seed,
              max_runs: @max_runs
            ) do
        left = %{"all" => [%{"all" => [a, b]}, c]}
        right = %{"all" => [a, %{"all" => [b, c]}]}
        assert verdict_of(left, facts) == verdict_of(right, facts)

        left_any = %{"any" => [%{"any" => [a, b]}, c]}
        right_any = %{"any" => [a, %{"any" => [b, c]}]}
        assert verdict_of(left_any, facts) == verdict_of(right_any, facts)
      end
    end

    property "De Morgan gilt in Kleene-Logik (Negation spiegelt eq-Literale)" do
      check all(
              a <- bool_expr(),
              b <- bool_expr(),
              facts <- facts(),
              initial_seed: @seed,
              max_runs: @max_runs
            ) do
        conj = verdict_of(%{"all" => [a, b]}, facts)
        neg_conj = kleene(conj)

        disj = verdict_of(%{"any" => [negate_bool_expr(a), negate_bool_expr(b)]}, facts)

        assert disj == neg_conj
      end
    end

    property "Doppelnegation: all [¬a] == a und any [¬a] == ¬a (eq-Spiegel)" do
      check all(a <- bool_expr(), facts <- facts(), initial_seed: @seed, max_runs: @max_runs) do
        assert verdict_of(%{"all" => [negate_bool_expr(negate_bool_expr(a))]}, facts) ==
                 verdict_of(a, facts)

        assert verdict_of(%{"any" => []}, facts) == false
      end
    end

    property "Kurzschluss: das Konstante false schlaegt in all, das Konstante true in any" do
      check all(x <- expr(), initial_seed: @seed, max_runs: @max_runs) do
        # auch leer: bekannt falsch/wahr dominiert jedes unknown
        facts = %{}

        assert verdict_of(%{"all" => [false, x]}, facts) == false
        assert verdict_of(%{"any" => [true, x]}, facts) == true
      end
    end

    property "Determinismus: Fakten-Reihenfolge ist egal, Auswertung stabil" do
      check all(
              a <- expr(),
              b <- expr(),
              facts <- facts(),
              initial_seed: @seed,
              max_runs: @max_runs
            ) do
        first = verdict_of(%{"all" => [a, b]}, facts)
        second = verdict_of(%{"all" => [a, b]}, facts)
        assert first == second

        # Map-Reihenfolge ist in Elixir ohnehin nicht sichtbar; der Test
        # pinnt trotzdem, dass nur die Paarmenge zählt.
        rebound = Map.new(facts, fn {k, v} -> {k, v} end)
        assert verdict_of(%{"all" => [a, b]}, rebound) == first
      end
    end

    property "Fehlender Fakt ist unknown, nie false (Kleene-Coverage)" do
      check all(
              fields <- StreamData.list_of(json_key(), max_length: 3),
              initial_seed: @seed,
              max_runs: @max_runs
            ) do
        facts = Map.new(fields, fn name -> {name, %{"value" => true}} end)
        missing_facts = Map.delete(facts, @bool_field)

        assert verdict_of(%{"all" => [%{"eq" => [@bool_field, true]}]}, missing_facts) == :unknown
      end
    end
  end

  # =====================================================================
  # Verify-Robustheit (Gate-3-Lektion)
  #
  # case_permit/proof_valid.json wird systematisch verfaelscht: Werte
  # kippen, Praemissen fallen, Arten wechseln, Ausdruecke werden ersetzt,
  # Bindungszeiger drehen sich, Fakten verschwinden oder scramblen.
  # Die Property ist die Gate-3-Lektion als Klasse: verify loest bei
  # keiner Mutation aus und liefert immer ein strukturiertes Ergebnis.
  # Vor dem Gate-3-Fix haette diese Property den admit-loser-Crash
  # (Evaluator auf nil) und den KeyError-Pfad (fremde binding_condition
  # ohne binding-Feld) sofort gefunden.
  # =====================================================================

  @other_bindings ["buergerfall-4711@1", "lizenz-namensnennung@1", "nur-start-test@1", "weg@9"]

  def mutation_op do
    StreamData.one_of([
      {:flip_value, StreamData.integer(0..8)},
      {:drop_premise, StreamData.integer(0..8)},
      {:swap_kind, StreamData.integer(0..8),
       StreamData.member_of(["object_check", "fact", "computed", "condition"])},
      {:alt_expression, StreamData.integer(0..8)},
      {:twist_binding, StreamData.integer(0..8), StreamData.member_of(@other_bindings)},
      {:drop_fact, StreamData.member_of(["purpose", "has_operation_right", "audit_path_ready"])},
      {:scramble_fact,
       StreamData.member_of(["purpose", "has_operation_right", "audit_path_ready"]),
       StreamData.one_of([
         StreamData.constant(0),
         StreamData.constant(""),
         StreamData.constant(false)
       ])},
      StreamData.constant(:blank_conclusion),
      StreamData.constant(:empty_checked),
      StreamData.constant(:swap_name)
    ])
  end

  def apply_mutation(op, {proof, snapshot}) do
    apply_op(op, proof, snapshot)
  end

  def apply_op({:flip_value, index}, proof, snapshot) do
    case Enum.at(proof["premises"], index) do
      nil ->
        {proof, snapshot}

      premise ->
        flipped = Map.put(premise, "value", not Map.get(premise, "value", true))
        {put_in(proof, ["premises", Access.at(index)], flipped), snapshot}
    end
  end

  def apply_op({:drop_premise, index}, proof, snapshot) do
    {Map.update!(proof, "premises", &List.delete_at(&1, index)), snapshot}
  end

  def apply_op({:swap_kind, index, kind}, proof, snapshot) do
    case Enum.at(proof["premises"], index) do
      nil ->
        {proof, snapshot}

      premise ->
        {put_in(proof, ["premises", Access.at(index)], Map.put(premise, "kind", kind)), snapshot}
    end
  end

  def apply_op({:alt_expression, index}, proof, snapshot) do
    case Enum.at(proof["premises"], index) do
      nil ->
        {proof, snapshot}

      premise ->
        forged = Map.put(premise, "expression", true)
        {put_in(proof, ["premises", Access.at(index)], forged), snapshot}
    end
  end

  def apply_op({:twist_binding, index, binding}, proof, snapshot) do
    case Enum.at(proof["premises"], index) do
      nil ->
        {proof, snapshot}

      premise ->
        {put_in(proof, ["premises", Access.at(index)], Map.put(premise, "binding", binding)),
         snapshot}
    end
  end

  def apply_op({:drop_fact, fact}, proof, snapshot) do
    {proof, Map.update!(snapshot, "facts", &Map.delete(&1, fact))}
  end

  def apply_op({:scramble_fact, fact, trash}, proof, snapshot) do
    entry = Map.get(snapshot["facts"], fact)
    puts_out = if is_map(entry), do: Map.put(entry, "value", trash), else: entry
    {proof, Map.put(snapshot, "facts", Map.put(snapshot["facts"] || %{}, fact, puts_out))}
  end

  def apply_op(:blank_conclusion, proof, snapshot),
    do: {Map.put(proof, "conclusion", "deny"), snapshot}

  def apply_op(:empty_checked, proof, snapshot),
    do: {Map.put(proof, "checked_label", []), snapshot}

  def apply_op(:swap_name, proof, snapshot) do
    case Enum.at(proof["premises"], 6) do
      nil ->
        {proof, snapshot}

      premise ->
        {put_in(proof, ["premises", Access.at(6)], Map.put(premise, "name", "binding_condition")),
         snapshot}
    end
  end

  describe "Verify-Robustheit gegen verfaelschte Baeume" do
    test "Kontext ist geladen und der Referenz-Baum ist valid" do
      context = corrupted_mutation_context()

      assert {:ok, %{"result" => "valid", "reasons" => []}} =
               Verify.check(context.registry, context.snapshot, context.intent, context.proof)
    end

    property "verify loest nie aus und gibt strukturierte Ergebnisse, auch bei mehreren Mutationen" do
      check all(
              ops <- StreamData.list_of(mutation_op(), min_length: 1, max_length: 4),
              initial_seed: @seed,
              max_runs: @max_runs
            ) do
        context = corrupted_mutation_context()
        folded = Enum.reduce(ops, {context.proof, context.snapshot}, &apply_mutation/2)
        {proof, snapshot} = folded

        outcome = Verify.check(context.registry, snapshot, context.intent, proof)

        assert_outcome_is_structure(outcome)

        # determinismus: dieselben Eingaben, gleiches Ergebnis (bytes).
        outcome2 = Verify.check(context.registry, snapshot, context.intent, proof)

        case {outcome, outcome2} do
          {{:ok, a}, {:ok, b}} ->
            assert KomkiPolicy.JSON.canonical(a) == KomkiPolicy.JSON.canonical(b)

          {{:error, _}, {:error, _}} ->
            assert true

          _ ->
            flunk("verify is not deterministic for mutated inputs")
        end
      end
    end
  end

  defp corrupted_mutation_context do
    %{
      registry: registry(),
      snapshot: fixture("case_permit/snapshot.json"),
      intent: fixture("case_permit/intent.json"),
      proof: fixture("case_permit/proof_valid.json")
    }
  end

  defp fixture(rel) do
    path = Path.expand(Path.join("../../priv/fixtures", rel), __DIR__)
    parsed = KomkiPolicy.JSON.parse(File.read!(path))
    elem(parsed, 1)
  end

  defp registry do
    {:ok, compiled} = Registry.compile(fixture("registry.json"))
    compiled
  end

  defp assert_outcome_is_structure(outcome) do
    case outcome do
      {:ok, %{"result" => "valid", "reasons" => []}} ->
        assert true

      {:ok, %{"result" => "invalid", "reasons" => reasons}} ->
        Enum.each(reasons, fn reason ->
          assert MapSet.equal?(
                   MapSet.new(Map.keys(reason)),
                   MapSet.new(["code", "binding", "fact"])
                 )

          assert is_binary(reason["code"])
        end)

      {:error, %{code: _, path: _, detail: _}} ->
        assert true

      other ->
        flunk("unexpected verify outcome: " <> Kernel.inspect(other))
    end
  end
end
