defmodule KomkiConnectorRis.RisHttpTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorRis.RisHttp

  test "cli laesst den Runner ohne Argumente und im Test weg" do
    refute_runner = fn _argv -> flunk("Runner darf hier nicht laufen") end

    assert RisHttp.cli([], refute_runner) == :ok
    # Unter `mix test` gilt: keine CLI-Ausfuehrung.
    assert RisHttp.cli(["--port", "1"], refute_runner) == :ok
  end

  test "cli ruft den Runner mit :force" do
    assert RisHttp.cli(["--port", "1"], fn argv -> {:gestartet, argv} end, true) ==
             {:gestartet, ["--port", "1"]}
  end

  test "cassette_files liefert nur *.json, sortiert, als Pfade" do
    dir = tmp_dir()
    File.write!(Path.join(dir, "b.json"), "{}")
    File.write!(Path.join(dir, "a.json"), "{}")
    File.write!(Path.join(dir, "notiz.txt"), "x")
    File.write!(Path.join(dir, "0001-get-x.json.enc"), "rkt1")

    assert RisHttp.cassette_files(dir) == [
             Path.join(dir, "a.json"),
             Path.join(dir, "b.json")
           ]

    assert RisHttp.cassette_files(tmp_dir()) == []
  end

  test "decode_json liefert {:ok, term} oder :error statt zu werfen" do
    assert RisHttp.decode_json(~s({"a": 1})) == {:ok, %{"a" => 1}}
    assert RisHttp.decode_json("[1, 2]") == {:ok, [1, 2]}
    assert RisHttp.decode_json("kein json") == :error
    assert RisHttp.decode_json("") == :error
  end

  test "part_body dekodiert body_b64, faellt auf body zurueck, sonst leer" do
    assert RisHttp.part_body(%{"body_b64" => Base.encode64("aufgezeichnet")}) == "aufgezeichnet"
    assert RisHttp.part_body(%{"body" => "handgeschrieben"}) == "handgeschrieben"
    assert RisHttp.part_body(%{}) == ""

    # Ungueltiges Base64 wirft wie Base.decode64! — die Kassetten stammen vom
    # Recorder oder aus der Hand, kaputte Bodies sind kein Fall fuer Stille.
    assert_raise ArgumentError, fn -> RisHttp.part_body(%{"body_b64" => "!!!"}) end
  end

  test "parse_flags nimmt String-Flaggen in beliebiger Reihenfolge" do
    kinds = [cassette: :string, out: :string, compare: :string]

    assert {:ok, opts} = RisHttp.parse_flags(["--out", "/tmp/x", "--cassette", "/tmp/c"], kinds)
    assert Keyword.get(opts, :out) == "/tmp/x"
    assert Keyword.get(opts, :cassette) == "/tmp/c"

    # Ein Flag zweimal: der letzte Wert gewinnt, wie bisher.
    assert RisHttp.parse_flags(["--out", "alt", "--out", "neu"], out: :string) ==
             {:ok, [out: "neu"]}
  end

  test "parse_flags verlangt bei :integer eine ganze Zahl" do
    assert RisHttp.parse_flags(["--port", "4010"], port: :integer) == {:ok, [port: 4010]}

    for bad <- ["4010x", "abc", "", "--mode"] do
      assert :error = RisHttp.parse_flags(["--port", bad], port: :integer)
    end
  end

  test "parse_flags meldet Unbekanntes und Wert-loses mit :error" do
    assert :error = RisHttp.parse_flags(["--kein-flag", "x"], out: :string)
    assert :error = RisHttp.parse_flags(["bar"], out: :string)
    assert :error = RisHttp.parse_flags(["--out"], out: :string)

    # Keine Argumente sind gueltig: gartenstadt laeuft mit Defaults.
    assert RisHttp.parse_flags([], []) == {:ok, []}
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "ris-http-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
