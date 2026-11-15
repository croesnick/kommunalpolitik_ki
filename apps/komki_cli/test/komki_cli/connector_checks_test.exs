defmodule KomkiCli.ConnectorChecksTest do
  @moduledoc "Doctor checks of the sealed credentials; the keychain is the test seam."

  use ExUnit.Case, async: true

  alias KomkiCli.{Config, ConnectorChecks, TestSupport}
  alias KomkiConnector.Manifest

  defp credential_check(state) do
    cfg = Config.defaults(TestSupport.tmp_area!("komki-checks"))

    cfg
    |> ConnectorChecks.all(fn _service -> state end)
    |> Enum.find(&(&1.name == "credential BRAVE_API_KEY"))
  end

  test "versiegelt: keine Warnung" do
    refute credential_check(:sealed).reason =~ "WARNUNG"
  end

  test "altes Siegel: Warnung mit dem Weg, ohne einen Wert" do
    check = credential_check(:outdated)

    assert check.reason =~ "WARNUNG"
    assert check.reason =~ "ktv1"
    assert check.reason =~ "komki secret set brave"
  end

  describe "ping-Check bei Fassungsdrift (Ticket #553)" do
    # Fake-Connector: echter Listener auf dem (kurz gehaltenen) RIS-Socket,
    # der `ping` mit einer alteren Fassung als das Manifest beantwortet.
    defp ping_listener(socket, answer) do
      Task.async(fn ->
        {:ok, listen} =
          :gen_tcp.listen(0, [
            :binary,
            packet: 4,
            packet_size: Sidecar.Frame.max_bytes(),
            ifaddr: {:local, String.to_charlist(socket)},
            active: false
          ])

        loop(listen, answer)
      end)
    end

    defp loop(listen, answer) do
      case :gen_tcp.accept(listen, 10_000) do
        {:ok, sock} ->
          reply =
            with {:ok, frame} <- :gen_tcp.recv(sock, 0, 5_000),
                 {:ok, %{"call_id" => call_id}} <- Sidecar.Frame.decode(frame) do
              {:ok, bin} = Sidecar.Frame.encode(Sidecar.Frame.ok(call_id, answer))
              bin
            else
              _ -> nil
            end

          if reply, do: :gen_tcp.send(sock, reply)
          :gen_tcp.close(sock)
          loop(listen, answer)

        {:error, _} ->
          :gen_tcp.close(listen)
      end
    end

    test "falsche Fassung: Doctor nennt den naechsten Schritt" do
      # Kurze Basis: der Listener bindet den Socket wirklich (103-Byte-Grenze).
      short = "/tmp/k553d-" <> TestSupport.unique_suffix()
      File.mkdir_p!(short)
      cfg = Config.defaults(short)
      socket = Manifest.socket_path(cfg.base_dir, "ris")
      File.mkdir_p!(Path.dirname(socket))
      listener = ping_listener(socket, %{"version" => "komki-ris/2"})
      Sidecar.Token.provision!(socket)

      try do
        check =
          cfg
          |> ConnectorChecks.all(fn _service -> :sealed end)
          |> Enum.find(&(&1.name == "ping ris"))

        assert check.ok == false
        assert check.reason =~ "falsche Fassung"
        assert check.reason =~ "komki down && komki up"
      after
        Task.shutdown(listener)
        File.rm_rf(short)
      end
    end

    # Ticket #515: Der Connector sondiert seine Gegenstelle beim Start und
    # meldet das Ergebnis auf `ping`. Ohne den Schluessel (Connector ohne
    # Sonde) bleibt der Check unveraendert gruen.
    test "Gegenstelle ok (Ticket #515): Doctor meldet die Sonde" do
      short = "/tmp/k515d-" <> TestSupport.unique_suffix()
      File.mkdir_p!(short)
      cfg = Config.defaults(short)
      socket = Manifest.socket_path(cfg.base_dir, "ris")
      File.mkdir_p!(Path.dirname(socket))
      listener = ping_listener(socket, %{"version" => "komki-ris/3", "upstream" => "ok"})
      Sidecar.Token.provision!(socket)

      try do
        check =
          cfg
          |> ConnectorChecks.all(fn _service -> :sealed end)
          |> Enum.find(&(&1.name == "ping ris"))

        assert check.ok == true
        assert check.reason =~ "komki-ris/3"
        assert check.reason =~ "Gegenstelle ok"
      after
        Task.shutdown(listener)
        File.rm_rf(short)
      end
    end

    test "unbekannte Gegenstelle (Ticket #515): Doctor meldet rot mit festem Text" do
      short = "/tmp/k515e-" <> TestSupport.unique_suffix()
      File.mkdir_p!(short)
      cfg = Config.defaults(short)
      socket = Manifest.socket_path(cfg.base_dir, "ris")
      File.mkdir_p!(Path.dirname(socket))

      listener =
        ping_listener(socket, %{"version" => "komki-ris/3", "upstream" => "upstream-error"})

      Sidecar.Token.provision!(socket)

      try do
        check =
          cfg
          |> ConnectorChecks.all(fn _service -> :sealed end)
          |> Enum.find(&(&1.name == "ping ris"))

        assert check.ok == false
        assert check.reason =~ "falsche Gegenstelle: Fehler beim angebundenen Dienst"
      after
        Task.shutdown(listener)
        File.rm_rf(short)
      end
    end

    test "Connector ohne Sonde (Ticket #515): Check unveraendert gruen" do
      short = "/tmp/k515f-" <> TestSupport.unique_suffix()
      File.mkdir_p!(short)
      cfg = Config.defaults(short)
      socket = Manifest.socket_path(cfg.base_dir, "ris")
      File.mkdir_p!(Path.dirname(socket))
      listener = ping_listener(socket, %{"version" => "komki-ris/3"})
      Sidecar.Token.provision!(socket)

      try do
        check =
          cfg
          |> ConnectorChecks.all(fn _service -> :sealed end)
          |> Enum.find(&(&1.name == "ping ris"))

        assert check.ok == true
        assert check.reason == "komki-ris/3"
      after
        Task.shutdown(listener)
        File.rm_rf(short)
      end
    end
  end
end
