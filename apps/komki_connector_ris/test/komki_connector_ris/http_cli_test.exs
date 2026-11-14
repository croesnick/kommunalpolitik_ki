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
    opts = Http.http_options("https://risapi3.komuna.net/web/meetings/1", 5_000)
    assert opts[:timeout] == 5_000
    assert opts[:connect_timeout] == 5_000
    assert opts[:autoredirect] == false

    ssl = opts[:ssl]
    assert ssl[:verify] == :verify_peer
    assert is_list(ssl[:cacerts]) and ssl[:cacerts] != []
    assert ssl[:server_name_indication] == ~c"risapi3.komuna.net"
    assert is_function(ssl[:customize_hostname_check][:match_fun])

    # Klartext: leere ssl-Option, damit httpc keinen Default ueber
    # cacerts_get (Schluesselbund) berechnet (Labbook L-108).
    assert Keyword.fetch!(Http.http_options("http://127.0.0.1:4010/", 100), :ssl) == []
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

      assert {:ok, "X\n\nA & B ä C"} =
               Top.text(%{"textblocks" => [%{"caption" => "X", "content" => content}]})

      assert Top.date("2026-09-15T18:00:00") == "2026-09-15"
      assert Top.date("15.09.2026") == ""
      assert Top.date(nil) == ""
    end

    test "Tag-Strip ohne Regex: vollstaendige Tags zu Leerzeichen, Rest bleibt (#486)" do
      # Dasselbe Ergebnis wie die alte Regex ~r/<[^>]*>/, ohne deren Klippe:
      # auch ein unvollstaendiges '<' ohne '>' bleibt wortgetreu stehen.
      assert {:ok, "A b x"} =
               Top.text(%{
                 "textblocks" => [%{"content" => Base.encode64("<p>A</p>b<c<d><b>x")}]
               })

      assert {:ok, "a c<d"} =
               Top.text(%{"textblocks" => [%{"content" => Base.encode64("a<b>c<d")}]})

      # Rohtext ohne Base64 (der Hostile-Fall aus #486): linear statt Regex.
      assert {:ok, text} =
               Top.text(%{"textblocks" => [%{"content" => String.duplicate("<", 60_000)}]})

      assert byte_size(text) == 60_000
    end

    test "Byte-Budget: uebergrosse Bloecke werden abgelehnt, nicht verarbeitet (#486)" do
      # Ein Block ueber dem Budget: Ablehnung statt Endlosverarbeitung.
      assert {:error, :budget} =
               Top.text(%{"textblocks" => [%{"content" => String.duplicate("<", 70_000)}]})

      # Drei Bloecke je 64 KiB: Summe 192 KiB, die Antwort passt noch.
      voll = %{"content" => String.duplicate("a", 65_536)}
      assert {:ok, _} = Top.text(%{"textblocks" => [voll, voll, voll]})

      # Der vierte uebersteigt die Summe: Budget-Fehler.
      assert {:error, :budget} = Top.text(%{"textblocks" => [voll, voll, voll, voll]})
    end

    test "Restfrist: text/2 fragt vor jedem Block ab, 0 bricht ab (#486)" do
      test_pid = self()

      remaining = fn ->
        send(test_pid, :frage)
        10_000
      end

      assert {:ok, _} =
               Top.text(
                 %{
                   "textblocks" => [%{"content" => "a"}, %{"content" => "b"}, %{"content" => "c"}]
                 },
                 remaining
               )

      assert_received :frage
      assert_received :frage
      assert_received :frage
      refute_received :frage

      assert {:error, :deadline} = Top.text(%{"textblocks" => [%{"content" => "a"}]}, fn -> 0 end)
    end

    test "C0/C1-Steuerzeichen entfallen aus Text und Feldern (#487)" do
      content = Base.encode64("<p>Farbe \u001B[31mrot\u001B[0m und \u009B99m</p>")

      assert {:ok, text} =
               Top.text(%{"textblocks" => [%{"caption" => "T\u009Bitel", "content" => content}]})

      refute text =~ "\u001B"
      refute text =~ "\u009B"
      assert text =~ "Farbe [31mrot"
      assert text =~ "Titel"

      # Auch die Kurzfelder (Nummer, Titel, Sitzung) verlieren Steuerzeichen.
      assert Top.string("Antrag \u001B[31m") == "Antrag [31m"
      assert Top.string("\u009B") == ""
    end

    test "Feldlaengen kappen mit Marker, Bytes sind keine Zeichen (#487)" do
      assert Top.string(String.duplicate("T", 1_000)) == String.duplicate("T", 1_000)
      assert Top.string(String.duplicate("T", 1_001)) == String.duplicate("T", 1_000) <> "…"

      # 1 401 Bytes, aber nur 700 Zeichen: kein Schnitt.
      zwei_byte = String.duplicate("ü", 700)
      assert Top.string(zwei_byte) == zwei_byte

      # Kuerzeste Form: Kappe faellt nur bei ueber 1 000 Zeichen.
      assert Top.string("") == ""
    end
  end

  describe "Antwortgrenzen (#497)" do
    test "Body ueber 1 MiB: strukturierte Ablehnung statt Materialisierung" do
      :ok = Http.start(nil)

      big =
        %{"items" => String.duplicate("A", 2_097_152)}
        |> :json.encode()
        |> IO.iodata_to_binary()

      {port, _pid} = serve_once(big)

      assert {:error, :too_large} = Http.get_json("http://127.0.0.1:#{port}/x", [], 5_000)
    end

    test "JSON-Tiefe ueber der Grenze wird abgelehnt, Klammern in Strings zaehlen nicht" do
      :ok = Http.start(nil)

      {port_tief, _} = serve_once(String.duplicate("[", 17) <> String.duplicate("]", 17))
      assert {:error, :too_deep} = Http.get_json("http://127.0.0.1:#{port_tief}/x", [], 5_000)

      {port_flach, _} = serve_once(String.duplicate("[", 16) <> String.duplicate("]", 16))
      assert {:ok, term} = Http.get_json("http://127.0.0.1:#{port_flach}/x", [], 5_000)
      assert is_list(term)

      # 20 Klammern in einem String-Wert sind keine Schachtelung.
      {port_string, _} = serve_once(~s({"a": "[[[[[[[[[[[[[[[[[[[["}))
      assert {:ok, %{"a" => _}} = Http.get_json("http://127.0.0.1:#{port_string}/x", [], 5_000)
    end
  end

  describe "CLI.parse" do
    test "Pflicht- und Optionsargumente" do
      assert {:ok, %{socket: "/tmp/s", base_url: "https://risapi3.komuna.net/web/", proxy: nil}} =
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

      # Web-Basis (#518): Default ist die echte Oberflaeche, --web-url stellt um.
      assert {:ok, %{web_base_url: "https://ris.komuna.net/vgbuchloe/"}} =
               CLI.parse(["--socket", "/tmp/s"])

      assert {:ok, %{web_base_url: "https://web.example.org/mandant/"}} =
               CLI.parse(["--socket", "/tmp/s", "--web-url", "https://web.example.org/mandant"])
    end

    test "Fehlerfaelle" do
      assert {:error, _} = CLI.parse([])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--unbekannt", "x"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--base-url", "ftp://x/"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--base-url", "https://x/?a=1"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--web-url", "ftp://x/"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--web-url", "https://x/?a=1"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--proxy", "127.0.0.1"])
      assert {:error, _} = CLI.parse(["--socket", "/tmp/s", "--proxy", "127.0.0.1:70000"])
    end
  end

  # Ein-Antwort-Upstream auf Loopback: dient genau einen Body und schliesst
  # danach (fuer die Antwortgrenzen aus #497).
  defp serve_once(body) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :http_bin, active: false, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listener)
    pid = spawn(fn -> serve_body(listener, body) end)
    :ok = :gen_tcp.controlling_process(listener, pid)
    {port, pid}
  end

  defp serve_body(listener, body) do
    {:ok, sock} = :gen_tcp.accept(listener)
    drain_headers(sock)

    :gen_tcp.send(sock, [
      "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n",
      "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
      body
    ])

    :gen_tcp.close(sock)
  end

  defp drain_headers(sock) do
    case :gen_tcp.recv(sock, 0) do
      {:ok, :http_eoh} -> :ok
      {:ok, _} -> drain_headers(sock)
      other -> other
    end
  end
end
