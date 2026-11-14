defmodule KomkiConnectorRis.RisTagesordnungTest do
  # Nicht async: das httpc-Profil des Connectors ist knotenweit.
  use ExUnit.Case, async: false

  alias KomkiConnectorRis.{RisCassettes, RisMock, RisTagesordnung}

  describe "parse_cli" do
    test "--anmelden traegt keinen Wert, die Reihenfolge ist frei" do
      assert {:ok, %{anmelden: true, datum: ~D[2026-11-17]}} =
               RisTagesordnung.parse_cli(["--datum", "2026-11-17", "--anmelden"])

      assert {:ok, %{anmelden: true, datum: ~D[2026-11-17]}} =
               RisTagesordnung.parse_cli(["--anmelden", "--datum", "2026-11-17"])

      assert {:ok, %{anmelden: false, tresor: "/tmp/komki-tresor"}} =
               RisTagesordnung.parse_cli([
                 "--datum",
                 "2026-11-17",
                 "--tresor",
                 "/tmp/komki-tresor"
               ])

      # mix run gibt das Trennzeichen selbst mit (Aufrufform des Tickets).
      assert {:ok, %{anmelden: true, datum: ~D[2026-11-17]}} =
               RisTagesordnung.parse_cli(["--", "--datum", "2026-11-17", "--anmelden"])
    end

    test "--datum ist Pflicht" do
      assert {:error, usage} = RisTagesordnung.parse_cli(["--anmelden"])
      assert usage =~ "--datum"
      assert {:error, usage} = RisTagesordnung.parse_cli([])
      assert usage =~ "Aufruf"
    end

    test "Datum muss ISO sein" do
      assert {:error, message} = RisTagesordnung.parse_cli(["--datum", "17.11.2026"])
      assert message =~ "17.11.2026"
    end

    test "unbekannte Flags weist das Familien-Geruest ab" do
      assert {:error, _usage} = RisTagesordnung.parse_cli(["--datum", "2026-11-17", "--gremium"])
    end
  end

  describe "gegen den Mock" do
    setup do
      {mock, port} = RisMock.start(:ok)
      %{mock: mock, base_url: "http://127.0.0.1:#{port}/"}
    end

    test "Gast: Tagesordnung eines Tages, keine ungelosten Entities", %{base_url: base_url} do
      {code, meldungen} = RisTagesordnung.run(["--datum", "2026-09-15", "--base-url", base_url])

      assert code == 0

      assert [{:out, gast} | rest] = meldungen
      assert gast =~ "Gast-Modus"

      assert [
               "Sitzung 1001: Sitzung des Stadtrates — 2 öffentliche TOPs",
               top1,
               top3,
               "Texte mit ungelösten HTML-Entities: 0"
             ] = for({:out, line} <- rest, do: line)

      assert top1 =~ "TOP 1 Sanierung der Bahnhofstraße"
      assert top1 =~ "keine ungelösten Entities"
      assert top3 =~ "TOP 3 Bekanntgaben"
    end

    test "zaehlt Texte, nicht Entities: zwei Fundstellen in einem Text ergeben 1", %{
      mock: mock,
      base_url: base_url
    } do
      put_top(mock, %{
        "id" => "1001-5",
        "nr" => "5",
        "name" => "Ehrenamtspreis",
        "restricted" => false,
        "text" => "Der Preis geht an &lorem; e.V. (Vorstandschaft &ipsum; e.V.)"
      })

      {code, meldungen} = RisTagesordnung.run(["--datum", "2026-09-15", "--base-url", base_url])

      assert code == 1

      assert [top5 | _] =
               for({:out, line} <- meldungen, String.contains?(line, "Ehrenamtspreis"), do: line)

      assert top5 =~ "ungelöst: &lorem;, &ipsum;"

      assert List.last(for({:out, line} <- meldungen, do: line)) ==
               "Texte mit ungelösten HTML-Entities: 1"
    end

    test "Sitzungstag ohne Sitzung: klare Meldung", %{base_url: base_url} do
      {code, meldungen} = RisTagesordnung.run(["--datum", "2026-01-01", "--base-url", base_url])

      assert code == 1
      assert [{:err, message}] = meldungen
      assert message =~ "keine öffentliche Sitzung am 2026-01-01"
    end
  end

  describe "mit Anmeldung (Fakes wie ris_cassettes_test)" do
    setup do
      {mock, port} = RisMock.start(:ok)
      dir = Path.join(System.tmp_dir!(), "kmtag-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      %{mock: mock, base_url: "http://127.0.0.1:#{port}/", dir: dir}
    end

    # Zugangssiegel des Mock-Kontos; der Mock prueft login und password
    # gegen seinen Seed (apps/komki_mock/priv/seeds/ris/default.json).
    defp zugang(login \\ "ratsmitglied@komki.example", password \\ "mock-passwort"),
      do: JSON.encode!(%{"login" => login, "password" => password})

    defp tresor!(dir) do
      script = Path.join(dir, "komki-tresor")
      fake = Path.expand("../../komki_cli/test/support/fake_tresor.exs", __DIR__)

      File.write!(script, """
      #!/bin/sh
      exec elixir #{fake} "$@"
      """)

      File.chmod!(script, 0o755)
      script
    end

    # Wie ris_cassettes_test: gefaktes security ohne Keychain — der Wert
    # liegt in einer Datei, ohne Eintrag exit 44 (errSecItemNotFound).
    defp security!(dir, stored \\ nil) do
      script = Path.join(dir, "security")

      File.write!(script, """
      #!/bin/sh
      case "$1" in
        find-generic-password)
          [ -f #{dir}/stored ] || exit 44
          cat #{dir}/stored
          echo
          ;;
      esac
      """)

      File.chmod!(script, 0o755)
      if stored, do: File.write!(Path.join(dir, "stored"), stored)
      script
    end

    test "angemeldet liest die Texte vom angemeldeten Endpunkt", %{
      mock: mock,
      base_url: base_url,
      dir: dir
    } do
      # Als Gast bekommt dieser Mock keine Texte: Nur der angemeldete Lauf
      # kann sie zeigen.
      put_guest_texts(mock, false)

      tresor = tresor!(dir)
      {:ok, sealed} = RisCassettes.tresor_seal(zugang(), tresor: tresor)

      {code, meldungen} =
        RisTagesordnung.run(
          ["--datum", "2026-09-15", "--anmelden", "--base-url", base_url],
          security: security!(dir, sealed),
          tresor: tresor
        )

      assert code == 0

      lines = for({:out, line} <- meldungen, do: line)

      assert List.first(lines) =~ "Sitzung 1001"
      refute List.first(lines) =~ "Gast-Modus"

      assert [top1 | _] = for(line <- lines, String.contains?(line, "Sanierung"), do: line)
      assert top1 =~ "Zeichen, keine ungelösten Entities"
      refute top1 =~ ": 0 Zeichen"
      assert List.last(lines) == "Texte mit ungelösten HTML-Entities: 0"
    end

    test "abgelehnte Anmeldung: Meldung statt Absturz, Exit 1", %{
      base_url: base_url,
      dir: dir
    } do
      tresor = tresor!(dir)
      {:ok, sealed} = RisCassettes.tresor_seal(zugang("falsch", "auch falsch"), tresor: tresor)

      {code, meldungen} =
        RisTagesordnung.run(
          ["--datum", "2026-09-15", "--anmelden", "--base-url", base_url],
          security: security!(dir, sealed),
          tresor: tresor
        )

      assert code == 1
      assert [{:err, message}] = meldungen
      assert message =~ "RIS lehnt die Anmeldung ab"
    end

    test "fehlender Schluesselbund-Eintrag: Meldung statt Absturz, Exit 1", %{
      base_url: base_url,
      dir: dir
    } do
      {code, meldungen} =
        RisTagesordnung.run(
          ["--datum", "2026-09-15", "--anmelden", "--base-url", base_url],
          security: security!(dir),
          tresor: tresor!(dir)
        )

      assert code == 1
      assert [{:err, message}] = meldungen
      assert message =~ "Schlüsselbund-Eintrag 'ris-zugang' fehlt"
    end
  end

  defp put_top(mock, top) do
    %{"data" => %{"meetings" => [meeting | rest]} = data} = KomkiMock.Server.state(mock)
    meeting = Map.update!(meeting, "tops", &(&1 ++ [top]))
    {:ok, _} = KomkiMock.Server.put_data(mock, %{data | "meetings" => [meeting | rest]})
  end

  defp put_guest_texts(mock, flag) do
    %{"data" => data} = KomkiMock.Server.state(mock)
    {:ok, _} = KomkiMock.Server.put_data(mock, Map.put(data, "guest_texts", flag))
  end
end
