defmodule KomkiConnectorRis.RisRecorderTest do
  # Nicht async: das httpc-Profil ist knotenweit.
  use ExUnit.Case, async: false

  alias KomkiConnectorRis.{Http, MockRis, RisHttp, RisRecorder}

  @headers [{"accept", "application/json"}]
  @pdf <<"%PDF-1.7\n", 0, 255, 254, 13, 10>>

  test "zeichnet den Austausch auf und reicht die Antwort bytetreu weiter" do
    # Upstream ist der synthetische Mock: echte Daten kommen hier nie vor.
    {:ok, upstream, upstream_port} = MockRis.start()
    out = tmp_out()

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
    out = tmp_out()

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
    out = tmp_out()

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

  test "Upstream ohne abschliessenden Schraegstrich funktioniert" do
    # Tippfehler-Klasse wie bei Ratsinfo.Config.base_url/0: der Recorder
    # ergaenzt den Slash, statt jeden Pfad ins Leere laufen zu lassen.
    {:ok, upstream, upstream_port} = MockRis.start()
    out = tmp_out()

    {:ok, rec, port, _out} =
      RisRecorder.start(upstream: "http://127.0.0.1:#{upstream_port}", out: out)

    on_exit(fn ->
      RisRecorder.stop(rec)
      MockRis.stop(upstream)
      File.rm_rf(out)
    end)

    :ok = Http.start(nil)

    assert {:ok, %{"items" => [_, _]}} =
             Http.get_json("http://127.0.0.1:#{port}/guestmeetings", @headers, 5_000)
  end

  test "Upstream und Client erhalten alles ungeschwaerzt, die Kassette nicht" do
    {:ok, upstream_port} = start_echo_upstream(self())
    out = tmp_out()

    {:ok, rec, port, _out} =
      RisRecorder.start(upstream: "http://127.0.0.1:#{upstream_port}/", out: out)

    on_exit(fn ->
      RisRecorder.stop(rec)
      File.rm_rf(out)
    end)

    :ok = Http.start(nil)

    login = :json.encode(%{"login" => "beispiel@example.org", "password" => "geheim"})

    {:ok, {{_, 200, _}, _, auth_body}} =
      post(port, "/auth", [{"authorization", "Bearer alt"}], login)

    # Upstream bekommt Zugangsdaten und Kopfzeile unveraendert.
    assert_received {:upstream, "/auth", up_headers, up_body}
    assert :json.decode(up_body) == %{"login" => "beispiel@example.org", "password" => "geheim"}
    assert {"authorization", "Bearer alt"} in up_headers

    # Der Client bekommt die Antwort unveraendert ...
    assert :json.decode(auth_body)["refresh_token"] == "r-geheim"

    # ... die Kassette dagegen nur geschwaerzte Werte, auch fuer Felder, die
    # keine Sperrliste kennt. Die Struktur (Schluessel, Zahlen) bleibt.
    %{"request" => request, "response" => response} = read_cassette(out, "-post-auth.json")
    assert ["authorization", "<redacted>"] in request["headers"]

    assert request["body_b64"] |> Base.decode64!() |> :json.decode() ==
             %{"login" => "<redacted>", "password" => "<redacted>"}

    assert response["body_b64"] |> Base.decode64!() |> :json.decode() ==
             %{
               "token" => "<redacted>",
               "refresh_token" => "<redacted>",
               "user" => %{"name" => "<redacted>"},
               "expires_in" => 3600
             }

    # Binaer-Download: Client und Kassette bytetreu.
    {:ok, {{_, 200, _}, _, pdf}} = get(port, "/agendaitems/documents/7")
    assert pdf == @pdf

    %{"response" => doc} = read_cassette(out, "-get-agendaitems-documents-7.json")
    assert Base.decode64!(doc["body_b64"]) == @pdf
  end

  test "Kassetten sind nur fuer den Eigentuemer lesbar" do
    {:ok, upstream, upstream_port} = MockRis.start()
    out = tmp_out()

    {:ok, rec, port, _out} =
      RisRecorder.start(upstream: "http://127.0.0.1:#{upstream_port}/", out: out)

    on_exit(fn ->
      RisRecorder.stop(rec)
      MockRis.stop(upstream)
      File.rm_rf(out)
    end)

    :ok = Http.start(nil)
    assert {:ok, _} = Http.get_json("http://127.0.0.1:#{port}/guestmeetings", @headers, 5_000)

    [file] = Path.wildcard(Path.join(out, "*.json"))
    assert Bitwise.band(File.stat!(out).mode, 0o777) == 0o700
    assert Bitwise.band(File.stat!(file).mode, 0o777) == 0o600
  end

  test "--out innerhalb eines Git-Repos wird abgewiesen" do
    # Dieses Repo selbst: hier duerfen nicht-oeffentliche Kassetten nie landen.
    inside = Path.join(__DIR__, "kassetten")

    assert {:error, {:out_in_repo, _repo}} = RisRecorder.start(out: inside)
    refute File.exists?(inside)

    assert :ok = RisRecorder.check_out(tmp_out())
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

  # --- Hilfen -------------------------------------------------------------------

  defp tmp_out,
    do: Path.join(System.tmp_dir!(), "ris-recorder-#{System.unique_integer([:positive])}")

  defp read_cassette(out, suffix) do
    [file] = Path.wildcard(Path.join(out, "*#{suffix}"))
    file |> File.read!() |> :json.decode()
  end

  defp get(port, path) do
    :httpc.request(
      :get,
      {~c"http://127.0.0.1:#{port}#{path}", []},
      [ssl: [], timeout: 5_000],
      [body_format: :binary],
      Http.profile()
    )
  end

  defp post(port, path, headers, body) do
    headers = for {k, v} <- headers, do: {String.to_charlist(k), String.to_charlist(v)}

    :httpc.request(
      :post,
      {~c"http://127.0.0.1:#{port}#{path}", headers, ~c"application/json", body},
      [ssl: [], timeout: 5_000],
      [body_format: :binary],
      Http.profile()
    )
  end

  # Synthetischer Upstream, der meldet, was er bekommt: so laesst sich pruefen,
  # dass der Proxy nur die Kassette schwaerzt, nicht den Weg zum RIS.
  defp start_echo_upstream(test_pid) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :http_bin, active: false, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listener)
    pid = spawn(fn -> echo_loop(listener, test_pid) end)
    :ok = :gen_tcp.controlling_process(listener, pid)
    on_exit(fn -> Process.exit(pid, :kill) end)
    {:ok, port}
  end

  defp echo_loop(listener, test_pid) do
    {:ok, sock} = :gen_tcp.accept(listener)
    {:ok, _method, target, headers, body} = RisHttp.read_request(sock)
    send(test_pid, {:upstream, target, headers, body})

    {content_type, resp} =
      case target do
        "/auth" ->
          {"application/json",
           :json.encode(%{
             "token" => "t-geheim",
             "refresh_token" => "r-geheim",
             "user" => %{"name" => "Beispielperson"},
             "expires_in" => 3600
           })}

        _ ->
          {"application/pdf", @pdf}
      end

    resp = IO.iodata_to_binary(resp)

    :gen_tcp.send(sock, [
      "HTTP/1.1 200 OK\r\ncontent-type: #{content_type}\r\n",
      "content-length: #{byte_size(resp)}\r\nconnection: close\r\n\r\n",
      resp
    ])

    :gen_tcp.close(sock)
    echo_loop(listener, test_pid)
  end
end
