defmodule KomkiConnectorRis.RisNgrammTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorRis.RisNgramm

  @fixtures Path.expand("fixtures/gartenstadt", __DIR__)

  test "findet durchgerutschte echte Saetze" do
    echt = tmp_dir()
    synth = tmp_dir()

    satz = "die verwaltung hat die anregungen sorgfaeltig geprueft"
    kassette(echt, "1.json", "{\"text\": \"#{satz}\"}")
    kassette(synth, "1.json", "{\"text\": \"vorwort #{satz} nachwort\"}")

    ergebnis = RisNgramm.pruefen(synth, echt, 6)

    assert ergebnis.geprueft == 1
    assert [{datei, streifen}] = ergebnis.funde
    assert datei == "1.json"

    # Two overlapping 6-gram windows of the sentence that slipped through.
    assert "die verwaltung hat die anregungen sorgfaeltig" in streifen
    assert "verwaltung hat die anregungen sorgfaeltig geprueft" in streifen
  end

  test "erfundene Saetze mit kurzen Ueberlappungen bleiben frei" do
    echt = tmp_dir()
    synth = tmp_dir()

    kassette(echt, "1.json", "{\"text\": \"die buchloe verwaltung hat die unterlagen geprueft\"}")

    kassette(
      synth,
      "1.json",
      "{\"text\": \"die gartenstadt verwaltung hat die anlagen geprueft\"}"
    )

    assert RisNgramm.pruefen(synth, echt, 6).funde == []
  end

  test "Base64-HTML wird dekodiert geprueft" do
    echt = tmp_dir()
    synth = tmp_dir()

    html = "<p>die verwaltung hat die anregungen sorgfaeltig geprueft</p>"

    kassette(echt, "1.json", "{\"content\": \"#{Base.encode64(html)}\"}")
    kassette(synth, "1.json", "{\"content\": \"#{Base.encode64(html)}\"}")

    assert length(RisNgramm.pruefen(synth, echt, 6).funde) == 1
  end

  test "Genau-N ueberlappt, Genau-N-minus-eins nicht" do
    echt = tmp_dir()
    treffer = tmp_dir()
    sauber = tmp_dir()

    kassette(echt, "1.json", "{\"text\": \"alpha beta gamma delta\"}")
    kassette(treffer, "1.json", "{\"text\": \"xx alpha beta gamma yy\"}")
    kassette(sauber, "1.json", "{\"text\": \"alpha beta xx gamma delta\"}")

    assert length(RisNgramm.pruefen(treffer, echt, 3).funde) == 1
    assert RisNgramm.pruefen(sauber, echt, 3).funde == []
  end

  test "Nicht-JSON-Bodies krachen nicht" do
    echt = tmp_dir()
    synth = tmp_dir()

    kassette(echt, "1.json", "%PDF-1.4 rohdaten binarstrom")
    kassette(synth, "1.json", "%PDF-1.4 ganz andere rohdaten")

    assert RisNgramm.pruefen(synth, echt, 6).funde == []
  end

  test "committete Kassetten sind gegen erfundene Dritttexte frei" do
    echt = tmp_dir()

    dritttext =
      "{\"text\": \"Der Bauausschuss berät die Straßenverkehrsordnung und empfiehlt danach eine Anpassung\"}"

    kassette(echt, "1.json", dritttext)

    ergebnis = RisNgramm.pruefen(@fixtures, echt, 6)

    assert ergebnis.geprueft == length(File.ls!(@fixtures))
    assert ergebnis.funde == []
  end

  test "parse_cli und gramm_aus pruefen die Argumente" do
    assert {:error, usage} = RisNgramm.parse_cli(["--echt", "/tmp"])
    assert usage =~ "Aufruf"

    assert {:error, fehlt} =
             RisNgramm.parse_cli(["--synthetisch", "/gibtsnicht", "--echt", "/tmp"])

    assert fehlt =~ "existiert nicht"

    assert {:ok, opts} = RisNgramm.parse_cli(["--synthetisch", "/tmp", "--echt", "/tmp"])
    assert {:ok, 6} = RisNgramm.gramm_aus(opts)
    assert {:ok, 3} = RisNgramm.gramm_aus(Keyword.put(opts, :gramm, "3"))
    assert {:error, _} = RisNgramm.gramm_aus(Keyword.put(opts, :gramm, "1"))
    assert {:error, _} = RisNgramm.gramm_aus(Keyword.put(opts, :gramm, "abc"))
  end

  # --- Helpers ------------------------------------------------------------------

  defp kassette(dir, name, body) do
    cassette = %{
      "request" => %{"method" => "GET", "path" => "/x", "query" => :null, "headers" => []},
      "response" => %{"status" => 200, "headers" => [], "body" => body}
    }

    File.write!(Path.join(dir, name), IO.iodata_to_binary(:json.encode(cassette)))
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "ris-ngramm-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
