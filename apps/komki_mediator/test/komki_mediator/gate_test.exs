defmodule KomkiMediator.GateTest do
  use ExUnit.Case, async: false

  alias KomkiMediator.{Gate, Room, TestHelpers}
  alias KomkiPolicy.{Derive, JSON}

  setup do
    base = TestHelpers.provisioned_base()
    env_map = TestHelpers.restart_env(base)

    %{
      base: base,
      gamma: env_map.gamma,
      room: env_map.room,
      journal_path: env_map.journal_path,
      env: env_map
    }
  end

  # -----------------------------------------------------------------------
  # Ping: Permit-Fluss mit PDR-Begleitdokument
  # -----------------------------------------------------------------------

  test "ping wird erlaubt: decision_id, labels, payload_hash", %{env: env} do
    response = Gate.call(env, "ping", %{}, TestHelpers.ping_executor(env.gamma))

    assert response["decision"] == "permit"
    assert response["decision_id"] =~ "pdr-"
    assert response["labels"] == ["mediator-ping@1"]
    assert response["payload_hash"] =~ "sha256:"
    assert response["tools"] == KomkiMediator.Fassung.tools()
  end

  test "PDR-Datensatz: Form, byte-kanonischer Chunk, abrufdatum ISO8601", %{
    env: env,
    journal_path: journal_path
  } do
    response = Gate.call(env, "ping", %{}, TestHelpers.ping_executor(env.gamma))

    [_pre_chunk, chunk] = TestHelpers.journal_chunks_raw(journal_path)
    assert [pre, pdr] = TestHelpers.journal_records(journal_path)

    # Vorbeleg vor dem Executor (Audit vor Wirkung)
    assert pre["outcome"] == "executing"
    assert pre["decision"] == "permit"
    assert pre["admitted"] == nil
    assert pre["intent_id"] == pdr["intent_id"]

    # Der Eintrag ist selbst byte-kanonisch.
    assert JSON.canonical(pdr) == chunk

    assert pdr["schema"] == "komki-pdr/4"
    assert pdr["decision"] == "permit"
    assert pdr["outcome"] == "admitted"
    assert pdr["admitted"] == true
    assert pdr["decision_id"] == response["decision_id"]
    assert pdr["gamma"]["registry_id"] == "reg-komki-arbeitsraum"
    assert pdr["gamma"]["gamma_hash"] =~ "sha256:"
    assert pdr["intent_hash"] =~ "sha256:"
    assert pdr["payload_hash"] =~ "sha256:"
    assert pdr["intent_id"] =~ "intent-"
    assert pdr["snapshot_id"] =~ "snap-"
    assert pdr["fassung_id"] == "komki-mediator/3"

    {:ok, _, _} = DateTime.from_iso8601(pdr["abrufdatum"])
  end

  test "Vorbeleg steht im Journal, bevor der Executor laeuft", %{
    env: env,
    journal_path: journal_path
  } do
    test = self()

    executor = fn ->
      send(test, {:executor_sah, TestHelpers.journal_records(journal_path)})
      TestHelpers.admit_executor(env.room, "doc-oeffentlich").()
    end

    Gate.call(env, "admit_document", %{"document_id" => "doc-oeffentlich"}, executor)

    assert_received {:executor_sah, [%{"outcome" => "executing", "tool" => "admit_document"}]}
  end

  test "Negativtest: ohne schreibbares Journal laeuft der Executor nie", %{env: env} do
    test = self()
    {:ok, journal} = Agent.start(fn -> nil end)
    Agent.stop(journal)
    executor = fn -> send(test, :executor_lief) end

    catch_exit(
      Gate.call(
        %{env | journal: journal},
        "admit_document",
        %{"document_id" => "doc-oeffentlich"},
        executor
      )
    )

    refute_received :executor_lief
  end

  # -----------------------------------------------------------------------
  # admit_document: die drei Entscheidungspfade
  # -----------------------------------------------------------------------

  test "doc-oeffentlich -> Permit mit Inhalt; identischer Aufruf, gleicher intent_hash", %{
    env: env,
    journal_path: journal_path
  } do
    executor = TestHelpers.admit_executor(env.room, "doc-oeffentlich")
    params = %{"document_id" => "doc-oeffentlich"}

    first = Gate.call(env, "admit_document", params, executor)
    second = Gate.call(env, "admit_document", params, executor)

    assert first["decision"] == "permit"
    assert first["content"] != nil
    assert first["content"] == File.read!(Path.join(env.room.documents_dir, "doc-oeffentlich.md"))
    assert second["decision"] == "permit"

    intent_hashes = intent_hashes_from_journal(journal_path)
    assert Enum.count(intent_hashes) == 2
    # Byte-Stabilitaet des gerenderten Aufrufs: gleicher Aufruf -> gleicher
    # Hash (daher exakt eine uniq-Menge).
    assert Enum.count(Enum.uniq(intent_hashes)) == 1
  end

  test "unterschiedliche Paramter heissen unterschiedliche intent_hash", %{
    env: env,
    journal_path: journal_path
  } do
    Gate.call(env, "ping", %{}, TestHelpers.ping_executor(env.gamma))

    Gate.call(
      env,
      "admit_document",
      %{"document_id" => "doc-oeffentlich"},
      TestHelpers.admit_executor(env.room, "doc-oeffentlich")
    )

    intent_hashes = intent_hashes_from_journal(journal_path)
    assert Enum.count(intent_hashes) == 2
    assert Enum.count(Enum.uniq(intent_hashes)) == 2
  end

  # R.5.4 (#213): das Validierungslabel ist B_W des Raums, nicht λ(x).
  test "recherche: doc-vertraulich liegt nicht in B_W -> deny label_not_included", %{
    env: env,
    journal_path: journal_path
  } do
    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-vertraulich"},
        fn -> flunk("Executor darf nach einem deny nicht laufen") end
      )

    assert response["decision"] == "deny"
    assert [%{"code" => "label_not_included"} | _] = response["remedies"]
    assert response["hinweis"] == KomkiMediator.Hinweis.text(:deny)

    assert [pdr] = TestHelpers.journal_records(journal_path)
    assert pdr["checked_label"] == env.room.workspace_bindings
  end

  test "Raum ohne workspace_bindings: admit_document faellt fail-closed aus", %{
    env: env,
    journal_path: journal_path
  } do
    env = put_in(env.room.workspace_bindings, nil)

    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-oeffentlich"},
        fn -> flunk("Executor darf ohne B_W nicht laufen") end
      )

    assert response["decision"] == "error"
    assert response["detail"] =~ "workspace_bindings"

    assert [%{"outcome" => "error", "admitted" => false}] =
             TestHelpers.journal_records(journal_path)
  end

  test "doc-vertraulich -> deny mit Engine-Remedy-Katalog (kein nackter Fehler)", %{
    env: env,
    journal_path: journal_path
  } do
    env = put_in(env.room.workspace_bindings, ["doc-vertraulich@1"])

    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-vertraulich"},
        TestHelpers.admit_executor(env.room, "doc-vertraulich")
      )

    assert response["decision"] == "deny"
    assert response["decision_id"] =~ "pdr-"
    assert response["registry_id"] == "reg-komki-arbeitsraum"

    # Engine-Katalog (KomkiPolicy.Remedies, CONTRACT § 2.8), unverändert
    # durchgereicht: der Blocker spiegelt sich mit fakt_nachreichen VOR
    # neuer_raum; admit kennt keine aktionsfreigabe.
    assert response["remedies"] == [
             %{
               "code" => "binding_condition_false",
               "binding" => "doc-vertraulich@1",
               "condition" => "purpose",
               "transitions" => [
                 %{"type" => "fakt_nachreichen", "facts" => ["purpose"]},
                 %{
                   "type" => "neuer_raum",
                   "required_bindings" => ["doc-vertraulich@1"],
                   "required_recipients" => ["nutzende-person", "pi-agent"]
                 }
               ]
             }
           ]

    assert response["relaxation_authorities"] == []
    refute Map.has_key?(response, "content")

    assert [pdr] = TestHelpers.journal_records(journal_path)
    assert pdr["decision"] == "deny"
    assert pdr["outcome"] == "not_admitted"
  end

  test "doc-pending-freigabe -> indeterminate mit Engine-Remedy-Katalog", %{
    env: env,
    journal_path: journal_path
  } do
    env = put_in(env.room.workspace_bindings, ["doc-pending-freigabe@1"])

    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-pending-freigabe"},
        TestHelpers.admit_executor(env.room, "doc-pending-freigabe")
      )

    assert response["decision"] == "indeterminate"

    assert response["remedies"] == [
             %{
               "code" => "missing_fact",
               "fact" => "vertraulich_freigabe",
               "binding" => "doc-pending-freigabe@1",
               "transitions" => [
                 %{"type" => "fakt_nachreichen", "facts" => ["vertraulich_freigabe"]},
                 %{
                   "type" => "neuer_raum",
                   "required_bindings" => ["doc-pending-freigabe@1"],
                   "required_recipients" => ["nutzende-person", "pi-agent"]
                 }
               ]
             }
           ]

    # Γ-L1 (R.2.2): die Lockerungsbefugnis der benannten Bindung bleibt
    # Teil der Antwort, aus dem rohen Registry-Term. Der Store exportiert sie
    # bis #109 als [] (fail-closed, #208).
    assert response["relaxation_authorities"] == []

    assert [pdr] = TestHelpers.journal_records(journal_path)
    assert pdr["decision"] == "indeterminate"
    assert pdr["outcome"] == "not_admitted"
  end

  test "unbekanntes Dokument -> Entscheidungsfehler, PDR not_admitted, kein Crash", %{
    env: env,
    journal_path: journal_path
  } do
    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-phantom"},
        TestHelpers.admit_executor(env.room, "doc-phantom")
      )

    assert response["decision"] == "error"
    assert response["detail"] == "unbekanntes Objekt: \"doc-phantom\""

    assert [pdr] = TestHelpers.journal_records(journal_path)
    assert pdr["outcome"] == "not_admitted"
    assert pdr["intent_hash"] =~ "sha256:"
  end

  test "admit_document auf ein Nicht-Dokument (mediator-ping) -> unknown_object (#134)", %{
    env: env,
    journal_path: journal_path
  } do
    test = self()

    response =
      Gate.call(env, "admit_document", %{"document_id" => "mediator-ping"}, fn ->
        send(test, :executor_called)
        {:error, :enoent}
      end)

    assert response["decision"] == "error"
    assert response["detail"] == "unbekanntes Objekt: \"mediator-ping\""
    refute_received :executor_called
    assert [%{"outcome" => "not_admitted"}] = TestHelpers.journal_records(journal_path)
  end

  # -----------------------------------------------------------------------
  # Tor 2 separat: Rueckhaltung bei verfaelschtem Beweis (Orakel)
  # -----------------------------------------------------------------------

  test "verfaelschter Beweis -> Rueckhaltung ohne Inhalt, PDR redacted", %{
    env: env,
    journal_path: journal_path
  } do
    intent_hash = "sha256:" <> String.duplicate("ab", 32)
    snapshot = build_snapshot(env, "doc-oeffentlich", intent_hash)
    intent = build_intent(env, "doc-oeffentlich")
    {:ok, decision} = Derive.decide(env.gamma.compiled, snapshot, intent)

    # Beweis verfaelschen: ein Praemissenwert wird gekippt.
    tampered = rewrite_first_fact_value(decision["proof"])

    response =
      Gate.admit_result(
        env,
        "admit_document",
        intent_hash,
        intent,
        snapshot,
        tampered,
        {:ok, %{"content" => "geheim"}}
      )

    assert response["decision"] == "permit"
    assert response["admitted"] == "redacted"
    assert response["reason"] =~ "fehlgeschlagen"
    refute Map.has_key?(response, "content")

    {:ok, pdr} = journal_last_record(journal_path)
    assert pdr["admitted"] == "redacted"
    assert pdr["outcome"] == "redacted"
  end

  # -----------------------------------------------------------------------
  # Fail-closed: stirbt der Journal-Prozess, wirft das Gate
  # -----------------------------------------------------------------------

  test "Journal tot -> Gate wirft (keine Antwort ohne Journal-Schreibzugriff)", %{env: env} do
    GenServer.stop(KomkiMediator.Journal)

    assert catch_exit(Gate.call(env, "ping", %{}, TestHelpers.ping_executor(env.gamma)))
  end

  # -----------------------------------------------------------------------
  # Gate 2, zweiter Pruefschritt: Payload-Bindung gegen den Snapshot
  # -----------------------------------------------------------------------

  test "fremdes object_id im Result -> Rueckhaltung (payload_object_mismatch)", %{
    env: env,
    journal_path: journal_path
  } do
    intent_hash = "sha256:" <> String.duplicate("ab", 32)
    snapshot = build_snapshot(env, "doc-oeffentlich", intent_hash)
    intent = build_intent(env, "doc-oeffentlich")
    {:ok, decision} = Derive.decide(env.gamma.compiled, snapshot, intent)

    # Die Entscheidung ist unverfaelscht, das Vollzugs-Ergebnis aber
    # verdreht: es traegt den Claim eines anderen Raum-Objekts.
    response =
      Gate.admit_result(
        env,
        "admit_document",
        intent_hash,
        intent,
        snapshot,
        decision,
        {:ok, %{"object_id" => "doc-vertraulich", "content" => "geheim"}}
      )

    assert response["decision"] == "permit"
    assert response["admitted"] == "redacted"
    assert response["verify"] == ["payload_object_mismatch"]
    assert response["decision_id"] =~ "pdr-"
    assert response["payload_hash"] =~ "sha256:"
    refute Map.has_key?(response, "content")
    refute Map.has_key?(response, "remedies")

    {:ok, pdr} = journal_last_record(journal_path)
    assert pdr["outcome"] == "redacted"
    assert pdr["admitted"] == "redacted"
  end

  test "Result ohne object_id -> Rueckhaltung (payload_identity_missing)", %{
    env: env,
    journal_path: journal_path
  } do
    intent_hash = "sha256:" <> String.duplicate("ab", 32)
    snapshot = build_snapshot(env, "doc-oeffentlich", intent_hash)
    intent = build_intent(env, "doc-oeffentlich")
    {:ok, decision} = Derive.decide(env.gamma.compiled, snapshot, intent)

    response =
      Gate.admit_result(
        env,
        "admit_document",
        intent_hash,
        intent,
        snapshot,
        decision,
        {:ok, %{"content" => "unbelegt"}}
      )

    assert response["admitted"] == "redacted"
    assert response["verify"] == ["payload_identity_missing"]
    refute Map.has_key?(response, "content")

    {:ok, pdr} = journal_last_record(journal_path)
    assert pdr["outcome"] == "redacted"
  end

  test "payload_hash bindet die Antwort ohne ihr eigenes payload_hash-Feld (beide Pfade)", %{
    env: env
  } do
    # Admitted-Pfad: permit mit Vollzugsergebnis.
    admitted = Gate.call(env, "ping", %{}, TestHelpers.ping_executor(env.gamma))

    # Rueckhalte-Pfad: verfaelschter Beweis.
    intent_hash = "sha256:" <> String.duplicate("cd", 32)
    snapshot = build_snapshot(env, "doc-oeffentlich", intent_hash)
    intent = build_intent(env, "doc-oeffentlich")
    {:ok, decision} = Derive.decide(env.gamma.compiled, snapshot, intent)
    tampered = rewrite_first_fact_value(decision["proof"])

    redacted =
      Gate.admit_result(
        env,
        "admit_document",
        intent_hash,
        intent,
        snapshot,
        tampered,
        {:ok, %{"content" => "geheim"}}
      )

    for response <- [admitted, redacted] do
      assert response["payload_hash"] =~ "sha256:"
      # Die Antwort ohne das eigene payload_hash-Feld re-kanonisiert
      # ergibt exakt den Hash (kein Selbstbezug).
      base = Map.delete(response, "payload_hash")
      assert response["payload_hash"] == KomkiMediator.Hash.sha256_hex(JSON.canonical(base))
    end
  end

  test "Extra-Feld in den Parametern heisst neuer, unverwechselbarer intent_hash (exakter Call)",
       %{
         env: env,
         journal_path: journal_path
       } do
    executor = TestHelpers.admit_executor(env.room, "doc-oeffentlich")

    Gate.call(env, "admit_document", %{"document_id" => "doc-oeffentlich"}, executor)

    Gate.call(
      env,
      "admit_document",
      %{"document_id" => "doc-oeffentlich", "extra" => "feld"},
      executor
    )

    intent_hashes = intent_hashes_from_journal(journal_path)
    assert Enum.count(intent_hashes) == 2
    assert Enum.count(Enum.uniq(intent_hashes)) == 2
  end

  # -----------------------------------------------------------------------
  # Helfer
  # -----------------------------------------------------------------------

  # Eintraege sind multi-line-Kanons: hier ein einzelnes Orakeldokument.
  defp journal_last_record(journal_path) do
    chunk = List.last(TestHelpers.journal_chunks_raw(journal_path))
    JSON.parse(chunk)
  end

  # -----------------------------------------------------------------------
  # list_documents (#218)
  # -----------------------------------------------------------------------

  test "list_documents: recherche nennt nur doc-oeffentlich, ohne Inhalt, mit PDR", %{
    env: env,
    journal_path: journal_path
  } do
    response = Gate.list_documents(env)

    assert response["decision"] == "permit"

    assert response["documents"] == [
             %{"document_id" => "doc-oeffentlich", "labels" => ["doc-oeffentlich@2"]}
           ]

    assert response["labels"] == env.room.workspace_bindings
    refute inspect(response) =~ "Notiz"

    assert [pdr] = TestHelpers.journal_records(journal_path)
    assert pdr["tool"] == "list_documents"
    assert pdr["outcome"] == "admitted"
    assert pdr["checked_label"] == env.room.workspace_bindings
    assert pdr["payload_hash"] == response["payload_hash"]
  end

  test "list_documents: zulaessig ist, was die Engine fuer B_W erlaubt", %{env: env} do
    env = put_in(env.room.facts["purpose"]["value"], "vertraulich")
    env = put_in(env.room.workspace_bindings, ["doc-oeffentlich@2", "doc-vertraulich@1"])

    ids = Enum.map(Gate.list_documents(env)["documents"], & &1["document_id"])
    assert ids == ["doc-oeffentlich", "doc-vertraulich"]
  end

  test "list_documents ohne workspace_bindings: Fehler mit PDR", %{
    env: env,
    journal_path: journal_path
  } do
    response = Gate.list_documents(put_in(env.room.workspace_bindings, nil))

    assert response["decision"] == "error"
    refute Map.has_key?(response, "documents")

    assert [%{"tool" => "list_documents", "outcome" => "error"}] =
             TestHelpers.journal_records(journal_path)
  end

  # Ein Hash je Ablauf: der Vorbeleg (`executing`) traegt denselben Hash.
  defp intent_hashes_from_journal(journal_path) do
    journal_path
    |> TestHelpers.journal_records()
    |> Enum.reject(&(&1["outcome"] == "executing"))
    |> Enum.map(fn pdr -> pdr["intent_hash"] end)
  end

  # Baustein wie im Gate, nur mit fixer digest12-Quelle (der intent_hash).
  defp build_snapshot(env, document_id, intent_hash) do
    {:ok, object} =
      Room.object_for_call(env.room, "admit_document", %{"document_id" => document_id})

    Room.snapshot_for(
      env.room,
      env.gamma,
      object,
      KomkiMediator.Hash.digest12(intent_hash),
      env.room.workspace_bindings
    )
  end

  defp build_intent(env, document_id) do
    %{
      "schema" => "komki-intent/1",
      "intent_id" => "intent-gate-test",
      "operation" => "admit",
      "object" => document_id <> "@v1",
      "workspace" => env.room.workspace_id
    }
  end

  defp rewrite_first_fact_value(proof) do
    [premise | rest] = proof["premises"]
    mutated = Map.put(premise, "value", false)
    Map.put(proof, "premises", [mutated | rest])
  end
end
