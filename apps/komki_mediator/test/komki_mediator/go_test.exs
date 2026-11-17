defmodule KomkiMediator.GoTest do
  # Ticket #98: GO for a blocked output. Room vertraulich: handing
  # web_search to the web search (transfer, #298) is denied with
  # recipient_not_allowed; since #354 the catalog offers an
  # Offenlegungsfreigabe for exactly that search text (Szene 4), the
  # window answers it like any GO. The Aktionsfreigabe checks (replay,
  # freshness window, foreign call) run on vault_search in the project
  # room: there ratsprojekte@1 lacks a transfer rule while the recipients
  # pass, so a plain GO still applies.
  # A test process plays the person and answers through the same functions
  # as `komki go`.
  use ExUnit.Case, async: false

  alias KomkiMediator.{ConnectorGate, FakeConnector, Go, GoStand, TestHelpers}

  @params %{"query" => "Foerderung Radweg"}
  @vault_params %{"text" => "Foerderung Radweg"}

  setup do
    base = TestHelpers.provisioned_base()
    dir = FakeConnector.short_dir()
    go_dir = Path.join(base, "go")
    on_exit(fn -> File.rm_rf!(dir) end)

    File.mkdir_p!(go_dir)
    File.touch!(Go.listener_path(go_dir))
    TestHelpers.stop_named(GoStand)
    start_supervised!({GoStand, %{dir: go_dir, scope: "go-test"}})

    env =
      base
      |> TestHelpers.restart_env(%{connectors_dir: dir, go: %{dir: go_dir, timeout_ms: 2_000}})
      |> TestHelpers.vertraulich()

    test = self()

    pid =
      FakeConnector.start("web", dir, env.journal_path, fn _op, _params, _context ->
        send(test, :web_called)
        {:ok, %{"results" => [], "abrufdatum" => "2026-10-25"}}
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    %{env: env, go_dir: go_dir}
  end

  # vault_search with a call GO (Aktionsfreigabe, § 4.6): the project room
  # carries ratsprojekte@1 without a transfer rule; the vault's observers
  # lie inside every binding's recipient circle.
  defp aktion(env, bindings \\ KomkiMediator.Templates.projektraum_bindings()) do
    test = self()

    pid =
      FakeConnector.start("vault", env.connectors_dir, env.journal_path, fn _op, _p, _c ->
        send(test, :vault_called)
        {:ok, %{"results" => []}}
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
    put_in(env.room.workspace_bindings, bindings)
  end

  # Die nutzende Person: wartet auf die Anfrage und beantwortet sie mit
  # `answer` (true, false oder eine fertige Antwort-Map).
  defp person(go_dir, answer) do
    test = self()

    spawn_link(fn ->
      request = wait_for_request(go_dir, 100)
      send(test, {:request, request})

      case answer do
        go? when is_boolean(go?) ->
          Go.answer(go_dir, request, go?)

        fun when is_function(fun, 1) ->
          Go.write_atomic(
            Path.join(go_dir, request["call_hash"] <> ".answer.json"),
            fun.(request)
          )
      end
    end)
  end

  # `operation` narrows the wait: an answered request can still be pending
  # for a moment while the next one is already there.
  defp wait_for_request(go_dir, tries, operation \\ nil)

  defp wait_for_request(_go_dir, 0, _operation), do: flunk("keine GO-Anfrage")

  # Without `operation` exactly one request may be pending: a second one
  # would be a duplicate GO request for the same gate.
  defp wait_for_request(go_dir, tries, nil) do
    case Go.pending(go_dir) do
      [request] -> request
      [] -> retry(go_dir, tries, nil)
    end
  end

  defp wait_for_request(go_dir, tries, operation) do
    case Enum.find(Go.pending(go_dir), &(&1["operation"] == operation)) do
      nil -> retry(go_dir, tries, operation)
      request -> request
    end
  end

  defp retry(go_dir, tries, operation) do
    Process.sleep(20)
    wait_for_request(go_dir, tries - 1, operation)
  end

  defp outcomes(env), do: Enum.map(TestHelpers.journal_records(env.journal_path), & &1["outcome"])

  test "GO erteilt: genau der gebundene Call laeuft, belegt vor der Wirkung", %{
    env: env,
    go_dir: go_dir
  } do
    person(go_dir, true)

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "permit"
    assert_received :web_called
    assert_received {:request, request}
    assert request["tool"] == "web_search"
    assert request["params"] == Map.put(@params, "count", 5)
    assert "recipient_not_allowed" in request["blockers"]
    assert request["operation"] == "transfer"

    # Emit decision, transfer deny, the GO commit (released) right after the
    # nonce, then the record before effect, all before execution; every
    # record carries the call's call_id.
    assert outcomes(env) == ["permitted", "not_admitted", "released", "emitted", "admitted"]

    [decided, deny, released, emitted, admit] = TestHelpers.journal_records(env.journal_path)
    assert decided["rule"] == "emit"
    assert released["rule"] == "transfer"
    assert released["checked_label"] == emitted["assigned_label"]

    assert Enum.all?(
             [decided, deny, released, admit],
             &(&1["call_id"] == emitted["decision_id"])
           )

    assert map_size(GoStand.current()["consumed"]) == 1
    assert Go.pending(go_dir) == []
  end

  test "Replay derselben Freigabe scheitert: Nonce verbraucht", %{env: env, go_dir: go_dir} do
    env = aktion(env)
    test = self()

    person(go_dir, fn request ->
      release = Go.release_for(request, System.os_time(:second))
      send(test, {:release, release})
      release
    end)

    assert ConnectorGate.call(env, "vault_search", @vault_params)["decision"] == "permit"
    assert_received {:release, release}
    assert_received :vault_called

    person(go_dir, fn _request -> release end)
    response = ConnectorGate.call(env, "vault_search", @vault_params)

    assert response["decision"] == "deny"
    assert "release_nonce_consumed" in Enum.map(response["remedies"], & &1["code"])
    refute_received :vault_called
  end

  # #354, Szene 4: Aus dem Raum vertraulich geht ein Suchtext nur mit einer
  # Offenlegungsfreigabe hinaus; das Fenster sieht, welche Bindung sie
  # aufhebt. Eine Aktionsfreigabe als Antwort ist ein Nein.
  test "Suchtext aus vertraulich: Offenlegung, eine Aktionsfreigabe zaehlt nicht", %{
    env: env,
    go_dir: go_dir
  } do
    person(go_dir, fn request -> Go.release_for(request, System.os_time(:second)) end)

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "deny"
    assert response["go"] == "abgelehnt"
    refute_received :web_called

    assert_received {:request, request}
    assert request["kind"] == "offenlegungsfreigabe"
    assert request["ausgabeart"] == "suchanfrage"
    assert request["aufgehoben"] == ["vault-vertraulich@1"]
    assert "vault-vertraulich@1" not in request["ziellabel"]
    assert request["teile"] == []
  end

  test "GO verweigert: keine Ausfuehrung, der Katalog bleibt sichtbar", %{
    env: env,
    go_dir: go_dir
  } do
    person(go_dir, false)

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "deny"
    assert response["go"] == "abgelehnt"
    # Nach einem Nein ist fuer das Modell Schluss (#166)
    assert response["hinweis"] == KomkiMediator.Hinweis.text(:go_refused)
    assert "recipient_not_allowed" in Enum.map(response["remedies"], & &1["code"])
    refute_received :web_called
    assert outcomes(env) == ["permitted", "not_admitted", "go_refused"]

    # All records belong to the same call; deny and refusal to the same
    # snapshot (CONTRACT §6.1 step 7).
    [decided, deny, refused] = TestHelpers.journal_records(env.journal_path)
    assert decided["call_id"] == deny["call_id"]
    assert is_binary(refused["call_id"])
    assert refused["call_id"] == deny["call_id"]
    assert refused["snapshot_id"] == deny["snapshot_id"]
  end

  test "keine Antwort bis zum Ablauf: deny, kein stiller Fallback", %{env: env} do
    env = put_in(env.go.timeout_ms, 300)

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "deny"
    assert response["go"] == "keine Antwort"
    assert response["hinweis"] == KomkiMediator.Hinweis.text(:go_timeout)
    refute_received :web_called
    assert outcomes(env) == ["permitted", "not_admitted", "go_timeout"]
    assert Go.pending(env.go.dir) == []
  end

  # Szene 4, #354: Aus einem Raum mit nichtoeffentlichen Ratsunterlagen gibt
  # es fuer die Websuche kein Fenster, denn ratsarbeit@1 traegt keine
  # Befugnis fuer suchanfrage. ratsarbeit@1 hat auch keine emit-Regel; der
  # Vermittler entscheidet die Uebergabe deshalb vor dem emit-GO und fragt
  # gar nicht erst.
  test "Szene 4: Websuche aus dem Mandatsraum ohne Fenster", %{env: env, go_dir: go_dir} do
    env = put_in(env.room.workspace_bindings, ["ratsarbeit@1", "web-oeffentlich@1"])

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "deny"
    assert response["rule"] == "transfer"
    refute Map.has_key?(response, "go")
    refute_received :web_called
    assert Go.pending(go_dir) == []
    assert outcomes(env) == ["not_admitted", "not_admitted"]

    # pi hoert nur, dass nichts uebertragen wurde, und an wen es nicht darf;
    # kein Katalog, der eine umformulierte Suche nahelegt (Gegenprobe 13.5).
    assert response["hinweis"] == KomkiMediator.Hinweis.text(:not_transmitted)
    assert response["recipients_outside"] == ["brave-search"]
    refute Map.has_key?(response, "remedies")
  end

  test "Frische-Fenster ueberschritten: deny release_expired", %{env: env, go_dir: go_dir} do
    env = aktion(env)
    person(go_dir, fn request -> Go.release_for(request, System.os_time(:second) - 3_600) end)

    response = ConnectorGate.call(env, "vault_search", @vault_params)

    assert response["decision"] == "deny"
    assert "release_expired" in Enum.map(response["remedies"], & &1["code"])
    refute_received :vault_called
  end

  test "Freigabe fuer einen anderen Call: deny release_call_mismatch", %{
    env: env,
    go_dir: go_dir
  } do
    env = aktion(env)

    person(go_dir, fn request ->
      Go.release_for(
        %{request | "call_hash" => String.duplicate("0", 64)},
        System.os_time(:second)
      )
    end)

    response = ConnectorGate.call(env, "vault_search", @vault_params)

    assert "release_call_mismatch" in Enum.map(response["remedies"], & &1["code"])
    refute_received :vault_called
  end

  test "Commit scheitert (Stand nicht schreibbar): keine Wirkung", %{env: env, go_dir: go_dir} do
    # stand.json als Verzeichnis: das Umbenennen beim Persistieren scheitert
    File.mkdir_p!(Path.join(GoStand.path(go_dir), "blockiert"))
    person(go_dir, true)

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "error"
    assert response["detail"] =~ "GO nicht committet"
    assert response["rule"] == "transfer"
    refute_received :web_called
    assert map_size(GoStand.current()["consumed"]) == 0

    # The failed commit stays linked to its call (#298 review).
    [_decided, deny, failed] = TestHelpers.journal_records(env.journal_path)
    assert failed["rule"] == "transfer"
    assert failed["outcome"] == "error"
    assert failed["call_id"] == deny["call_id"]
    assert failed["snapshot_id"] == deny["snapshot_id"]
    assert is_binary(failed["call_id"])
  end

  test "HITL load: ein GO je geblockter Operation", %{env: env, go_dir: go_dir} do
    for query <- ["Radweg", "Spielplatz"] do
      person(go_dir, true)
      assert ConnectorGate.call(env, "web_search", %{"query" => query})["decision"] == "permit"
    end

    assert Enum.count(outcomes(env), &(&1 == "released")) == 2
    assert map_size(GoStand.current()["consumed"]) == 2
  end

  test "niemand hoert zu (komki run): deny sofort, keine Anfrage", %{env: env} do
    File.rm!(Go.listener_path(env.go.dir))

    {micros, response} = :timer.tc(fn -> ConnectorGate.call(env, "web_search", @params) end)

    assert response["decision"] == "deny"
    refute Map.has_key?(response, "go")
    assert micros < 1_000_000

    # Since #354 the GO for a search text is the Offenlegungsfreigabe; the
    # catalog stays visible and the note stays the plain deny.
    refute Go.offered(response["remedies"])
    assert Go.offered_offenlegung(response["remedies"])
    assert response["hinweis"] == KomkiMediator.Hinweis.text(:deny)
  end

  test "veralteter Herzschlag zaehlt nicht", %{env: env} do
    File.touch!(Go.listener_path(env.go.dir), System.os_time(:second) - 60)
    refute Go.listening?(env.go.dir)
  end

  test "ohne GO-Konfiguration: deny wie bisher, keine Anfrage", %{env: env} do
    response = ConnectorGate.call(Map.delete(env, :go), "web_search", @params)

    assert response["decision"] == "deny"
    refute Map.has_key?(response, "go")
    assert Go.pending(env.go.dir) == []
  end

  # A binding without emit and transfer rules (doc-vertraulich@1) blocks
  # both gates: two GO prompts for one call, each a decision of its own
  # (decision 2026-10-31: leave as is). The journal shows every step. The
  # vault's observers lie inside its recipient circle, so both GOs are
  # plain Aktionsfreigaben (#354 leaves them alone).
  test "emit-GO und transfer-GO: jede Entscheidung im Journal, eine call_id", %{
    env: env,
    go_dir: go_dir
  } do
    env = aktion(env, ["doc-vertraulich@1", "vault-oeffentlich@1"])
    test = self()

    spawn_link(fn ->
      for operation <- ["emit", "transfer"] do
        request = wait_for_request(go_dir, 100, operation)
        send(test, {:request, operation})
        Go.answer(go_dir, request, true)
      end
    end)

    ConnectorGate.call(env, "vault_search", @vault_params)

    assert_received {:request, "emit"}
    assert_received {:request, "transfer"}
    assert_received :vault_called

    records = TestHelpers.journal_records(env.journal_path)

    # Every step of the call, ending with admit (doc-vertraulich@1 admits
    # only for the purpose vertraulich).
    assert Enum.map(records, &{&1["rule"], &1["outcome"]}) == [
             {"emit", "not_admitted"},
             {"emit", "released"},
             {"transfer", "not_admitted"},
             {"transfer", "released"},
             {"emit", "emitted"},
             {"admit", "not_admitted"}
           ]

    [call_id] = records |> Enum.map(& &1["call_id"]) |> Enum.uniq()
    [_, emit_go, _, transfer_go, emitted, _] = records
    assert emitted["decision_id"] == call_id
    # The record before effect relies on both GO records.
    assert emitted["authorized_by"] == [emit_go["decision_id"], transfer_go["decision_id"]]
  end
end
