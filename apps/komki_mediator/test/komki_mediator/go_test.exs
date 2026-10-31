defmodule KomkiMediator.GoTest do
  # Ticket #98: GO for a blocked output. Room vertraulich: handing
  # web_search to the web search (transfer, #298) is denied with
  # recipient_not_allowed; the catalog offers a call GO.
  # Ein Testprozess spielt die nutzende Person und antwortet ueber dieselben
  # Funktionen wie `komki go`.
  use ExUnit.Case, async: false

  alias KomkiMediator.{ConnectorGate, FakeConnector, Go, GoStand, TestHelpers}

  @params %{"query" => "Foerderung Radweg"}

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

  defp wait_for_request(_go_dir, 0), do: flunk("keine GO-Anfrage")

  defp wait_for_request(go_dir, tries) do
    case Go.pending(go_dir) do
      [request] ->
        request

      [] ->
        Process.sleep(20)
        wait_for_request(go_dir, tries - 1)
    end
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

    # Transfer deny, then emit and the released transfer in decision order,
    # both before execution; every record carries the call's call_id.
    assert outcomes(env) == ["not_admitted", "emitted", "released", "admitted"]

    [deny, emitted, released, admit] = TestHelpers.journal_records(env.journal_path)
    assert released["rule"] == "transfer"
    assert released["checked_label"] == emitted["assigned_label"]
    assert Enum.all?([deny, released, admit], &(&1["call_id"] == emitted["decision_id"]))
    assert map_size(GoStand.current()["consumed"]) == 1
    assert Go.pending(go_dir) == []
  end

  test "Replay derselben Freigabe scheitert: Nonce verbraucht", %{env: env, go_dir: go_dir} do
    test = self()

    person(go_dir, fn request ->
      release = Go.release_for(request, System.os_time(:second))
      send(test, {:release, release})
      release
    end)

    assert ConnectorGate.call(env, "web_search", @params)["decision"] == "permit"
    assert_received {:release, release}
    assert_received :web_called

    person(go_dir, fn _request -> release end)
    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "deny"
    assert "release_nonce_consumed" in Enum.map(response["remedies"], & &1["code"])
    refute_received :web_called
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
    assert outcomes(env) == ["not_admitted", "go_refused"]
  end

  test "keine Antwort bis zum Ablauf: deny, kein stiller Fallback", %{env: env} do
    env = put_in(env.go.timeout_ms, 300)

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "deny"
    assert response["go"] == "keine Antwort"
    assert response["hinweis"] == KomkiMediator.Hinweis.text(:go_timeout)
    refute_received :web_called
    assert outcomes(env) == ["not_admitted", "go_timeout"]
    assert Go.pending(env.go.dir) == []
  end

  test "Frische-Fenster ueberschritten: deny release_expired", %{env: env, go_dir: go_dir} do
    person(go_dir, fn request -> Go.release_for(request, System.os_time(:second) - 3_600) end)

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "deny"
    assert "release_expired" in Enum.map(response["remedies"], & &1["code"])
    refute_received :web_called
  end

  test "Freigabe fuer einen anderen Call: deny release_call_mismatch", %{
    env: env,
    go_dir: go_dir
  } do
    person(go_dir, fn request ->
      Go.release_for(
        %{request | "call_hash" => String.duplicate("0", 64)},
        System.os_time(:second)
      )
    end)

    response = ConnectorGate.call(env, "web_search", @params)

    assert "release_call_mismatch" in Enum.map(response["remedies"], & &1["code"])
    refute_received :web_called
  end

  test "Commit scheitert (Stand nicht schreibbar): keine Wirkung", %{env: env, go_dir: go_dir} do
    # stand.json als Verzeichnis: das Umbenennen beim Persistieren scheitert
    File.mkdir_p!(Path.join(GoStand.path(go_dir), "blockiert"))
    person(go_dir, true)

    response = ConnectorGate.call(env, "web_search", @params)

    assert response["decision"] == "error"
    assert response["detail"] =~ "GO nicht committet"
    refute_received :web_called
    assert map_size(GoStand.current()["consumed"]) == 0
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
end
