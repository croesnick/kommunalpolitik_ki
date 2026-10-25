defmodule KomkiCli.AnzeigeTest do
  use ExUnit.Case, async: true

  alias KomkiCli.{Anzeige, TestSupport}

  setup do
    {:ok, cfg: TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-anzeige"))}
  end

  test "schreibt Einstieg und Ansicht ins pi-Home", %{cfg: cfg} do
    :ok = Anzeige.write!(cfg)

    for {name, content} <- Anzeige.files() do
      assert File.read!(Path.join(Anzeige.dir(cfg), name)) == content
    end

    assert File.exists?(Anzeige.entry(cfg))
  end

  test "eine veränderte Anzeige überlebt den nächsten pi-Start nicht", %{cfg: cfg} do
    :ok = Anzeige.write!(cfg)
    File.write!(Path.join(Anzeige.dir(cfg), "view.ts"), "// manipuliert")
    File.write!(Path.join(Anzeige.dir(cfg), "extra.ts"), "// eingeschleust")

    :ok = Anzeige.write!(cfg)

    assert Enum.sort(File.ls!(Anzeige.dir(cfg))) == ["index.ts", "view.ts"]
    {"view.ts", view} = List.keyfind(Anzeige.files(), "view.ts", 0)
    assert File.read!(Path.join(Anzeige.dir(cfg), "view.ts")) == view
  end

  test "die Extension registriert nur Renderer, keine Handler" do
    {"index.ts", index} = List.keyfind(Anzeige.files(), "index.ts", 0)

    assert index =~ "registerToolRenderer"
    refute index =~ ~r/\bpi\.on\(|registerTool\(|registerCommand|sendMessage|executeTool/
  end
end
