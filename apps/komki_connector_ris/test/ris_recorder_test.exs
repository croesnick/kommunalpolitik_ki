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

  test "zeichnet auch POST-Anfragen mit Body auf (Login)" do
    # Upstream ist der synthetische Mock; der antwortet auf POST mit 405 —
    # fuer den Austausch genuegt das: Methode, Body und Redaktion werden geprueft.
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

    body = :json.encode(%{"login" => "beispiel@example.org", "password" => "geheim"})

    headers =
      Enum.map(
        [{"content-type", "application/json"}, {"accept", "application/json"}],
        fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end
      )

    {:ok, {{_, 405, _}, _, _}} =
      :httpc.request(
        :post,
        {"http://127.0.0.1:#{port}/auth", headers, ~c"application/json", body},
        [ssl: [], timeout: 5_000],
        [body_format: :binary],
        Http.profile()
      )

    [file] = Path.wildcard(Path.join(out, "*.json"))
    %{"request" => request, "response" => response} = file |> File.read!() |> :json.decode()

    assert request["method"] == "POST"
    assert request["path"] == "/auth"
    # Kein Query: :json dekodiert JSON-null als :null.
    assert request["query"] == :null

    # Login und Passwort stehen nie in der Kassette.
    assert request["body_b64"] |> Base.decode64!() |> :json.decode() ==
             %{"login" => "<redacted>", "password" => "<redacted>"}

    assert response["status"] == 405
  end

  test "Nummerierung schliesst an vorhandene Kassetten an" do
    {:ok, upstream, upstream_port} = MockRis.start()
    upstream_url = "http://127.0.0.1:#{upstream_port}/"
    out = Path.join(System.tmp_dir!(), "ris-recorder-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      MockRis.stop(upstream)
      File.rm_rf(out)
    end)

    :ok = Http.start(nil)

    {:ok, rec1, port1, _out} = RisRecorder.start(upstream: upstream_url, out: out)
    assert {:ok, _} = Http.get_json("http://127.0.0.1:#{port1}/guestmeetings", @headers, 5_000)
    RisRecorder.stop(rec1)

    {:ok, rec2, port2, _out} = RisRecorder.start(upstream: upstream_url, out: out)
    assert {:ok, _} = Http.get_json("http://127.0.0.1:#{port2}/guestmeetings", @headers, 5_000)
    RisRecorder.stop(rec2)

    # Die zweite Session ueberschreibt die erste nicht.
    assert Path.wildcard(Path.join(out, "*.json")) == [
             Path.join(out, "0001-get-guestmeetings.json"),
             Path.join(out, "0002-get-guestmeetings.json")
           ]
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
