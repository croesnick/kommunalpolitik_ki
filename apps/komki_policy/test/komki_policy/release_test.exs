defmodule KomkiPolicy.ReleaseTest do
  use ExUnit.Case, async: true

  alias KomkiPolicy.{JSON, Release, Stand}

  @fixtures_dir Path.expand("../../priv/fixtures", __DIR__)

  defp fixture(path) do
    @fixtures_dir
    |> Path.join(path)
    |> File.read!()
    |> JSON.parse()
    |> elem(1)
  end

  # =====================================================================
  # Release-Validierung (§ 2.6)
  # =====================================================================

  describe "Release-Schema (komki-release/1)" do
    test "gültige Release-Fixture validiert und trägt alle Felder" do
      {:ok, release} = Release.validate(fixture("case_release_permit/release.json"))

      assert release.release_id == "go-ausgabe-4711"
      assert release.kind == "aktionsfreigabe"
      assert release.operation == "emit"
      assert release.valid_from == 1000
      assert release.valid_until == 1100
    end

    test "unbekanntes Feld -> unknown_field (invalid/release_unknown_field.json)" do
      assert {:error, %{code: :unknown_field}} =
               Release.validate(fixture("invalid/release_unknown_field.json"))
    end

    test "invalid_window: valid_from > valid_until (invalid/release_bad_window.json)" do
      assert {:error, %{code: :invalid_window, path: "$.valid_from"}} =
               Release.validate(fixture("invalid/release_bad_window.json"))
    end

    test "unbekanntes kind -> invalid_kind (RESTorakel: geschlossene Menge)" do
      release = Map.put(fixture("case_release_permit/release.json"), "kind", "geheime-freigabe")

      assert {:error, %{code: :invalid_kind}} = Release.validate(release)
    end

    test "falsches Hex-Format (content_digest/call_hash) -> invalid_digest" do
      checksum = fixture("case_release_permit/release.json")

      assert {:error, %{code: :invalid_digest, path: "$.content_digest"}} =
               Release.validate(Map.put(checksum, "content_digest", "ABCD"))

      assert {:error, %{code: :invalid_digest, path: "$.call_hash"}} =
               Release.validate(
                 Map.put(checksum, "call_hash", String.upcase(checksum["call_hash"]))
               )
    end

    test "nicht implementiertes kind ist KEIN Eingabefehler: offenlegungsfreigabe validiert" do
      assert {:ok, %{kind: "offenlegungsfreigabe"}} =
               Release.validate(
                 Map.put(
                   fixture("case_release_permit/release.json"),
                   "kind",
                   "offenlegungsfreigabe"
                 )
               )
    end

    test "unbekannte operation -> invalid_operation; bekannte nicht-emit validiert" do
      base = fixture("case_release_permit/release.json")

      assert {:error, %{code: :invalid_operation}} =
               Release.validate(Map.put(base, "operation", "anzeige"))

      assert {:ok, %{operation: "admit"}} = Release.validate(Map.put(base, "operation", "admit"))
    end
  end

  # =====================================================================
  # Call-Hash-Formel (§ 2.6, verbindlich)
  # =====================================================================

  describe "call_hash/4 (verbindliche Formel)" do
    test "sha256 über kanonischer Form inkl. finalen Newline; kleingeschrieben" do
      digest = "91c1a28117d6d2e06c7345509d15a8beec707a90b89d3e4c4277fbcb1818b2f2"

      payload =
        KomkiPolicy.JSON.canonical(%{
          "content_digest" => digest,
          "object" => "obj-ausgabe-a@v1",
          "operation" => "emit",
          "workspace" => "ws-fall-4711"
        })

      expected = Base.encode16(:crypto.hash(:sha256, payload), case: :lower)

      assert Release.call_hash(digest, "obj-ausgabe-a@v1", "emit", "ws-fall-4711") == expected
      assert Regex.match?(~r/\A[0-9a-f]{64}\z/, expected)
    end

    test "Feste Pin: call_hash aus case_release_permit (Formel-Fixure ist roundtrip-konsistent)" do
      release = fixture("case_release_permit/release.json")

      assert Release.call_hash(
               release["content_digest"],
               release["object"],
               release["operation"],
               release["workspace"]
             ) == release["call_hash"]
    end

    test "Variation des Digests ändert den Hash" do
      a = Release.call_hash("aaaa", "o@v1", "emit", "ws")
      b = Release.call_hash("bbbb", "o@v1", "emit", "ws")
      refute a == b
    end
  end

  # =====================================================================
  # Stand (§ 2.7) + advance (atomarer Übergang)
  # =====================================================================

  defp proposal(release_id, nonce, stand_ref, version, call_hash) do
    %{
      "release_id" => release_id,
      "nonce" => nonce,
      "stand_ref" => stand_ref,
      "stand_version_after" => version,
      "call_hash" => call_hash
    }
  end

  describe "Stand-Schema (komki-stand/1)" do
    test "gültige Stand-Fixture validiert" do
      {:ok, stand} = Stand.validate(fixture("case_release_permit/stand.json"))

      assert stand.stand_id == "stand-4711"
      assert stand.version == 5
      assert stand.consumed == %{}
    end

    test "unbekanntes Feld -> unknown_field; ungültige Version -> invalid_stand_version" do
      assert {:error, %{code: :unknown_field}} =
               Stand.validate(Map.merge(fixture("case_release_permit/stand.json"), %{"x" => 1}))

      assert {:error, %{code: :invalid_stand_version}} =
               Stand.validate(Map.put(fixture("case_release_permit/stand.json"), "version", -1))
    end
  end

  describe "advance (§ 2.7, Compare-and-Swap über die Version)" do
    test "Erfolg: version+1 und consumed um nonce -> release_id erweitert" do
      stand = fixture("case_release_permit/stand.json")

      {:ok, next} =
        Stand.advance(
          stand,
          proposal("go-ausgabe-4711", "go-nonce-4711-a", "stand-4711@5", 6, "cafe")
        )

      assert next.version == 6
      assert next.consumed == %{"go-nonce-4711-a" => "go-ausgabe-4711"}
      assert next.stand_id == "stand-4711"
    end

    test "CAS: zweiter Commit desselben GOs gegen stand@v+1 wird refused (stand_version_conflict)" do
      stand = fixture("case_release_permit/stand.json")
      p = proposal("go-ausgabe-4711", "go-nonce-4711-a", "stand-4711@5", 6, "cafe")

      {:ok, next} = Stand.advance(stand, p)
      next_record = Stand.to_record(next)

      # dieselbe Ausführung gegen den fortgeschriebenen Stand: Versionsabgleich scheitert
      assert {:refused, %{code: :stand_version_conflict}} = Stand.advance(next_record, p)

      # auch der Ausstiegspunkt versagt: der zweite Commit trägt denselben stand_ref auf Basis des Ursprungsstands
      assert {:refused, %{code: :stand_version_conflict}} =
               Stand.advance(next_record, Map.put(p, "stand_ref", "stand-4711@5"))
    end

    test "Nonce bereits verbraucht -> refused (nonce_already_consumed)" do
      stand = fixture("case_release_replay/stand.json")

      assert stand["consumed"] == %{"go-nonce-4711-a" => "go-ausgabe-4711"}

      assert {:refused, %{code: :nonce_already_consumed}} =
               Stand.advance(
                 stand,
                 proposal("go-ausgabe-4711", "go-nonce-4711-a", "stand-4711@5", 6, "cafe")
               )
    end

    test "Stand-Version zuerst geprüft: widersprüchliche Version + Nonce -> stand_version_conflict" do
      stand = fixture("case_release_replay/stand.json")

      assert {:refused, %{code: :stand_version_conflict}} =
               Stand.advance(
                 stand,
                 proposal("go-ausgabe-4711", "go-nonce-4711-a", "phantom@7", 8, "cafe")
               )
    end

    # #120: handgebaute Proposals werden vor dem Commit abgelehnt — die
    # Ausgabe-Invariante (to_record validiert als komki-stand/1) hält ohne
    # Nachvalidierung.
    test "Nicht-Kebab-Nonce im Proposal -> invalid_reference_id (kein Commit)" do
      stand = fixture("case_release_permit/stand.json")

      assert {:error, %{code: :invalid_reference_id, path: "$.nonce"}} =
               Stand.advance(
                 stand,
                 proposal("go-ausgabe-4711", "Nonce_Falsch_1", "stand-4711@5", 6, "cafe")
               )
    end

    test "Nicht-Kebab-release_id im Proposal -> invalid_reference_id (Ausgabe-Invariante)" do
      stand = fixture("case_release_permit/stand.json")

      assert {:error, %{code: :invalid_reference_id, path: "$.release_id"}} =
               Stand.advance(
                 stand,
                 proposal("GO_FALSCH_1", "go-nonce-4711-a", "stand-4711@5", 6, "cafe")
               )
    end

    test "stand_version_after != version + 1 -> refused stand_version_conflict (kein Commit)" do
      stand = fixture("case_release_permit/stand.json")

      assert {:refused, %{code: :stand_version_conflict}} =
               Stand.advance(
                 stand,
                 proposal("go-ausgabe-4711", "go-nonce-4711-a", "stand-4711@5", 7, "cafe")
               )
    end

    test "Ausgabe-Invariante: to_record des fortgeschriebenen Standes validiert als komki-stand/1" do
      stand = fixture("case_release_permit/stand.json")

      {:ok, next} =
        Stand.advance(
          stand,
          proposal("go-ausgabe-4711", "go-nonce-4711-a", "stand-4711@5", 6, "cafe")
        )

      assert {:ok, ^next} = Stand.validate(Stand.to_record(next))
    end

    test "unvollständige/übertypische Proposal-Form -> invalid_proposal (Eingabefehler)" do
      stand = fixture("case_release_permit/stand.json")

      assert {:error, %{code: :invalid_proposal}} =
               Stand.advance(stand, %{"release_id" => "go", "nonce" => "n"})

      assert {:error, %{code: :invalid_proposal}} = Stand.advance(stand, "kein objekt")
    end

    test "Extra-Feld im Proposal -> unknown_field (geschlossene § 4.6-Form, Befund 18)" do
      stand = fixture("case_release_permit/stand.json")

      proposal =
        Map.merge(proposal("go-ausgabe-4711", "go-nonce-4711-a", "stand-4711@5", 6, "cafe"), %{
          "kommentar" => "unbekanntes Extra-Feld"
        })

      assert {:error, %{code: :unknown_field, path: "$.kommentar"}} =
               Stand.advance(stand, proposal)
    end

    test "advance ist rein: der übergebene Stand bleibt unverändert" do
      stand = fixture("case_release_permit/stand.json")
      p = proposal("go-ausgabe-4711", "go-nonce-4711-a", "stand-4711@5", 6, "cafe")

      Stand.advance(stand, p)

      assert stand["version"] == 5
      assert stand["consumed"] == %{}
    end
  end
end
