defmodule KomkiConnectorRis.RisRecorderTest do
  # Nicht async: das httpc-Profil ist knotenweit.
  use ExUnit.Case, async: false

  alias KomkiConnectorRis.{Http, MockRis, RisRecorder}

  @headers [{"accept", "application/json"}]

  test "zeichnet den Austausch auf und reicht die Antwort bytetreu weiter" do
    # Upstream ist der synthetische Mock: echte Daten kommen hier nie vor.
    {:ok, upstream, upstream_port} = MockRis.start()
    out = Path.join(System.tmp_dir!(), "ris-recorder-#{System.unique_integer([:positive])}")

    {:ok, rec, port, _out} =
      RisRecorder.start(upstream: "http://127.0.0.1:#{upstream_port}/", out: out)

    on_exit(fn ->
      RisRecorder.stop(rec)
      MockRis.stop(upstream)
      File.rm_rf(out)
    end)

    :ok = Http.start(nil)

    assert {:ok, %{"items" => [_, _]}} =
             Http.get_json(
               "http://127.0.0.1:#{port}/guestmeetings?client=32&from=2026-01-01&until=2026-12-31",
               @headers,
               5_000
             )

    [file] = Path.wildcard(Path.join(out, "*.json"))
    %{"request" => request, "response" => response} = file |> File.read!() |> :json.decode()

    assert request["method"] == "GET"
    assert request["path"] == "/guestmeetings"
    assert request["query"] == "client=32&from=2026-01-01&until=2026-12-31"
    assert ["accept", "application/json"] in request["headers"]

    assert response["status"] == 200
    assert ["content-type", "application/json"] in response["headers"]

    assert response["body_b64"] |> Base.decode64!() |> String.contains?("Sitzung des Stadtrates")
  end

  test "Geheimnisse werden nur in der Kassette redigiert" do
    headers = [{"authorization", "Bearer geheim"}, {"accept", "application/json"}]

    assert RisRecorder.scrub_headers(headers, ["authorization"]) ==
             [{"authorization", "<redacted>"}, {"accept", "application/json"}]

    body = %{"token" => "geheim", "items" => [%{"jwt" => "geheim", "name" => "Beispiel"}]}

    assert RisRecorder.redact_json(body, ["token", "jwt"]) ==
             %{
               "token" => "<redacted>",
               "items" => [%{"jwt" => "<redacted>", "name" => "Beispiel"}]
             }
  end
end
