defmodule KomkiMediator.RoomTest do
  use ExUnit.Case, async: true

  alias KomkiMediator.{Gamma, Room}
  alias KomkiPolicy.Derive

  setup do
    base = KomkiMediator.TestHelpers.provisioned_base()
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))
    {:ok, room} = Room.load(Path.join(base, "mediator"))

    %{gamma: gamma, room: room}
  end

  test "Raum traegt Identitaet, Arbeitsraum und Umfeld", %{room: room} do
    assert room.identity == "pi-agent"
    assert room.workspace_id == "ws-komki-arbeitsraum"
    assert room.environment == "lokaler-arbeitsraum@1"
    assert room.facts["purpose"]["value"] == "offene-recherche"
  end

  test "Ping-Objekt verbindet wie unabhaengig, unbekannte Objekte bleiben strukturierter Fehler",
       %{room: room} do
    {:ok, object} = Room.object_for_call(room, "ping", %{})

    assert object.object_id == "mediator-ping"
    assert object.version == "v1"
    assert object.labels == ["mediator-ping@1"]

    assert {:error, :unknown_object, "doc-phantom"} =
             Room.object_for_call(room, "admit_document", %{"document_id" => "doc-phantom"})
  end

  test "admit_document-loeset das Objekt aus den Room-Parametern auf", %{room: room} do
    {:ok, object} =
      Room.object_for_call(room, "admit_document", %{"document_id" => "doc-oeffentlich"})

    assert object.labels == ["doc-oeffentlich@1"]
  end

  # Der gebaute Snapshot muss durch die Eingabepruefung von Derive
  # (Schema, Referenzkohärenz) ankommen.
  test "Snapshot wird von Derive.decide akzeptiert (doc-oeffentlich)", %{gamma: gamma, room: room} do
    {:ok, object} =
      Room.object_for_call(room, "admit_document", %{"document_id" => "doc-oeffentlich"})

    snapshot = Room.snapshot_for(room, gamma, object, "abc123def456")

    intent = %{
      "schema" => "komki-intent/1",
      "intent_id" => "intent-testuvwxyz",
      "operation" => "admit",
      "object" => "doc-oeffentlich@v1",
      "workspace" => room.workspace_id
    }

    assert {:ok, %{"decision" => "permit", "proof" => proof}} =
             Derive.decide(gamma.compiled, snapshot, intent)

    assert proof["checked_label"] == object.labels
  end

  test "checked_label == workspace bindings == Objekt-Labels", %{gamma: gamma, room: room} do
    {:ok, object} = Room.object_for_call(room, "ping", %{})
    snapshot = Room.snapshot_for(room, gamma, object, "abc123def456")

    assert snapshot["workspace"]["bindings"] == object.labels
    assert snapshot["object"]["labels"] == object.labels
    assert snapshot["object"]["classification"] == "classified"
  end

  test "falsches Schema faellt in einen strukturierten Schema-Fehler" do
    base = KomkiMediator.TestHelpers.provisioned_base()
    path = Path.join([base, "mediator", "room.json"])
    File.write!(path, ~S({"schema": "fremd-schema/1"}))

    assert {:error, {:room_schema, %{"expected" => "komki-mediator-room/1"}}} =
             Room.load(Path.join(base, "mediator"))
  end
end
