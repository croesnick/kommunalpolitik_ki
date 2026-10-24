defmodule KomkiMediator.TemplatesMigrationTest do
  @moduledoc """
  Automatische Migration der Vorlagen (Ticket #177). Die Fixtures unter
  `test/fixtures/vorlagen/<commit>/` sind byte-genau die kanonischen
  Vorlagen der frueheren Fassungen auf main (#106: ed612a2, #107: d9159ec),
  erzeugt aus dem Git-Verlauf.
  """

  use ExUnit.Case, async: true

  alias KomkiMediator.{Templates, TestHelpers}
  alias KomkiPolicy.JSON

  @fixtures Path.expand("../fixtures/vorlagen", __DIR__)

  defp sha(raw), do: Base.encode16(:crypto.hash(:sha256, raw), case: :lower)

  defp base_with(registry_rev, room_rev) do
    base = TestHelpers.tmp_base()
    dir = Path.join(base, "mediator")
    File.mkdir_p!(Path.join(dir, "documents"))

    File.cp!(
      Path.join([@fixtures, registry_rev, "registry.json"]),
      Path.join(dir, "registry.json")
    )

    File.cp!(Path.join([@fixtures, room_rev, "room.json"]), Path.join(dir, "room.json"))
    {base, dir}
  end

  test "Pflege: @current entspricht den tatsaechlichen Vorlagen" do
    assert Templates.current_hashes() == %{
             "registry.json" => sha(JSON.canonical(Templates.registry())),
             "room.json" => sha(JSON.canonical(Templates.room()))
           }
  end

  for rev <- ["ed612a2", "d9159ec"] do
    test "unveraenderte Vorlagen aus #{rev} werden ersetzt; Journal und Dokumente bleiben" do
      {base, dir} = base_with(unquote(rev), unquote(rev))
      journal = Path.join([dir, "journal", "pdr.jsonl"])
      File.mkdir_p!(Path.dirname(journal))
      File.write!(journal, "eintrag\n")
      eigenes_dokument = Path.join([dir, "documents", "doc-oeffentlich.md"])
      File.write!(eigenes_dokument, "# eigener Text\n")

      assert {:migrated, _} = Templates.provision!(base)

      assert File.read!(Path.join(dir, "registry.json")) == JSON.canonical(Templates.registry())
      assert File.read!(Path.join(dir, "room.json")) == JSON.canonical(Templates.room())
      assert File.read!(journal) == "eintrag\n"
      assert File.read!(eigenes_dokument) == "# eigener Text\n"

      # danach stabil
      assert Templates.provision!(base) == :already_provisioned
    end
  end

  test "alte Registry, aber veraenderter Raum: Abbruch mit Erklaerung, nichts ueberschrieben" do
    {base, dir} = base_with("d9159ec", "d9159ec")
    room_path = Path.join(dir, "room.json")
    File.write!(room_path, File.read!(room_path) <> " ")
    before = {File.read!(Path.join(dir, "registry.json")), File.read!(room_path)}

    assert {:error, detail} = Templates.provision!(base)
    assert detail =~ "registry.json ist eine unveraenderte alte Vorlage"
    assert detail =~ "room.json wurde veraendert"
    assert {File.read!(Path.join(dir, "registry.json")), File.read!(room_path)} == before
  end

  test "beide Dateien eigen (weder aktuell noch alt): bleiben unberuehrt" do
    {base, dir} = base_with("d9159ec", "d9159ec")
    for file <- ["registry.json", "room.json"], do: File.write!(Path.join(dir, file), "{}")

    assert Templates.provision!(base) == :already_provisioned
    assert File.read!(Path.join(dir, "registry.json")) == "{}"
  end
end
