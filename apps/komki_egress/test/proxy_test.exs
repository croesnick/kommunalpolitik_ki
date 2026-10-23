defmodule KomkiEgress.ProxyTest do
  # Nicht async: die Tests binden echte Loopback-Ports.
  use ExUnit.Case, async: false

  alias KomkiEgress.Config

  @loopback {127, 0, 0, 1}

  # ---------------------------------------------------------------------
  # Helfer
  # ---------------------------------------------------------------------

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, ip: @loopback)
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # Echo-Upstream auf Loopback: schickt jedes empfangene Paket zurück.
  defp start_upstream do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, ip: @loopback, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      echo(socket)
    end)

    port
  end

  defp echo(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        :ok = :gen_tcp.send(socket, data)
        echo(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  # Startet den Proxy; Logzeilen landen als {:log, record} beim Test.
  defp start_proxy(ports, opts \\ []) do
    test = self()
    {:ok, config} = Config.parse(JSON.encode!(%{"ports" => ports}))
    opts = Keyword.put_new(opts, :log, fn record -> send(test, {:log, record}) end)
    {:ok, pids} = KomkiEgress.start(config, opts)
    on_exit(fn -> KomkiEgress.stop(pids) end)
    :ok
  end

  defp loopback_opts do
    [resolver: fn _host -> {:ok, [@loopback]} end, address_allowed?: fn _ -> true end]
  end

  defp connect(port) do
    {:ok, socket} = :gen_tcp.connect(@loopback, port, [:binary, active: false])
    socket
  end

  defp request(port, data) do
    socket = connect(port)
    :ok = :gen_tcp.send(socket, data)
    socket
  end

  defp read_all(socket, acc \\ "") do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, data} -> read_all(socket, acc <> data)
      {:error, _} -> acc
    end
  end

  defp assert_denied(port, data, reason) do
    socket = request(port, data)
    assert "HTTP/1.1 403 Forbidden\r\n" <> _ = read_all(socket)
    assert_receive {:log, %{decision: "deny", reason: ^reason} = record}, 2_000
    record
  end

  defp connect_line(target), do: "CONNECT #{target} HTTP/1.1\r\nHost: #{target}\r\n\r\n"

  # ---------------------------------------------------------------------
  # Erlaubter Tunnel
  # ---------------------------------------------------------------------

  test "erlaubter CONNECT baut einen Tunnel zu genau der geprüften Adresse auf" do
    upstream = start_upstream()
    proxy = free_port()
    target = "upstream.test:#{upstream}"
    start_proxy(%{"#{proxy}" => %{"connector" => "web", "allow" => [target]}}, loopback_opts())

    # Früh mitgeschickte Bytes nach dem Kopf werden mit durchgereicht.
    socket = request(proxy, connect_line("UPSTREAM.test:#{upstream}") <> "frueh")
    assert {:ok, "HTTP/1.1 200 Connection Established\r\n\r\n" <> rest} = :gen_tcp.recv(socket, 0)
    echoed = if rest == "", do: elem(:gen_tcp.recv(socket, 0, 1_000), 1), else: rest
    assert echoed == "frueh"

    :ok = :gen_tcp.send(socket, "ping")
    assert {:ok, "ping"} = :gen_tcp.recv(socket, 0, 1_000)
    :gen_tcp.close(socket)

    assert_receive {:log, record}, 2_000

    assert %{
             decision: "allow",
             port: ^proxy,
             connector: "web",
             address: "127.0.0.1",
             bytes_up: 9,
             bytes_down: 9
           } = record

    assert record.host == target
    assert is_integer(record.duration_ms)
  end

  test "Logzeile enthält keine Inhalte" do
    log =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        KomkiEgress.Log.write(%{port: 1, connector: "web", host: "a.de:443", decision: "deny"})
      end)

    assert %{"event" => "connection", "host" => "a.de:443"} = JSON.decode!(log)

    proxy = free_port()
    start_proxy(%{"#{proxy}" => %{"connector" => "web", "allow" => ["a.de:443"]}})
    record = assert_denied(proxy, "GET http://a.de/geheim?token=x HTTP/1.1\r\n\r\n", :method)
    refute inspect(record) =~ "geheim"
    assert record.host == nil
  end

  test "Idle-Timeout beendet einen stillen Tunnel" do
    upstream = start_upstream()
    proxy = free_port()
    target = "upstream.test:#{upstream}"

    start_proxy(
      %{"#{proxy}" => %{"connector" => "web", "allow" => [target]}},
      loopback_opts() ++ [idle_timeout: 200]
    )

    socket = request(proxy, connect_line(target))
    assert {:ok, "HTTP/1.1 200 Connection Established\r\n\r\n"} = :gen_tcp.recv(socket, 0)
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 2_000)
    assert_receive {:log, %{decision: "allow", bytes_up: 0, bytes_down: 0}}, 2_000
  end

  # ---------------------------------------------------------------------
  # Ablehnungen
  # ---------------------------------------------------------------------

  describe "Ablehnung mit 403" do
    setup do
      web = free_port()
      ris = free_port()

      start_proxy(
        %{
          "#{web}" => %{"connector" => "web", "allow" => ["api.search.brave.com:443"]},
          "#{ris}" => %{"connector" => "ris", "allow" => ["ris.komuna.net:443"]}
        },
        loopback_opts()
      )

      %{web: web}
    end

    test "nicht gelisteter Host", %{web: web} do
      record = assert_denied(web, connect_line("evil.example:443"), :not_allowed)
      assert record.host == "evil.example:443"
    end

    test "gelisteter Host mit anderem Port", %{web: web} do
      assert_denied(web, connect_line("api.search.brave.com:80"), :not_allowed)
    end

    test "Host eines anderen Connector-Ports", %{web: web} do
      record = assert_denied(web, connect_line("ris.komuna.net:443"), :not_allowed)
      assert record.connector == "web"
    end

    test "Klartext-GET und andere Methoden", %{web: web} do
      assert_denied(web, "GET http://api.search.brave.com/ HTTP/1.1\r\n\r\n", :method)
      assert_denied(web, "POST / HTTP/1.1\r\nHost: api.search.brave.com\r\n\r\n", :method)
      assert_denied(web, "connect api.search.brave.com:443 HTTP/1.1\r\n\r\n", :method)
    end

    test "IP-Literale als Host", %{web: web} do
      assert_denied(web, connect_line("127.0.0.1:443"), :ip_literal)
      assert_denied(web, connect_line("[::1]:443"), :ip_literal)
      assert_denied(web, connect_line("169.254.169.254:80"), :ip_literal)
    end

    test "kaputte Request-Zeilen", %{web: web} do
      assert_denied(web, "CONNECT api.search.brave.com:443\r\n\r\n", :malformed)
      assert_denied(web, "CONNECT api.search.brave.com HTTP/1.1\r\n\r\n", :malformed)
      assert_denied(web, "CONNECT api.search.brave.com:443 HTTP/2\r\n\r\n", :malformed)
      assert_denied(web, "\r\n\r\n", :malformed)
    end

    test "Header zu groß", %{web: web} do
      # Genau 8192 Bytes ohne Leerzeile: der Proxy liest alles und lehnt ab,
      # der Puffer wächst nicht unbegrenzt.
      assert_denied(web, String.duplicate("A", 8192), :header_too_large)

      # Größerer Kopf mit Leerzeile: der Proxy hört nach 8 KiB auf zu lesen.
      # Ungelesene Bytes können beim Schließen einen Reset auslösen, daher
      # zählt hier die Logzeile, nicht die Antwort.
      padding = String.duplicate("X-Pad: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\r\n", 300)
      data = "CONNECT api.search.brave.com:443 HTTP/1.1\r\n" <> padding <> "\r\n"
      assert byte_size(data) > 8192
      socket = request(web, data)
      read_all(socket)
      assert_receive {:log, %{decision: "deny", reason: :header_too_large}}, 2_000
    end
  end

  test "Header-Timeout schließt die Verbindung mit 408" do
    proxy = free_port()

    start_proxy(
      %{"#{proxy}" => %{"connector" => "web", "allow" => ["a.de:443"]}},
      header_timeout: 200
    )

    socket = request(proxy, "CONNECT a.de:443 HTTP/1.1\r\n")
    assert "HTTP/1.1 408 Request Timeout\r\n" <> _ = read_all(socket)
    assert_receive {:log, %{decision: "deny", reason: :header_timeout}}, 2_000
  end

  # ---------------------------------------------------------------------
  # DNS-Rebinding
  # ---------------------------------------------------------------------

  describe "DNS-Rebinding" do
    test "localhost löst auf Loopback auf und wird ohne Test-Override abgelehnt" do
      upstream = start_upstream()
      proxy = free_port()
      target = "localhost:#{upstream}"
      start_proxy(%{"#{proxy}" => %{"connector" => "web", "allow" => [target]}})

      record = assert_denied(proxy, connect_line(target), :blocked_address)
      assert record.address == nil
    end

    test "injizierter Resolver auf private Ziele: Standardprüfung lehnt ab" do
      for address <- [
            {127, 0, 0, 1},
            {10, 1, 2, 3},
            {169, 254, 169, 254},
            {0, 0, 0, 0, 0, 0, 0, 1}
          ] do
        proxy = free_port()

        start_proxy(
          %{"#{proxy}" => %{"connector" => "web", "allow" => ["rebind.test:443"]}},
          resolver: fn _ -> {:ok, [address]} end
        )

        assert_denied(proxy, connect_line("rebind.test:443"), :blocked_address)
      end
    end

    test "eine einzige private unter mehreren Adressen reicht zur Ablehnung" do
      proxy = free_port()

      start_proxy(
        %{"#{proxy}" => %{"connector" => "web", "allow" => ["rebind.test:443"]}},
        resolver: fn _ -> {:ok, [{93, 184, 215, 14}, {192, 168, 1, 1}]} end
      )

      assert_denied(proxy, connect_line("rebind.test:443"), :blocked_address)
    end
  end

  # ---------------------------------------------------------------------
  # Upstream-Fehler
  # ---------------------------------------------------------------------

  test "nicht auflösbarer Host und abgewiesener Upstream: 502" do
    proxy = free_port()
    closed = free_port()

    start_proxy(
      %{"#{proxy}" => %{"connector" => "web", "allow" => ["nx.test:443", "down.test:#{closed}"]}},
      resolver: fn
        "nx.test" -> {:error, :nxdomain}
        "down.test" -> {:ok, [@loopback]}
      end,
      address_allowed?: fn _ -> true end
    )

    socket = request(proxy, connect_line("nx.test:443"))
    assert "HTTP/1.1 502 Bad Gateway\r\n" <> _ = read_all(socket)
    assert_receive {:log, %{reason: :resolve_failed}}, 2_000

    socket = request(proxy, connect_line("down.test:#{closed}"))
    assert "HTTP/1.1 502 Bad Gateway\r\n" <> _ = read_all(socket)
    assert_receive {:log, %{reason: :connect_failed}}, 2_000
  end

  # ---------------------------------------------------------------------
  # Netzwerk (standardmäßig ausgeschlossen)
  # ---------------------------------------------------------------------

  @tag :network
  test "echter CONNECT zu api.search.brave.com:443 (nur TCP-Aufbau)" do
    proxy = free_port()
    start_proxy(%{"#{proxy}" => %{"connector" => "web", "allow" => ["api.search.brave.com:443"]}})

    socket = request(proxy, connect_line("api.search.brave.com:443"))

    assert {:ok, "HTTP/1.1 200 Connection Established\r\n\r\n"} =
             :gen_tcp.recv(socket, 0, 15_000)

    :gen_tcp.close(socket)
    assert_receive {:log, %{decision: "allow", address: address}}, 5_000
    assert {:ok, ip} = :inet.parse_address(String.to_charlist(address))
    assert KomkiEgress.Address.public?(ip)
  end
end
