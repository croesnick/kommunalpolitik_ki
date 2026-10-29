defmodule KomkiMediator.FassungTest do
  use ExUnit.Case, async: true

  test "tools sind die festgedrehte Fassung (geordnet)" do
    assert KomkiMediator.Fassung.tools() == [
             "ping",
             "list_documents",
             "admit_document",
             "ris_search",
             "ris_show",
             "vault_read",
             "vault_search",
             "vault_write_test",
             "web_search"
           ]
  end

  # Die Connector-Tools der Fassung sind genau die des Manifests
  # (Connector-Vertrag §5.1) — kein zweiter Ort fuer Tool-Namen.
  # admit_document liegt seit #169 im Manifest documents; ping und
  # list_documents (#218) beantwortet der Vermittler selbst.
  test "Connector-Tools der Fassung == KomkiConnector.Manifest.tools" do
    own = KomkiMediator.Fassung.own_tools()

    assert own == ["ping", "list_documents"]
    assert KomkiMediator.Fassung.tools() == own ++ KomkiConnector.Manifest.tools()
  end

  test "fassung_id ist die versionierte Kennung" do
    assert KomkiMediator.Fassung.fassung_id() == "komki-mediator/3"
  end

  # D.9: Die vom anubis-Server advertised Tool-Namen muessen exakt der
  # Fassung entsprechen — jede zusaetzliche Komponente waere eine
  # Fassungsumgehung.
  test "advertised MCP-Tool-Namen == Fassung.tools" do
    advertised =
      Enum.map(KomkiMediator.Server.__components__(), fn component -> component.name end)

    assert Enum.sort(advertised) == Enum.sort(KomkiMediator.Fassung.tools())
  end

  # Die advertised Parameter-Schemas spiegeln das Manifest: gleiche Felder,
  # gleiche Pflichtfelder, gleiche Grenzen und Muster.
  test "Connector-Tool-Schemas spiegeln KomkiConnector.Manifest" do
    tools = Map.new(KomkiMediator.Server.__components__(:tool), &{&1.name, &1})

    for manifest <- KomkiConnector.Manifest.all(), {_op, spec} <- manifest.ops do
      schema = tools[spec.tool].input_schema
      assert tools[spec.tool].description == spec.description
      assert Enum.sort(Map.keys(schema["properties"])) == Enum.sort(Map.keys(spec.params))

      required = for {name, field} <- spec.params, Map.get(field, :required, true), do: name
      assert Enum.sort(Map.get(schema, "required", [])) == Enum.sort(required)

      for {name, field} <- spec.params do
        property = schema["properties"][name]
        assert property["type"] == Atom.to_string(field.type)

        case field.type do
          :string ->
            assert property["maxLength"] == field.max
            assert property["pattern"] == (field[:pattern] && Regex.source(field.pattern))

          :integer ->
            assert {property["minimum"], property["maximum"]} == {field.min, field.max}
        end
      end
    end
  end
end
