defmodule KomkiMediator.GoStoreTest do
  # Ticket #205: Jedes Schreiben braucht ein GO. Γ hat keine store-Regel,
  # also lehnt die Engine store ab und bietet eine Aktionsfreigabe fuer
  # genau diesen Call an. Raum recherche, vault_write_test.
  use ExUnit.Case, async: false

  alias KomkiMediator.{ConnectorGate, FakeConnector, Go, GoStand, Templates, TestHelpers}

  @params %{"title" => "Notiz", "body" => "Inhalt"}

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
      TestHelpers.restart_env(base, %{connectors_dir: dir, go: %{dir: go_dir, timeout_ms: 2_000}})

    %{env: env, go_dir: go_dir}
  end

  defp vault(env, labels_fun) do
    test = self()

    pid =
      FakeConnector.start("vault", env.connectors_dir, env.journal_path, fn op,
                                                                            _params,
                                                                            context ->
        send(test, {:written, op, context})
        {:ok, %{"note_id" => "komki-test/notiz.md", "labels" => labels_fun.(context)}}
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
  end

  defp person(go_dir, go?) do
    test = self()

    spawn_link(fn ->
      request = wait_for_request(go_dir, 100)
      send(test, {:request, request})
      Go.answer(go_dir, request, go?)
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

  defp journal(env),
    do: Enum.map(TestHelpers.journal_records(env.journal_path), &{&1["rule"], &1["outcome"]})

  test "GO erteilt: die Notiz wird geschrieben, belegt vor der Wirkung", %{
    env: env,
    go_dir: go_dir
  } do
    vault(env, & &1["assigned_label"])
    person(go_dir, true)

    response = ConnectorGate.call(env, "vault_write_test", @params)

    assert response["decision"] == "permit"
    assert response["labels"] == Templates.recherche_bindings()

    assert_received {:written, "write_test", %{"assigned_label" => assigned}}
    assert assigned == Templates.recherche_bindings()

    assert_received {:request, request}
    assert request["operation"] == "store"
    assert request["tool"] == "vault_write_test"
    assert request["params"] == @params
    assert request["blockers"] == ["missing_operation_rule"]

    # store deny -> GO commit (released) -> emit record -> execution -> admit
    assert journal(env) == [
             {"store", "not_admitted"},
             {"store", "released"},
             {"emit", "emitted"},
             {"admit", "admitted"}
           ]

    assert map_size(GoStand.current()["consumed"]) == 1
  end

  test "GO verweigert: nichts wird geschrieben", %{env: env, go_dir: go_dir} do
    vault(env, & &1["assigned_label"])
    person(go_dir, false)

    response = ConnectorGate.call(env, "vault_write_test", @params)

    assert response["decision"] == "deny"
    assert response["go"] == "abgelehnt"
    refute_received {:written, _, _}
    assert journal(env) == [{"store", "not_admitted"}, {"store", "go_refused"}]
  end

  test "niemand hoert zu (komki run): abgelehnt, nichts geschrieben, keine Anfrage", %{env: env} do
    File.rm!(Go.listener_path(env.go.dir))
    vault(env, & &1["assigned_label"])

    response = ConnectorGate.call(env, "vault_write_test", @params)

    assert response["decision"] == "deny"
    refute Map.has_key?(response, "go")
    refute_received {:written, _, _}
    assert Go.pending(env.go.dir) == []
  end

  test "mit GO: abweichende Labels in der Rueckmeldung -> redacted", %{env: env, go_dir: go_dir} do
    vault(env, fn _context -> ["vault-oeffentlich@1"] end)
    person(go_dir, true)

    response = ConnectorGate.call(env, "vault_write_test", @params)

    assert response["admitted"] == "redacted"
    assert response["verify"] == ["label_mismatch"]
  end

  test "lesende Operationen fragen nicht", %{env: env} do
    pid =
      FakeConnector.start("vault", env.connectors_dir, env.journal_path, fn _op, _p, _c ->
        {:ok, %{"results" => []}}
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)

    response = ConnectorGate.call(env, "vault_search", %{"text" => "Radweg"})

    assert response["decision"] == "permit"
    assert Go.pending(env.go.dir) == []
    refute Enum.any?(journal(env), fn {rule, _} -> rule == "store" end)
  end
end
