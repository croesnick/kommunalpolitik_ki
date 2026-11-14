defmodule KomkiMediator.StandLesenTest do
  # Ticket #419, Szene 12: den Stand lesen. rp_stand_lesen is admit-only
  # (connector contract §6.4): the engine decides only whether
  # ratsprojekte@1 may enter the room, before the connector reads the file,
  # and there is no GO on this path. Gegenproben 12.0 bis 12.2, 12.8 und
  # 12.9 run as scenes through the ConnectorGate; 12.10 and 12.11 have no
  # connector yet and run as engine cases against the Γ seed. 12.3 to 12.7
  # belong to the hub (#438).
  use ExUnit.Case, async: false

  alias KomkiMediator.{
    ConnectorGate,
    FakeConnector,
    Go,
    GoStand,
    Hinweis,
    Room,
    Templates,
    TestHelpers
  }

  alias KomkiMediator.Room.Object
  alias KomkiPolicy.Derive

  @stand ~s({"projekte": [{"titel": "Radweg Bahnhofstraße", "stand": "Antrag in Vorbereitung"}]})

  setup do
    base = TestHelpers.provisioned_base()
    dir = FakeConnector.short_dir()
    go_dir = Path.join(base, "go")
    on_exit(fn -> File.rm_rf!(dir) end)

    File.mkdir_p!(go_dir)
    File.touch!(Go.listener_path(go_dir))
    TestHelpers.stop_named(GoStand)
    start_supervised!({GoStand, %{dir: go_dir, scope: "go-stand-lesen"}})

    env =
      TestHelpers.restart_env(base, %{connectors_dir: dir, go: %{dir: go_dir, timeout_ms: 2_000}})

    %{env: env, go_dir: go_dir}
  end

  defp hub(env) do
    pid =
      FakeConnector.start("ratsprojekte", env.connectors_dir, env.journal_path, fn
        "stand_lesen", _params, _context ->
          {:ok, %{"stand" => @stand}}

        "fakt_vorschlagen", _params, context ->
          {:ok, %{"status" => "vorgeschlagen", "labels" => context["assigned_label"]}}
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)
  end

  defp web(env) do
    pid =
      FakeConnector.start("web", env.connectors_dir, env.journal_path, fn _op, _params, _ctx ->
        {:ok, %{"results" => [], "abrufdatum" => "2026-11-12"}}
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

  defp projektraum(env),
    do: put_in(env.room.workspace_bindings, Templates.projektraum_bindings())

  defp journal(env),
    do: Enum.map(TestHelpers.journal_records(env.journal_path), &{&1["rule"], &1["outcome"]})

  @tag :szenario_12
  test "12.0 Normalfall: im Projektraum kommt der Stand in den Raum, ohne GO und ohne Anfrage", %{
    env: env
  } do
    hub(env)

    response = ConnectorGate.call(projektraum(env), "rp_stand_lesen", %{})

    assert response["decision"] == "permit"
    assert response["stand"] == @stand
    assert response["object_id"] == "ratsprojekte-stand"
    assert response["labels"] == Templates.projektraum_bindings()

    # The connector got the constant request: no parameters, no context.
    assert_received {:connector_called, "ratsprojekte", "stand_lesen", params, context, records}
    assert params == %{}
    assert context == %{}

    # Admit only: the permit was in the journal before the connector ran
    # (record before effect), then the admission. No emit, no transfer.
    assert records == 1
    assert journal(env) == [{"admit", "executing"}, {"admit", "admitted"}]

    [executing, admitted] = TestHelpers.journal_records(env.journal_path)
    assert executing["checked_label"] == Templates.projektraum_bindings()
    assert admitted["payload_hash"] == response["payload_hash"]

    # Nobody was asked.
    assert Go.pending(env.go.dir) == []
  end

  @tag :szenario_12
  test "12.1 im Rechercheraum erreicht der Stand den Agenten nicht, der Connector wird nie gerufen",
       %{env: env} do
    # Without any connector: the denial comes before the file is touched.
    without = ConnectorGate.call(env, "rp_stand_lesen", %{})

    hub(env)
    with_hub = ConnectorGate.call(env, "rp_stand_lesen", %{})

    for response <- [without, with_hub] do
      assert response["decision"] == "deny"
      refute Map.has_key?(response, "stand")
      refute Map.has_key?(response, "go")
    end

    # The answer does not depend on whether the stand exists.
    assert Map.drop(without, ["decision_id", "payload_hash"]) ==
             Map.drop(with_hub, ["decision_id", "payload_hash"])

    refute_received {:connector_called, _, _, _, _, _}
    assert Go.pending(env.go.dir) == []
    assert journal(env) == [{"admit", "not_admitted"}, {"admit", "not_admitted"}]

    [pdr | _] = TestHelpers.journal_records(env.journal_path)
    assert "label_not_included" in Enum.map(pdr["remedies"], & &1["code"])
  end

  @tag :szenario_12
  test "12.1 die Websuche bleibt im Rechercheraum frei", %{env: env} do
    web(env)

    response = ConnectorGate.call(env, "web_search", %{"query" => "Radweg Bahnhofstraße"})

    assert response["decision"] == "permit"
    assert Go.pending(env.go.dir) == []
  end

  @tag :szenario_12
  test "12.2 Websuche im Projektraum: Miriam sieht den genauen Suchtext, ohne GO geht nichts raus",
       %{env: env, go_dir: go_dir} do
    web(env)
    person(go_dir, false)

    response =
      ConnectorGate.call(projektraum(env), "web_search", %{"query" => "Radweg Bahnhofstraße"})

    assert response["decision"] == "deny"
    assert response["go"] == "abgelehnt"
    refute_received {:connector_called, "web", _, _, _, _}

    assert_received {:request, request}
    assert request["operation"] == "transfer"
    assert request["tool"] == "web_search"
    assert request["params"]["query"] == "Radweg Bahnhofstraße"
    assert "recipient_not_allowed" in request["blockers"]
  end

  @tag :szenario_12
  test "12.2 mit GO geht genau diese Suche raus", %{env: env, go_dir: go_dir} do
    web(env)
    person(go_dir, true)

    response =
      ConnectorGate.call(projektraum(env), "web_search", %{"query" => "Radweg Bahnhofstraße"})

    assert response["decision"] == "permit"

    assert_received {:connector_called, "web", "search", %{"query" => "Radweg Bahnhofstraße"}, _,
                     _}
  end

  @tag :szenario_12
  test "12.8 Fakt aus dem Projektraum vorschlagen: erlaubt mit GO wie 11.0", %{
    env: env,
    go_dir: go_dir
  } do
    hub(env)
    person(go_dir, true)

    params = %{
      "titel" => "Neue Zählung",
      "teile" => [%{"aussage" => "Die Zählung ergab 420 Räder am Tag.", "quelle" => "antwort-1"}]
    }

    response = ConnectorGate.call(projektraum(env), "rp_fakt_vorschlagen", params)

    assert response["decision"] == "permit"
    assert response["status"] == "vorgeschlagen"

    assert_received {:request, request}
    refute Map.has_key?(request, "kind")
    assert request["operation"] == "store"
    assert request["blockers"] == ["missing_operation_rule"]

    assert_received {:connector_called, "ratsprojekte", "fakt_vorschlagen", _, context, _}
    assert context["assigned_label"] == Templates.projektraum_bindings()
  end

  @tag :szenario_12
  test "12.9 Stand und Nichtöffentliches in einem Raum: nichts geht in den Hub, kein Fenster dafür",
       %{env: env, go_dir: go_dir} do
    hub(env)
    # ratsarbeit@1 has no emit rule, so creating the request asks for an
    # emit GO first (as in Gegenprobe 13.1); the store into the hub then
    # gets no window and nothing is transmitted.
    person(go_dir, true)

    env =
      put_in(
        env.room.workspace_bindings,
        Enum.sort(["ratsarbeit@1" | Templates.projektraum_bindings()])
      )

    params = %{
      "titel" => "Grunderwerb",
      "teile" => [
        %{"aussage" => "Die Stadt verhandelt über Fläche Nord.", "quelle" => "antwort-1"}
      ]
    }

    response = ConnectorGate.call(env, "rp_fakt_vorschlagen", params)

    assert response["decision"] == "deny"
    assert response["hinweis"] == Hinweis.text(:not_transmitted)
    assert "vorstand" in response["recipients_outside"]

    assert_received {:request, %{"operation" => "emit"}}
    assert Go.pending(go_dir) == []
    refute_received {:connector_called, _, _, _, _, _}
  end

  # The criterion of §6.4 is checked on every call: if the operation's
  # environment had an observer outside the room's, the request would be
  # an output. Then there is no decision and no connector call.
  test "Kriterium verletzt: Beobachter ausserhalb des Raums, kein Aufruf", %{env: env} do
    hub(env)

    env =
      env
      |> with_environment("nur-person@1", ["nutzende-person"])
      |> projektraum()
      |> put_in([Access.key(:room), Access.key(:environment)], "nur-person@1")

    response = ConnectorGate.call(env, "rp_stand_lesen", %{})

    assert response["decision"] == "error"
    assert response["rule"] == "admit"
    assert response["detail"] =~ "pi-agent"
    refute_received {:connector_called, _, _, _, _, _}
    assert journal(env) == [{"admit", "error"}]
  end

  # The object's labels come from the manifest only: an object of the same
  # name in room.json changes nothing.
  test "room.json kann die Labels des Stands nicht ersetzen", %{env: env} do
    hub(env)

    env =
      put_in(env.room.objects["ratsprojekte-stand"], %{
        "type" => "document",
        "version" => "v1",
        "labels" => ["doc-oeffentlich@2"]
      })

    assert ConnectorGate.call(env, "rp_stand_lesen", %{})["decision"] == "deny"
    refute_received {:connector_called, _, _, _, _, _}
  end

  # ---------------------------------------------------------------------
  # 12.10 and 12.11: engine cases. Neither the Fraktionsordner nor the
  # Ortsverband has a connector yet, so the test adds their environments to
  # a copy of the Γ seed and asks the engine directly what a store from
  # the Projektraum would yield.
  # ---------------------------------------------------------------------

  @tag :szenario_12
  test "12.10 aus dem Projektraum in den Fraktionsordner: Empfängertest besteht, Schreiben nur mit GO",
       %{env: env} do
    env =
      with_environment(env, "fraktionsordner@1", [
        "fraktion",
        "nextcloud-betreiber",
        "nutzende-person",
        "pi-agent"
      ])

    {:ok, decision} = store_from_projektraum(env, "fraktionsordner@1")

    assert decision["decision"] == "deny"
    codes = Enum.map(decision["remedies"], & &1["code"])
    assert "missing_operation_rule" in codes
    refute "recipient_not_allowed" in codes
    assert is_binary(Go.offered(decision["remedies"]))
  end

  @tag :szenario_12
  test "12.11 Bericht an den Ortsverband: abgelehnt, kein GO und keine Lockerung", %{env: env} do
    env =
      with_environment(env, "ortsverband-mail@1", [
        "mail-provider",
        "nutzende-person",
        "ortsverband",
        "pi-agent"
      ])

    {:ok, decision} = store_from_projektraum(env, "ortsverband-mail@1")

    assert decision["decision"] == "deny"

    outside =
      Enum.find_value(
        decision["remedies"],
        &(&1["code"] == "recipient_not_allowed" && &1["recipients_outside"])
      )

    assert outside == ["mail-provider", "ortsverband"]
    assert Go.offered(decision["remedies"]) == nil
    assert Go.offered_offenlegung(decision["remedies"]) == nil
    assert Hinweis.not_transmitted?("store", decision["remedies"])
  end

  # Γ for these tests only: one more environment, its new observers added.
  defp with_environment(env, id, observers) do
    term =
      env.gamma.term
      |> Map.update!("observers", &Enum.sort(Enum.uniq(&1 ++ observers)))
      |> put_in(["environments", id], %{"observers" => observers})

    {:ok, compiled} = KomkiPolicy.Registry.compile(term)
    %{env | gamma: %{env.gamma | term: term, compiled: compiled}}
  end

  # The store decision the ConnectorGate would ask after emit: the output
  # carries λ(y) = B_W of the Projektraum, the snapshot's environment is
  # the target.
  defp store_from_projektraum(env, environment) do
    env = projektraum(env)
    digest = "sha256:" <> String.duplicate("ab", 32)

    object = %Object{
      object_id: "out-abababababab",
      version: "v1",
      labels: env.room.workspace_bindings
    }

    snapshot =
      Room.connector_snapshot(env.room, env.gamma, %{
        snapshot_id: "snap-store-abababababab",
        environment: environment,
        object: object,
        facts:
          Map.put(env.room.facts, "output_content_digest", %{
            "value" => digest,
            "source" => "komki-mediator",
            "source_kind" => "technical"
          })
      })

    intent = %{
      "schema" => "komki-intent/1",
      "intent_id" => "intent-store-abababababab",
      "operation" => "store",
      "object" => "out-abababababab@v1",
      "workspace" => env.room.workspace_id
    }

    Derive.decide(env.gamma.compiled, snapshot, intent)
  end
end
