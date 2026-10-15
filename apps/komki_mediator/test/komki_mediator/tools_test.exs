defmodule KomkiMediator.ToolsTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias KomkiMediator.{TestHelpers, Tools}

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
    assert body["tools"] == ["ping", "admit_document"]
    assert body["registry_id"] == "reg-komki-arbeitsraum"
    assert gamma.registry_id == "reg-komki-arbeitsraum"
  end

  test "admit_document doc-oeffentlich: permit mit Inhalt", %{base: base} do
    content = File.read!(Path.join([base, "mediator", "documents", "doc-oeffentlich.md"]))

    assert {:reply, response, _frame} =
             Tools.AdmitDocument.execute(%{document_id: "doc-oeffentlich"}, Frame.new())

    refute response.isError

    body = parse_json_body(response)
    assert body["decision"] == "permit"
    assert body["object_id"] == "doc-oeffentlich"
    assert body["document_id"] == "doc-oeffentlich"
    assert body["content"] == content
    assert body["labels"] == ["doc-oeffentlich@1"]
  end

  test "admit_document doc-vertraulich: deny als Remedy-Plan, isError bleibt false", %{base: base} do
    _ = base

    assert {:reply, response, _frame} =
             Tools.AdmitDocument.execute(%{document_id: "doc-vertraulich"}, Frame.new())

    refute response.isError

    body = parse_json_body(response)
    assert body["decision"] == "deny"
    refute Map.has_key?(body, "content")
    assert [%{"type" => "provide_fact", "clears" => "purpose"}] = body["remedies"]
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
