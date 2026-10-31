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

  # Frische Instanz: `komki up` exportiert registry.json vor dem ersten
  # Vermittler-Start (#208). room.json und Dokumente muessen trotzdem kommen.
  test "nur registry.json vorhanden (Export): room.json und Dokumente werden angelegt" do
    base = KomkiMediator.TestHelpers.tmp_base("kmtpl-")
    on_exit(fn -> File.rm_rf(base) end)

    mediator_dir = Path.join(base, "mediator")
    File.mkdir_p!(mediator_dir)
    File.write!(Path.join(mediator_dir, "registry.json"), "EXPORT")

    assert Templates.provision!(base) == :ok
    assert File.read!(Path.join(mediator_dir, "registry.json")) == "EXPORT"
    assert File.exists?(Path.join(mediator_dir, "room.json"))
    assert File.exists?(Path.join([mediator_dir, "documents", "doc-oeffentlich.md"]))
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

  # R.5.4 (#213): Im Default-Raum recherche liegen die Labels der beiden
  # anderen Dokumente ausserhalb von B_W.
  test "Raum recherche: doc-vertraulich und doc-pending-freigabe nicht in B_W", %{base: base} do
    decisions = room_decisions(base)

    for object_id <- ["doc-vertraulich", "doc-pending-freigabe"] do
      assert decisions[object_id]["decision"] == "deny"
      assert %{"code" => "label_not_included"} = hd(decisions[object_id]["blockers"])
    end
  end

  test "Raum mit doc-vertraulich@1 in B_W: deny mit binding_condition_false", %{base: base} do
    decision = room_decisions(base, ["doc-vertraulich@1"])["doc-vertraulich"]

    assert decision["decision"] == "deny"

    assert List.first(decision["blockers"]) == %{
             "code" => "binding_condition_false",
             "binding" => "doc-vertraulich@1",
             "condition" => "purpose"
           }
  end

  test "Raum mit doc-pending-freigabe@1 in B_W: indeterminate mit missing_fact", %{base: base} do
    decision = room_decisions(base, ["doc-pending-freigabe@1"])["doc-pending-freigabe"]

    assert decision["decision"] == "indeterminate"

    assert List.first(decision["missing_evidence"]) == %{
             "code" => "missing_fact",
             "fact" => "vertraulich_freigabe",
             "binding" => "doc-pending-freigabe@1"
           }
  end

  # Γ-Konventionen des Connector-Vertrags §7.
  test "Registry traegt Beobachter, Umgebungen und Connector-Bindungen nach §7" do
    registry = Templates.registry()

    assert registry["observers"] == [
             "brave-search",
             "nutzende-person",
             "pi-agent",
             "ris-betreiber"
           ]

    assert registry["fact_fields"]["output_content_digest"] == "string"

    assert registry["environments"]["web-suche@1"]["observers"] == [
             "brave-search",
             "nutzende-person",
             "pi-agent"
           ]

    assert registry["environments"]["ris-abruf@1"]["observers"] == [
             "nutzende-person",
             "pi-agent",
             "ris-betreiber"
           ]

    for binding <- [
          "doc-oeffentlich@2",
          "ris-oeffentlich@1",
          "web-oeffentlich@1",
          "vault-oeffentlich@1"
        ] do
      assert registry["bindings"][binding]["readers"] == registry["observers"]

      assert registry["bindings"][binding]["operations"] == %{
               "admit" => true,
               "emit" => true,
               "transfer" => true
             }
    end

    assert registry["bindings"]["vault-vertraulich@1"]["readers"] == [
             "nutzende-person",
             "pi-agent"
           ]

    assert {:ok, _} = KomkiPolicy.Registry.compile(registry)
  end

  # `bindings` ersetzt B_W des Default-Raums (nil: recherche).
  defp room_decisions(base, bindings \\ nil) do
    {:ok, gamma} = Gamma.load(Path.join([base, "mediator", "registry.json"]))
    {:ok, room} = Room.load(Path.join(base, "mediator"))
    room = if bindings, do: %{room | workspace_bindings: bindings}, else: room

    object_ids = ["mediator-ping", "doc-oeffentlich", "doc-vertraulich", "doc-pending-freigabe"]

    Map.new(object_ids, fn object_id ->
      params = if object_id == "mediator-ping", do: %{}, else: %{"document_id" => object_id}
      tool = if object_id == "mediator-ping", do: "ping", else: "admit_document"

      {:ok, object} = Room.object_for_call(room, tool, params)
      {:ok, checked} = Room.bindings_for(room, tool, object)
      snapshot = Room.snapshot_for(room, gamma, object, "aaaabbbbcccc", checked)

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
