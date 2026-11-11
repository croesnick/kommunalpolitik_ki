defmodule Ratsprojekte.SqlcipherTest do
  # exqlite baut im Workspace gegen die SQLCipher-Systembibliothek
  # (ADR 0004 „Betrieb‟, #435). Diese Tests machen daraus eine Regel statt
  # Ausrüstung: Der Build wird nachgewiesen (cipher_version), und das
  # Verhalten ohne/mit Schlüssel ist wie vom ADR gefordert — ohne
  # Schlüssel verhält sich SQLCipher wie normales SQLite (Dev ohne echte
  # Daten), mit Schlüssel ist die Datei Chiffretext. Der Schreibweg für
  # den echten Schlüssel im Release kommt mit dem lokalen Betrieb (#440);
  # PRAGMA key direkt nach dem Öffnen ist derselbe Mechanismus, den auch
  # Exqlite.Connection intern nutzt.
  use Ratsprojekte.DataCase, async: true

  @plaintext_header "SQLite format 3"
  @key "gartenstadt-erst-wurf"

  test "exqlite ist gegen SQLCipher gebaut (PRAGMA cipher_version)" do
    result = Ratsprojekte.Repo.query!("PRAGMA cipher_version")

    assert result.rows != [],
           """
           exqlite wurde nicht gegen SQLCipher gebaut: PRAGMA cipher_version \
           liefert keine Zeile. Systembibliothek installieren \
           (brew install sqlcipher, siehe docs/prerequisites.md) und exqlite \
           neu kompilieren: mix deps.compile exqlite --force
           """
  end

  test "ohne Schluessel verhaelt sich SQLCipher wie normales SQLite" do
    path = tmp_db("unkeyed")

    assert {:ok, conn} = Exqlite.Sqlite3.open(path)
    assert :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE probe (text TEXT)")
    insert_probe(conn, "Klartext")
    assert select_first_probe(conn) == "Klartext"
    assert :ok = Exqlite.Sqlite3.close(conn)

    # Die Datei ist eine ganz normale, unverschlüsselte SQLite-Datei.
    assert file_header(path) == @plaintext_header
  end

  test "mit Schluessel ist die Datei Chiffretext und ohne Schluessel nicht lesbar" do
    path = tmp_db("keyed")

    assert {:ok, conn} = Exqlite.Sqlite3.open(path)
    assert :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA key = '#{@key}'")
    assert :ok = Exqlite.Sqlite3.execute(conn, "CREATE TABLE probe (text TEXT)")
    insert_probe(conn, "Geheimtext")
    assert :ok = Exqlite.Sqlite3.close(conn)

    # Chiffretext: kein SQLite-Header, der Klartext steht nicht in der Datei.
    header = file_header(path)
    refute header == @plaintext_header
    refute File.read!(path) =~ "Geheimtext"

    # Ohne Schlüssel scheitert die erste Leseoperation an der Datei.
    assert {:ok, conn} = Exqlite.Sqlite3.open(path)

    # Sqlite3.execute meldet Fehler als plain reason (hier: „file is not a
    # database“) — der Wortlaut gehört SQLCipher, nicht festgezurrt.
    assert {:error, _reason} =
             Exqlite.Sqlite3.execute(conn, "SELECT count(*) FROM sqlite_master")

    assert :ok = Exqlite.Sqlite3.close(conn)

    # Mit Schlüssel kommt der Text zurück.
    assert {:ok, conn} = Exqlite.Sqlite3.open(path)
    assert :ok = Exqlite.Sqlite3.execute(conn, "PRAGMA key = '#{@key}'")
    assert select_first_probe(conn) == "Geheimtext"
    assert :ok = Exqlite.Sqlite3.close(conn)
  end

  defp tmp_db(name) do
    Path.join(
      System.tmp_dir!(),
      "ratsprojekte_sqlcipher_#{name}_#{System.unique_integer([:positive])}.db"
    )
  end

  defp insert_probe(conn, text) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO probe VALUES ('#{text}')")
    :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
  end

  defp select_first_probe(conn) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT text FROM probe")
    {:row, [text]} = Exqlite.Sqlite3.step(conn, stmt)
    :done = Exqlite.Sqlite3.step(conn, stmt)
    :ok = Exqlite.Sqlite3.release(conn, stmt)
    text
  end

  defp file_header(path) do
    path |> File.read!() |> binary_part(0, byte_size(@plaintext_header))
  end
end
