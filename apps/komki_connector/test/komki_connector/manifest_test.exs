defmodule KomkiConnector.ManifestTest do
  @moduledoc """
  Die komki-Manifeste (CONTRACT.md §5): Tool-Namen, Schemas, Fassungen
  und die Grenzen, die der Vermittler und das Profil brauchen. Seit der
  Sidecar-Extraktion leben diese Assertions hier, nicht mehr im
  Protokoll-Test.
  """

  use ExUnit.Case, async: true

  alias KomkiConnector.Manifest
  alias Sidecar.Params

  test "sidecar!/1: unveraendertes Manifest plus version = Fassung" do
    # Kein Vergleich der ganzen Maps: getrennt kompilierte Regexe in den
    # Schemas sind unter OTP 28 nie gleich.
    for id <- Manifest.ids() do
      manifest = Manifest.fetch!(id)
      sidecar = Manifest.sidecar!(id)
      assert sidecar.version == manifest.fassung
      assert Map.keys(Map.delete(sidecar, :version)) == Map.keys(manifest)
      assert Map.keys(sidecar.ops) == Map.keys(manifest.ops)
    end
  end

  test "Tools: eindeutig, by_tool, keine URL- oder Host-Parameter" do
    tools = Manifest.tools()
    assert tools == Enum.uniq(tools)
    # DURCHSTICH #409 (Wegwerf): + rp_fakt_vorschlagen; #419: + rp_stand_lesen
    assert length(tools) == 9
    assert {:ok, %{id: "documents"}, "read"} = Manifest.by_tool("admit_document")
    assert {:ok, %{id: "vault"}, "write_test"} = Manifest.by_tool("vault_write_test")

    assert {:ok, %{id: "ratsprojekte"}, "fakt_vorschlagen"} =
             Manifest.by_tool("rp_fakt_vorschlagen")

    assert :error = Manifest.by_tool("exec")

    for m <- Manifest.all(), {_op, spec} <- m.ops, name <- Map.keys(spec.params) do
      refute name in ["url", "host", "path", "command"]
    end
  end

  test "Fassungen und IDs der fuenf Connectoren (DURCHSTICH #409: + ratsprojekte)" do
    assert Manifest.ids() == ["documents", "ratsprojekte", "ris", "vault", "web"]

    for id <- Manifest.ids() do
      assert %{id: ^id, fassung: "komki-" <> _} = Manifest.fetch!(id)
    end
  end

  # Connector contract §6.4 (#419): an admit-only operation takes no
  # parameters, names its fixed object and has an environment of its own;
  # its labels are the manifest's import_labels.
  test "Nur-Aufnahme-Operationen: ohne Parameter, mit Objekt, Umgebung und Label" do
    admit_only =
      for m <- Manifest.all(), {op, %{kind: :admit_only} = spec} <- m.ops, do: {m, op, spec}

    assert [{manifest, "stand_lesen", spec}] = admit_only
    assert spec.tool == "rp_stand_lesen"
    assert spec.params == %{}
    assert spec.object == "ratsprojekte-stand"
    assert Manifest.environment(manifest, "stand_lesen") == "lokaler-arbeitsraum@1"
    assert manifest.import_labels == ["ratsprojekte@1"]
  end

  test "environment/2: eigene Umgebung der Operation, sonst die des Connectors" do
    manifest = Manifest.fetch!("ratsprojekte")
    assert Manifest.environment(manifest, "fakt_vorschlagen") == "ratsprojekte-bestand@1"
    assert Manifest.environment(manifest, "stand_lesen") == "lokaler-arbeitsraum@1"
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
