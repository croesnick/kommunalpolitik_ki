defmodule KomkiMediator.RemediesTest do
  @moduledoc """
  Single-Sourcing des Remedy-Katalogs (#115): der Vermittler haelt keine
  eigene Abbildung Blocker/Belege -> Fortsetzung. Der Katalog entsteht
  allein in der Engine (`KomkiPolicy.Remedies`, CONTRACT § 2.8) und reist
  in der Entscheidung. Diese Tests pinnen, dass die Vermittler-Antwort
  exakt den Engine-Katalog traegt — durchgerechnet gegen das Engine-Modul
  selbst, nicht gegen eine im Test nachgebaute Form.
  """

  use ExUnit.Case, async: false

  alias KomkiMediator.{Gate, Room, TestHelpers}
  alias KomkiPolicy.{Calculus, Derive, Remedies}

  setup do
    base = TestHelpers.provisioned_base()
    env_map = TestHelpers.restart_env(base)

    %{env: env_map, gamma: env_map.gamma, room: env_map.room}
  end

  # -----------------------------------------------------------------------
  # Passthrough: Antwort-Katalog == Engine-Katalog (byte-gleich)
  # -----------------------------------------------------------------------

  test "deny: Antwort-Katalog ist byte-gleich dem Katalog aus KomkiPolicy.Remedies", %{
    env: env,
    gamma: gamma
  } do
    env = own_room(env, "doc-vertraulich")
    room = env.room

    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-vertraulich"},
        TestHelpers.admit_executor(room, "doc-vertraulich")
      )

    assert response["decision"] == "deny"

    {:ok, decision} = derive_decision(gamma, room, "doc-vertraulich")

    expected =
      Remedies.catalog(
        gamma.compiled,
        catalog_ctx(gamma, room, "doc-vertraulich"),
        :admit,
        decision["blockers"]
      )

    # Drei Mal derselbe Katalog: Engine-Entscheidung, Engine-Modul
    # direkt gerechnet, Vermittler-Antwort.
    assert response["remedies"] == decision["remedies"]
    assert response["remedies"] == expected
  end

  test "indeterminate: Antwort-Katalog ist byte-gleich dem Katalog aus KomkiPolicy.Remedies", %{
    env: env,
    gamma: gamma
  } do
    env = own_room(env, "doc-pending-freigabe")
    room = env.room

    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-pending-freigabe"},
        TestHelpers.admit_executor(room, "doc-pending-freigabe")
      )

    assert response["decision"] == "indeterminate"

    {:ok, decision} = derive_decision(gamma, room, "doc-pending-freigabe")

    expected =
      Remedies.catalog(
        gamma.compiled,
        catalog_ctx(gamma, room, "doc-pending-freigabe"),
        :admit,
        decision["missing_evidence"]
      )

    assert response["remedies"] == decision["remedies"]
    assert response["remedies"] == expected
  end

  # -----------------------------------------------------------------------
  # Normative Ordnung (§ 2.8): nicht-verletzende Fortsetzungen VOR
  # GO-Einträgen; admit kennt keine aktionsfreigabe
  # -----------------------------------------------------------------------

  test "Ordnung im Katalog: fakt_nachreichen VOR neuer_raum, kein GO am admit-Pfad", %{
    env: env
  } do
    env = own_room(env, "doc-vertraulich")

    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-vertraulich"},
        fn -> {:ok, %{"content" => "egal"}} end
      )

    [entry] = response["remedies"]

    assert Enum.map(entry["transitions"], & &1["type"]) == [
             "fakt_nachreichen",
             "neuer_raum"
           ]

    assert Enum.all?(response["remedies"], fn remedy ->
             not Enum.any?(remedy["transitions"], &(&1["type"] == "aktionsfreigabe"))
           end)
  end

  test "indeterminate kennt kein aktionsfreigabe: ein GO stellt keine Belege her", %{
    env: env
  } do
    env = own_room(env, "doc-pending-freigabe")

    response =
      Gate.call(
        env,
        "admit_document",
        %{"document_id" => "doc-pending-freigabe"},
        fn -> {:ok, %{"content" => "egal"}} end
      )

    [entry] = response["remedies"]

    assert Enum.map(entry["transitions"], & &1["type"]) == [
             "fakt_nachreichen",
             "neuer_raum"
           ]
  end

  # -----------------------------------------------------------------------
  # Relaxationsbefugnisse bleiben Γ-L1-Metadaten (R.2.2) aus dem rohen
  # Registry-Term — kein Bestandteil des Engine-Katalogs
  # -----------------------------------------------------------------------

  test "Relaxationsbefugnisse kommen aus dem rohen Registry-Term, je benannter Bindung", %{
    env: env,
    gamma: gamma
  } do
    # Seit #208 kommt Γ aus dem Label-Store, der Lockerungsbefugnisse bis
    # #109 als [] exportiert (fail-closed).
    assert gamma.term["bindings"]["doc-pending-freigabe@1"]["relaxation_authorities"] == []

    # Die kompilierte Form traegt sie bewusst nicht — der Katalog der
    # Engine kann sie folglich auch nicht tragen.
    refute Map.has_key?(
             gamma.compiled.bindings["doc-pending-freigabe@1"],
             "relaxation_authorities"
           )

    pending =
      Gate.call(
        own_room(env, "doc-pending-freigabe"),
        "admit_document",
        %{"document_id" => "doc-pending-freigabe"},
        fn -> {:ok, %{"content" => "egal"}} end
      )

    vertraulich =
      Gate.call(
        own_room(env, "doc-vertraulich"),
        "admit_document",
        %{"document_id" => "doc-vertraulich"},
        fn -> {:ok, %{"content" => "egal"}} end
      )

    assert pending["relaxation_authorities"] == []
    assert vertraulich["relaxation_authorities"] == []
  end

  # -----------------------------------------------------------------------
  # Helfer: Entscheidung und Katalog-Kontext so wie Gate und Derive sie
  # bilden (reine Funktion der Entscheidungslage, § 2.8)
  # -----------------------------------------------------------------------

  # Raum, dessen B_W genau die Labels des Dokuments sind: so zeigt die
  # Engine den Blocker der Dokument-Bindung selbst (seit #213 entscheidet
  # admit_document gegen B_W).
  defp own_room(env, document_id) do
    put_in(env.room.workspace_bindings, env.room.objects[document_id]["labels"])
  end

  defp derive_decision(gamma, room, document_id) do
    {:ok, object} = Room.object_for_call(room, "admit_document", %{"document_id" => document_id})
    snapshot = Room.snapshot_for(room, gamma, object, "remediestest", room.workspace_bindings)
    intent = intent(room, document_id)
    Derive.decide(gamma.compiled, snapshot, intent)
  end

  defp catalog_ctx(gamma, room, document_id) do
    {:ok, object} = Room.object_for_call(room, "admit_document", %{"document_id" => document_id})

    %{
      rule: :admit,
      object_labels: object.labels,
      checked: room.workspace_bindings,
      rho: Calculus.actual_recipients(gamma.compiled, room.environment),
      object_ref: object.object_id <> "@" <> object.version,
      call_hash: nil
    }
  end

  defp intent(room, document_id) do
    %{
      "schema" => "komki-intent/1",
      "intent_id" => "intent-remedies-test",
      "operation" => "admit",
      "object" => document_id <> "@v1",
      "workspace" => room.workspace_id
    }
  end
end
