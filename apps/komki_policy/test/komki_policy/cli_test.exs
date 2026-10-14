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
  # decide: Freigabe-Zweig (CONTRACT § 4.6, § 7)
  # ---------------------------------------------------------------------

  defp release_dir(name), do: Path.join("case_release_#{name}", "")

  defp run_release_decide(name) do
    dir = release_dir(name)

    CLI.run([
      "decide",
      "--registry",
      fixture_path("registry.json"),
      "--snapshot",
      fixture_path(Path.join(dir, "snapshot.json")),
      "--intent",
      fixture_path(Path.join(dir, "intent.json")),
      "--release",
      fixture_path(Path.join(dir, "release.json")),
      "--stand",
      fixture_path(Path.join(dir, "stand.json"))
    ])
  end

  test "decide case_release_permit -> Exit 0, permit mit release-Objekt (kein stiller Fallback)" do
    {output, code} = run_release_decide("permit")

    assert code == 0
    parsed = assert_canonical(output)
    assert parsed["decision"] == "permit"
    assert parsed["rule"] == "emit"
    assert is_nil(parsed["proof"])
    assert is_nil(parsed["remedies"])
    assert parsed["release"]["stand_ref"] == "stand-4711@5"
    assert parsed["release"]["stand_version_after"] == 6
    assert parsed["release"]["nonce"] == "go-nonce-4711-a"
  end

  test "decide case_release_swap -> Exit 0, deny release_call_mismatch (Inhaltstausch erkannt)" do
    {output, code} = run_release_decide("swap")

    assert code == 0
    parsed = assert_canonical(output)
    assert parsed["decision"] == "deny"

    assert [%{"code" => "release_call_mismatch", "binding" => nil, "condition" => nil}] =
             parsed["blockers"]

    refute is_nil(parsed["remedies"])
  end

  test "decide case_release_replay -> deny release_nonce_consumed" do
    {_, code} = run_release_decide("replay")
    assert code == 0

    {output, _} = run_release_decide("replay")
    parsed = assert_canonical(output)
    assert [%{"code" => "release_nonce_consumed"}] = parsed["blockers"]
  end

  test "decide Release-Fälle expired/not_yet_valid/scope/authority -> je deny mit korrektem Blocker" do
    Enum.each(
      %{
        "expired" => "release_expired",
        "not_yet_valid" => "release_not_yet_valid",
        "scope" => "release_scope_mismatch",
        "authority" => "release_authority_unknown"
      },
      fn {name, code} ->
        {output, 0} = run_release_decide(name)
        parsed = assert_canonical(output)
        assert [%{"code" => ^code}] = parsed["blockers"], name
      end
    )
  end

  test "decide --release ohne --stand -> Exit 2, usage (nur paarweise gültig)" do
    {output, code} =
      CLI.run([
        "decide",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        fixture_path("case_emit_permit/snapshot.json"),
        "--intent",
        fixture_path("case_emit_permit/intent.json"),
        "--release",
        fixture_path("case_release_permit/release.json")
      ])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
  end

  test "decide --stand ohne --release -> Exit 2, usage" do
    {output, code} =
      CLI.run([
        "decide",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        fixture_path("case_emit_permit/snapshot.json"),
        "--intent",
        fixture_path("case_emit_permit/intent.json"),
        "--stand",
        fixture_path("case_release_permit/stand.json")
      ])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
  end

  test "decide Freigabe kind offenlegungsfreigabe -> Exit 3, unsupported (kein deny)" do
    release = Map.put(fixture("case_release_permit/release.json"), "kind", "offenlegungsfreigabe")
    path = Path.join(System.tmp_dir!(), "komki-policy-offenlegungsfreigabe.json")
    File.write!(path, JSON.canonical(release))

    {output, code} =
      CLI.run([
        "decide",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        fixture_path("case_release_permit/snapshot.json"),
        "--intent",
        fixture_path("case_release_permit/intent.json"),
        "--release",
        path,
        "--stand",
        fixture_path("case_release_permit/stand.json")
      ])

    assert code == 3
    parsed = assert_canonical(output)
    assert parsed["result"] == "unsupported"
    assert parsed["rule"] == "offenlegungsfreigabe"
  end

  test "decide --release/--stand mit admit-Intent -> Exit 3, unsupported (nicht Exit 2 emit_digest_missing, Befund 17)" do
    {output, code} =
      CLI.run([
        "decide",
        "--registry",
        fixture_path("registry.json"),
        "--snapshot",
        # admit-Snapshot ohne output_content_digest: die Reihenfolge § 4.6
        # prüft die Operation VOR der Digest-Pflicht -> unsupported (Exit 3).
        fixture_path("case_permit/snapshot.json"),
        "--intent",
        fixture_path("case_permit/intent.json"),
        "--release",
        fixture_path("case_release_permit/release.json"),
        "--stand",
        fixture_path("case_release_permit/stand.json")
      ])

    assert code == 3
    parsed = assert_canonical(output)
    assert parsed["result"] == "unsupported"
    assert parsed["rule"] == "admit"
  end

  # ---------------------------------------------------------------------
  # advance (CONTRACT § 2.7, § 7)
  # ---------------------------------------------------------------------

  defp proposal_from_decision(decision) do
    {:ok, parsed} = JSON.parse(decision)
    Map.fetch!(parsed, "release")
  end

  defp run_advance(stand_rel, proposal) do
    path = Path.join(System.tmp_dir!(), "komki-policy-advance-proposal.json")
    File.write!(path, JSON.canonical(proposal))

    CLI.run([
      "advance",
      "--stand",
      fixture_path(stand_rel),
      "--proposal",
      path
    ])
  end

  test "advance Erfolg -> Exit 0, neuer Stand kanonisch (version+1, nonce verbraucht)" do
    {permit_output, 0} = run_release_decide("permit")
    proposal = proposal_from_decision(permit_output)

    {output, code} = run_advance("case_release_permit/stand.json", proposal)

    assert code == 0
    parsed = assert_canonical(output)
    assert parsed["schema"] == "komki-stand/1"
    assert parsed["stand_id"] == "stand-4711"
    assert parsed["version"] == 6
    assert parsed["consumed"] == %{"go-nonce-4711-a" => "go-ausgabe-4711"}
  end

  test "advance CAS: zweiter Commit desselben GOs gegen stand@v+1 -> Exit 1, refused" do
    {permit_output, 0} = run_release_decide("permit")
    proposal = proposal_from_decision(permit_output)

    {output, code} = run_advance("case_release_permit/stand.json", proposal)
    assert code == 0
    {:ok, advanced} = JSON.parse(output)
    assert advanced["version"] == 6

    # Vollzug außerhalb des Kerns: der fortgeschriebene Stand ist der neue
    # Schlüsselstand; derselbe GO-Verbrauchsvorschlag wird dagegen verwirft.
    next_stand_path = Path.join(System.tmp_dir!(), "komki-policy-stand-4711-v6.json")
    File.write!(next_stand_path, JSON.canonical(advanced))

    {output2, code2} =
      CLI.run([
        "advance",
        "--stand",
        next_stand_path,
        "--proposal",
        Path.join(System.tmp_dir!(), "komki-policy-advance-proposal.json")
      ])

    assert code2 == 1
    parsed = assert_canonical(output2)
    assert parsed["result"] == "refused"
    assert parsed["code"] == "stand_version_conflict"
  end

  test "advance gegen verbrauchten Stand (nonce) -> Exit 1, refused (nonce_already_consumed)" do
    {_, _} = run_release_decide("permit")

    proposal = %{
      "release_id" => "go-ausgabe-4711",
      "nonce" => "go-nonce-4711-a",
      "stand_ref" => "stand-4711@5",
      "stand_version_after" => 6,
      "call_hash" => "cafe"
    }

    {output, code} = run_advance("case_release_replay/stand.json", proposal)

    assert code == 1
    parsed = assert_canonical(output)
    assert parsed["result"] == "refused"
    assert parsed["code"] == "nonce_already_consumed"
  end

  test "advance ohne --proposal -> Exit 2, usage" do
    {output, code} =
      CLI.run(["advance", "--stand", fixture_path("case_release_permit/stand.json")])

    assert code == 2
    parsed = assert_canonical(output)
    assert parsed["code"] == "usage"
  end

  test "usage-String erwähnt advance und die Freigabe-Flags" do
    {output, code} = run_cli([])

    assert code == 2
    assert String.contains?(output, "advance --stand")
    assert String.contains?(output, "--release <g.json> --stand <st.json>")
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
