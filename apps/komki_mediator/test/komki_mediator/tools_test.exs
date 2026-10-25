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
    assert body["labels"] == ["doc-oeffentlich@1"]
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
    # CONTRACT § 2.8) — hier ueber das MCP-Tool hindurch, in derselben Form
    # wie direkt durchs Gate gepinnt (remedies_test).
    assert body["remedies"] == [
             %{
               "code" => "binding_condition_false",
               "binding" => "doc-vertraulich@1",
               "condition" => "purpose",
               "transitions" => [
                 %{"type" => "fakt_nachreichen", "facts" => ["purpose"]},
                 %{
                   "type" => "neuer_raum",
                   "required_bindings" => ["doc-vertraulich@1"],
                   "required_recipients" => ["nutzende-person", "pi-agent"]
                 }
               ]
             }
           ]
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
