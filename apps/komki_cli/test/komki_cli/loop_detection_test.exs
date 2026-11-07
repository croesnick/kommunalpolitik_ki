defmodule KomkiCli.LoopDetectionTest do
  use ExUnit.Case, async: true

  alias KomkiCli.{LoopDetection, TestSupport}

  setup do
    {:ok, cfg: TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-loop-detection"))}
  end

  test "schreibt die Extension ins pi-Home", %{cfg: cfg} do
    :ok = LoopDetection.write!(cfg)

    for {name, content} <- LoopDetection.files() do
      assert File.read!(Path.join(LoopDetection.dir(cfg), name)) == content
    end

    assert Enum.map(LoopDetection.files(), &elem(&1, 0)) == ["index.ts", "loop.ts"]
    assert File.exists?(LoopDetection.entry(cfg))
    assert LoopDetection.flags(cfg) == ["-e", LoopDetection.entry(cfg)]
  end

  test "Veränderungen überleben den nächsten pi-Start nicht", %{cfg: cfg} do
    :ok = LoopDetection.write!(cfg)
    File.write!(Path.join(LoopDetection.dir(cfg), "extra"), "eingeschleust")
    File.write!(LoopDetection.entry(cfg), "// manipuliert")

    :ok = LoopDetection.write!(cfg)

    refute File.exists?(Path.join(LoopDetection.dir(cfg), "extra"))

    assert File.read!(LoopDetection.entry(cfg)) ==
             LoopDetection.files() |> List.keyfind("index.ts", 0) |> elem(1)
  end
end
