defmodule KomkiConnector.ManifestTest do
  @moduledoc """
  Die komki-Manifeste (CONTRACT.md §5): Tool-Namen, Schemas, Fassungen
  und die Grenzen, die der Vermittler und das Profil brauchen. Seit der
  Sidecar-Extraktion leben diese Assertions hier, nicht mehr im
  Protokoll-Test.
  """

  use ExUnit.Case, async: true

  alias KomkiConnector.{Manifest, Params}

  test "Tools: eindeutig, by_tool, keine URL- oder Host-Parameter" do
    tools = Manifest.tools()
    assert tools == Enum.uniq(tools)
    assert length(tools) == 7
    assert {:ok, %{id: "documents"}, "read"} = Manifest.by_tool("admit_document")
    assert {:ok, %{id: "vault"}, "write_test"} = Manifest.by_tool("vault_write_test")
    assert :error = Manifest.by_tool("exec")

    for m <- Manifest.all(), {_op, spec} <- m.ops, name <- Map.keys(spec.params) do
      refute name in ["url", "host", "path", "command"]
    end
  end

  test "Fassungen und IDs der vier Connectoren" do
    assert Manifest.ids() == ["documents", "ris", "vault", "web"]

    for id <- Manifest.ids() do
      assert %{id: ^id, fassung: "komki-" <> _} = Manifest.fetch!(id)
    end
  end

  test "socket_path: komki-Layout unter der Basis" do
    assert Manifest.socket_path("/basis", "ris") == "/basis/run/connectors/ris.sock"
  end

  test "Params.check gegen das Vault-Schema" do
    schema = Manifest.fetch!("vault").ops["read"].params
    assert {:ok, _} = Params.check(schema, %{"note_id" => "projekte/Bahnhof.md"})
    assert {:error, _} = Params.check(schema, %{"note_id" => "x.txt"})
    assert {:error, _} = Params.check(schema, %{})
    assert {:error, _} = Params.check(schema, %{"note_id" => 5})
  end
end
