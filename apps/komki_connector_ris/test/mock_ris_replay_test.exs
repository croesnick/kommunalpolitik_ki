defmodule KomkiConnectorRis.MockRisReplayTest do
  # Nicht async: das httpc-Profil des Connectors ist knotenweit.
  use ExUnit.Case, async: false

  alias KomkiConnectorRis.{Http, MockRis}

  @cassettes Path.expand("fixtures/replay", __DIR__)
  @headers [{"accept", "application/json"}]

  test "spielt aufgezeichnete Antworten bytetreu zurueck" do
    {:ok, mock, port} = MockRis.start(mode: {:replay, @cassettes})
    on_exit(fn -> MockRis.stop(mock) end)
    :ok = Http.start(nil)
    base = "http://127.0.0.1:#{port}/"

    # Exakter Treffer (Methode, Pfad, Query).
    assert {:ok, %{"items" => [sitzung]}} =
             Http.get_json(
               base <> "guestmeetings?client=32&from=2026-01-01&until=2026-12-31",
               @headers,
               5_000
             )

    assert sitzung["name"] == "Beispielsitzung"
    assert sitzung["committeename"] == "Beispielgremium"

    # Gleicher Pfad, anderes Zeitfenster: Rueckgriff auf die gleiche Aufzeichnung.
    assert {:ok, %{"items" => [_]}} =
             Http.get_json(
               base <> "guestmeetings?client=32&from=2025-01-01&until=2025-12-31",
               @headers,
               5_000
             )

    # Detail mit geschuetztem Sitzungsteil.
    assert {:ok, %{"parts" => [oeffentlich, geschuetzt]}} =
             Http.get_json(base <> "guestmeetings/4711", @headers, 5_000)

    assert oeffentlich["protectedpart"] == false
    assert geschuetzt["protectedpart"] == true

    # Aufgezeichneter 404 bleibt 404.
    assert {:error, :not_found} = Http.get_json(base <> "guestmeetings/9999", @headers, 5_000)

    # Nicht Aufgezeichnetes antwortet mit eigenem 404.
    assert {:error, :not_found} = Http.get_json(base <> "gibtsnicht", @headers, 5_000)
  end

  test "spielt auch POST-Anfragen zurueck (Login)" do
    {:ok, mock, port} = MockRis.start(mode: {:replay, @cassettes})
    on_exit(fn -> MockRis.stop(mock) end)
    :ok = Http.start(nil)

    {:ok, {{_, 200, _}, _headers, body}} =
      :httpc.request(
        :post,
        {"http://127.0.0.1:#{port}/auth", [], ~c"application/json", ~s({"login":"x"})},
        [ssl: [], timeout: 5_000],
        [body_format: :binary],
        Http.profile()
      )

    assert :json.decode(body) == %{"token" => "beispiel-token"}
  end

  test "parse_cli meldet fehlendes Kassettenverzeichnis" do
    assert {:error, missing} =
             MockRis.parse_cli([
               "--port",
               "4010",
               "--mode",
               "replay",
               "--cassette",
               "/gibt-es-nicht"
             ])

    assert missing =~ "existiert nicht"

    assert {:ok, _opts} =
             MockRis.parse_cli(["--port", "4010", "--mode", "replay", "--cassette", @cassettes])
  end
end
