defmodule KomkiPolicy.LeanSpecTest do
  @moduledoc false

  # Differential tests of `Verify.check/4` and `Derive.decide/3` against the
  # proven Lean model (#625, #629, lean/README.md). Needs the binary from
  # `cd lean && lake build`; excluded by default, run with
  # `mix test --only lean_spec`.
  #
  # Only cases inside the validated domain are compared: Elixir has to
  # return a verdict, a decision or a modelled input error, which is every
  # input error of `verify`, `derive` and `advance`, `Registry.compile/1`
  # included. Within
  # that domain, everything compared has to match. KOMKI_SPEC_SEED and
  # KOMKI_SPEC_RUNS widen the search; a mismatch writes its cases to a JSONL
  # file for replay with `komki-spec verify-batch` or `derive-batch`.

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias KomkiPolicy.{Calculus, CLI, Context, Derive, Evaluator, Registry, Release, Stand, Verify}

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
  # Every reason code of verify.ex, in check order (§ 5).
  @verify_codes ~w(snapshot_mismatch registry_mismatch intent_mismatch rule_mismatch
                   unsupported_rule checked_label_mismatch missing_required_premise
                   unknown_premise fact_missing fact_value_mismatch premise_not_true
                   object_quarantine label_inclusion_false label_assignment_false
                   label_preservation_false recipient_inclusion_false expression_mismatch
                   fact_refs_mismatch condition_false condition_unknown conclusion_mismatch
                   conclusion_unsupported)
  # Input errors of verify: intent, snapshot and coherence (§ 2.2, § 2.3),
  # the output prerequisites and the proof's validation (§ 4.5, § 5).
  @proof_input_errors ~w(invalid_record invalid_reference_id unknown_environment
                         unknown_fact_field intent_snapshot_mismatch invalid_flag
                         invalid_classification invalid_fact_value invalid_operation
                         invalid_reference_list invalid_source invalid_source_kind
                         registry_ref_mismatch unknown_binding_reference unknown_observer
                         unsorted_references emit_digest_missing
                         emit_object_not_classified missing_field invalid_schema unknown_field
                         invalid_entry invalid_premise invalid_premise_kind
                         unknown_premise_field)
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

  # Breaks reaching every code of Registry.compile/1 on every level
  # (CONTRACT § 2.1, § 3), the pairs listed in @registry_errors. New entries
  # get their own ids; `:observer` stands for an observer of the world,
  # `:binding` for one of its bindings, `@binding_spec` for a valid binding.
  @binding_spec %{
    "readers" => [:observer],
    "operations" => %{},
    "relaxation_authorities" => []
  }
  @authority %{"authority" => :observer, "restriction" => "readers", "output" => "sitzungsmappe"}
  @registry_breaks [
    {[], 7},
    {["schema"], :delete},
    {["schema"], "komki-registry/1"},
    {["zusatz"], true},
    {["registry_id"], "Reg 1"},
    {["observers"], "o-a"},
    {["observers"], []},
    {["observers"], [7]},
    {["observers"], ["o-a", "o-a"]},
    {["observers"], ["O"]},
    {["observers"], ["O", "O"]},
    {["fact_fields"], :delete},
    {["fact_fields"], 7},
    {["fact_fields", "count"], "float"},
    {["environments"], %{}},
    {["environments", "kein-ref"], %{"observers" => [:observer]}},
    {["environments", "env-neu@1"], 7},
    {["environments", "env-neu@1"], %{"observers" => [:observer], "zusatz" => 1}},
    {["environments", "env-neu@1"], %{"observers" => []}},
    {["environments", "env-neu@1"], %{"observers" => ["o-fremd"]}},
    {["environments", "env-neu@1"], %{"observers" => ["O"]}},
    {["environments", "env-neu@1"], %{"observers" => 7}},
    {["bindings"], 7},
    {["bindings", "kein-ref"], @binding_spec},
    {["bindings", "b-neu@1"], 7},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "zusatz", 1)},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "readers", "o-a")},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "readers", ["o-fremd"])},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "readers", ["O"])},
    {["bindings", "b-neu@1"], Map.delete(@binding_spec, "relaxation_authorities")},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "relaxation_authorities", [7])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [Map.put(@authority, "zusatz", 1)])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [Map.put(@authority, "authority", "O")])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [
       Map.put(@authority, "authority", "o-fremd")
     ])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [Map.put(@authority, "restriction", "x")])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [Map.put(@authority, "output", "O")])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [Map.put(@authority, "output", "x-y")])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [@authority, @authority])},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "operations", 7)},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "operations", %{"plan" => true})},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "operations", %{"admit" => 7})},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{"admit" => %{"eq" => ["count"]}})},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{"emit" => %{"all" => [true, %{"not" => 1}]}})},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{"store" => %{"eq" => ["fremd", 1]}})},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{"transfer" => %{"eq" => ["count", "x"]}})},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{"admit" => %{"eq" => ["scope", nil]}})},
    # Valid: an empty `member` list on a scalar field.
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{"emit" => %{"member" => ["count", []]}})},
    {["transformations"], 7},
    {["transformations"], nil},
    {["transformations", "kein-ref"], %{"input_labels" => [], "output_labels" => []}},
    {["transformations", "t-neu@1"], 7},
    {["transformations", "t-neu@1"], %{"input_labels" => "x", "output_labels" => []}},
    {["transformations", "t-neu@1"], %{"input_labels" => [7], "output_labels" => []}},
    {["transformations", "t-neu@1"], %{"input_labels" => [], "output_labels" => []}},
    {["transformations", "t-neu@1"], %{"input_labels" => ["z@1", "a@1"], "output_labels" => []}},
    {["transformations", "t-neu@1"], %{"input_labels" => ["x@1"], "output_labels" => []}},
    {["transformations", "t-neu@1"], %{"input_labels" => [:binding], "output_labels" => 7}},
    {["transformations", "t-neu@1"],
     %{"input_labels" => [:binding], "output_labels" => ["z@1", "a@1"]}},
    {["transformations", "t-neu@1"], %{"input_labels" => [:binding], "output_labels" => ["x@1"]}},
    {["transformations", "t-neu@1"],
     %{"input_labels" => ["x@1"], "output_labels" => [], "zusatz" => 1}},
    # Two defects in one entry, so the order within it shows.
    {["bindings", "b-neu@1"], Map.merge(@binding_spec, %{"zusatz" => 1, "readers" => "o-a"})},
    {["bindings", "b-neu@1"],
     Map.merge(@binding_spec, %{"readers" => "o-a", "relaxation_authorities" => 7})},
    {["bindings", "b-neu@1"],
     Map.merge(@binding_spec, %{"relaxation_authorities" => 7, "operations" => 7})},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [
       %{@authority | "authority" => "o-fremd", "restriction" => "x"}
     ])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [
       Map.merge(@authority, %{"authority" => "O", "zusatz" => 1})
     ])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "relaxation_authorities", [
       %{@authority | "restriction" => "x", "output" => "O"}
     ])},
    {["bindings", "b-neu@1"], Map.put(@binding_spec, "relaxation_authorities", [@authority, 7])},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{"plan" => true, "admit" => 7})},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{"admit" => 7, "emit" => %{"not" => 1}})},
    {["bindings", "b-neu@1"],
     Map.put(@binding_spec, "operations", %{
       "admit" => %{"any" => [%{"eq" => ["fremd", 1]}, %{"not" => 1}]}
     })},
    {["environments", "env-neu@1"], %{"observers" => [], "zusatz" => 1}},
    {["transformations", "t-neu@1"], %{"input_labels" => [], "output_labels" => 7}}
  ]

  # Every code and path the registry breaks reach.
  @registry_errors [
    {"duplicate_entry", "$.observers"},
    {"duplicate_relaxation_authority", "$.bindings.b-neu@1.relaxation_authorities"},
    {"empty_list", "$.environments.env-neu@1.observers"},
    {"empty_list", "$.observers"},
    {"empty_list", "$.transformations.t-neu@1.input_labels"},
    {"invalid_entry", "$.bindings.b-neu@1.readers"},
    {"invalid_entry", "$.environments.env-neu@1.observers"},
    {"invalid_entry", "$.observers"},
    {"invalid_fact_type", "$.fact_fields"},
    {"invalid_observers", "$.bindings.b-neu@1.readers"},
    {"invalid_observers", "$.environments.env-neu@1.observers"},
    {"invalid_observers", "$.observers"},
    {"invalid_operations", "$.bindings.b-neu@1.operations"},
    {"invalid_output_kind", "$.bindings.b-neu@1.relaxation_authorities.[0].output"},
    {"invalid_record", "$"},
    {"invalid_record", "$.bindings.b-neu@1"},
    {"invalid_record", "$.bindings.b-neu@1.relaxation_authorities.[0]"},
    {"invalid_record", "$.environments.env-neu@1"},
    {"invalid_record", "$.transformations.t-neu@1"},
    {"invalid_reference_id", "$.bindings"},
    {"invalid_reference_id", "$.bindings.b-neu@1.relaxation_authorities.[0].authority"},
    {"invalid_reference_id", "$.bindings.b-neu@1.relaxation_authorities.[0].output"},
    {"invalid_reference_id", "$.environments"},
    {"invalid_reference_id", "$.transformations"},
    {"invalid_registry_id", "$.registry_id"},
    {"invalid_relaxation_authorities", "$.bindings.b-neu@1.relaxation_authorities"},
    {"invalid_restriction_kind", "$.bindings.b-neu@1.relaxation_authorities.[0].restriction"},
    {"invalid_schema", "$.schema"},
    {"invalid_transformations", "$.transformations"},
    {"invalid_transformations", "$.transformations.t-neu@1.input_labels"},
    {"no_bindings", "$.bindings"},
    {"no_environments", "$.environments"},
    {"unknown_binding_reference", "$.transformations.t-neu@1.input_labels"},
    {"unknown_binding_reference", "$.transformations.t-neu@1.output_labels"},
    {"unknown_fact_field", "$.bindings.b-neu@1.operations.store"},
    {"unknown_field", "$.bindings.b-neu@1.relaxation_authorities.[0].zusatz"},
    {"unknown_field", "$.bindings.b-neu@1.zusatz"},
    {"unknown_field", "$.environments.env-neu@1.zusatz"},
    {"unknown_field", "$.transformations.t-neu@1.zusatz"},
    {"unknown_field", "$.zusatz"},
    {"unknown_observer", "$.bindings.b-neu@1.readers"},
    {"unknown_observer", "$.bindings.b-neu@1.relaxation_authorities.[0].authority"},
    {"unknown_observer", "$.environments.env-neu@1.observers"},
    {"unknown_operation", "$.bindings.b-neu@1.operations.plan"},
    {"invalid_transformations", "$.transformations.t-neu@1.output_labels"},
    {"expression_type_mismatch", "$.bindings.b-neu@1.operations.admit"},
    {"expression_type_mismatch", "$.bindings.b-neu@1.operations.transfer"},
    {"unsorted_references", "$.transformations.t-neu@1.input_labels"},
    {"unsorted_references", "$.transformations.t-neu@1.output_labels"},
    {"unsupported_expression", "$.bindings.b-neu@1.operations.admit"},
    {"unsupported_expression", "$.bindings.b-neu@1.operations.emit.[1]"}
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
    :duplicate_label,
    # One per code and path of validate_snapshot/2; `:delete` drops the
    # key, `[]` replaces the whole record.
    {:break, [], 7},
    {:break, ["schema"], "komki-snapshot/0"},
    {:break, ["schema"], :delete},
    {:break, ["zusatz"], true},
    {:break, ["aaa"], true},
    {:break, ["snapshot_id"], "Snap 1"},
    {:break, ["registry_ref"], "reg-fremd"},
    {:break, ["identity"], "fremd"},
    {:break, ["workspace"], 7},
    {:break, ["workspace", "zusatz"], 1},
    {:break, ["workspace", "workspace_id"], nil},
    {:break, ["workspace", "valid"], "ja"},
    {:break, ["workspace", "bindings"], "b-eins@1"},
    {:break, ["workspace", "bindings"], [7]},
    {:break, ["workspace", "bindings"], ["z@1", "a@1"]},
    {:break, ["workspace", "bindings"], ["b-fremd@1"]},
    {:break, ["workspace", "environment"], :delete},
    {:break, ["workspace", "environment"], "env-fremd"},
    {:break, ["object"], []},
    {:break, ["object", "zusatz"], 1},
    {:break, ["object", "object_id"], "Obj"},
    {:break, ["object", "version"], "v_1"},
    {:break, ["object", "classification"], "offen"},
    {:break, ["object", "labels"], nil},
    {:break, ["object", "labels"], ["b-fremd@1"]},
    {:break, ["facts"], 7},
    {:break, ["facts", "audit_path_ready"], 7},
    {:break, ["facts", "audit_path_ready", "zusatz"], 1},
    # Undeclared and with a foreign field: the closed fields come first.
    {:break, ["facts", "fremd"], %{"value" => true, "source" => "s", "zusatz" => 1}},
    {:break, ["facts", "audit_path_ready", "source"], 7},
    {:break, ["facts", "audit_path_ready", "source"], :delete},
    {:break, ["facts", "audit_path_ready", "value"], "ja"},
    {:break, ["facts", "count", "value"], 2.0},
    {:break, ["facts", "fremd"], %{"value" => true, "source" => "s", "source_kind" => "test"}},
    {:break, ["facts", "audit_path_ready", "source_kind"], "erfunden"},
    {:break, ["facts", "audit_path_ready", "value"], nil}
  ]
  # One per code and path of validate_intent/1 and ensure_coherence/2.
  @intent_corruptions [
    {:break, [], "intent"},
    {:break, ["schema"], "komki-intent/0"},
    {:break, ["schema"], :delete},
    {:break, ["zusatz"], true},
    {:break, ["aaa"], true},
    {:break, ["intent_id"], "Intent 1"},
    {:break, ["object"], "obj-drt"},
    {:break, ["workspace"], 7},
    {:break, ["operation"], "plan"},
    {:break, ["workspace"], "ws-fremd"},
    {:break, ["object"], "obj-fremd@v1"},
    {:break, ["object"], "obj-drt@v2"},
    {:break, ["object"], "a@b@c"}
  ]

  # Every code and path the breaks above reach (validate_intent/1,
  # validate_snapshot/2, ensure_coherence/2).
  @context_errors [
    {"intent_snapshot_mismatch", "$.object"},
    {"intent_snapshot_mismatch", "$.workspace"},
    {"invalid_classification", "$.object.classification"},
    {"invalid_fact_value", "$.facts.audit_path_ready.value"},
    {"invalid_fact_value", "$.facts.count.value"},
    {"invalid_flag", "$.workspace.valid"},
    {"invalid_operation", "$.operation"},
    {"invalid_record", "$"},
    {"invalid_record", "$.facts"},
    {"invalid_record", "$.facts.audit_path_ready"},
    {"invalid_record", "$.object"},
    {"invalid_record", "$.workspace"},
    {"invalid_reference_id", "$.intent_id"},
    {"invalid_reference_id", "$.object"},
    {"invalid_reference_id", "$.object.object_id"},
    {"invalid_reference_id", "$.object.version"},
    {"invalid_reference_id", "$.snapshot_id"},
    {"invalid_reference_id", "$.workspace"},
    {"invalid_reference_id", "$.workspace.workspace_id"},
    {"invalid_reference_list", "$.object.labels"},
    {"invalid_reference_list", "$.workspace.bindings"},
    {"invalid_schema", "$.schema"},
    {"invalid_source", "$.facts.audit_path_ready.source"},
    {"invalid_source_kind", "$.facts.audit_path_ready.source_kind"},
    {"registry_ref_mismatch", "$.registry_ref"},
    {"unknown_binding_reference", "$.object.labels"},
    {"unknown_binding_reference", "$.workspace.bindings"},
    {"unknown_environment", "$.workspace.environment"},
    {"unknown_fact_field", "$.facts.fremd"},
    {"unknown_field", "$.aaa"},
    {"unknown_field", "$.facts.audit_path_ready.zusatz"},
    {"unknown_field", "$.facts.fremd.zusatz"},
    {"unknown_field", "$.object.zusatz"},
    {"unknown_field", "$.workspace.zusatz"},
    {"unknown_field", "$.zusatz"},
    {"unknown_observer", "$.identity"},
    {"unsorted_references", "$.object.labels"},
    {"unsorted_references", "$.workspace.bindings"}
  ]

  # One per code and path of Release.validate/1, Stand.validate/1 and
  # validate_proposal/1 (CONTRACT § 2.6, § 2.7, § 4.6); `:delete` drops the
  # field, `[]` replaces the whole record.
  @release_breaks [
    {[], 7},
    {["schema"], :delete},
    {["schema"], "komki-release/9"},
    {["schema"], nil},
    {["zusatz"], true},
    {["ausgabeart"], "sitzungsmappe"},
    {["release_id"], "Go 1"},
    {["kind"], "erfunden"},
    {["kind"], "offenlegungsfreigabe"},
    {["operation"], "plan"},
    {["object"], "obj"},
    {["workspace"], 7},
    {["content_digest"], "abc"},
    {["call_hash"], String.upcase(@hex)},
    {["call_hash"], String.duplicate("g", 64)},
    {["scope"], "Scope"},
    {["authority"], nil},
    {["valid_from"], -1},
    {["valid_until"], "100"},
    {["valid_from"], 999_999},
    {["valid_from"], 60.0},
    {["valid_until"], 1000.0},
    {:merge, %{"valid_from" => 50, "valid_until" => 50}},
    {["nonce"], "N"}
  ]
  @offenlegung_breaks [
    {["ausgabeart"], :delete},
    {["ausgabeart"], nil},
    {["ausgabeart"], "erfunden"},
    {["ausgabeart"], 7},
    {["ziellabel"], :delete},
    {["ziellabel"], []},
    {["ziellabel"], ["ratsprojekte@1", "b-eins@1"]},
    {["ziellabel"], ["ratsprojekte@1", "ratsprojekte@1"]},
    {["ziellabel"], nil},
    {["ziellabel"], ["kein-ref"]},
    {["ziellabel"], "ratsprojekte@1"},
    {["schema"], "komki-release/1"}
  ]
  @stand_breaks [
    {[], "stand"},
    {["schema"], :delete},
    {["schema"], 1},
    {["schema"], nil},
    {["zusatz"], true},
    {["stand_id"], "Stand"},
    {["version"], -1},
    {["version"], "3"},
    {["scope"], 7},
    {["as_of"], "50"},
    {["as_of"], -5},
    {["version"], 3.0},
    {["consumed"], :delete},
    {["consumed"], []},
    {["consumed"], %{"N" => "go-a"}},
    {["consumed"], %{"n-a" => 7}}
  ]
  @proposal_breaks [
    {[], nil},
    {["zusatz"], true},
    {["ausgabeart"], "sitzungsmappe"},
    {:merge, %{"ausgabeart" => "erfunden", "ziellabel" => ["ratsprojekte@1"]}},
    {:merge, %{"ausgabeart" => "ratsprojekte-essenz", "ziellabel" => []}},
    {:merge, %{"ausgabeart" => nil, "ziellabel" => nil}},
    {:merge, %{"ausgabeart" => "ratsprojekte-essenz", "ziellabel" => ["a@1", "a@1"]}},
    {["release_id"], nil},
    {["release_id"], :delete},
    {["release_id"], "Go"},
    {["nonce"], 7},
    {["stand_ref"], "stand-drt@03"},
    {["stand_ref"], "stand-drt@"},
    {["call_hash"], "abc"},
    {["call_hash"], String.duplicate("g", 64)},
    {["stand_version_after"], -1}
  ]

  # Every code and path the breaks above reach.
  @schema_errors [
    {"invalid_as_of", "$.as_of"},
    {"invalid_digest", "$.call_hash"},
    {"invalid_digest", "$.content_digest"},
    {"invalid_kind", "$.kind"},
    {"invalid_operation", "$.operation"},
    {"invalid_output_kind", "$.ausgabeart"},
    {"invalid_proposal", "$"},
    {"invalid_proposal", "$.ausgabeart"},
    {"invalid_proposal", "$.call_hash"},
    {"invalid_proposal", "$.stand_version_after"},
    {"invalid_proposal", "$.ziellabel"},
    {"invalid_record", "$"},
    {"invalid_record", "$.consumed"},
    {"invalid_reference_id", "$.authority"},
    {"invalid_reference_id", "$.consumed"},
    {"invalid_reference_id", "$.nonce"},
    {"invalid_reference_id", "$.object"},
    {"invalid_reference_id", "$.release_id"},
    {"invalid_reference_id", "$.scope"},
    {"invalid_reference_id", "$.stand_id"},
    {"invalid_reference_id", "$.stand_ref"},
    {"invalid_reference_id", "$.workspace"},
    {"invalid_schema", "$.schema"},
    {"invalid_stand_version", "$.version"},
    {"invalid_window", "$.valid_from"},
    {"invalid_window", "$.valid_until"},
    {"invalid_ziellabel", "$.ziellabel"},
    {"missing_field", "$.ausgabeart"},
    {"missing_field", "$.schema"},
    {"missing_field", "$.ziellabel"},
    {"unknown_field", "$.ausgabeart"},
    {"unknown_field", "$.zusatz"}
  ]

  # The error codes of JSON.parse/1, which the Lean parser models.
  @json_error_codes ~w(empty_input trailing_data incomplete_document unexpected_byte invalid_number
                       unterminated_literal duplicate_json_key trailing_comma invalid_string
                       invalid_utf8)
  # komki-policy calls per command kind: each one compiles and parses files.
  @cli_runs 300

  # Pieces of a JSON string: raw characters and every kind of escape.
  @string_parts ~w(a b z A Z 0 9 / é € 😀 ﻿ ࠀ က 퀀   𐀀 񀀀 󿿿 \\" \\\\ \\/ \\b \\f \\n \\r \\t \\u0041 \\u00e9 \\u20AC \\ud83d\\ude00 \\u0000 \\u001f \\uFFFF \\u007F) ++
                  [<<0x7F>>, " "]

  # JSON documents on the edges of the grammar and of UTF-8 (CONTRACT.md § 6).
  @json_edge_cases [
    "",
    "   ",
    "-0",
    "1E5",
    "1e400",
    "-1e400",
    "1e-400",
    "0e99999999",
    "1.7976931348623157e308",
    "1.7976931348623159e308",
    "179769313486231580793728971405303415079934132710037826936173778980444968292764750946649017977587207096330286416692887910946555547851940402630657488671505820681908902000708383676273854845817711531764475730270069855571366959622842914819860834936475292719074168444365510704342711559699508093042880177904174497792e-5",
    "123456789012345678901234567890",
    "+1",
    "NaN",
    "Infinity",
    "01",
    "1.",
    ".5",
    "1e",
    "1e+",
    "--1",
    "tru",
    "truex",
    "true_",
    "nul",
    "[1,]",
    "[,1]",
    "{\"a\":1,}",
    "{,}",
    "{\"a\" 1}",
    "{\"a\":1,\"a\":2}",
    "{\"a\":1,\"\\u0061\":2}",
    "\"\\ud800\"",
    "\"\\ud800\\u0041\"",
    "\"\\ud800\\udc00\"",
    "\"\\udc00\"",
    "\"\\u12\"",
    "\"\\u12g4\"",
    "\"\\x\"",
    "\"a\nb\"",
    "\"\\",
    "\"abc",
    <<?", 0xC0, 0x80, ?">>,
    <<?", 0xED, 0xA0, 0x80, ?">>,
    <<?", 0xED, 0x9F, 0xBF, ?">>,
    <<?", 0xE0, 0x80, 0x80, ?">>,
    <<?", 0xF4, 0x90, 0x80, 0x80, ?">>,
    <<?", 0xF4, 0x8F, 0xBF, 0xBF, ?">>,
    <<?", 0xEF, 0xBF, 0xBF, ?">>,
    <<?", 0xFF, ?">>,
    <<?", 0xE2, 0x82, ?">>,
    <<0xEF, 0xBB, 0xBF, ?{, ?}>>,
    "[1] x",
    "{} {}",
    "[\"a\", 1, true, null, {}, []]",
    "\f1",
    "1\v",
    <<0xC2, 0xA0, ?1>>,
    <<?", 0xC2, 0x80, ?">>,
    <<?", 0xDF, 0xBF, ?">>,
    <<?", 0xC2, 0xC0, ?">>,
    <<?", 0xE0, 0xA0, 0x80, ?">>,
    <<?", 0xE1, 0x80, 0x80, ?">>,
    <<?", 0xE1, 0xC0, 0x80, ?">>,
    <<?", 0xE3, 0x80, 0x80, ?">>,
    <<?", 0xEC, 0xBF, 0xBF, ?">>,
    <<?", 0xEC, 0x7F, 0x80, ?">>,
    <<?", 0xEE, 0x80, 0x80, ?">>,
    <<?", 0xEE, 0x80, 0xC0, ?">>,
    <<?", 0xF0, 0x90, 0x80, 0x80, ?">>,
    <<?", 0xF0, 0x8F, 0xBF, 0xBF, ?">>,
    <<?", 0xF1, 0x80, 0x80, 0x80, ?">>,
    <<?", 0xF3, 0xBF, 0xBF, 0xBF, ?">>,
    <<?", 0xF3, 0x80, 0x80, 0x7F, ?">>,
    <<?", 0xF5, 0x80, 0x80, 0x80, ?">>
  ]

  # The overflow bound of binary_to_float/1 and one below, as a fraction, with
  # an exponent and in scientific form: the bound fails, one below does not.
  @overflow_cases (for t <- [2 ** 1024 - 2 ** 970, 2 ** 1024 - 2 ** 970 - 1] do
                     digits = Integer.to_string(t)
                     {first, rest} = String.split_at(digits, 1)
                     [digits <> ".0", digits <> "e0", first <> "." <> rest <> "e308"]
                   end)
                  |> List.flatten()

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
            audit_attacks() ++
              unknown_conditions() ++
              shape_proofs() ++ for({s, i} <- worlds, p <- proofs, do: {s, i, p}) do
        {raw, registry, snapshot, intent, proof}
      end

    stats = compare!(cases, "korpus")

    assert stats.valid >= 6
    assert stats.invalid >= 500
    assert stats.input_error >= 6
    assert stats.input_errors["invalid_record"] == 2
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

    assert @proof_input_errors -- Map.keys(stats.input_errors) == [],
           "Eingabefehler ohne Fall: #{inspect(@proof_input_errors -- Map.keys(stats.input_errors))}"

    assert @verify_codes -- Map.keys(stats.codes) == [],
           "Befundcodes ohne Fall: #{inspect(@verify_codes -- Map.keys(stats.codes))}"

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

  test "Freigabe, Stand und Vorschlag: Eingabefehler wie im Lean-Modell" do
    cases = fixture_release_cases()
    aktion = Enum.find(cases, &(elem(&1, 4)["kind"] == "aktionsfreigabe"))
    offen = Enum.find(cases, &(elem(&1, 4)["kind"] == "offenlegungsfreigabe"))
    {raw, registry, snapshot, intent, release, stand} = aktion
    intent_breaks = for {:break, path, value} <- @intent_corruptions, do: {path, value}

    decide =
      for(r <- break_variants(release, @release_breaks), do: put_elem(aktion, 4, r)) ++
        for(r <- break_variants(elem(offen, 4), @offenlegung_breaks), do: put_elem(offen, 4, r)) ++
        for(s <- break_variants(stand, @stand_breaks), do: put_elem(aktion, 5, s)) ++
        for(
          a <- @release_breaks,
          b <- @stand_breaks,
          do: {raw, registry, snapshot, intent, schema_break(release, a), schema_break(stand, b)}
        ) ++
        for a <- intent_breaks,
            b <- @release_breaks,
            do:
              {raw, registry, snapshot, schema_break(intent, a), schema_break(release, b), stand}

    proposal = proposal("n-neu", 3, 4)

    advance =
      for(p <- break_variants(proposal, @proposal_breaks), do: {@stand, p}) ++
        for(s <- break_variants(@stand, @stand_breaks), do: {s, proposal}) ++
        for a <- @stand_breaks,
            b <- @proposal_breaks,
            do: {schema_break(@stand, a), schema_break(proposal, b)}

    decide_pairs = Enum.map(decide, &release_pair/1)

    advance_pairs =
      for {s, p} <- advance,
          do:
            {%{"stand" => s, "proposal" => p, "intent" => %{"operation" => "advance"}},
             elixir_advance(s, p)}

    compare_json!(decide_pairs, "release-batch", "release", "Release/Stand.validate und Lean")
    compare_json!(advance_pairs, "advance-batch", "advance", "Stand.advance/2 und Lean")

    codes =
      for {_, %{"input_error" => code, "path" => path}} <- decide_pairs ++ advance_pairs,
          uniq: true,
          do: {code, path}

    IO.puts(
      "\nlean_spec schemas: #{length(decide_pairs) + length(advance_pairs)} Fälle, #{length(codes)} Fehler"
    )

    missing = @schema_errors -- codes
    assert missing == [], "Schemafehler ohne Fall: #{inspect(missing)}"
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
    generated = seeded_list(domain_gen())

    pairs =
      Enum.map(generated ++ defect_pairs(generated) ++ registry_pairs(generated), &domain_case/1)

    compare_json!(
      pairs,
      "domain-batch",
      "domain",
      "Registry.compile/Context und dem Wertebereich"
    )

    snapshots = Enum.count(pairs, fn {_, e} -> e["snapshot"] end)

    codes =
      Enum.frequencies(
        for {_, %{"context_error" => %{"path" => p, "code" => c}}} <- pairs, do: {c, p}
      )

    registry_codes =
      for {_, %{"registry_error" => %{"path" => p, "code" => c}}} <- pairs, uniq: true, do: {c, p}

    missing_registry = @registry_errors -- registry_codes
    assert missing_registry == [], "Registry-Fehler ohne Fall: #{inspect(missing_registry)}"

    IO.puts(
      "\nlean_spec domain: registries #{length(pairs)}, snapshots #{snapshots}, context errors #{map_size(codes)}"
    )

    assert length(pairs) >= 3_000
    assert snapshots >= 1_000
    missing = @context_errors -- Map.keys(codes)
    assert missing == [], "Kontextfehler ohne Fall: #{inspect(missing)}"
  end

  # The JSON layer (CONTRACT.md § 6) byte for byte: the fixtures, generated
  # documents in many spellings, tokens on the grammar's edges, nesting
  # around the encoder's limit and single-byte mutants of all of them.
  test "JSON: Parser und kanonischer Encoder gleichen dem Lean-Modell" do
    fixtures =
      (@fixtures_dir <> "/**/*.json")
      |> Path.wildcard()
      |> Enum.map(&File.read!/1)

    documents =
      fixtures ++
        @json_edge_cases ++ @overflow_cases ++ nested_documents() ++ seeded_list(json_doc_gen())

    pairs = Enum.map(documents, &json_pair/1)
    compare_json!(pairs, "json-batch", "json", "KomkiPolicy.JSON und dem Lean-Modell")

    stats = Enum.frequencies_by(pairs, fn {_, result} -> result["error"] || "ok" end)
    IO.puts("\nlean_spec json: #{inspect(stats)}")

    assert stats["ok"] >= 2_000
    assert map_size(stats) >= 11, "zu wenige Fehlerarten: #{inspect(Map.keys(stats))}"
  end

  # komki-policy itself (CONTRACT.md § 7): the worlds of the other tests as
  # files, every fourth with one byte changed, through CLI.run/1, against
  # the strict parser and the model on the same bytes.
  test "CLI: komki-policy antwortet wie das Lean-Modell, samt Exit-Code" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "komki-spec-cli-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    try do
      calls = cli_commands()

      pairs =
        Enum.map(Enum.with_index(calls), fn {{command, values}, i} ->
          cli_pair(dir, command, cli_files(values, i))
        end) ++
          for(
            {command, values} <- broken_snapshot_calls(calls),
            do: cli_pair(dir, command, intact_files(values))
          ) ++
          for {command, files} <- broken_registry_calls(calls),
              do: cli_pair(dir, command, files)

      compare_json!(pairs, "cli-batch", "cli", "komki-policy und dem Lean-Modell")

      # Over the generated calls only: the fixed ones would meet the
      # thresholds for decide on their own.
      stats =
        Enum.frequencies_by(Enum.take(pairs, length(calls)), fn
          {line, %{"exit" => exit}} -> {line["command"], exit}
        end)

      IO.puts("\nlean_spec cli: #{inspect(stats)}")

      for key <-
            [{"decide", 0}, {"decide", 2}, {"decide", 3}, {"verify", 0}, {"verify", 1}] ++
              [{"verify", 2}, {"advance", 0}, {"advance", 1}, {"advance", 2}] do
        assert Map.get(stats, key, 0) >= 10, "zu wenige Fälle #{inspect(key)}"
      end

      # A renamed input error code would drop its cases silently.
      codes =
        Enum.frequencies(for {_, %{"result" => %{"input_error" => code}}} <- pairs, do: code)

      for code <- @derive_input_errors do
        assert Map.get(codes, to_string(code), 0) >= 5, "zu wenige Fälle #{code}"
      end
    after
      File.rm_rf!(dir)
    end
  end

  # Not a comparison with Lean, but the property the Lean theorems state
  # for the model (catalog_*_effective, #631, and release_catalog_*_effective
  # after a denied release): a GO the catalog offers takes effect. Each offer
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
         do: {:normal, compiled, snapshot, intent, Derive.decide(compiled, snapshot, intent)}
       ) ++
         for(
           {_, compiled, snapshot, intent, result} <- released,
           do: {:release, compiled, snapshot, intent, result}
         ))
      |> Enum.flat_map(fn
        {branch, compiled, snapshot, intent,
         {:ok, %{"decision" => "deny", "remedies" => remedies}}} ->
          for entry <- remedies,
              go <- entry["transitions"],
              go["type"] in ~w(aktionsfreigabe offenlegungsfreigabe),
              go["scope"] == "call",
              do: {branch, compiled, snapshot, intent, go}

        _ ->
          []
      end)
      |> Enum.uniq()

    failing =
      for {_, compiled, snapshot, intent, go} <- offers,
          release = release_from_offer(compiled, snapshot, intent, go),
          result = Derive.decide_with_release(compiled, snapshot, intent, release, @stand),
          not match?({:ok, %{"decision" => "permit"}}, result),
          do: {go, snapshot, intent, result}

    counts = Enum.frequencies_by(offers, fn {branch, _, _, _, go} -> {branch, go["type"]} end)
    IO.puts("\nlean_spec GO-Angebote: #{inspect(counts)}")

    assert failing == [], "Angebot wirkt nicht: #{inspect(Enum.take(failing, 2), limit: 8)}"

    # Each branch on its own: offers after a denied release must not hide
    # behind the normal branch's.
    for branch <- [:normal, :release],
        {type, min} <- [{"aktionsfreigabe", 1_000}, {"offenlegungsfreigabe", 10}] do
      assert Map.get(counts, {branch, type}, 0) >= min, "zu wenige #{type}-Angebote (#{branch})"
    end
  end

  # ---------------------------------------------------------------------
  # Comparison
  # ---------------------------------------------------------------------

  defp compare!(cases, label) do
    judged =
      cases
      |> Enum.map(fn {raw, registry, snapshot, intent, proof} ->
        line = %{"registry" => raw, "snapshot" => snapshot, "intent" => intent, "proof" => proof}
        {line, elixir_report(registry, snapshot, intent, proof)}
      end)
      |> Enum.with_index()

    lean = run_lean("verify-batch", judged)

    mismatches =
      for {{line, report}, id} <- judged,
          parse_decision(Map.get(lean, id)) != report,
          do: {id, report, parse_decision(Map.get(lean, id)), line}

    report_mismatches!(mismatches, label, "Verify.check/4 und dem Lean-Prüfer")

    verdicts =
      Enum.map(judged, fn {{line, report}, _} -> {rule_of(line["proof"]), verdict(report)} end)

    count = fn verdict -> Enum.count(verdicts, fn {_, v} -> v == verdict end) end

    %{
      compared: length(judged),
      valid: count.("valid"),
      invalid: count.("invalid"),
      input_error: count.("input_error"),
      valid_by_rule:
        verdicts
        |> Enum.filter(fn {_, v} -> v == "valid" end)
        |> Enum.frequencies_by(fn {rule, _} -> rule end),
      codes:
        Enum.frequencies(
          for {{_, %{"reasons" => reasons}}, _} <- judged, reason <- reasons, do: reason["code"]
        ),
      input_errors: Enum.frequencies(for {{_, %{"input_error" => code}}, _} <- judged, do: code)
    }
  end

  # The model knows every input error of verify against a compiled
  # registry: intent, snapshot, coherence, the output prerequisites (#628)
  # and the proof's validation, each with code and path.
  defp elixir_report(registry, snapshot, intent, proof) do
    case Verify.check(registry, snapshot, intent, proof) do
      {:ok, outcome} -> outcome
      {:error, %{code: code, path: path}} -> %{"input_error" => to_string(code), "path" => path}
    end
  end

  # The intent may be broken as a whole (`@intent_corruptions`).
  defp operation_of(%{"operation" => op}), do: op
  defp operation_of(_intent), do: nil

  defp rule_of(%{"rule" => rule}), do: rule
  defp rule_of(_proof), do: nil

  defp verdict(%{"result" => result}), do: result
  defp verdict(%{"input_error" => _}), do: "input_error"

  defp compare_decisions!(cases, label) do
    cases
    |> Enum.map(fn {raw, registry, snapshot, intent} ->
      line = %{
        "registry" => raw,
        "snapshot" => snapshot,
        "intent" => intent
      }

      {line, elixir_decision(registry, snapshot, intent)}
    end)
    |> compare_json!("derive-batch", label, "Derive.decide/3 und dem Lean-Modell")
  end

  # Pairs {case line, Elixir result} against the Lean batch `command`;
  # returns the results counted by operation and kind.
  defp compare_json!(pairs, command, label, what) do
    judged = Enum.with_index(pairs)

    lean = run_lean(command, judged)

    mismatches =
      for {{line, result}, id} <- judged,
          parse_decision(Map.get(lean, id)) != result,
          do: {id, result, parse_decision(Map.get(lean, id)), line}

    report_mismatches!(mismatches, label, what)

    Enum.frequencies_by(judged, fn {{line, result}, _} ->
      {operation_of(line["intent"]), result["decision"] || Enum.at(Map.keys(result), 0)}
    end)
  end

  defp release_pair({raw, registry, snapshot, intent, release, stand}) do
    line = %{
      "registry" => raw,
      "snapshot" => snapshot,
      "intent" => intent,
      "release" => release,
      "stand" => stand
    }

    {line, elixir_release(registry, snapshot, intent, release, stand)}
  end

  defp elixir_release(registry, snapshot, intent, release, stand) do
    case Derive.decide_with_release(registry, snapshot, intent, release, stand) do
      {:ok, decision} ->
        decision |> Map.take(@release_fields) |> Map.put("gos", gos(decision["remedies"]))

      {:unsupported, _} ->
        %{"unsupported" => true}

      {:error, %{code: code, path: path}} ->
        %{"input_error" => to_string(code), "path" => path}
    end
  end

  defp elixir_advance(stand, proposal) do
    case Stand.advance(stand, proposal) do
      {:ok, next} -> %{"ok" => next |> Stand.to_record() |> Map.delete("schema")}
      {:refused, %{code: code}} -> %{"refused" => to_string(code)}
      {:error, %{code: code, path: path}} -> %{"input_error" => to_string(code), "path" => path}
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
  # echoes of the input. Against a compiled registry the model knows every
  # input error of the normal branch.
  defp elixir_decision(registry, snapshot, intent) do
    case Derive.decide(registry, snapshot, intent) do
      {:ok, decision} ->
        decision |> Map.take(@decision_fields) |> Map.put("gos", gos(decision["remedies"]))

      {:unsupported, _} ->
        %{"unsupported" => true}

      {:error, %{code: code, path: path}} ->
        %{"input_error" => to_string(code), "path" => path}
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
    path =
      Path.join(
        System.tmp_dir!(),
        "komki-spec-#{System.pid()}-#{System.unique_integer([:positive])}.jsonl"
      )

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
    path = Path.join(System.tmp_dir!(), "komki-spec-mismatch-#{label}-#{System.pid()}.jsonl")
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

  # Conditions whose facts are gone (verdict unknown) and that claim false:
  # verify.ex reports the recomputed verdict before the claim.
  defp unknown_conditions do
    {:ok, registry} = Registry.compile(fixture("registry.json"))

    for dir <- ~w(case_permit case_emit_permit),
        snapshot = fixture(dir <> "/snapshot.json"),
        intent = fixture(dir <> "/intent.json") do
      claimed =
        Map.update!(derived_proof(registry, snapshot, intent), "premises", fn premises ->
          Enum.map(premises, &refute_condition/1)
        end)

      facts = Map.drop(snapshot["facts"], ["purpose", "input_in_approved_case_scope"])
      {%{snapshot | "facts" => facts}, intent, claimed}
    end
  end

  # validate_proof/1 on a proof that is no object.
  # validate_proof/1 on a proof that is no object, and two defects at once,
  # so the order of its checks shows. Then a quarantined object whose tree
  # claims not_quarantine false: object_quarantine comes first.
  defp shape_proofs do
    snapshot = fixture("case_permit/snapshot.json")
    intent = fixture("case_permit/intent.json")
    permit = fixture("case_permit/proof_valid.json")
    index = Enum.find_index(permit["premises"], &(&1["kind"] == "condition"))

    broken = [
      [],
      "komki-proof/1",
      permit |> Map.put("zusatz", true) |> Map.delete("intent_ref"),
      %{permit | "conclusion" => 7, "rule" => 7},
      update_in(
        permit,
        ["premises", Access.at(index)],
        &%{&1 | "expression" => nil, "value" => 7}
      ),
      put_in(permit, ["premises", Access.at(index), "expression"], "x")
    ]

    quarantined = put_in(snapshot, ["object", "classification"], "quarantine")

    for(proof <- broken, do: {snapshot, intent, proof}) ++
      [{quarantined, intent, put_named(permit, "not_quarantine", "value", false)}]
  end

  defp refute_condition(%{"kind" => "condition"} = premise), do: %{premise | "value" => false}
  defp refute_condition(premise), do: premise

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

      cases ++ mirrored ++ broken_verify_cases(raw, registry, snapshot, op, sources)
    else
      {:error, _} -> []
    end
  end

  # The first tree on a broken snapshot or intent, once a malformed proof
  # on a broken snapshot; for an output rule also a coherence error on a
  # snapshot outside the rule's domain. check/4 reports the context first.
  defp broken_verify_cases(_raw, _registry, _snapshot, _op, []), do: []

  defp broken_verify_cases(raw, registry, snapshot, op, [{_, tree} | _]) do
    off =
      if op in Derive.output_operations(),
        do: [{hd(off_domain(snapshot)), Map.put(intent(op), "workspace", "ws-fremd")}],
        else: []

    [{broken, _} | _] = contexts = broken_contexts(snapshot, op)

    [{raw, registry, broken, intent(op), 7}] ++
      for {s, i} <- contexts ++ off, do: {raw, registry, s, i, tree}
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

      worlds ++
        [{raw, registry, snapshot, intent("start")}] ++
        for {s, i} <- broken_contexts(snapshot, op), do: {raw, registry, s, i}
    else
      {:error, _} -> []
    end
  end

  # One defect of snapshot or intent per world, picked by hash, so a check
  # meets the context errors in its own order; also with `start`.
  defp broken_contexts(snapshot, op) do
    pick = fn corruptions ->
      breaks = for {:break, _, _} = c <- corruptions, do: c
      Enum.at(breaks, :erlang.phash2(snapshot, length(breaks)))
    end

    broken = corrupt_snapshot(snapshot, pick.(@snapshot_corruptions))

    [
      {broken, intent(op)},
      {snapshot, corrupt_snapshot(intent(op), pick.(@intent_corruptions))},
      {broken, intent("start")}
    ]
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

  # Every ordered pair of two :break defects on one clean world, so the
  # order of the checks shows.
  defp defect_pairs(generated) do
    {raw, snapshot, intent} = Enum.find(generated, &clean_context?/1)
    snapshot_breaks = for {:break, _, _} = c <- @snapshot_corruptions, do: c
    intent_breaks = for {:break, _, _} = c <- @intent_corruptions, do: c

    for(
      a <- snapshot_breaks,
      b <- snapshot_breaks,
      a != b,
      do: {raw, snapshot |> corrupt_snapshot(a) |> corrupt_snapshot(b), intent}
    ) ++
      for a <- intent_breaks,
          b <- intent_breaks,
          a != b,
          do: {raw, snapshot, intent |> corrupt_snapshot(a) |> corrupt_snapshot(b)}
  end

  # Every registry break alone and every ordered pair on one clean world.
  defp registry_pairs(generated) do
    {raw, snapshot, intent} = Enum.find(generated, &clean_context?/1)
    fill = %{observer: hd(raw["observers"]), binding: hd(Enum.sort(Map.keys(raw["bindings"])))}
    breaks = for {path, v} <- @registry_breaks, do: {path, fill_in(v, fill)}

    for({path, v} <- breaks, do: {break_path(raw, path, v), snapshot, intent}) ++
      for {pa, va} = a <- breaks,
          {pb, vb} = b <- breaks,
          a != b,
          do: {raw |> break_path(pa, va) |> break_path(pb, vb), snapshot, intent}
  end

  defp fill_in(atom, fill) when is_map_key(fill, atom), do: fill[atom]
  defp fill_in(list, fill) when is_list(list), do: Enum.map(list, &fill_in(&1, fill))
  defp fill_in(%{} = map, fill), do: Map.new(map, fn {k, v} -> {k, fill_in(v, fill)} end)
  defp fill_in(value, _fill), do: value

  defp clean_context?({raw, snapshot, intent}) do
    case Registry.compile(raw) do
      {:ok, compiled} ->
        context_error(compiled, snapshot, intent) == nil and
          is_map_key(snapshot["facts"], "audit_path_ready")

      {:error, _} ->
        false
    end
  end

  # A redeclared base fact gets a string value in half the snapshots, so
  # Context has to hold the base fact to boolean against fact_fields (§ 4.2).
  defp domain_gen do
    gen all(
          {raw, op, snapshot, _other, _} <- world_gen(),
          registry_corruption <- corruption_gen(@registry_corruptions),
          intent_corruption <- corruption_gen(@intent_corruptions),
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
       corrupt_snapshot(snapshot, snapshot_corruption),
       corrupt_snapshot(intent(op), intent_corruption)}
    end
  end

  defp domain_case({raw, snapshot, intent}) do
    case Registry.compile(raw) do
      {:ok, compiled} ->
        accepted = match?({:ok, _}, Context.validate_snapshot(snapshot, compiled))

        {%{"registry" => raw, "snapshot" => snapshot, "intent" => intent},
         %{
           "registry" => true,
           "snapshot" => if(accepted, do: true),
           "context_error" => context_error(compiled, snapshot, intent)
         }}

      {:error, %{code: code, path: path}} ->
        {%{"registry" => raw, "snapshot" => snapshot, "intent" => intent},
         %{"registry_error" => %{"code" => to_string(code), "path" => path}}}
    end
  end

  # The first error of validate_intent/1, validate_snapshot/2 and
  # ensure_coherence/2, in that order.
  defp context_error(compiled, snapshot, intent) do
    with {:ok, auth} <- Context.validate_intent(intent),
         {:ok, ctx} <- Context.validate_snapshot(snapshot, compiled),
         :ok <- Context.ensure_coherence(ctx, auth) do
      nil
    else
      {:error, %{code: code, path: path}} -> %{"code" => to_string(code), "path" => path}
    end
  end

  # Puts `value` at `path` (`:delete` drops the key, `[]` replaces the term);
  # a missing or non-object parent leaves the term as it is.
  defp break_path(_term, [], value), do: value
  defp break_path(term, [key], :delete) when is_map(term), do: Map.delete(term, key)
  defp break_path(term, [key], value) when is_map(term), do: Map.put(term, key, value)

  defp break_path(term, [key | rest], value) when is_map(term) and is_map_key(term, key),
    do: Map.update!(term, key, &break_path(&1, rest, value))

  defp break_path(term, _path, _value), do: term

  defp schema_break(term, {:merge, fields}) when is_map(term), do: Map.merge(term, fields)
  defp schema_break(term, {:merge, _}), do: term
  defp schema_break(term, {path, value}), do: break_path(term, path, value)

  # Each break alone and every ordered pair, so the order of the checks shows.
  defp break_variants(term, breaks) do
    for(b <- breaks, do: schema_break(term, b)) ++
      for a <- breaks, b <- breaks, a != b, do: term |> schema_break(a) |> schema_break(b)
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
  defp corrupt_snapshot(term, {:break, path, value}), do: break_path(term, path, value)

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

  # ---------------------------------------------------------------------
  # The JSON layer (CONTRACT.md § 6)
  # ---------------------------------------------------------------------

  # Arrays and objects nested around the encoder's depth limit (#473).
  defp nested_documents do
    for depth <- [127, 128, 129, 130], open <- ["[", "{\"k\":"] do
      close = if open == "[", do: "]", else: "}"
      String.duplicate(open, depth) <> "0" <> String.duplicate(close, depth)
    end
  end

  defp json_pair(bytes),
    do: {%{"hex" => Base.encode16(bytes, case: :lower)}, elixir_json(bytes)}

  defp elixir_json(bytes) do
    case KomkiPolicy.JSON.parse(bytes) do
      {:ok, value} ->
        text = KomkiPolicy.JSON.canonical(mask_floats(value))
        %{"ok" => text, "sha256" => Base.encode16(:crypto.hash(:sha256, text), case: :lower)}

      {:error, %{code: code}} ->
        %{"error" => to_string(code)}
    end
  rescue
    error in KomkiPolicy.JSON.DepthLimitError -> %{"error" => to_string(error.code)}
  end

  defp mask_floats(value) when is_float(value), do: "<float>"
  defp mask_floats(value) when is_list(value), do: Enum.map(value, &mask_floats/1)
  defp mask_floats(%{} = value), do: Map.new(value, fn {k, v} -> {k, mask_floats(v)} end)
  defp mask_floats(value), do: value

  # A document as bytes: spelled with varying whitespace and escapes, four in
  # five with one byte inserted, replaced or dropped, or cut short.
  defp json_doc_gen do
    gen all(
          doc <- spelled_gen(),
          mutation <- StreamData.member_of([:none, :insert, :replace, :delete, :truncate]),
          at <- StreamData.integer(0..1_000),
          byte <-
            StreamData.member_of(
              ~c',]}:"\\-+.e01 \nunt' ++
                [
                  0x00,
                  0x0B,
                  0x0C,
                  0x1F,
                  0x7F,
                  0x80,
                  0xA0,
                  0xC0,
                  0xC2,
                  0xE1,
                  0xED,
                  0xF1,
                  0xF4,
                  0xFF
                ]
            )
        ) do
      bytes = IO.iodata_to_binary(doc)
      mutate(bytes, mutation, div(at * byte_size(bytes), 1_000), byte)
    end
  end

  defp mutate(bytes, :none, _at, _byte), do: bytes

  defp mutate(bytes, :insert, at, byte),
    do: binary_part(bytes, 0, at) <> <<byte>> <> binary_part(bytes, at, byte_size(bytes) - at)

  defp mutate(bytes, kind, at, byte) when at < byte_size(bytes) do
    rest = binary_part(bytes, at + 1, byte_size(bytes) - at - 1)

    case kind do
      :replace -> binary_part(bytes, 0, at) <> <<byte>> <> rest
      :delete -> binary_part(bytes, 0, at) <> rest
      :truncate -> binary_part(bytes, 0, at)
    end
  end

  defp mutate(bytes, _kind, _at, _byte), do: bytes

  defp spelled_gen do
    ws = StreamData.member_of(["", " ", "\n", "\t", "\r\n  "])

    StreamData.tree(spelled_leaf_gen(), fn child ->
      StreamData.one_of([
        StreamData.bind(ws, fn w ->
          StreamData.map(StreamData.list_of(child, max_length: 4), fn items ->
            ["[", w, Enum.intersperse(items, [w, ",", w]), w, "]"]
          end)
        end),
        StreamData.bind(ws, fn w ->
          StreamData.map(
            StreamData.list_of({spelled_key_gen(), child}, max_length: 4),
            fn entries ->
              pairs = Enum.map(entries, fn {k, v} -> [k, w, ":", w, v] end)
              ["{", w, Enum.intersperse(pairs, [w, ",", w]), w, "}"]
            end
          )
        end)
      ])
    end)
  end

  defp spelled_leaf_gen do
    StreamData.one_of([
      StreamData.member_of(["null", "true", "false"]),
      StreamData.map(StreamData.integer(), &Integer.to_string/1),
      StreamData.member_of(["-0", "18446744073709551616", "-99999999999999999999999"]),
      StreamData.member_of(["1.5", "-0.0", "1e5", "1E-5", "2.5e+3", "0.1", "123.456e-7"]),
      spelled_string_gen()
    ])
  end

  defp spelled_key_gen do
    StreamData.one_of([
      StreamData.member_of([
        "\"a\"",
        "\"b\"",
        "\"\\u0061\"",
        "\"A\"",
        "\"é\"",
        "\"\\u00e9\"",
        "\"\"",
        "\"a\\u0000\""
      ]),
      spelled_string_gen()
    ])
  end

  defp spelled_string_gen do
    @string_parts
    |> StreamData.member_of()
    |> StreamData.list_of(max_length: 6)
    |> StreamData.map(fn parts -> ["\"", parts, "\""] end)
  end

  # ---------------------------------------------------------------------
  # The CLI (CONTRACT.md § 7)
  # ---------------------------------------------------------------------

  defp cli_commands do
    worlds = world_gen() |> seeded_list() |> Enum.take(@cli_runs)

    decide =
      for {raw, _, snapshot, intent} <-
            worlds |> Enum.flat_map(&decision_cases/1) |> Enum.take(@cli_runs),
          do: {"decide", [{"registry", raw}, {"snapshot", snapshot}, {"intent", intent}]}

    verify =
      for {raw, _, snapshot, intent, proof} <-
            worlds |> Enum.flat_map(&world_cases/1) |> Enum.take(@cli_runs),
          do:
            {"verify",
             [{"registry", raw}, {"snapshot", snapshot}, {"intent", intent}, {"proof", proof}]}

    release =
      for {raw, _, snapshot, intent, release, stand} <-
            release_world_gen()
            |> seeded_list()
            |> Enum.take(@cli_runs)
            |> Enum.flat_map(&release_cases/1)
            |> Enum.take(@cli_runs),
          do:
            {"decide",
             [
               {"registry", raw},
               {"snapshot", snapshot},
               {"intent", intent},
               {"release", release},
               {"stand", stand}
             ]}

    advance =
      for {stand, proposal} <- advance_gen() |> seeded_list() |> Enum.take(@cli_runs),
          do: {"advance", [{"stand", stand}, {"proposal", proposal}]}

    decide ++ verify ++ release ++ advance
  end

  # A snapshot Context rejects, with the call's own operation and with
  # `start`: without a release `decide` answers `unsupported` first, with one
  # the input error (#644). An unknown environment is an input error the
  # model knows; a snapshot without `object` fails its decoder, so only the
  # early `unsupported` answers it. The files stay intact, so the snapshot
  # is the only defect.
  defp broken_snapshot_calls(calls) do
    for {"decide", [registry, {"snapshot", snapshot}, {"intent", intent} | release] = values} <-
          calls |> Enum.filter(&match?({"decide", _}, &1)) |> Enum.take_every(10),
        decides?(values),
        {broken, operation} <- broken_snapshots(snapshot, intent["operation"], release) do
      {"decide",
       [registry, {"snapshot", broken}, {"intent", %{intent | "operation" => operation}}] ++
         release}
    end
  end

  # A registry Registry.compile/1 rejects next to a snapshot that is no
  # JSON at all: the CLI compiles the registry before it parses the other
  # files, so the registry error wins.
  defp broken_registry_calls(calls) do
    for {command, values} <- Enum.take_every(calls, 20),
        List.keymember?(values, "registry", 0) do
      files =
        Enum.map(intact_files(values), fn
          {"registry", _} ->
            {"registry",
             KomkiPolicy.JSON.canonical(Map.put(Map.new(values)["registry"], "zusatz", true))}

          {"snapshot", _} ->
            {"snapshot", "{"}

          file ->
            file
        end)

      {command, files}
    end
  end

  defp broken_snapshots(snapshot, operation, release) do
    unknown = put_in(snapshot, ["workspace", "environment"], "umgebung-unbekannt@1")
    without_object = if release == [], do: [{Map.delete(snapshot, "object"), "start"}], else: []
    [{unknown, operation}, {unknown, "start"}] ++ without_object
  end

  # Only calls that decide as they are: the model checks the whole input up
  # front, so a second defect would fail there first.
  defp decides?(values) do
    files = Map.new(values)

    case Registry.compile(files["registry"]) do
      {:ok, registry} -> match?({:ok, _}, decide_files(registry, files))
      {:error, _} -> false
    end
  end

  defp decide_files(registry, %{"release" => release, "stand" => stand} = files),
    do: Derive.decide_with_release(registry, files["snapshot"], files["intent"], release, stand)

  defp decide_files(registry, files),
    do: Derive.decide(registry, files["snapshot"], files["intent"])

  # The canonical bytes of each file. In every fourth case one file gets a
  # byte inserted, replaced or dropped, or is cut short. In every eighth the
  # files from a rotating position on break, each with a parser code of its
  # own, so the order the CLI reads them in shows.
  defp cli_files(values, i) do
    files = intact_files(values)
    target = rem(div(i, 4), length(files))
    first = rem(div(i, 8), length(files))

    files
    |> Enum.with_index()
    |> Enum.map(fn
      {{name, bytes}, k} when rem(i, 8) == 2 and k >= first ->
        {name, cli_break(bytes, k + div(i, 8))}

      {{name, bytes}, ^target} when rem(i, 4) == 0 ->
        {name, cli_mutate(bytes, i)}

      {{name, bytes}, _} ->
        {name, bytes}
    end)
  end

  defp intact_files(values),
    do: for({name, value} <- values, do: {name, KomkiPolicy.JSON.canonical(value)})

  defp cli_mutate(bytes, i) do
    kind = Enum.at([:insert, :replace, :delete, :truncate], :erlang.phash2({i, :kind}, 4))
    byte = Enum.at(~c',]}:"\\-0 ', :erlang.phash2({i, :byte}, 9))
    mutate(bytes, kind, rem(i * 7919, byte_size(bytes)), byte)
  end

  # Five breakages, five parser codes; a call reads at most five files.
  defp cli_break(bytes, k) do
    case rem(k, 5) do
      0 -> "x" <> bytes
      1 -> bytes <> "x"
      2 -> ""
      3 -> String.replace_suffix(String.trim_trailing(bytes), "}", ",}")
      4 -> String.replace(bytes, "\"", "\"" <> <<0xFF>>, global: false)
    end
  end

  defp cli_pair(dir, command, files) do
    argv =
      Enum.flat_map(files, fn {name, bytes} ->
        path = Path.join(dir, name <> ".json")
        File.write!(path, bytes)
        ["--" <> name, path]
      end)

    {out, exit} = CLI.run([command | argv])

    line = %{
      "command" => command,
      "files" =>
        Map.new(files, fn {name, bytes} -> {name, Base.encode16(bytes, case: :lower)} end)
    }

    {line, cli_expected(command, files, out, exit)}
  end

  defp cli_expected(command, files, out, exit) do
    {:ok, parsed} = KomkiPolicy.JSON.parse(out)
    release? = List.keymember?(files, "release", 0)

    case {command, exit, parsed} do
      {_, 2, %{"result" => "error", "code" => code, "path" => path}} ->
        cli_input_error(code, path)

      {"decide", 0, _} ->
        %{"exit" => 0, "result" => decided(parsed, release?)}

      {"decide", 3, %{"result" => "unsupported"}} ->
        %{"exit" => 3, "result" => %{"unsupported" => true}}

      {"verify", _, _} when exit in [0, 1] ->
        %{"exit" => exit, "result" => parsed}

      {"advance", 0, %{"schema" => "komki-stand/1"}} ->
        %{"exit" => 0, "result" => %{"ok" => Map.delete(parsed, "schema")}}

      {"advance", 1, %{"result" => "refused", "code" => code}} ->
        %{"exit" => 1, "result" => %{"refused" => code}}

      _ ->
        %{"exit" => exit, "result" => parsed}
    end
  end

  defp decided(decision, release?) do
    fields = if release?, do: @release_fields, else: @decision_fields
    decision |> Map.take(fields) |> Map.put("gos", gos(decision["remedies"]))
  end

  defp cli_input_error(code, _path) when code in @json_error_codes,
    do: %{"exit" => 2, "result" => %{"error" => code}}

  defp cli_input_error(code, path),
    do: %{"exit" => 2, "result" => %{"input_error" => code, "path" => path}}

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
      release = release_variant(raw, snapshot, op, hd(variants))

      for(
        target <- [snapshot, repaired(snapshot, op)],
        variant <- variants,
        do: {raw, registry, target, intent(op), release_variant(raw, target, op, variant), @stand}
      ) ++
        for {s, i} <- broken_contexts(snapshot, op), do: {raw, registry, s, i, release, @stand}
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
        {StreamData.constant(:top),
         StreamData.member_of(["snapshot_ref", "registry_ref", "intent_ref"]),
         StreamData.constant("fremd")}
      ),
      # The proof's own shape (validate_proof/1): each error code once.
      StreamData.member_of([
        {:top, "schema", "komki-proof/0"},
        {:top, "zusatz", true},
        {:top, "rule", 7},
        {:top, "conclusion", 7},
        {:top, "registry_ref", 7},
        {:top, "snapshot_ref", 7},
        {:top, "intent_ref", 7},
        {:top, "checked_label", ["b-eins@1", 7]},
        {:top, "premises", %{}},
        {:drop_top, "schema"},
        {:drop_top, "intent_ref"}
      ]),
      StreamData.tuple(
        {StreamData.constant(:put), index,
         StreamData.member_of(~w(kind name value binding fact expression)),
         StreamData.member_of([7, nil, "x"])}
      ),
      StreamData.tuple(
        {StreamData.constant(:drop_key), index, StreamData.member_of(~w(kind name value))}
      ),
      # Kind and name both broken: the kind is checked first.
      StreamData.tuple(
        {StreamData.constant(:replace), index, StreamData.member_of([7, %{"kind" => 7}])}
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

  # Once `premises` is no list, the premise mutations have nothing to act on.
  defp mutate(_mutation, proof)
       when not (is_map_key(proof, "premises") and is_list(:erlang.map_get("premises", proof))),
       do: proof

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
  defp mutate({:drop_top, key}, proof), do: Map.delete(proof, key)
  defp mutate({:drop_key, i, key}, proof), do: update_premise(proof, i, &Map.delete(&1, key))
  defp mutate({:replace, i, value}, proof), do: update_premise(proof, i, fn _ -> value end)

  defp floatify_expression(%{"expression" => expression} = premise),
    do: Map.put(premise, "expression", floatify(expression))

  defp floatify_expression(premise), do: premise

  defp scramble([first | _] = list), do: Enum.reverse(list) ++ [first]
  defp scramble(value), do: value

  defp floatify(value) when is_integer(value), do: value * 1.0
  defp floatify(value) when is_list(value), do: Enum.map(value, &floatify/1)
  defp floatify(value) when is_map(value), do: Map.new(value, fn {k, v} -> {k, floatify(v)} end)
  defp floatify(value), do: value

  # Premises that are no object any more stay as they are.
  defp update_premise(proof, i, fun) do
    Map.update!(proof, "premises", fn premises ->
      List.update_at(premises, i, fn
        premise when is_map(premise) -> fun.(premise)
        premise -> premise
      end)
    end)
  end
end
