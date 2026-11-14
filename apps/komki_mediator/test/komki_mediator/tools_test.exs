defmodule KomkiMediator.ToolsTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias KomkiMediator.{FakeConnector, TestHelpers, Tools}

  setup do
    base = TestHelpers.provisioned_base()
    env_map = TestHelpers.restart_env(base)
    %{base: base, gamma: env_map.gamma}
  end

  defp parse_json_body(response) do
    [%{"type" => "text", "text" => json}] = response.content
    JSON.decode!(json)
  end

  test "ping: permit + Liveness-Vertragswerkzeuge", %{gamma: gamma} do
    assert {:reply, response, _frame} = Tools.Ping.execute(%{}, Frame.new())
    refute response.isError

    body = parse_json_body(response)
    assert body["decision"] == "permit"
    assert body["object_id"] == "mediator-ping"
    assert body["tools"] == KomkiMediator.Fassung.tools()
    assert body["registry_id"] == "reg-komki-arbeitsraum"
    assert gamma.registry_id == "reg-komki-arbeitsraum"
  end

  test "admit_document doc-oeffentlich: permit mit Inhalt vom Dokument-Connector", %{base: base} do
    content = File.read!(Path.join([base, "mediator", "documents", "doc-oeffentlich.md"]))
    dir = FakeConnector.short_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    env = TestHelpers.restart_env(base, %{connectors_dir: dir})

    FakeConnector.start("documents", dir, env.journal_path, fn "read",
                                                               %{"document_id" => id},
                                                               _ ->
      {:ok, %{"document_id" => id, "content" => content}}
    end)

    assert {:reply, response, _frame} =
             Tools.AdmitDocument.execute(%{document_id: "doc-oeffentlich"}, Frame.new())

    refute response.isError

    body = parse_json_body(response)
    assert body["decision"] == "permit"
    assert body["object_id"] == "doc-oeffentlich"
    assert body["document_id"] == "doc-oeffentlich"
    assert body["content"] == content
    # Aufnahme in den Raum: die Antwort traegt B_W (R.5.4, #213)
    assert body["labels"] == KomkiMediator.Templates.recherche_bindings()
    # Erst nach dem permit, mit genau dieser document_id
    assert_received {:connector_called, "documents", "read",
                     %{"document_id" => "doc-oeffentlich"}, %{}, _records}
  end

  test "admit_document doc-vertraulich: deny, der Dokument-Connector wird nicht gerufen", %{
    base: base
  } do
    dir = FakeConnector.short_dir()
    on_exit(fn -> File.rm_rf!(dir) end)
    env = TestHelpers.restart_env(base, %{connectors_dir: dir})
    FakeConnector.start("documents", dir, env.journal_path, fn _, _, _ -> {:ok, %{}} end)

    assert {:reply, response, _frame} =
             Tools.AdmitDocument.execute(%{document_id: "doc-vertraulich"}, Frame.new())

    assert parse_json_body(response)["decision"] == "deny"
    refute_received {:connector_called, "documents", _, _, _, _}
  end

  test "admit_document doc-vertraulich: deny als Remedy-Plan, isError bleibt false", %{base: base} do
    _ = base

    assert {:reply, response, _frame} =
             Tools.AdmitDocument.execute(%{document_id: "doc-vertraulich"}, Frame.new())

    refute response.isError

    body = parse_json_body(response)
    assert body["decision"] == "deny"
    refute Map.has_key?(body, "content")

    # Der Katalog stammt aus der Engine-Entscheidung (KomkiPolicy.Remedies,
    # CONTRACT § 2.8); im Raum recherche liegt das Label nicht in B_W
    # (#213). Der Hinweis macht die Sperre zum Endpunkt (#166).
    assert [%{"code" => "label_not_included"} | _] = body["remedies"]
    assert body["hinweis"] == KomkiMediator.Hinweis.text(:deny)
  end

  test "list_documents: document_id und Labels, keine Inhalte" do
    assert {:reply, response, _frame} = Tools.ListDocuments.execute(%{}, Frame.new())
    refute response.isError

    body = parse_json_body(response)
    assert body["decision"] == "permit"

    assert body["documents"] == [
             %{"document_id" => "doc-oeffentlich", "labels" => ["doc-oeffentlich@2"]}
           ]

    refute Map.has_key?(hd(body["documents"]), "content")
  end

  test "unbekanntes Dokument: Entscheidungsfehler, kein Crash" do
    assert {:reply, response, _frame} =
             Tools.AdmitDocument.execute(%{document_id: "doc-phantom"}, Frame.new())

    refute response.isError
    body = parse_json_body(response)
    assert body["decision"] == "error"
    assert body["detail"] =~ "unbekanntes Objekt"
  end
end
