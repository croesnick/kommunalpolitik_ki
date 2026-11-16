defmodule KomkiCli.GammaTest do
  # Ticket #208: Γ aus dem Label-Store; registry.json ist der Export.
  use ExUnit.Case, async: true

  alias KomkiCli.{Gamma, LabelStore, TestSupport}
  alias KomkiMediator.Templates
  alias KomkiPolicy.JSON

  setup do
    %{cfg: TestSupport.fixture_cfg(TestSupport.tmp_area!("komki-gamma"))}
  end

  test "frische Instanz: Export ist byte-gleich der Vorlage", %{cfg: cfg} do
    assert :written = Gamma.sync(cfg)
    assert File.read!(Gamma.registry_path(cfg)) == JSON.canonical(Templates.registry())
    # Der erste Vermittler-Start legt room.json und die Dokumente an und
    # laesst den Export unberuehrt; danach ist alles eingerichtet.
    assert Templates.provision!(cfg.base_dir) == :ok
    assert File.read!(Gamma.registry_path(cfg)) == JSON.canonical(Templates.registry())
    assert File.exists?(Path.join([cfg.base_dir, "mediator", "room.json"]))
    assert Templates.provision!(cfg.base_dir) == :already_provisioned
  end

  test "zweiter Lauf aendert nichts", %{cfg: cfg} do
    assert :written = Gamma.sync(cfg)
    assert :unchanged = Gamma.sync(cfg)
  end

  # Ticket #354, ADR 0007: Ein Store aus der Vorlage vor der Befugnis fuer
  # suchanfrage startet weiter. komki up ersetzt genau die vier
  # mitgelieferten Bindungen und haelt jeden Uebergang fest; die
  # Fingerabdruecke in Templates.superseded_bindings/0 treffen die alte
  # Fassung.
  test "Vorlagen-Upgrade: Store von vor #354 bekommt die Befugnis fuer suchanfrage", %{
    cfg: cfg
  } do
    seed = Templates.label_store_seed()

    old =
      Enum.reduce(Map.keys(Templates.superseded_bindings()), seed, fn id, acc ->
        update_in(acc, ["bindings", id, "relaxation_authorities"], fn entries ->
          Enum.reject(entries, &(&1["output"] == "suchanfrage"))
        end)
      end)

    assert old != seed
    assert {:ok, _} = LabelStore.import_registry(Gamma.db_path(cfg), old)

    assert :written = Gamma.sync(cfg)
    assert File.read!(Gamma.registry_path(cfg)) == JSON.canonical(Templates.registry())

    {:ok, upgrades} = LabelStore.binding_upgrades(Gamma.db_path(cfg))

    assert upgrades |> Enum.map(& &1["binding"]) |> Enum.sort() ==
             Enum.sort(Map.keys(Templates.superseded_bindings()))

    assert :unchanged = Gamma.sync(cfg)
  end

  test "eigene Bindungen aus dem Store kommen in den Export", %{cfg: cfg} do
    seed = Templates.label_store_seed()
    own = put_in(seed, ["bindings", "vorlage-ausschuss@1"], seed["bindings"]["doc-oeffentlich@1"])

    assert {:ok, _} = LabelStore.import_registry(Gamma.db_path(cfg), own)
    assert :written = Gamma.sync(cfg)

    {:ok, exported} = JSON.parse(File.read!(Gamma.registry_path(cfg)))
    assert Map.has_key?(exported["bindings"], "vorlage-ausschuss@1")
    assert Map.has_key?(exported["bindings"], "ris-oeffentlich@1")
  end

  test "abweichend registrierte Bindung bricht ab (fail-closed)", %{cfg: cfg} do
    changed =
      put_in(
        Templates.label_store_seed(),
        ["bindings", "doc-oeffentlich@1", "readers"],
        ["nutzende-person"]
      )

    assert {:ok, _} = LabelStore.import_registry(Gamma.db_path(cfg), changed)
    assert {:error, reason} = Gamma.sync(cfg)
    assert reason =~ "Γ aus dem Label-Store"
    refute File.exists?(Gamma.registry_path(cfg))
  end
end
