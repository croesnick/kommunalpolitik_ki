defmodule KomkiCli.PinsTest do
  @moduledoc """
  Programm-Pins, Negativtests der Steuerebene: ein ausgetauschtes oder
  veraendertes Programm haelt den Start an.
  """

  use ExUnit.Case, async: true

  alias KomkiCli.{Pins, TestSupport}

  # Instanz mit echten Dateien: komki, node, llama-server und ein pi-Paket.
  defp setup_tools do
    dir = TestSupport.tmp_area!("komki-pins")
    bin = fn name -> place!(Path.join([dir, "bin", name]), "#!/bin/sh\n# " <> name <> "\n") end
    pkg = Path.join([dir, "lib", "node_modules", "@earendil-works", "pi-coding-agent"])
    cli_js = place!(Path.join([pkg, "dist", "bundle", "cli.js"]), "console.log('pi')\n")
    place!(Path.join([pkg, "package.json"]), ~s({"name":"pi"}\n))

    cfg = %{
      TestSupport.fixture_cfg(Path.join(dir, "base"))
      | komki_bin: bin.("komki"),
        mediator_bin: nil,
        egress_bin: nil,
        connector_bins: %{},
        escript_bin: nil,
        node_bin: bin.("node"),
        cli_js: cli_js,
        llama_server_bin: bin.("llama-server")
    }

    %{cfg: %{cfg | pins: Pins.compute(cfg)}, pkg: pkg, dir: dir}
  end

  defp place!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  defp failing(cfg), do: for(%{ok: false, name: name} <- Pins.checks(cfg), do: name)

  test "frisch festgehalten: alle Pins gruen" do
    %{cfg: cfg} = setup_tools()
    names = Enum.map(Pins.checks(cfg), & &1.name)
    assert "pin komki" in names
    assert "pin pi" in names
    assert "pin komki-tresor" in names
    assert failing(cfg) == []
  end

  test "Negativtest: veraendertes Programm haelt den Start an" do
    %{cfg: cfg} = setup_tools()
    File.write!(cfg.llama_server_bin, "#!/bin/sh\necho boese\n")

    assert failing(cfg) == ["pin llama-server"]
    [check] = Enum.filter(Pins.checks(cfg), &(&1.name == "pin llama-server"))
    assert check.reason =~ "verändert seit dem Festhalten"
  end

  test "Negativtest: jede Aenderung im pi-Paket zaehlt (Inhalt, neue Datei, Umbenennung, Link)" do
    %{cfg: cfg, pkg: pkg} = setup_tools()

    tamper = [
      fn -> File.write!(Path.join([pkg, "dist", "bundle", "cli.js"]), "boese()\n") end,
      fn -> File.write!(Path.join(pkg, "extra.js"), "neu\n") end,
      fn -> File.rename!(Path.join(pkg, "package.json"), Path.join(pkg, "package2.json")) end,
      fn -> File.ln_s!("/etc/hosts", Path.join(pkg, "link")) end
    ]

    Enum.reduce(tamper, cfg, fn change, cfg ->
      change.()
      assert failing(cfg) == ["pin pi"]
      # fuer den naechsten Schritt den aktuellen Stand festhalten
      %{cfg | pins: Pins.compute(cfg)}
    end)
  end

  test "Negativtest: Symlink umgebogen aendert den Baum-Hash" do
    %{pkg: pkg} = setup_tools()
    link = Path.join(pkg, "ziel")
    File.ln_s!("a", link)
    {:ok, before} = Pins.hash(pkg)
    File.rm!(link)
    File.ln_s!("b", link)
    {:ok, later} = Pins.hash(pkg)
    refute before == later
  end

  test "ohne Pins (Instanz von vor den Pins): Start angehalten mit Hinweis auf setup" do
    %{cfg: cfg} = setup_tools()
    cfg = %{cfg | pins: %{}}
    assert "pin komki" in failing(cfg)
    assert Enum.all?(Pins.checks(cfg), &(&1.reason =~ "komki setup"))
  end

  test "drift: neuer Pfad ist :new, gleiche Stelle mit anderen Bytes ist :changed" do
    %{cfg: cfg, dir: dir} = setup_tools()
    File.write!(cfg.node_bin, "anders")
    moved = place!(Path.join([dir, "neu", "llama-server"]), "#!/bin/sh\n")
    cfg2 = %{cfg | llama_server_bin: moved}

    assert Pins.drift(cfg2, Pins.compute(cfg2)) == %{new: ["llama-server"], changed: ["node"]}
  end

  test "fehlende Datei ist ein Befund, kein Absturz" do
    %{cfg: cfg} = setup_tools()
    File.rm!(cfg.node_bin)
    assert "pin node" in failing(cfg)
  end

  # Zweite Programmform (#288): Das Verzeichnis der NIF-Anwendung gehoert
  # zum Programm des Dokument-Connectors — als eigener Pin (Baum-Hash). Der
  # Pin findet die Fundstelle auch ueber das Multicall-Programm
  # (Connectors.binary/2), wenn connector_bins keinen Eintrag traegt.
  test "Connector mit NIF: Verzeichnis der NIF-Anwendung als eigener Pin" do
    dir = TestSupport.tmp_area!("komki-pins-nif")
    program = place!(Path.join([dir, "bin", "komki"]), "#!/bin/sh\n# komki\n")
    File.mkdir_p!(Path.join([dir, "bin", "lib", "ex_pdfium", "ebin"]))
    File.mkdir_p!(Path.join([dir, "bin", "lib", "ex_pdfium", "priv", "native"]))

    File.write!(
      Path.join([dir, "bin", "lib", "ex_pdfium", "priv", "native", "libpdfium.dylib"]),
      "dylib\n"
    )

    nif = TestSupport.readlink!(Path.join([dir, "bin", "lib", "ex_pdfium"]))

    # Fixture-Werkzeugpfade existieren nicht: ohne sie bleibt der Pin-Satz
    # auf komki und den NIF beschraenkt (place! legt nur dieses Programm an).
    cfg =
      struct!(TestSupport.fixture_cfg(Path.join(dir, "base")),
        komki_bin: program,
        mediator_bin: nil,
        egress_bin: nil,
        connector_bins: %{},
        escript_bin: nil,
        node_bin: nil,
        cli_js: nil,
        llama_server_bin: nil
      )

    assert {"komki-connector-documents-nif", nif} in Pins.artifacts(cfg)

    cfg = %{cfg | pins: Pins.compute(cfg)}
    assert %{"path" => ^nif, "sha256" => sha} = cfg.pins["komki-connector-documents-nif"]
    assert sha =~ ~r/^[0-9a-f]{64}$/
    assert failing(cfg) == []

    # Veraenderte native Datei haelt den Start an: neue Bytes, neuer Baum-Hash.
    File.write!(
      Path.join([dir, "bin", "lib", "ex_pdfium", "priv", "native", "libpdfium.dylib"]),
      "boese\n"
    )

    assert failing(cfg) == ["pin komki-connector-documents-nif"]
  end

  test "Connector mit NIF, ohne Verzeichnis: kein Pin-Eintrag" do
    dir = TestSupport.tmp_area!("komki-pins-ohne-nif")
    program = place!(Path.join([dir, "bin", "komki"]), "#!/bin/sh\n# komki\n")

    cfg =
      struct!(TestSupport.fixture_cfg(Path.join(dir, "base")),
        komki_bin: program,
        connector_bins: %{}
      )

    refute Enum.any?(Pins.artifacts(cfg), fn {name, _} -> String.ends_with?(name, "-nif") end)
  end
end
