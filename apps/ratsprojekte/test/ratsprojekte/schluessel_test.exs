defmodule Ratsprojekte.SchluesselTest do
  use ExUnit.Case, async: true

  import Ratsprojekte.Betrieb

  alias Ratsprojekte.{Ort, Schluessel}

  test "Wiederherstellungscode: hin und zurück, tolerant gegen Schreibweise" do
    key = Schluessel.neu()
    code = Schluessel.code(key)

    assert code =~ ~r/\A([A-Z2-7]{4}-){12}[A-Z2-7]{4}\z/
    assert {:ok, ^key} = Schluessel.aus_code(code)

    assert {:ok, ^key} =
             Schluessel.aus_code(" " <> String.downcase(String.replace(code, "-", " ")) <> "\n")

    assert {:error, :falscher_code} = Schluessel.aus_code("ABCD-EFGH")
  end

  test "Siegel liegt mit 0600 im Home, öffnet nur über den Provider" do
    home = home!()
    key = eingerichtet!(home)

    assert {:ok, %File.Stat{mode: mode}} = File.stat(Ort.schluessel(home))
    assert Bitwise.band(mode, 0o777) == 0o600
    refute File.read!(Ort.schluessel(home)) =~ Base.encode16(key, case: :lower)
    assert {:ok, ^key} = Schluessel.oeffnen(home, provider(home))

    # Another enclave key (another Mac) cannot open it.
    other = {SealedEnvelope.KeyAgreement.FileTestDouble, path: Path.join(home, "anderer.key")}
    _ = SealedEnvelope.seal("x", other)
    assert {:error, {:tresor, _}} = Schluessel.oeffnen(home, other)
  end

  test "ohne Siegel: nicht eingerichtet" do
    home = home!()
    assert {:error, :nicht_eingerichtet} = Schluessel.oeffnen(home, provider(home))
  end

  test "pruefen: passender und falscher Schlüssel, fehlende Datenbank" do
    home = home!()
    key = Schluessel.neu()
    db = Ort.datenbank(home)

    assert :ok = Schluessel.pruefen(key, db)

    {:ok, conn} = Exqlite.Sqlite3.open(db)
    :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA key = " <> Schluessel.pragma(key))
    :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE probe (text TEXT)")
    :ok = Exqlite.Sqlite3.close(conn)

    assert :ok = Schluessel.pruefen(key, db)
    assert {:error, :falscher_schluessel} = Schluessel.pruefen(Schluessel.neu(), db)
  end
end
