defmodule KomkiMediator.GoEssenzTest do
  # Ticket #423, Szene 13: gegengelesene Essenz aus dem Fraktionsraum in
  # den ratsprojekte-Hub — die Lockerung mit Offenlegungsfreigabe. Die
  # Gegenproben 13.0 bis 13.4 des Referenzszenarios laufen hier als Tests
  # (13.5 und 13.6 deckt go_store_test.exs beziehungsweise der Hub).
  use ExUnit.Case, async: false

  alias KomkiMediator.{ConnectorGate, FakeConnector, Go, GoStand, Hinweis, Templates, TestHelpers}

  @teile [
    %{
      "aussage" => "Die Fraktion favourisiert die Fuehrung entlang der Bahntrasse.",
      "quelle" => "antwort-trasse"
    },
    %{
      "aussage" => "Der Antragsentwurf nennt eine Beteiligung der Anwohner.",
      "quelle" => "antwort-entwurf"
    }
  ]

  @params %{
    "titel" => "Essenz aus dem Fraktionsraum",
    "teile" => @teile,
    "projekt_hinweis" => "radweg-bahnhofstrasse"
  }

  setup do
    base = TestHelpers.provisioned_base()
    dir = FakeConnector.short_dir()
    go_dir = Path.join(base, "go")
    on_exit(fn -> File.rm_rf!(dir) end)

    File.mkdir_p!(go_dir)
    File.touch(Go.listener_path(go_dir))
    TestHelpers.stop_named(GoStand)
    start_supervised!({GoStand, %{dir: go_dir, scope: "go-essenz"}})

    env =
      TestHelpers.restart_env(base, %{connectors_dir: dir, go: %{dir: go_dir, timeout_ms: 2_000}})

    hub =
      FakeConnector.start("ratsprojekte", dir, env.journal_path, fn _op, _params, context ->
        {:ok, %{"status" => "vorgeschlagen", "labels" => context["assigned_label"]}}
      end)

    on_exit(fn -> Process.exit(hub, :kill) end)

    %{env: env, go_dir: go_dir}
  end

  # Die nutzende Person im Test: wartet auf die Anfrage und antwortet.
  # Eine Offenlegungs-Anfrage wird mit Teileauswahl (leer = alle) und GO
  # beantwortet; eine gewoehnliche Aktionsfreigabe (etwa das emit-GO im
  # Raum mit ratsarbeit@1) mit j/n.
  defp person(go_dir, selection \\ [], go? \\ true) do
    test = self()

    spawn_link(fn ->
      request = wait_for_request(go_dir, 100)
      send(test, {:request, request})
      answer_request(go_dir, request, selection, go?)
    end)
  end

  defp answer_request(go_dir, %{"kind" => "offenlegungsfreigabe"} = request, selection, go?) do
    ids =
      if selection == [] do
        Enum.map(request["teile"], & &1["id"])
      else
        request["teile"] |> Enum.filter(&(&1["nummer"] in selection)) |> Enum.map(& &1["id"])
      end

    if go?,
      do: Go.answer_selection(go_dir, request, ids),
      else: Go.answer_selection(go_dir, request, [])
  end

  defp answer_request(go_dir, request, _selection, go?),
    do: Go.answer(go_dir, request, go?)

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

  defp fraktion(env), do: put_in(env.room.workspace_bindings, Templates.fraktion_bindings())

  defp fraktion_mit(env, binding) do
    put_in(
      env.room.workspace_bindings,
      Enum.sort(Enum.uniq(Templates.fraktion_bindings() ++ [binding]))
    )
  end

  defp journal(env),
    do: Enum.map(TestHelpers.journal_records(env.journal_path), &{&1["rule"], &1["outcome"]})

  @tag :szenario_13
  test "13.0 Normalfall: Fenster mit Text, Ausgabeart und allen Empfaengern, danach wie 11.0", %{
    env: env,
    go_dir: go_dir
  } do
    person(go_dir)

    response = ConnectorGate.call(fraktion(env), "rp_fakt_vorschlagen", @params)

    # Quittung wie Szene 11: immer dieselbe Form, nichts aus dem Hub.
    assert response["decision"] == "permit"
    assert response["rule"] == "admit"
    assert response["status"] == "vorgeschlagen"
    assert response["labels"] == Enum.sort(Templates.fraktion_bindings())

    assert_received {:connector_called, "ratsprojekte", "fakt_vorschlagen", params, context, _}
    assert length(params["teile"]) == 2
    assert context["assigned_label"] == Enum.sort(Templates.fraktion_bindings())

    # Das Fenster zeigt den genauen Text (params), die Ausgabeart, das
    # Ziellabel, alle Empfaenger des Ziels und die Teile mit Kennung.
    assert_received {:request, request}
    assert request["kind"] == "offenlegungsfreigabe"
    assert request["operation"] == "store"
    assert request["tool"] == "rp_fakt_vorschlagen"
    assert request["params"] == @params
    assert request["ausgabeart"] == "ratsprojekte-essenz"
    assert request["ziellabel"] == ["ratsprojekte@1"]

    assert request["empfaenger"] == [
             "fraktion",
             "nextcloud-betreiber",
             "nutzende-person",
             "pi-agent",
             "sicherung",
             "vorstand"
           ]

    assert Enum.map(request["teile"], & &1["id"]) == ["teil-1", "teil-2"]
    assert "recipient_not_allowed" in request["blockers"]

    # Journal: emit und store werden entschieden, das GO committet vor
    # der Wirkung; der released-Datensatz haelt die Offenlegung fest.
    assert journal(env) == [
             {"emit", "permitted"},
             {"store", "not_admitted"},
             {"store", "released"},
             {"emit", "emitted"},
             {"admit", "admitted"}
           ]

    released = Enum.at(TestHelpers.journal_records(env.journal_path), 2)

    assert released["offenlegung"] == %{
             "ausgabeart" => "ratsprojekte-essenz",
             "ziellabel" => ["ratsprojekte@1"],
             "empfaenger" => [
               "fraktion",
               "nextcloud-betreiber",
               "nutzende-person",
               "pi-agent",
               "sicherung",
               "vorstand"
             ]
           }

    assert map_size(GoStand.current()["consumed"]) == 1
  end

  @tag :szenario_13
  test "13.0 Abwahl: ein neues Ereignis mit neuem Hash, nur die gewaehlten Teile gehen", %{
    env: env,
    go_dir: go_dir
  } do
    person(go_dir, [1])

    response = ConnectorGate.call(fraktion(env), "rp_fakt_vorschlagen", @params)

    assert response["decision"] == "permit"
    assert response["status"] == "vorgeschlagen"

    assert_received {:connector_called, "ratsprojekte", "fakt_vorschlagen", params, _context, _}
    assert length(params["teile"]) == 1
    assert hd(params["teile"]) == Enum.at(@teile, 0)

    # Die Abwahl leitet den reduzierten Call neu ab (emit und store erneut,
    # beide journalt) und die Freigabe bindet das neue Ereignis.
    assert journal(env) == [
             {"emit", "permitted"},
             {"store", "not_admitted"},
             {"emit", "permitted"},
             {"store", "not_admitted"},
             {"store", "released"},
             {"emit", "emitted"},
             {"admit", "admitted"}
           ]

    assert_received {:request, request}
    records = TestHelpers.journal_records(env.journal_path)

    # Der Vorbeleg bindet die tatsaechlich gesendeten (reduzierten)
    # Parameter; die Freigabe wurde ueber den Hash des REDUZIERTEN Calls
    # entschieden — eine Abwahl ist ein neues Ereignis mit neuem Hash
    # (R.6.2), die Anfrage gilt dem vollen Call.
    vorbeleg = Enum.find(records, &(&1["outcome"] == "emitted"))
    assert vorbeleg["payload_hash"] == vorbeleg_hash_fuer(params)

    released = Enum.find(records, &(&1["outcome"] == "released"))
    assert released["intent_hash"] == reduced_intent_hash(params)
    refute released["intent_hash"] == request["content_digest"]
  end

  @tag :szenario_13
  test "13.0 GO verweigert: nichts verlaesst den Raum, der Hub bleibt unberuehrt", %{
    env: env,
    go_dir: go_dir
  } do
    person(go_dir, [], false)

    response = ConnectorGate.call(fraktion(env), "rp_fakt_vorschlagen", @params)

    assert response["decision"] == "deny"
    assert response["go"] == "abgelehnt"
    assert response["hinweis"] == Hinweis.text(:go_refused)
    refute_received {:connector_called, _, _, _, _, _}

    assert journal(env) == [
             {"emit", "permitted"},
             {"store", "not_admitted"},
             {"store", "go_refused"}
           ]
  end

  @tag :szenario_13
  test "niemand hoert zu: Katalog bleibt sichtbar (kein stiller Fallback), kein Fenster", %{
    env: env,
    go_dir: go_dir
  } do
    File.rm(Go.listener_path(go_dir))

    response = ConnectorGate.call(fraktion(env), "rp_fakt_vorschlagen", @params)

    # Kein Fenster: niemand wurde gefragt. Die Ablehnung nennt die
    # Offenlegungsfreigabe als Fortsetzung — sie kann niemand vom Agenten
    # erteilt werden, aber der Weg steht im Katalog wie bei jeder
    # Aktionsfreigabe auch.
    assert response["decision"] == "deny"
    assert Go.pending(go_dir) == []
    refute_received {:connector_called, _, _, _, _, _}

    transition =
      response["remedies"]
      |> Enum.flat_map(& &1["transitions"])
      |> Enum.find(&(&1["type"] == "offenlegungsfreigabe"))

    assert transition["ausgabeart"] == "ratsprojekte-essenz"
    assert transition["ziellabel"] == ["ratsprojekte@1"]
    # Der Weg von Hand bleibt die Grenz-Aussage, nicht die Offenlegung:
    assert response["hinweis"] == Hinweis.text(:deny)
  end

  @tag :szenario_13
  test "13.1 eine Bindung ohne Befugnis (ratsarbeit): kein Offenlegungsfenster, nichts uebertragen",
       %{
         env: env,
         go_dir: go_dir
       } do
    # ratsarbeit@1 hat keine emit-Regel: Das Erzeugen braucht ein GO
    # (Szene 3, interne Uebernahme). Die Person gibt es — und der Store
    # in den Hub bleibt fensterlos (Gegenprobe 13.1/13.5).
    person(go_dir)
    env = fraktion_mit(env, "ratsarbeit@1")

    response = ConnectorGate.call(env, "rp_fakt_vorschlagen", @params)

    assert response["decision"] == "deny"
    assert response["hinweis"] == Hinweis.text(:not_transmitted)

    assert response["recipients_outside"] == [
             "fraktion",
             "nextcloud-betreiber",
             "sicherung",
             "vorstand"
           ]

    # Keine Lockerungsstellen, kein Katalog, keine Inhalte (13.5):
    assert Enum.sort(Map.keys(response)) ==
             ~w(decision decision_id hinweis recipients_outside registry_id rule)

    # Niemand wurde nach der Offenlegung gefragt: Nach dem emit-GO ist
    # keine weitere Anfrage offen, der Connector wurde nie gerufen.
    assert Go.pending(go_dir) == []
    refute_received {:connector_called, _, _, _, _, _}
  end

  @tag :szenario_13
  test "13.3 Abo-Artikel im Raum: nichts fuer ratsprojekte, nur Kurzzitat waere moeglich", %{
    env: env,
    go_dir: go_dir
  } do
    person(go_dir)
    env = fraktion_mit(env, "abo-az@1")

    response = ConnectorGate.call(env, "rp_fakt_vorschlagen", @params)

    assert response["decision"] == "deny"
    assert response["hinweis"] == Hinweis.text(:not_transmitted)

    assert response["recipients_outside"] == [
             "fraktion",
             "nextcloud-betreiber",
             "sicherung",
             "vorstand"
           ]

    assert Go.pending(go_dir) == []
    refute_received {:connector_called, _, _, _, _, _}
  end

  @tag :szenario_13
  test "13.4 privat: true gibt es nicht — der Praecheck weist es vor jeder Entscheidung ab", %{
    env: env
  } do
    response =
      ConnectorGate.call(fraktion(env), "rp_fakt_vorschlagen", Map.put(@params, "privat", true))

    assert response["decision"] == "error"
    assert String.contains?(response["detail"], "privat")
    refute_received {:connector_called, _, _, _, _, _}
    assert journal(env) == [{"emit", "error"}]
  end

  # Der Vorbeleg bindet %{op, params, context} kanonisch (Connector-Vertrag
  # §6) — hier fuer die Reduktion nachgerechnet.
  defp vorbeleg_hash_fuer(params) do
    KomkiMediator.PDR.payload_hash(%{
      "op" => "fakt_vorschlagen",
      "params" => params,
      "context" => %{"assigned_label" => Enum.sort(Templates.fraktion_bindings())}
    })
  end

  # intent_hash des (reduzierten) Calls: sha256 ueber {tool, params}
  # kanonisch — so entscheidet der Vermittler jeden Call.
  defp reduced_intent_hash(params) do
    KomkiMediator.Hash.sha256_hex(
      KomkiPolicy.JSON.canonical(%{"tool" => "rp_fakt_vorschlagen", "params" => params})
    )
  end
end
