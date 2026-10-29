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
end
