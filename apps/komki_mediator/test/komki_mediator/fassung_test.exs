defmodule KomkiMediator.FassungTest do
  use ExUnit.Case, async: true

  test "tools sind die festgedrehte Fassung (geordnet)" do
    assert KomkiMediator.Fassung.tools() == ["ping", "admit_document"]
  end

  test "mcp_tool_exposure deckt genau die Tool-Menge ab" do
    exposure = KomkiMediator.Fassung.mcp_tool_exposure()

    assert exposure == %{"ping" => "direct", "admit_document" => "direct"}
    assert Enum.sort(Map.keys(exposure)) == Enum.sort(KomkiMediator.Fassung.tools())
  end

  test "fassung_id ist die versionierte Kennung" do
    assert KomkiMediator.Fassung.fassung_id() == "komki-mediator/1"
  end

  # D.9: Die vom anubis-Server advertised Tool-Namen muessen exakt der
  # Fassung entsprechen — jede zusaetzliche Komponente waere eine
  # Fassungsumgehung.
  test "advertised MCP-Tool-Namen == Fassung.tools" do
    advertised =
      Enum.map(KomkiMediator.Server.__components__(), fn component -> component.name end)

    assert Enum.sort(advertised) == Enum.sort(KomkiMediator.Fassung.tools())
  end
end
