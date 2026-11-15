defmodule Ratsprojekte.CLITest do
  # Talks to a running lock through the admin socket, as `ratsprojekte` does.
  use ExUnit.Case, async: false

  import Ratsprojekte.Betrieb

  alias Ratsprojekte.{CLI, Ort, Schluessel, Sperre}

  # einrichten loads the LaunchAgent; tests replace launchctl.
  defp ohne_launchd, do: [launchagent: fn _home -> :ok end]

  describe "einrichten" do
    test "versiegelt einen Schlüssel, zeigt den Code einmal und startet den Hub" do
      home = home!()
      test = self()

      io = [
        launchagent: fn ^home ->
          send(test, :launchagent)
          :ok
        end
      ]

      assert {text, 0} = CLI.run(["einrichten"], home, provider(home), io)
      assert_received :launchagent
      assert text =~ "komki secret erzeugen ratsprojekte-hub | ratsprojekte connector-token"
      assert text =~ "http://localhost:4100"
      [code] = Regex.run(~r/([A-Z2-7]{4}-){12}[A-Z2-7]{4}/, text, capture: :first)

      assert {:ok, key} = Schluessel.oeffnen(home, provider(home))
      assert {:ok, ^key} = Schluessel.aus_code(code)
      assert {_, 1} = CLI.run(["einrichten"], home, provider(home), ohne_launchd())
    end

    test "scheitert der LaunchAgent, bleibt der Code trotzdem sichtbar" do
      home = home!()
      io = [launchagent: fn _ -> {:error, "launchctl bootstrap (exit 5)"} end]
      assert {text, 1} = CLI.run(["einrichten"], home, provider(home), io)
      assert text =~ ~r/([A-Z2-7]{4}-){12}[A-Z2-7]{4}/
      assert text =~ "exit 5"
    end

    test "verweigert, wenn schon eine Datenbank da ist" do
      home = home!()
      File.write!(Ort.datenbank(home), "")
      assert {text, 1} = CLI.run(["einrichten"], home, provider(home), ohne_launchd())
      assert text =~ "recover"
    end
  end

  describe "über den Verwaltungs-Socket" do
    setup do
      home = home!()
      eingerichtet!(home)
      sperre = sperre!(home)

      start_supervised!(
        {Ratsprojekte.Verwaltung,
         pfad: Ort.verwaltung(home), sperre: sperre, basis_url: fn -> "http://localhost:4100" end}
      )

      %{home: home, sperre: sperre}
    end

    test "open entsperrt und öffnet den Browser mit einem einlösbaren Link", %{
      home: home,
      sperre: sperre
    } do
      assert {"Hub läuft, gesperrt.\n", 0} = CLI.run(["status"], home, provider(home))

      browser = fn link -> send(self(), {:browser, link}) end
      assert {_, 0} = CLI.run(["open"], home, provider(home), browser: browser)
      assert_received {:browser, "http://localhost:4100/zugang/" <> token}
      assert {:ok, _} = Sperre.einloesen(sperre, token)

      assert {"Hub läuft, offen.\n", 0} = CLI.run(["status"], home, provider(home))
      assert {_, 0} = CLI.run(["sperren"], home, provider(home))
      assert Sperre.status(sperre) == :gesperrt
    end

    test "Socket hat die Rechte 0600, unbekannte Zeilen bekommen einen Fehler", %{home: home} do
      assert {:ok, %File.Stat{mode: mode}} = File.stat(Ort.verwaltung(home))
      assert Bitwise.band(mode, 0o777) == 0o600

      {:ok, sock} =
        :gen_tcp.connect({:local, Ort.verwaltung(home)}, 0, [
          :binary,
          packet: :line,
          active: false
        ])

      :ok = :gen_tcp.send(sock, "loeschen\n")
      assert {:ok, "fehler unbekannter Befehl\n"} = :gen_tcp.recv(sock, 0, 2_000)
    end

    test "open ohne Siegel: Fehler ohne Link", %{home: home} do
      File.rm!(Ort.schluessel(home))
      browser = fn link -> send(self(), {:browser, link}) end
      assert {text, 1} = CLI.run(["open"], home, provider(home), browser: browser)
      assert text =~ "nicht eingerichtet"
      refute_received {:browser, _}
    end

    # F21 (#490): Wer am Touch-ID-Dialog nicht unterscheiden kann, ob die
    # eigene Stelle fragt oder ein anderes Programm, gibt statt seiner Freigabe
    # womöglich dessen. Der Prüfcode macht die Anfrage zurechenbar.
    test "oeffnen ohne Prüfcode bekommt keinen Link", %{home: home} do
      {:ok, sock} =
        :gen_tcp.connect({:local, Ort.verwaltung(home)}, 0, [
          :binary,
          packet: :line,
          active: false
        ])

      :ok = :gen_tcp.send(sock, "oeffnen\n")
      assert {:ok, "fehler oeffnen braucht einen Prüfcode" <> _} = :gen_tcp.recv(sock, 0, 2_000)
      :ok = :gen_tcp.close(sock)
    end

    test "oeffnen mit Prüfcode entsperrt wie open", %{home: home, sperre: sperre} do
      {:ok, sock} =
        :gen_tcp.connect({:local, Ort.verwaltung(home)}, 0, [
          :binary,
          packet: :line,
          active: false
        ])

      :ok = :gen_tcp.send(sock, "oeffnen 111222\n")
      assert {:ok, "ok http://localhost:4100/zugang/" <> line} = :gen_tcp.recv(sock, 0, 2_000)
      token = String.trim(line)
      assert {:ok, _} = Sperre.einloesen(sperre, token)
      assert Sperre.status(sperre) == :offen
      :ok = :gen_tcp.close(sock)
    end

    test "open zeigt den Prüfcode im Terminal, bevor der Dialog fragt", %{home: home} do
      browser = fn link -> send(self(), {:browser, link}) end

      io = [
        browser: browser,
        pruefcode: fn text -> send(self(), {:pruefcode, text}) end
      ]

      assert {_, 0} = CLI.run(["open"], home, provider(home), io)
      assert_received {:pruefcode, text}
      assert text =~ ~r/\d{6}/
      assert_received {:browser, _}
    end
  end

  describe "Entsperr-Anfragen gedrosselt (#490)" do
    setup do
      home = home!()
      eingerichtet!(home)
      sperre = sperre!(home, provider: aufzeichner(home, warten: true))

      start_supervised!(
        {Ratsprojekte.Verwaltung,
         pfad: Ort.verwaltung(home), sperre: sperre, basis_url: fn -> "http://localhost:4100" end}
      )

      %{home: home, sperre: sperre}
    end

    # Der Socket serialisiert seine Verbindungen; ein Programm kann aber
    # zeitgleich mit der Sperrseite fragen. Dann weist der Hub klar ab.
    test "während einer laufenden Anfrage weist der Socket weitere klar ab", %{
      home: home,
      sperre: sperre
    } do
      erste = Task.async(fn -> Sperre.oeffnen(sperre, "111222") end)
      assert_receive {:agree, _}

      {:ok, sock} =
        :gen_tcp.connect({:local, Ort.verwaltung(home)}, 0, [
          :binary,
          packet: :line,
          active: false
        ])

      :ok = :gen_tcp.send(sock, "oeffnen 222333\n")

      assert {:ok, "fehler eine Entsperr-Anfrage läuft schon\n"} =
               :gen_tcp.recv(sock, 0, 2_000)

      :ok = :gen_tcp.close(sock)
      send(erste.pid, :freigabe)
      assert {:ok, _} = Task.await(erste, 10_000)
    end

    # Review-Nacharbeit zu #490: `sperren` ist wie `oeffnen` für jedes Programm
    # im Benutzerkonto über den Socket erreichbar. Räumte es den Platz der
    # laufenden Anfrage, bekäme der nächste `oeffnen` statt der Abweisung
    # wieder einen eigenen Dialog samt Link.
    test "sperren über den Socket räumt den Platz einer laufenden Anfrage nicht", %{
      home: home,
      sperre: sperre
    } do
      erste = Task.async(fn -> Sperre.oeffnen(sperre, "111222") end)
      assert_receive {:agree, _}

      {:ok, sperren_sock} =
        :gen_tcp.connect({:local, Ort.verwaltung(home)}, 0, [
          :binary,
          packet: :line,
          active: false
        ])

      :ok = :gen_tcp.send(sperren_sock, "sperren\n")
      assert {:ok, "ok\n"} = :gen_tcp.recv(sperren_sock, 0, 2_000)
      :ok = :gen_tcp.close(sperren_sock)

      {:ok, sock} =
        :gen_tcp.connect({:local, Ort.verwaltung(home)}, 0, [
          :binary,
          packet: :line,
          active: false
        ])

      :ok = :gen_tcp.send(sock, "oeffnen 222333\n")

      # Nach dem Fix kommt die Abweisung sofort. Vor dem Fix hänge die zweite
      # Anfrage an der Dialog-Bremse (fünf Sekunden) und käme dann als voller
      # Link zurück — die sechs Sekunden lassen genau das sichtbar werden.
      assert {:ok, "fehler eine Entsperr-Anfrage läuft schon\n"} =
               :gen_tcp.recv(sock, 0, 6_000)

      :ok = :gen_tcp.close(sock)
      send(erste.pid, :freigabe)
      assert {:ok, _} = Task.await(erste, 10_000)
    end
  end

  test "ohne laufenden Hub sagt open, was zu tun ist" do
    home = home!()
    assert {text, 1} = CLI.run(["open"], home, provider(home))
    assert text =~ "läuft nicht"
  end

  test "recover versiegelt den Schlüssel aus dem Code neu (neuer Mac)" do
    home = home!()
    {text, 0} = CLI.run(["einrichten"], home, provider(home), ohne_launchd())
    [code] = Regex.run(~r/([A-Z2-7]{4}-){12}[A-Z2-7]{4}/, text, capture: :first)
    sperre = sperre!(home)
    {:ok, _} = Sperre.oeffnen(sperre, "111222")
    :ok = Sperre.sperren(sperre)

    # Seal and enclave key gone, as after a restore onto another Mac.
    File.rm!(Ort.schluessel(home))
    File.rm!(Path.join(home, "enclave.key"))

    gets = fn _prompt -> "  " <> String.downcase(code) <> "\n" end
    assert {text, 0} = CLI.run(["recover"], home, provider(home), gets: gets)
    assert text =~ "komki secret erzeugen ratsprojekte-hub"
    assert {:ok, _} = Sperre.oeffnen(sperre, "111222")

    falsch = fn _prompt -> Schluessel.code(Schluessel.neu()) end
    assert {text, 1} = CLI.run(["recover"], home, provider(home), gets: falsch)
    assert text =~ "passt nicht"
  end

  test "connector-token hinterlegt nur einen Hash" do
    home = home!()
    hash = String.duplicate("ab", 32)

    assert {_, 0} =
             CLI.run(["connector-token"], home, provider(home), gets: fn _ -> hash <> "\n" end)

    assert File.read!(Ort.token_hash(home)) == hash <> "\n"

    assert {_, 1} =
             CLI.run(["connector-token"], home, provider(home),
               gets: fn _ -> "klartext-token\n" end
             )

    assert File.read!(Ort.token_hash(home)) == hash <> "\n"

    # Empty stdin: the komki in PATH failed (older version without `erzeugen`).
    assert {text, 1} = CLI.run(["connector-token"], home, provider(home), gets: fn _ -> :eof end)
    assert text =~ "nichts auf stdin"
  end

  test "zu langes Home: verständlicher Fehler statt Absturz" do
    lang = Path.join(home!(), String.duplicate("x", 90))
    assert {text, 1} = CLI.run(["status"], lang, nil)
    assert text =~ "zu lang"
    assert_raise ArgumentError, ~r/zu lang/, fn -> Ratsprojekte.Ort.anlegen!(lang) end
  end

  test "unbekannter Befehl: Aufruf, Exit 2" do
    assert {"Aufruf:" <> _, 2} = CLI.run(["start"], home!(), nil)
  end
end
