defmodule KomkiConnectorWeb.UnitsTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorWeb.{Brave, CLI, Http, Text}

  test "Text.clean entfernt Tags, dekodiert Entities, normalisiert Leerraum" do
    assert Text.clean("a <strong>b</strong>\n\t c", 100) == "a b c"
    assert Text.clean("&lt;script&gt; &amp;&#228;&#xE4;&nbsp;&apos;", 100) == "<script> &ää '"
    assert Text.clean("&unbekannt; &#0; &#xD800;", 100) == "&unbekannt; &#0; &#xD800;"
    assert Text.clean("äöü" <> String.duplicate("x", 10), 4) == "äöüx"
  end

  test "Brave.url baut Pfad und Query relativ zur Basis" do
    assert Brave.url("https://api.search.brave.com/", "a&b=c", 5) ==
             "https://api.search.brave.com/res/v1/web/search?q=a%26b%3Dc&count=5"

    assert Brave.url("http://127.0.0.1:4000/", "x y", 1) ==
             "http://127.0.0.1:4000/res/v1/web/search?q=x%20y&count=1"
  end

  test "Brave.web_url? akzeptiert nur http und https mit Host" do
    assert Brave.web_url?("https://example.org/x")
    assert Brave.web_url?("http://example.org")
    refute Brave.web_url?("ftp://example.org")
    refute Brave.web_url?("javascript:alert(1)")
    refute Brave.web_url?("data:text/html,x")
    refute Brave.web_url?("//example.org")
    refute Brave.web_url?("https://")
  end

  test "Transport.secret_ok? laesst https immer zu, http nur Loopback (#496)" do
    assert KomkiConnector.Transport.secret_ok?(
             "https://api.search.brave.com/res/v1/web/search?q=x"
           )

    assert KomkiConnector.Transport.secret_ok?("http://127.0.0.1:4020/res/v1/web/search?q=x")
    assert KomkiConnector.Transport.secret_ok?("http://localhost:4020/")
    assert KomkiConnector.Transport.secret_ok?("http://[::1]:4020/")
    assert KomkiConnector.Transport.secret_ok?("http://127.8.9.9:4020/")

    # 192.0.2.1: RFC-5737-TEST-NET, garantiert kein Loopback
    refute KomkiConnector.Transport.secret_ok?("http://192.0.2.1:9/")
    refute KomkiConnector.Transport.secret_ok?("http://websuche.example/")
    refute KomkiConnector.Transport.secret_ok?("ftp://127.0.0.1:4020/")
    refute KomkiConnector.Transport.secret_ok?("https://")
    refute KomkiConnector.Transport.secret_ok?("kein-url")
  end

  test "Brave.headers haengt den Token nur an zulaessige Transporte (#496)" do
    assert {:ok, headers} = Brave.headers("https://api.search.brave.com/", "schluessel")
    assert {~c"x-subscription-token", ~c"schluessel"} in headers

    assert {:ok, headers} = Brave.headers("http://127.0.0.1:4020/", "schluessel")
    assert {~c"x-subscription-token", ~c"schluessel"} in headers

    assert {:error, :cleartext} = Brave.headers("http://192.0.2.1:9/", "schluessel")
    assert {:error, :cleartext} = Brave.headers("http://websuche.example/", "schluessel")
  end

  test "CLI.parse lehnt http zu fremden Hosts ab, Loopback bleibt erlaubt (#496)" do
    assert {:error, reason} =
             CLI.parse(["--socket", "/tmp/w.sock", "--base-url", "http://websuche.example/"])

    assert reason =~ "https"

    assert {:error, _} =
             CLI.parse(["--socket", "/tmp/w.sock", "--base-url", "http://192.0.2.1:9/"])

    assert {:ok, %{base_url: "http://localhost:4020/"}} =
             CLI.parse(["--socket", "/tmp/w.sock", "--base-url", "http://localhost:4020/"])
  end

  test "Proxy-Option wird gebildet: nur https_proxy, ohne Proxy keine Option" do
    assert {:ok, {~c"127.0.0.1", 8123}} = CLI.parse_proxy("127.0.0.1:8123")
    assert {:ok, nil} = CLI.parse_proxy(nil)
    assert {:error, _} = CLI.parse_proxy("127.0.0.1")
    assert {:error, _} = CLI.parse_proxy("127.0.0.1:0")
    assert {:error, _} = CLI.parse_proxy(":80")
    assert {:error, _} = CLI.parse_proxy("h:80x")

    assert Http.proxy_options({~c"127.0.0.1", 8123}) == [
             https_proxy: {{~c"127.0.0.1", 8123}, []}
           ]

    assert Http.proxy_options(nil) == []
  end

  test "CLI.parse: Socket Pflicht, Default-Basis, unbekannte Argumente abgewiesen" do
    assert {:ok, %{socket: "/tmp/w.sock", proxy: nil, base_url: "https://api.search.brave.com/"}} =
             CLI.parse(["--socket", "/tmp/w.sock"])

    assert {:ok, %{proxy: {~c"127.0.0.1", 9}, base_url: "http://127.0.0.1:1/"}} =
             CLI.parse([
               "--socket",
               "/tmp/w.sock",
               "--proxy",
               "127.0.0.1:9",
               "--base-url",
               "http://127.0.0.1:1/"
             ])

    assert {:error, _} = CLI.parse([])
    assert {:error, _} = CLI.parse(["--socket", "/tmp/w.sock", "--api-key", "x"])
    assert {:error, _} = CLI.parse(["--socket", "/tmp/w.sock", "--base-url", "file:///etc"])
  end

  test "TLS-Optionen pruefen Zertifikat und Hostnamen" do
    opts = Http.ssl_options("api.search.brave.com")
    assert opts[:verify] == :verify_peer
    assert opts[:server_name_indication] == ~c"api.search.brave.com"
    assert is_list(opts[:cacerts]) and opts[:cacerts] != []
    assert is_function(opts[:customize_hostname_check][:match_fun])
  end
end
