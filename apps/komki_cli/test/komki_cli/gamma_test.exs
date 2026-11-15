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

  # ----------------------------------------------------------------------
  # Store aus einer frueheren Vorlage (#513) und Export-Rechte (#485)
  # ----------------------------------------------------------------------

  @vor_298 Path.expand("../fixtures/vorlagen/23721f4-vor-298/label-store-seed.json", __DIR__)

  # Store aus der Vorlage vor #298 (c6b5f75): die @1-Connector-Bindungen
  # tragen noch keine transfer-Regel. Die Fixture ist byte-genau der Seed
  # `label_store_seed/0` der Fassung 23721f4 (Eltern-Commit von c6b5f75),
  # erzeugt aus dem Git-Verlauf — nicht aus der Live-Instanz.
  defp import_vor_298!(cfg, own_bindings \\ %{}) do
    {:ok, raw} = File.read(@vor_298)
    {:ok, seed} = JSON.parse(raw)
    seed = put_in(seed, ["bindings"], Map.merge(seed["bindings"], own_bindings))
    assert {:ok, _} = LabelStore.import_registry(Gamma.db_path(cfg), seed)
  end

  test "Store aus der Vorlage vor #298: Migration mit Sicherung, dann startklar (#513)", %{
    cfg: cfg
  } do
    import_vor_298!(cfg)

    assert {:replaced, backup} = Gamma.migrate_outdated_store(cfg)
    assert File.exists?(backup)
    assert mode(backup) == 0o600
    refute File.exists?(Gamma.db_path(cfg) <> ".migrationsprobe")

    # Die Sicherung bleibt lesbar und traegt weiter die alte Fassung.
    assert {:ok, alt} = LabelStore.export(backup)
    assert alt =~ "doc-oeffentlich@2"

    assert :written = Gamma.sync(cfg)
    assert File.read!(Gamma.registry_path(cfg)) == JSON.canonical(Templates.registry())

    # Ein Store der aktuellen Vorlage wird nicht erneut ersetzt.
    assert :ok = Gamma.migrate_outdated_store(cfg)
  end

  test "eigene Bindungen: Abbruch bleibt, Meldung nennt den nächsten Schritt (#513)", %{
    cfg: cfg
  } do
    {:ok, raw} = File.read(@vor_298)
    {:ok, vorlage} = JSON.parse(raw)
    eigene = Map.fetch!(vorlage["bindings"], "ris-oeffentlich@1")

    import_vor_298!(cfg, %{"eigene-fraktion@1" => eigene})

    assert {:error, reason} = Gamma.sync(cfg)
    assert reason =~ "Bindung unveränderlich"
    assert reason =~ "Nächster Schritt: " <> Gamma.db_path(cfg)
  end

  test "Export und Vermittler-Verzeichnis entstehen mit 0600/0700 (#485)", %{cfg: cfg} do
    assert :written = Gamma.sync(cfg)

    assert mode(Path.dirname(Gamma.registry_path(cfg))) == 0o700
    assert mode(Gamma.registry_path(cfg)) == 0o600
  end

  # Review zu #500: Die Basis haertet Gamma.sync (korrigierend), nicht
  # LabelStore.with_conn — --db ist eine freie Pfadnaht und darf
  # beliebige Verzeichnisse nie auf 0700 ziehen.
  test "Instanzbasis wird korrigierend auf 0700 gehärtet (#500)", %{cfg: cfg} do
    File.chmod!(cfg.base_dir, 0o755)

    assert :written = Gamma.sync(cfg)

    assert mode(cfg.base_dir) == 0o700
  end

  defp mode(path) do
    {:ok, stat} = File.stat(path)
    Bitwise.band(stat.mode, 0o777)
  end
end
