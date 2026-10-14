defmodule KomkiMediator.TemplatesTest do
  use ExUnit.Case, async: true

  alias KomkiMediator.{Gamma, Room, Templates}
  alias KomkiPolicy.{Derive, JSON}

  setup do
    %{base: KomkiMediator.TestHelpers.provisioned_base()}
  end

  # Idempotenz: ein redigierter Raum wird nie ueberschrieben.
  test "provision! bleibt beim zweiten Aufruf byte- und mtime-stabil", %{base: base} do
    registry_path = Path.join([base, "mediator", "registry.json"])
    room_path = Path.join([base, "mediator", "room.json"])

    {:ok, stat_before} = File.stat(registry_path)
    room_before = File.read!(room_path)

    assert Templates.provision!(base) == :already_provisioned

    {:ok, stat_after} = File.stat(registry_path)
    assert File.read!(room_path) == room_before
    assert stat_after.mtime == stat_before.mtime
  end

  test "die drei Dokumente liegen mit deutschem Inhalt", %{base: base} do
    documents_dir = Path.join([base, "mediator", "documents"])

    for document_id <- ["doc-oeffentlich", "doc-vertraulich", "doc-pending-freigabe"] do
      path = Path.join(documents_dir, document_id <> ".md")
      content = File.read!(path)

      assert String.starts_with?(content, "# ")
      assert Templates.document_content(document_id) == content
    end
  end

  test "registry.json und room.json sind kanonische JSON-Bytes", %{base: base} do
    mediator_dir = Path.join(base, "mediator")

    for file <- ["registry.json", "room.json"] do
      {:ok, raw} = File.read(Path.join(mediator_dir, file))
      {:ok, term} = JSON.parse(raw)

      assert JSON.canonical(term) == raw
    end
  end

  # Der Default-Raum muss die drei Entscheidungspfade tatsaechlich
  # produzieren — geprueft durch echten Lauf der komki_policy-Ableitung.
  test "Raum fuehrt permit (doc-oeffentlich, mediator-ping) her", %{base: base} do
    decisions = room_decisions(base)

    assert decisions["doc-oeffentlich"]["decision"] == "permit"
    assert decisions["mediator-ping"]["decision"] == "permit"
  end

  test "Raum fuehrt deny mit binding_condition_false (doc-vertraulich) her", %{base: base} do
    decisions = room_decisions(base)

    assert decisions["doc-vertraulich"]["decision"] == "deny"

    assert List.first(decisions["doc-vertraulich"]["blockers"]) == %{
             "code" => "binding_condition_false",
             "binding" => "doc-vertraulich@1",
             "condition" => "purpose"
           }
  end

  test "Raum fuehrt indeterminate mit missing_fact (doc-pending-freigabe) her", %{base: base} do
    decisions = room_decisions(base)

    assert decisions["doc-pending-freigabe"]["decision"] == "indeterminate"

    assert List.first(decisions["doc-pending-freigabe"]["missing_evidence"]) == %{
             "code" => "missing_fact",
             "fact" => "vertraulich_freigabe",
             "binding" => "doc-pending-freigabe@1"
           }
  end

  defp room_decisions(base) do
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))
    {:ok, room} = Room.load(Path.join(base, "mediator"))

    object_ids = ["mediator-ping", "doc-oeffentlich", "doc-vertraulich", "doc-pending-freigabe"]

    Map.new(object_ids, fn object_id ->
      params = if object_id == "mediator-ping", do: %{}, else: %{"document_id" => object_id}
      tool = if object_id == "mediator-ping", do: "ping", else: "admit_document"

      {:ok, object} = Room.object_for_call(room, tool, params)
      snapshot = Room.snapshot_for(room, gamma, object, "aaaabbbbcccc")

      intent = %{
        "schema" => "komki-intent/1",
        "intent_id" => "intent-templates-orakel",
        "operation" => "admit",
        "object" => object.object_id <> "@" <> object.version,
        "workspace" => room.workspace_id
      }

      {:ok, decision} = Derive.decide(gamma.compiled, snapshot, intent)
      {object_id, decision}
    end)
  end
end
