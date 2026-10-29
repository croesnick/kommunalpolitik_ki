defmodule KomkiConnectorWeb.ConnectorTest do
  # Nicht async: der Log-Test hebt das Logger-Level global an.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias KomkiConnectorWeb.{Connector, MockHttp}
  alias Sidecar.{Client, Server}

  @key "BSA-geheim-0123456789abcdef"

  # `description: nil` laesst das Feld weg (wie Brave bei fehlendem Snippet).
  defp item(title, url, nil), do: %{"title" => title, "url" => url, "age" => "x"}

  defp item(title, url, description),
    do: %{"title" => title, "url" => url, "description" => description, "age" => "x"}

  defp body(items), do: IO.iodata_to_binary(:json.encode(%{"web" => %{"results" => items}}))

  # Startet Mock-API und Connector auf einem echten Unix-Socket unter /tmp.
  # Ohne Proxy teilen sich die Tests das Default-httpc-Profil; der
  # Proxy-Test nutzt ein eigenes.
  defp start(responder, init_extra \\ %{}) do
    {port, stop_mock} = MockHttp.start(responder)

    init_arg =
      Map.merge(
        %{
          credentials: %{"BRAVE_API_KEY" => @key},
          base_url: "http://127.0.0.1:#{port}/",
          timeout: 500
        },
        init_extra
      )

    socket_listen(init_arg, stop_mock)
  end

  defp socket_listen(init_arg, stop_mock) do
    path = "/tmp/kmw#{System.unique_integer([:positive])}.sock"
    {:ok, state} = Connector.init(init_arg)
    {:ok, listener} = Server.listen(path)
    token = Sidecar.Token.provision!(path)
    pid = spawn(fn -> Server.accept_loop(listener, Connector, state, token) end)
    :ok = :socket.setopt(listener, {:otp, :controlling_process}, pid)

    on_exit(fn ->
      Process.exit(pid, :kill)
      stop_mock.()
      File.rm(path)
    end)

    path
  end

  defp search(path, params), do: Client.call(path, "pdr-1", "search", params)

  test "erfolgreiche Suche: Anfrage, Header, Ergebnisform" do
    items = [
      item(
        "Kl&auml;ranlage &amp; <strong>Buchloe</strong>",
        "https://example.org/a",
        "Die <strong>Kläranlage</strong> &quot;Nord&quot; &#8211; Stand&#x21;"
      ),
      item("Zweiter", "http://example.org/b", nil)
    ]

    path = start(fn _req -> {200, body(items)} end)

    assert {:ok, result} = search(path, %{"query" => "Kläranlage Buchloe", "count" => 3})
    assert_received {:mock_request, req}

    assert req.method == "GET"
    assert req.target == "/res/v1/web/search?q=Kl%C3%A4ranlage%20Buchloe&count=3"
    assert req.headers["accept"] == "application/json"
    assert req.headers["x-subscription-token"] == @key

    assert Enum.sort(Map.keys(result)) == ["abrufdatum", "results"]
    assert {:ok, _, 0} = DateTime.from_iso8601(result["abrufdatum"])

    assert result["results"] == [
             %{
               "title" => "Kläranlage & Buchloe",
               "url" => "https://example.org/a",
               "snippet" => "Die Kläranlage \"Nord\" – Stand!"
             },
             %{"title" => "Zweiter", "url" => "http://example.org/b", "snippet" => ""}
           ]
  end

  test "Ergebnisse haben keine Zusatzfelder und begrenzte Laengen" do
    long = String.duplicate("a", 2000)
    path = start(fn _req -> {200, body([item(long, "https://example.org/x", long)])} end)

    assert {:ok, %{"results" => [r]} = result} = search(path, %{"query" => "x"})
    assert map_size(result) == 2
    assert Enum.sort(Map.keys(r)) == ["snippet", "title", "url"]
    assert String.length(r["title"]) == 300
    assert String.length(r["snippet"]) == 1000
  end

  test "count begrenzt die Treffer, Default ist 5" do
    items = for i <- 1..8, do: item("T#{i}", "https://example.org/#{i}", "d")
    path = start(fn _req -> {200, body(items)} end)

    assert {:ok, %{"results" => two}} = search(path, %{"query" => "x", "count" => 2})
    assert Enum.map(two, & &1["title"]) == ["T1", "T2"]

    assert {:ok, %{"results" => five}} = search(path, %{"query" => "x"})
    assert length(five) == 5
    assert_received {:mock_request, _}
    assert_received {:mock_request, %{target: target}}
    assert target =~ "count=5"
  end

  test "Nicht-HTTP-URLs und unvollstaendige Treffer werden vor dem Zaehlen verworfen" do
    items = [
      item("ftp", "ftp://example.org/f", "d"),
      item("js", "javascript:alert(1)", "d"),
      item("relativ", "/nur/pfad", "d"),
      item("ohne host", "https://", "d"),
      %{"url" => "https://example.org/ohne-titel"},
      item("<b></b>", "https://example.org/leerer-titel", "d"),
      item("ok", "https://example.org/ok", "d")
    ]

    path = start(fn _req -> {200, body(items)} end)

    assert {:ok, %{"results" => [%{"title" => "ok"}]}} =
             search(path, %{"query" => "x", "count" => 1})
  end

  test "Antwort ohne web-Block ergibt keine Treffer, kaputtes JSON upstream-error" do
    path =
      start(fn req ->
        if req.target =~ "leer", do: {200, ~s({"type":"search"})}, else: {200, "<html>"}
      end)

    assert {:ok, %{"results" => []}} = search(path, %{"query" => "leer"})
    assert {:error, %{"code" => "upstream-error"}} = search(path, %{"query" => "kaputt"})
  end

  test "fehlender Key: credential-missing, keine Anfrage an Brave" do
    path = start(fn _req -> {200, body([])} end, %{credentials: %{}})

    assert {:error, %{"code" => "credential-missing"}} = search(path, %{"query" => "x"})

    assert {:ok, %{"version" => "komki-web/1", "ops" => ["search"]}} =
             Client.call(path, "c", "ping", %{})

    refute_received {:mock_request, _}
  end

  test "leerer Key gilt als fehlend" do
    path = start(fn _req -> {200, body([])} end, %{credentials: %{"BRAVE_API_KEY" => ""}})
    assert {:error, %{"code" => "credential-missing"}} = search(path, %{"query" => "x"})
  end

  test "HTTP-Status 401, 403, 429, 500" do
    path =
      start(fn req ->
        [_, status] = Regex.run(~r/q=(\d+)/, req.target)
        {String.to_integer(status), ~s({"error":"x"})}
      end)

    assert {:error, %{"code" => "credential-missing"}} = search(path, %{"query" => "401"})
    assert {:error, %{"code" => "upstream-error"}} = search(path, %{"query" => "403"})

    # Der genaue Grund steht im Connector-Log, nicht in der Antwort.
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)

    log =
      ExUnit.CaptureLog.capture_log([level: :info], fn ->
        assert {:error, %{"code" => "upstream-error", "detail" => detail}} =
                 search(path, %{"query" => "429"})

        refute detail =~ "Rate-Limit"
      end)

    assert log =~ "Rate-Limit"
    assert {:error, %{"code" => "upstream-error"}} = search(path, %{"query" => "500"})
  end

  test "Timeout ergibt upstream-timeout" do
    path = start(fn _req -> :hang end, %{timeout: 300})
    assert {:error, %{"code" => "upstream-timeout"}} = search(path, %{"query" => "x"})
  end

  test "nicht erreichbare API ergibt upstream-error" do
    {:ok, l} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)

    path =
      socket_listen(
        %{
          credentials: %{"BRAVE_API_KEY" => @key},
          base_url: "http://127.0.0.1:#{port}/",
          timeout: 500
        },
        fn -> :ok end
      )

    assert {:error, %{"code" => "upstream-error"}} = search(path, %{"query" => "x"})
  end

  test "Key steht in keinem Log und keiner Fehlerantwort" do
    previous = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous) end)

    {replies, log} =
      with_log([level: :debug], fn ->
        path =
          start(fn req ->
            case Regex.run(~r/q=(\w+)/, req.target) do
              [_, "hang"] -> :hang
              [_, "ok"] -> {200, body([item("t", "https://example.org", "d")])}
              [_, "json"] -> {200, "nicht json"}
              [_, status] -> {String.to_integer(status), ~s({"key":"x"})}
            end
          end)

        for q <- ~w(ok json 401 403 429 500 hang),
            do: search(path, %{"query" => q})
      end)

    assert log =~ "sidecar=komki-web/1"
    refute log =~ @key
    refute inspect(replies) =~ @key
    assert Enum.count(replies, &match?({:error, _}, &1)) == 6
  end

  test "Zustand verbirgt den Key in inspect" do
    {:ok, state} =
      Connector.init(%{
        credentials: %{"BRAVE_API_KEY" => @key}
      })

    assert state.api_key.() == @key
    refute inspect(state) =~ @key
    refute inspect(state, structs: false) =~ @key
    refute IO.iodata_to_binary(:io_lib.format(~c"~p", [state])) =~ @key
  end

  test "mit Proxy laeuft HTTPS per CONNECT ueber den Proxy, ohne Key im Klartext" do
    {proxy_port, stop_proxy} = MockHttp.start(nil, raw: true)

    path =
      socket_listen(
        %{
          credentials: %{"BRAVE_API_KEY" => @key},
          base_url: "https://api.search.brave.com/",
          proxy: {~c"127.0.0.1", proxy_port},
          profile: :kmw_test_proxy,
          timeout: 2_000
        },
        stop_proxy
      )

    assert {:error, %{"code" => code}} = search(path, %{"query" => "x"})
    assert code in ["upstream-error", "upstream-timeout"]
    assert_received {:mock_request, req}
    assert req.method == "CONNECT"
    assert req.target == "api.search.brave.com:443"
    refute inspect(req) =~ @key
  end
end
