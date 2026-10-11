defmodule KomkiPolicy.CLITest do
  use ExUnit.Case, async: true

  alias KomkiPolicy.{CLI, JSON}

  @fixtures_path Path.expand("../../priv/fixtures", __DIR__)

  defp fixture_path(path), do: Path.join(@fixtures_path, path)

  defp fixture(path) do
    content = File.read!(fixture_path(path))
    {:ok, parsed} = JSON.parse(content)
    parsed
  end

  defp run_cli(args), do: CLI.run(args)

  defp run_decide(case_rel) do
    CLI.run([
      "decide",
      "--registry",
      fixture_path("registry.json"),
      "--snapshot",
      fixture_path(Path.join(case_rel, "snapshot.json")),
      "--intent",
      fixture_path(Path.join(case_rel, "intent.json"))
    ])
  end

  defp run_verify(case_rel, proof_rel) do
    CLI.run([
      "verify",
      "--registry",
      fixture_path("registry.json"),
      "--snapshot",
      fixture_path(Path.join(case_rel, "snapshot.json")),
      "--intent",
      fixture_path(Path.join(case_rel, "intent.json")),
      "--proof",
      fixture_path(proof_rel)
    ])
  end

  defp run_validate(registry_rel) do
    run_cli(["validate", "--registry", fixture_path(registry_rel)])
  end

  defp assert_canonical(output) do
    assert {:ok, parsed} = JSON.parse(output)
    assert JSON.canonical(parsed) == output
    parsed
  end

  defp reason_codes(reasons), do: Enum.map(reasons, &Map.fetch!(&1, "code"))

  # ---------------------------------------------------------------------
  # validate
  # ---------------------------------------------------------------------

  test "validate mit gültiger Registry -> Exit 0, result valid, kanonisch" do
    {output, code} = run_validate("registry.json")

    assert code == 0
    parsed = assert_canonical(output)
    assert parsed["result"] == "valid"
  end

  test "validate mit unbekanntem Feld -> Exit 2, code unknown_field" do
    {output, code} = run_validate("invalid/registry_unknown_field.json")

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["result"] == "error"
    assert parsed["code"] == "unknown_field"
  end

  test "validate mit doppeltem JSON-Schlüssel -> Exit 2, code duplicate_json_key" do
    {output, code} = run_validate("invalid/registry_duplicate_key.json")

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "duplicate_json_key"
  end

  test "validate mit fehlender Datei -> Exit 2, code read_error (kein Crash)" do
    {output, code} = run_cli(["validate", "--registry", "/tmp/komki-policy-nonexistent.json"])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "read_error"
    assert String.contains?(parsed["detail"], "/tmp/komki-policy-nonexistent.json")
  end

  test "validate ohne --registry -> Exit 2, code usage" do
    {output, code} = run_cli(["validate"])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
    assert String.contains?(parsed["detail"], "--registry")
  end

  # ---------------------------------------------------------------------
  # decide
  # ---------------------------------------------------------------------

  test "decide case_permit -> Exit 0, Decision-Feldkern exakt wie expected_decision" do
    {output, code} = run_decide("case_permit")

    assert code == 0
    parsed = assert_canonical(output)
    assert parsed["decision"] == "permit"
    # Fixture-Feldkern muss exakt matches (proof wird separat assertEquals A.7).
    expected = fixture("case_permit/expected_decision.json")
    assert Map.delete(parsed, "proof") == expected
    assert parsed["proof"]["schema"] == "komki-proof/1"
    assert parsed["proof"]["conclusion"] == "permit"
  end

  test "decide case_deny -> Exit 0 (deny ist legitimes Ergebnis), kanonisch" do
    {output, code} = run_decide("case_deny")

    assert code == 0
    parsed = assert_canonical(output)
    assert parsed["decision"] == "deny"
    refute is_nil(parsed["blockers"])
    assert is_nil(parsed["proof"])
  end

  test "decide case_indeterminate -> Exit 0, decision indeterminate mit Evidenz" do
    {output, code} = run_decide("case_indeterminate")

    assert code == 0
    parsed = assert_canonical(output)
    assert parsed["decision"] == "indeterminate"
    refute is_nil(parsed["missing_evidence"])
  end

  test "decide case_unsupported -> Exit 3, exakt erwartete unsupported-Ausgabe" do
    {output, code} = run_decide("case_unsupported")

    assert code == 3
    assert output == JSON.canonical(fixture("case_unsupported/expected_result.json"))
  end

  test "decide mit Kohärenzfehler -> Exit 2, code intent_snapshot_mismatch" do
    {output, code} =
      CLI.run([
        "decide",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        fixture_path("case_permit/snapshot.json"),
        "--intent",
        fixture_path("invalid/intent_version_mismatch.json")
      ])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["result"] == "error"
    assert parsed["code"] == "intent_snapshot_mismatch"
  end

  test "decide mit fehlender Snapshot-Datei -> Exit 2, code read_error (kein Crash)" do
    {output, code} =
      CLI.run([
        "decide",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        "/tmp/komki-policy-nonexistent-snapshot.json",
        "--intent",
        fixture_path("case_permit/intent.json")
      ])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "read_error"
  end

  test "decide ohne --intent -> Exit 2, code usage" do
    {output, code} =
      CLI.run([
        "decide",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        fixture_path("case_permit/snapshot.json")
      ])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
    assert String.contains?(parsed["detail"], "--intent")
  end

  test "decide mit Flag ohne Wert -> Exit 2, code usage" do
    {output, code} =
      CLI.run([
        "decide",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        fixture_path("case_permit/snapshot.json"),
        "--intent"
      ])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
    assert String.contains?(parsed["detail"], "--intent")
  end

  test "decide mit unerwartetem Positionsargument -> Exit 2, code usage" do
    {output, code} =
      CLI.run([
        "decide",
        "extra",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        fixture_path("case_permit/snapshot.json"),
        "--intent",
        fixture_path("case_permit/intent.json")
      ])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
  end

  # ---------------------------------------------------------------------
  # verify
  # ---------------------------------------------------------------------

  test "verify case_permit/proof_valid -> Exit 0, result valid, kanonisch" do
    {output, code} = run_verify("case_permit", "case_permit/proof_valid.json")

    assert code == 0
    parsed = assert_canonical(output)
    assert parsed["result"] == "valid"
    assert parsed["reasons"] == []
  end

  test "verify case_deny/proof_false_condition -> Exit 1 (Beweis verworfen)" do
    {output, code} = run_verify("case_deny", "proofs/proof_false_condition.json")

    assert code == 1
    parsed = assert_canonical(output)
    assert parsed["result"] == "invalid"
    assert "condition_false" in reason_codes(parsed["reasons"])
    assert "conclusion_mismatch" in reason_codes(parsed["reasons"])
  end

  test "verify case_permit/proof_foreign_snapshot -> Exit 1, snapshot_mismatch" do
    {output, code} = run_verify("case_permit", "proofs/proof_foreign_snapshot.json")

    assert code == 1
    parsed = assert_canonical(output)
    assert parsed["result"] == "invalid"

    assert parsed["reasons"] == [
             %{"code" => "snapshot_mismatch", "binding" => nil, "fact" => nil}
           ]
  end

  test "verify mit fehlender Proof-Datei -> Exit 2, code read_error" do
    {output, code} = run_verify("case_permit", "proofs/komki-policy-nonexistent-proof.json")

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "read_error"
  end

  test "verify ohne --proof -> Exit 2, code usage" do
    {output, code} =
      CLI.run([
        "verify",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        fixture_path("case_permit/snapshot.json"),
        "--intent",
        fixture_path("case_permit/intent.json")
      ])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
    assert String.contains?(parsed["detail"], "--proof")
  end

  # ---------------------------------------------------------------------
  # plan / unbekannter Befehl
  # ---------------------------------------------------------------------

  test "plan -> Exit 3, unsupported (kein deny, keine Decision)" do
    {output, code} = run_cli(["plan"])

    assert code == 3
    parsed = assert_canonical(output)
    assert parsed["result"] == "unsupported"
    assert parsed["rule"] == "plan"

    assert MapSet.equal?(
             MapSet.new(Map.keys(parsed)),
             MapSet.new(["detail", "result", "rule"])
           )
  end

  test "plan mit Trailing-Args -> ebenfalls Exit 3 (deterministisch ignoriert, MIN-5)" do
    {output, code} = run_cli(["plan", "--registry", fixture_path("registry.json"), "extra"])

    assert code == 3
    parsed = assert_canonical(output)
    assert parsed["result"] == "unsupported"
    assert parsed["rule"] == "plan"
  end

  test "unbekanntes Flag mit Wert -> Exit 2, Detail 'unknown option' (MIN-4)" do
    {output, code} = run_cli(["decide", "--foo", "bar"])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
    assert String.contains?(parsed["detail"], "unknown option --foo")
    refute String.contains?(parsed["detail"], "requires a value")
  end

  test "unbekanntes Flag ohne Wert -> Exit 2, Detail 'unknown option' (MIN-4)" do
    {output, code} = run_cli(["decide", "--foo"])

    assert code == 2
    parsed = assert_canonical(output)
    assert String.contains?(parsed["detail"], "unknown option --foo")
  end

  test "bekanntes Flag ohne Wert -> Exit 2, Detail 'requires a value' (MIN-4)" do
    {output, code} = run_cli(["decide", "--registry"])

    assert code == 2
    parsed = assert_canonical(output)
    assert String.contains?(parsed["detail"], "--registry requires a value")
  end

  test "unerwarteter argv-Typ fließt in dem Crash-Handler -> Exit 4, code internal_error (MIN-5, kein Abort)" do
    {output, code} =
      run_cli([
        "decide",
        "--registry",
        :not_a_path,
        "--snapshot",
        fixture_path("case_permit/snapshot.json"),
        "--intent",
        fixture_path("case_permit/intent.json")
      ])

    assert code == 4
    parsed = assert_canonical(output)
    assert parsed["result"] == "internal_error"
    assert parsed["code"] == "internal_error"
    assert String.contains?(parsed["detail"], "unhandled")
  end

  test "unbekannter Befehl -> Exit 2, code unknown_command, mit Usage-Hinweis" do
    {output, code} = run_cli(["planx", "--registry", fixture_path("registry.json")])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["result"] == "error"
    assert parsed["code"] == "unknown_command"
    assert String.contains?(parsed["detail"], "usage:")
  end

  test "leeres argv -> Exit 2, code usage (fehlende Argumente = Usage-Fehler)" do
    {output, code} = run_cli([])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
    assert String.contains?(parsed["detail"], "usage:")
  end

  # ---------------------------------------------------------------------
  # Output-Struktur & Determinismus (§ 6, § 7)
  # ---------------------------------------------------------------------

  test "zwei identische decide-Aufrufe -> byte-identisches stdout" do
    args1 = [
      "decide",
      "--registry",
      fixture_path("registry.json"),
      "--snapshot",
      fixture_path("case_permit/snapshot.json"),
      "--intent",
      fixture_path("case_permit/intent.json")
    ]

    args2 = [
      "decide",
      "--registry",
      fixture_path("registry.json"),
      "--snapshot",
      fixture_path("case_permit/snapshot.json"),
      "--intent",
      fixture_path("case_permit/intent.json")
    ]

    outcome = {run_cli(args1), run_cli(args2)}

    assert elem(outcome, 0) == elem(outcome, 1)
  end

  test "alle Outputs tragen genau ein finales Newline und keine Leerzeile" do
    outputs = [
      run_validate("registry.json"),
      run_decide("case_permit"),
      run_decide("case_unsupported"),
      run_cli(["plan"]),
      run_cli([])
    ]

    Enum.each(outputs, fn {output, _code} ->
      assert String.ends_with?(output, "\n")
      refute String.contains?(output, "\n\n")
      refute String.contains?(output, "\r")
    end)
  end

  test "decide permit: Beweisbaum aus der CLI wird von Verify bestätigt (Kopplung A.7)" do
    {permit_output, 0} = run_decide("case_permit")
    {:ok, decision} = JSON.parse(permit_output)
    proof = decision["proof"]

    {verify_output, code} = run_verify("case_permit", "case_permit/proof_valid.json")

    assert code == 0
    assert verify_output == JSON.canonical(%{"result" => "valid", "reasons" => []})
    assert proof["schema"] == "komki-proof/1"
  end
end
