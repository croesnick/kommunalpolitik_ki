defmodule KomkiConnectorRis.RisSkeletonTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorRis.RisSkeleton

  @fixtures Path.expand("fixtures/replay", __DIR__)
  @drifted Path.expand("fixtures/replay_drifted", __DIR__)

  test "extrahiert Endpunkte und Formen ohne Inhalte" do
    report = RisSkeleton.extract(@fixtures)

    assert Enum.sort(Map.keys(report["endpoints"])) == [
             "GET /guestagendaitems/{meetingId-agendaId}",
             "GET /guestmeetings",
             "GET /guestmeetings/{id}",
             "POST /auth"
           ]

    endpoints = report["endpoints"]

    # 404- und 200-Aufnahme von /guestmeetings/{id} landen auf einem Endpunkt.
    assert endpoints["GET /guestmeetings/{id}"]["statuses"] == [200, 404]
    assert endpoints["GET /guestmeetings"]["query_keys"] == ["client", "from", "until"]

    body = endpoints["GET /guestmeetings"]["response_body"]
    assert body["type"] == "object"
    assert body["keys"]["items"]["type"] == "array"

    # TOP-Details: Formen statt Werte.
    top = endpoints["GET /guestagendaitems/{meetingId-agendaId}"]["response_body"]

    assert top["keys"]["id"]["formats"] == ["id-pair"]
    assert top["keys"]["meetingid"] == %{"type" => "integer"}

    assert top["keys"]["textblocks"]["items"]["keys"]["content"]["formats"] == ["base64-html"]

    # Der Bericht ist strukturell: keine Werte der Fixtures, kein nil-String.
    json = report |> :json.encode() |> IO.iodata_to_binary()

    refute json =~ "Beispielsitzung"
    refute json =~ "Sachverhalt"
    refute json =~ "4711"
    refute json =~ ~s("nil")
  end

  test "gleiche Verzeichnisse sind formatgetreu" do
    assert RisSkeleton.compare(RisSkeleton.extract(@fixtures), RisSkeleton.extract(@fixtures)) ==
             []
  end

  test "Abweichungen werden gemeldet" do
    differences =
      RisSkeleton.compare(
        RisSkeleton.extract(@fixtures),
        RisSkeleton.extract(@drifted)
      )

    assert "Endpunkt nur in links: POST /auth" in differences

    assert Enum.any?(
             differences,
             &String.contains?(&1, "zustaendigkeit: Schluessel nur in rechts")
           ),
           "Schema-Drift fehlt: #{inspect(differences)}"

    assert Enum.any?(differences, &String.contains?(&1, "query_keys")),
           "Query-Drift fehlt: #{inspect(differences)}"
  end

  # --- Merge und Vergleich gegen selbstgebaute Kassetten --------------------

  test "dreifach divergierende Typen verschmelzen ohne Verlust" do
    dir = tmp_dir()

    write_cassette(dir, "1.json", ~s({"v": {"a": 1}}))
    write_cassette(dir, "2.json", ~s({"v": "s"}))
    write_cassette(dir, "3.json", ~s({"v": null}))

    %{"keys" => %{"v" => v}} =
      RisSkeleton.extract(dir)["endpoints"]["GET /x"]["response_body"]

    assert v == %{"type" => "mixed", "types" => ["null", "object", "string"]}

    # Unterschiedliche mixed-Mengen sind Drift, identische nicht.
    dir_b = tmp_dir()
    write_cassette(dir_b, "1.json", ~s({"v": 1}))
    write_cassette(dir_b, "2.json", ~s({"v": "s"}))

    differences = RisSkeleton.compare(RisSkeleton.extract(dir), RisSkeleton.extract(dir_b))
    assert Enum.any?(differences, &String.contains?(&1, "Typen"))

    same = RisSkeleton.compare(RisSkeleton.extract(dir), RisSkeleton.extract(dir))
    refute Enum.any?(same, &String.contains?(&1, "Typen"))
  end

  test "optionale Schluessel und ueberlappende Kardinalitaet sind keine Abweichung" do
    a = tmp_dir()
    write_cassette(a, "1.json", ~s({"items": [{"i": 1}], "opt": 1}))
    write_cassette(a, "2.json", ~s({"items": [{"i": 1}, {"i": 2}, {"i": 3}, {"i": 4}]}))

    b = tmp_dir()
    write_cassette(b, "1.json", ~s({"items": [{"i": 1}, {"i": 2}]}))

    # "opt" fehlt rechts, ist aber in links optional (nur eine Aufnahme);
    # Items-Laengen 1..4 und 2..2 ueberlappen.
    assert RisSkeleton.compare(RisSkeleton.extract(a), RisSkeleton.extract(b)) == []

    # Verpflichtende Schluessel und entkoppelte Laengen sind Drift.
    c = tmp_dir()
    write_cassette(c, "1.json", ~s({"items": [{"i": 1}], "req": 1}))

    d = tmp_dir()

    write_cassette(
      d,
      "1.json",
      ~s({"items": [{"i": 1}, {"i": 2}, {"i": 3}, {"i": 4}, {"i": 5}, {"i": 6}, {"i": 7}]})
    )

    differences = RisSkeleton.compare(RisSkeleton.extract(c), RisSkeleton.extract(d))

    assert Enum.any?(differences, &String.contains?(&1, "req: Schluessel nur in links"))
    assert Enum.any?(differences, &String.contains?(&1, "Kardinalitaet entkoppelt"))
  end

  test "aeltere Kassetten mit Query-String \"nil\" werden toleriert" do
    dir = tmp_dir()
    File.write!(Path.join(dir, "legacy.json"), legacy_nil_query_cassette())

    assert RisSkeleton.extract(dir)["endpoints"]["GET /x"]["query_keys"] == []
  end

  test "parse_cli meldet fehlende Verzeichnisse" do
    assert {:error, usage} = RisSkeleton.parse_cli(["--out", "/tmp/x"])
    assert usage =~ "Aufruf"

    assert {:error, missing} =
             RisSkeleton.parse_cli(["--cassette", "/gibt-es-nicht"])

    assert missing =~ "existiert nicht"

    assert {:ok, _opts} = RisSkeleton.parse_cli(["--cassette", @fixtures])
  end

  # --- Hilfsgross ------------------------------------------------------------

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "ris-skeleton-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp write_cassette(dir, name, body) do
    cassette = %{
      "request" => %{
        "method" => "GET",
        "path" => "/x",
        "query" => :null,
        "headers" => [["accept", "application/json"]]
      },
      "response" => %{
        "status" => 200,
        "headers" => [["content-type", "application/json"]],
        "body" => body
      }
    }

    File.write!(Path.join(dir, name), IO.iodata_to_binary(:json.encode(cassette)))
  end

  defp legacy_nil_query_cassette do
    # Kassetten aus der Zeit vor dem nil-Fix trugen "query": "nil" als String.
    ~s({"request":{"method":"GET","path":"/x","query":"nil","headers":[]},"response":{"status":200,"headers":[],"body":"{}"}})
  end
end
