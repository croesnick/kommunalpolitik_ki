defmodule KomkiConnectorRis.HttpCliTest do
  # Nicht async: start/1 setzt das knotenweite httpc-Profil neu auf.
  use ExUnit.Case, async: false

  alias KomkiConnectorRis.{CLI, Http, Top}

  describe "Proxy-Option" do
    test "profile_options baut den HTTPS-Proxy fuer :httpc" do
      assert Http.profile_options(nil) == []

      assert Http.profile_options({"127.0.0.1", 49_600}) ==
               [https_proxy: {{~c"127.0.0.1", 49_600}, []}]
    end

    test "start/1 reicht den Proxy an das httpc-Profil durch und setzt ihn zurueck" do
      assert :ok = Http.start({"127.0.0.1", 49_600})

      assert {:ok, [https_proxy: {{~c"127.0.0.1", 49_600}, []}]} =
               :httpc.get_options([:https_proxy], Http.profile())

      assert :ok = Http.start(nil)

      assert {:ok, [https_proxy: {:undefined, []}]} =
               :httpc.get_options([:https_proxy], Http.profile())
    end

    test "init mit --proxy-Wert landet im httpc-Profil" do
      assert {:ok, %{proxy: {"127.0.0.1", 49_601}}} =
               KomkiConnectorRis.init(%{proxy: {"127.0.0.1", 49_601}})

      assert {:ok, [https_proxy: {{~c"127.0.0.1", 49_601}, []}]} =
               :httpc.get_options([:https_proxy], Http.profile())

      assert :ok = Http.start(nil)
    end
  end

  test "HTTPS-Optionen: verify_peer, CA-Zertifikate, Hostname-Pruefung, Timeout" do
    opts = Http.http_options("https://risapi1.komuna.net/web/meetings/1", 5_000)
    assert opts[:timeout] == 5_000
    assert opts[:connect_timeout] == 5_000
    assert opts[:autoredirect] == false

    ssl = opts[:ssl]
    assert ssl[:verify] == :verify_peer
    assert is_list(ssl[:cacerts]) and ssl[:cacerts] != []
    assert ssl[:server_name_indication] == ~c"risapi1.komuna.net"
    assert is_function(ssl[:customize_hostname_check][:match_fun])

    # Klartext: leere ssl-Option, damit httpc keinen Default ueber
    # cacerts_get (Schluesselbund) berechnet (Labbook L-108).
    assert Keyword.fetch!(Http.http_options("http://127.0.0.1:4010/", 100), :ssl) == []
  end

  describe "CLI.parse" do
    test "Pflicht- und Optionsargumente" do
      assert {:ok, %{socket: "/tmp/s", base_url: "https://risapi1.komuna.net/web/", proxy: nil}} =
               CLI.parse(["--socket", "/tmp/s"])

      assert {:ok, %{base_url: "http://127.0.0.1:4010/", proxy: {"127.0.0.1", 49_600}}} =
               CLI.parse([
                 "--socket",
                 "/tmp/s",
                 "--base-url",
                 "http://127.0.0.1:4010",
                 "--proxy",
                 "127.0.0.1:49600"
               ])
    end

    test "Fehlerfaelle" do
      assert {:error, _} = CLI.parse([])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--unbekannt", "x"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--base-url", "ftp://x/"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--base-url", "https://x/?a=1"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--proxy", "127.0.0.1"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--proxy", "127.0.0.1:70000"])
    end
  end

  describe "Top" do
    test "nur restricted: false im ungeschuetzten Teil ist oeffentlich (fail-closed)" do
      meeting = %{
        "parts" => [
          %{"protectedpart" => true, "agendaitems" => [%{"id" => "1-5", "restricted" => false}]},
          %{"agendaitems" => [%{"id" => "1-6", "restricted" => false}]},
          %{
            "protectedpart" => false,
            "agendaitems" => [
              %{"id" => "1-1", "restricted" => false},
              %{"id" => "1-2", "restricted" => true},
              %{"id" => "1-3"},
              %{"id" => "1-4", "restricted" => nil},
              %{"id" => "../x", "restricted" => false}
            ]
          }
        ]
      }

      assert Enum.map(Top.public_items(meeting), & &1["id"]) == ["1-1"]
    end

    test "Text aus Base64-HTML, Entitaeten, Datum" do
      content = Base.encode64("<p>A &amp; B&nbsp;&#228;</p><br/>C")

      assert Top.text(%{"textblocks" => [%{"caption" => "X", "content" => content}]}) ==
               "X\n\nA & B ä C"

      assert Top.date("2026-09-15T18:00:00") == "2026-09-15"
      assert Top.date("15.09.2026") == ""
      assert Top.date(nil) == ""
    end
  end
end
