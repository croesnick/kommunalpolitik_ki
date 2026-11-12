defmodule Ratsprojekte.SperreTest do
  # One BetriebRepo for all tests, hence not async.
  use ExUnit.Case, async: false

  import Ratsprojekte.Betrieb

  alias Ratsprojekte.{Ort, Schluessel, Sperre}

  @plaintext_header "SQLite format 3"

  test "startet gesperrt: kein Zugang, keine Datenbank" do
    home = home!()
    eingerichtet!(home)
    sperre = sperre!(home)

    assert Sperre.status(sperre) == :gesperrt
    refute Sperre.zugang?(sperre, "irgendwas")
    refute File.exists?(Ort.datenbank(home))
  end

  test "öffnen: verschlüsselte Datenbank, Link genau einmal einlösbar" do
    home = home!()
    eingerichtet!(home)
    sperre = sperre!(home)

    assert {:ok, token} = Sperre.oeffnen(sperre)
    assert Sperre.status(sperre) == :offen
    assert {:ok, marker} = Sperre.einloesen(sperre, token)
    assert :error = Sperre.einloesen(sperre, token)
    assert Sperre.zugang?(sperre, marker)
    refute Sperre.zugang?(sperre, nil)

    Ratsprojekte.BetriebRepo.query!("INSERT INTO probe_1 (text) VALUES ('Geheimtext')")
    Sperre.sperren(sperre)

    assert binary_part(File.read!(Ort.datenbank(home)), 0, 15) != @plaintext_header
    refute File.read!(Ort.datenbank(home)) =~ "Geheimtext"
  end

  test "erneutes Öffnen fragt wieder den Schlüssel ab und gibt einen neuen Link, gleiche Sitzung" do
    home = home!()
    eingerichtet!(home)
    sperre = sperre!(home)

    {:ok, t1} = Sperre.oeffnen(sperre)
    {:ok, m1} = Sperre.einloesen(sperre, t1)
    {:ok, t2} = Sperre.oeffnen(sperre)
    assert t1 != t2
    assert {:ok, ^m1} = Sperre.einloesen(sperre, t2)

    # Without the seal (Touch ID refused, key gone) no further link.
    File.rm!(Ort.schluessel(home))
    assert {:error, :nicht_eingerichtet} = Sperre.oeffnen(sperre)
  end

  test "falscher Schlüssel zur vorhandenen Datenbank: bleibt gesperrt" do
    home = home!()
    eingerichtet!(home)
    sperre = sperre!(home)
    {:ok, _} = Sperre.oeffnen(sperre)
    Sperre.sperren(sperre)

    :ok = Schluessel.versiegeln(Schluessel.neu(), home, provider(home))
    assert {:error, :falscher_schluessel} = Sperre.oeffnen(sperre)
    assert Sperre.status(sperre) == :gesperrt
  end

  test "sperren: Repo weg, alte Sitzung und alte Links ungültig, LiveViews erfahren es" do
    home = home!()
    eingerichtet!(home)
    sperre = sperre!(home)
    Phoenix.PubSub.subscribe(Ratsprojekte.PubSub, Sperre.topic())

    {:ok, t1} = Sperre.oeffnen(sperre)
    {:ok, t2} = Sperre.oeffnen(sperre)
    {:ok, marker} = Sperre.einloesen(sperre, t1)
    :ok = Sperre.sperren(sperre)

    assert_receive :gesperrt
    assert Sperre.status(sperre) == :gesperrt
    refute Sperre.zugang?(sperre, marker)
    assert :error = Sperre.einloesen(sperre, t2)
    assert Process.whereis(Ratsprojekte.BetriebRepo) == nil
  end

  test "sperrt sich nach der eingestellten Zeit ohne Handlung" do
    home = home!()
    eingerichtet!(home)
    sperre = sperre!(home, sperre_nach: 150)
    Phoenix.PubSub.subscribe(Ratsprojekte.PubSub, Sperre.topic())

    {:ok, _} = Sperre.oeffnen(sperre)
    assert_receive :gesperrt, 1_000
    assert Sperre.status(sperre) == :gesperrt
  end

  test "Handlungen in der Oberfläche schieben die Sperre hinaus" do
    home = home!()
    eingerichtet!(home)
    sperre = sperre!(home, sperre_nach: 300)
    Phoenix.PubSub.subscribe(Ratsprojekte.PubSub, Sperre.topic())
    {:ok, _} = Sperre.oeffnen(sperre)

    for _ <- 1..6 do
      Sperre.handlung(sperre)
      refute_receive :gesperrt, 100
    end

    assert Sperre.status(sperre) == :offen
    assert_receive :gesperrt, 1_000
  end

  test "vor jeder Schemaänderung eine Kopie neben der Datenbank, nur die letzte bleibt" do
    home = home!()
    eingerichtet!(home)
    dir = migrationen!(home, 1)
    sperre = sperre!(home, migrationen: dir)

    # A new database is no schema change of existing data: no copy.
    {:ok, _} = Sperre.oeffnen(sperre)
    Ratsprojekte.BetriebRepo.query!("INSERT INTO probe_1 (text) VALUES ('Stand vor 2')")
    Sperre.sperren(sperre)
    refute File.exists?(Ort.kopie(home))

    # No pending migration: no copy either.
    {:ok, _} = Sperre.oeffnen(sperre)
    Sperre.sperren(sperre)
    refute File.exists?(Ort.kopie(home))

    migrationen!(home, 2)
    {:ok, _} = Sperre.oeffnen(sperre)
    Sperre.sperren(sperre)
    erste = File.read!(Ort.kopie(home))
    assert binary_part(erste, 0, 15) != @plaintext_header

    migrationen!(home, 3)
    {:ok, _} = Sperre.oeffnen(sperre)
    Sperre.sperren(sperre)

    assert File.read!(Ort.kopie(home)) != erste
    assert home |> File.ls!() |> Enum.count(&String.contains?(&1, "vor-migration")) == 1

    # The copy opens with the same key and holds the data from before.
    {:ok, key} = Schluessel.oeffnen(home, provider(home))
    assert :ok = Schluessel.pruefen(key, Ort.kopie(home))
  end
end
