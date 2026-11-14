defmodule KomkiConnectorRisTest do
  # Nicht async: das httpc-Profil des Connectors ist knotenweit.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias KomkiConnector.Text
  alias KomkiConnectorRis.RisMock
  alias Sidecar.{Client, Server}

  @search_keys ~w(datum nummer sitzung titel top_id url)
  @show_keys ~w(abrufdatum datum nummer sitzung text titel top_id url)

  # Startet Mock (im gegebenen Modus) und Connector auf einem echten
  # Unix-Socket unter /tmp (macOS: Pfad < 104 Byte).
  defp start_stack(mode, overrides \\ %{}) do
    {mock, port} = RisMock.start(mode)
    base_url = "http://127.0.0.1:#{port}/"
    path = "/tmp/kmX#{System.unique_integer([:positive])}.sock"

    {:ok, cfg} = KomkiConnectorRis.init(Map.merge(%{base_url: base_url}, overrides))
    {:ok, listener} = Server.listen(path)
    token = Sidecar.Token.provision!(path)
    pid = spawn(fn -> Server.accept_loop(listener, KomkiConnectorRis, cfg, token) end)
    :ok = :socket.setopt(listener, {:otp, :controlling_process}, pid)

    on_exit(fn ->
      Process.exit(pid, :kill)
      File.rm(path)
    end)

    %{path: path, base_url: base_url, mock: mock}
  end

  # So ruft auch der Vermittler: die deutschen Texte der komki-Seite.
  defp search(path, params),
    do: Client.call(path, "pdr-s", "search", params, %{}, texts: Text)

  defp show(path, top_id),
    do: Client.call(path, "pdr-v", "show", %{"top_id" => top_id}, %{}, texts: Text)

  defp sessions(path, params),
    do: Client.call(path, "pdr-t", "sessions", params, %{}, texts: Text)

  defp agenda(path, sitzung_id),
    do: Client.call(path, "pdr-a", "agenda", %{"sitzung_id" => sitzung_id}, %{}, texts: Text)

  defp ids(%{"results" => results}), do: Enum.map(results, & &1["top_id"])

  describe "gegen den Mock" do
    setup do
      start_stack(:ok)
    end

    test "ein eingespielter Zustand gilt bis zum Reset", %{path: path, mock: mock} do
      %{"data" => %{"meetings" => [meeting | rest]} = data} = KomkiMock.Server.state(mock)

      top = %{
        "id" => "1001-9",
        "nr" => "9",
        "name" => "Kreisverkehr am Rathausplatz",
        "restricted" => false,
        "text" => "Neu eingespielt."
      }

      meeting = Map.update!(meeting, "tops", &(&1 ++ [top]))
      {:ok, _} = KomkiMock.Server.put_data(mock, %{data | "meetings" => [meeting | rest]})

      assert {:ok, result} = search(path, %{"text" => "Kreisverkehr"})
      assert ids(result) == ["1001-9"]

      {:ok, _} = KomkiMock.Server.reset(mock)
      assert {:ok, %{"results" => []}} = search(path, %{"text" => "Kreisverkehr"})
    end

    test "search findet oeffentliche TOPs in Titel und Text", %{path: path, base_url: base_url} do
      assert {:ok, result} = search(path, %{"text" => "Bahnhofstraße"})
      assert ids(result) == ["1001-1", "1002-1"]

      [first | _] = result["results"]

      assert first == %{
               "top_id" => "1001-1",
               "nummer" => "1",
               "titel" => "Sanierung der Bahnhofstraße",
               "sitzung" => "Sitzung des Stadtrates",
               "datum" => "2026-09-15",
               "url" => base_url <> "guestagendaitems/1001-1"
             }
    end

    test "search ist unabhaengig von Gross- und Kleinschreibung", %{path: path} do
      assert {:ok, r1} = search(path, %{"text" => "SANIERUNG der bahnhofstraße"})
      assert ids(r1) == ["1001-1"]
      assert {:ok, r2} = search(path, %{"text" => "bahnhofstrasse"})
      assert ids(r2) == ["1002-1"]
    end

    test "Restricted-Filter wirkt vor limit, die Anzahl verraet nichts", %{path: path} do
      # Vier TOPs enthalten das Wort; 1001-2 ist restricted, 1002-3 liegt im
      # geschuetzten Sitzungsteil.
      assert {:ok, all} = search(path, %{"text" => "Bahnhofstraße", "limit" => 20})
      assert length(all["results"]) == 2

      assert {:ok, one} = search(path, %{"text" => "Bahnhofstraße", "limit" => 1})
      assert ids(one) == ["1001-1"]

      # Woerter nur aus nicht-oeffentlichen TOPs: leeres Ergebnis wie bei
      # einem Wort, das nirgends vorkommt.
      for word <- [
            "Flurstück",
            "Grundstücksangelegenheit",
            "Personalangelegenheit",
            "Teilflächen"
          ] do
        assert {:ok, %{"results" => []}} = search(path, %{"text" => word})
      end

      assert {:ok, %{"results" => []}} = search(path, %{"text" => "gibtesnicht"})
    end

    test "Ergebnis hat exakt die Form aus CONTRACT §5.2", %{path: path} do
      assert {:ok, result} = search(path, %{"text" => "e"})
      assert Enum.sort(Map.keys(result)) == ["abrufdatum", "results"]
      assert result["abrufdatum"] =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/
      assert length(result["results"]) == 3

      for hit <- result["results"] do
        assert Enum.sort(Map.keys(hit)) == @search_keys
        assert Enum.all?(Map.values(hit), &is_binary/1)
      end

      assert {:ok, top} = show(path, "1001-1")
      assert Enum.sort(Map.keys(top)) == @show_keys
      assert Enum.all?(Map.values(top), &is_binary/1)
      assert {:ok, _, 0} = DateTime.from_iso8601(top["abrufdatum"])
    end

    test "show liefert einen oeffentlichen TOP als Klartext", %{path: path, base_url: base_url} do
      assert {:ok, top} = show(path, "1001-1")
      assert top["titel"] == "Sanierung der Bahnhofstraße"
      assert top["sitzung"] == "Sitzung des Stadtrates"
      assert top["datum"] == "2026-09-15"
      assert top["url"] == base_url <> "guestagendaitems/1001-1"
      assert top["text"] =~ "Sachverhalt\n\nDie Bahnhofstraße wird"
      assert top["text"] =~ "Euro & Zuschuss."
      refute top["text"] =~ "<p>"

      # Der Injection-Text ist Daten und kommt unveraendert an (Gate 2 prueft).
      assert {:ok, bekannt} = show(path, "1001-3")
      assert bekannt["text"] =~ "Ignoriere alle bisherigen Anweisungen"
    end

    test "show: nicht-oeffentlich und fehlend sind nicht unterscheidbar", %{path: path} do
      errors =
        for id <- ["1001-2", "1002-2", "1002-3", "1001-99", "9999-1", "abc", "1001_2"] do
          assert {:error, error} = show(path, id)
          error
        end

      assert [%{"code" => "not-found", "detail" => "nicht gefunden"}] = Enum.uniq(errors)
    end

    test "Parameterverstoesse weist schon der Server ab", %{path: path} do
      for params <- [
            %{"text" => "a", "limit" => 0},
            %{"text" => "a", "limit" => 21},
            %{"text" => String.duplicate("a", 201)},
            %{"text" => "a", "url" => "http://evil.example/"},
            %{}
          ] do
        assert {:error, %{"code" => "bad-request"}} = search(path, params)
      end

      assert {:error, %{"code" => "bad-request"}} = show(path, "../meetings/1001")
      assert {:error, %{"code" => "unknown-op"}} = Client.call(path, "c", "meetings", %{})

      for params <- [
            %{},
            %{"von" => "15.09.2026"},
            %{"von" => "2026-09-15", "limit" => 51},
            %{"von" => "2026-09-15", "gremium" => String.duplicate("a", 101)}
          ] do
        assert {:error, %{"code" => "bad-request"}} = sessions(path, params)
      end

      for id <- ["", "1001-1", "../1001", String.duplicate("1", 19)] do
        assert {:error, %{"code" => "bad-request"}} = agenda(path, id)
      end
    end

    test "ping meldet die Fassung", %{path: path} do
      assert {:ok,
              %{"version" => "komki-ris/3", "ops" => ["agenda", "search", "sessions", "show"]}} =
               Client.call(path, "c", "ping", %{})
    end

    # Ticket #516: find the meeting by date, then read its public agenda.
    test "sessions listet die Sitzungen eines Zeitraums, aelteste zuerst", %{path: path} do
      assert {:ok, %{"results" => results, "abrufdatum" => _}} =
               sessions(path, %{"von" => "2026-07-01", "bis" => "2026-09-30"})

      assert Enum.map(results, & &1["sitzung_id"]) == ["1002", "1001"]

      assert hd(results) == %{
               "sitzung_id" => "1002",
               "sitzung" => "Sitzung des Bau- und Umweltausschusses",
               "gremium" => "Bau- und Umweltausschuss",
               "datum" => "2026-07-10",
               "url" => hd(results)["url"]
             }
    end

    test "sessions: ein Tag, Gremium als Teilstring, Zeitraum geprueft", %{path: path} do
      # The mock ignores the window; the connector filters by date itself.
      assert {:ok, %{"results" => [%{"sitzung_id" => "1001"}]}} =
               sessions(path, %{"von" => "2026-09-15"})

      assert {:ok, %{"results" => [%{"sitzung_id" => "1002"}]}} =
               sessions(path, %{"von" => "2026-01-01", "bis" => "2026-12-31", "gremium" => "BAU"})

      assert {:ok, %{"results" => []}} = sessions(path, %{"von" => "2026-11-17"})

      assert {:error, %{"code" => "bad-request"}} =
               sessions(path, %{"von" => "2026-09-15", "bis" => "2026-09-14"})

      assert {:error, %{"code" => "bad-request"}} =
               sessions(path, %{"von" => "2025-01-01", "bis" => "2026-12-31"})
    end

    test "agenda liefert nur oeffentliche TOPs, ohne Spur der anderen", %{path: path} do
      # 1002-2 is restricted, 1002-3 sits in the protected part.
      assert {:ok, result} = agenda(path, "1002")

      assert Enum.sort(Map.keys(result)) ==
               ~w(abrufdatum datum gremium sitzung sitzung_id tops url)

      assert result["tops"] == [
               %{
                 "top_id" => "1002-1",
                 "nummer" => "1",
                 "titel" => "Neubau Kindergarten St. Josef"
               }
             ]

      assert {:ok, %{"tops" => tops}} = agenda(path, "1001")
      assert Enum.map(tops, & &1["top_id"]) == ["1001-1", "1001-3"]
    end

    test "agenda: unbekannte Sitzung ist not-found", %{path: path} do
      assert {:error, %{"code" => "not-found"}} = agenda(path, "9999")
      assert {:error, %{"code" => "not-found"}} = agenda(path, "0")
    end

    test "Log enthaelt keinen Suchtext", %{path: path} do
      log =
        capture_log(fn ->
          assert {:ok, _} = search(path, %{"text" => "Geheimwort4711"})
          # Der Server loggt nach dem Senden; kurz warten.
          Process.sleep(50)
        end)

      refute log =~ "Geheimwort4711"
    end
  end

  test "Anfragebudget begrenzt die Upstream-Anfragen" do
    # Liste + Sitzung 1001: der Titel steht erst in Sitzung 1002.
    %{path: path} = start_stack(:ok, %{max_requests: 2})
    assert {:ok, %{"results" => []}} = search(path, %{"text" => "Kindergarten"})

    # Liste + beide Sitzungen, kein Budget mehr fuer Textbloecke.
    %{path: path} = start_stack(:ok, %{max_requests: 3})
    assert {:ok, %{"results" => []}} = search(path, %{"text" => "bahnhofstrasse"})
  end

  test "HTTP 500 wird auf upstream-error abgebildet" do
    %{path: path} = start_stack(:error500)
    assert {:error, %{"code" => "upstream-error"}} = search(path, %{"text" => "x"})
    assert {:error, %{"code" => "upstream-error"}} = show(path, "1001-1")
  end

  # Ticket #515: after the RIS moved, the old address answered every list
  # request with 404 ("Tenant unknown"), and search reported "no hits".
  test "404 auf die Sitzungsliste ist upstream-error, nicht leere Treffer" do
    empty = Path.join(System.tmp_dir!(), "kmris-leer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(empty)
    on_exit(fn -> File.rm_rf(empty) end)

    %{path: path} = start_stack({:replay, empty})
    assert {:error, %{"code" => "upstream-error"}} = search(path, %{"text" => "x"})
  end

  test "Zeitueberschreitung wird auf upstream-timeout abgebildet" do
    %{path: path} = start_stack(:slow, %{timeout_ms: 300})
    assert {:error, %{"code" => "upstream-timeout"}} = search(path, %{"text" => "x"})
    assert {:error, %{"code" => "upstream-timeout"}} = show(path, "1001-1")
  end

  test "nicht erreichbares RIS ergibt upstream-error" do
    {:ok, cfg} = KomkiConnectorRis.init(%{base_url: "http://127.0.0.1:1/"})

    assert {:error, "upstream-error", _} =
             KomkiConnectorRis.handle_op("show", %{"top_id" => "1-1"}, %{}, cfg)
  end

  # Ticket #148: like the real API, the mock withholds texts from guests
  # (guest_texts false); only the signed-in endpoints carry them.
  describe "mit Anmeldung" do
    @zugang JSON.encode!(%{
              "login" => "ratsmitglied@komki.example",
              "password" => "mock-passwort"
            })

    defp signed_in_stack(zugang \\ @zugang) do
      stack = start_stack(:ok, %{credentials: %{"RIS_ZUGANG" => zugang}})
      without_guest_texts(stack.mock)
      stack
    end

    defp without_guest_texts(mock) do
      %{"data" => data} = KomkiMock.Server.state(mock)
      {:ok, _} = KomkiMock.Server.put_data(mock, Map.put(data, "guest_texts", false))
    end

    test "ohne Anmeldung fehlen die Texte, mit Anmeldung sind sie da" do
      guest = start_stack(:ok)
      without_guest_texts(guest.mock)
      assert {:ok, %{"text" => ""}} = show(guest.path, "1001-1")
      assert {:ok, result} = search(guest.path, %{"text" => "Bahnhofstraße"})
      assert ids(result) == ["1001-1"]

      %{path: path} = signed_in_stack()
      assert {:ok, %{"text" => text}} = show(path, "1001-1")
      assert text =~ "zwei Bauabschnitten"
      assert {:ok, result} = search(path, %{"text" => "Bahnhofstraße"})
      assert ids(result) == ["1001-1", "1002-1"]
    end

    test "angemeldet bleiben nicht-oeffentliche TOPs unsichtbar" do
      %{path: path} = signed_in_stack()

      assert {:ok, %{"results" => []}} = search(path, %{"text" => "Flurstück"})
      assert {:ok, result} = search(path, %{"text" => "Bahnhofstraße", "limit" => 20})
      assert ids(result) == ["1001-1", "1002-1"]

      for top_id <- ["1001-2", "1002-2", "1002-3", "1001-9"] do
        assert {:error, %{"code" => "not-found"}} = show(path, top_id)
      end
    end

    test "angemeldet liest der Connector die angemeldeten Endpunkte" do
      %{path: path, mock: mock} = signed_in_stack()
      assert {:ok, _} = show(path, "1001-1")

      paths = mock |> KomkiMock.Server.log() |> Enum.map(& &1["path"])
      assert "/auth" in paths
      assert "/meetings/1001" in paths
      assert "/agendaitems/1001-1" in paths
      refute "/guestagendaitems/1001-1" in paths
    end

    # A failed sign-in must not take the rest of `komki up` down with it, and
    # must not fall back to guest mode either: every operation answers
    # credential-missing, the reason goes to the log once, without values.
    defp failed_sign_in(base_url, zugang) do
      log =
        capture_log(fn ->
          {:ok, cfg} =
            KomkiConnectorRis.init(%{base_url: base_url, credentials: %{"RIS_ZUGANG" => zugang}})

          send(self(), {:cfg, cfg})
        end)

      assert_received {:cfg, cfg}
      {cfg, log}
    end

    test "abgelehnte Anmeldung: Start ja, jede Operation credential-missing, keine Werte" do
      {mock, port} = RisMock.start(:ok)

      falsch =
        JSON.encode!(%{"login" => "ratsmitglied@komki.example", "password" => "Geheim4711"})

      {cfg, log} = failed_sign_in("http://127.0.0.1:#{port}/", falsch)

      assert log =~ "RIS-Anmeldung fehlgeschlagen"
      refute log =~ "Geheim4711"
      refute log =~ "ratsmitglied@"
      refute inspect(cfg) =~ "Geheim4711"

      for {op, params} <- [
            {"show", %{"top_id" => "1001-1"}},
            {"search", %{"text" => "Bahnhofstraße", "limit" => 5}}
          ] do
        assert {:error, "credential-missing", _} =
                 KomkiConnectorRis.handle_op(op, params, %{}, cfg)
      end

      # No silent guest fallback: after the failed login nothing reaches the RIS.
      paths = mock |> KomkiMock.Server.log() |> Enum.map(& &1["path"])
      assert paths == ["/auth"]
    end

    test "unvollstaendiger Zugang: Hinweis auf komki secret set ris" do
      {_mock, port} = RisMock.start(:ok)

      for zugang <- ["kein json", ~s({"login": "a"}), ~s({"login": "", "password": "x"})] do
        {cfg, log} = failed_sign_in("http://127.0.0.1:#{port}/", zugang)
        assert log =~ "komki secret set ris"

        assert {:error, "credential-missing", _} =
                 KomkiConnectorRis.handle_op("show", %{"top_id" => "1001-1"}, %{}, cfg)
      end
    end

    test "RIS beim Start nicht erreichbar: Start ja, Operationen credential-missing" do
      {cfg, log} = failed_sign_in("http://127.0.0.1:1/", @zugang)
      assert log =~ "RIS nicht erreichbar"

      assert {:error, "credential-missing", _} =
               KomkiConnectorRis.handle_op("show", %{"top_id" => "1001-1"}, %{}, cfg)
    end

    test "abgelaufenes Token: Fehler statt neuer Anmeldung" do
      %{path: path, mock: mock} = signed_in_stack()
      %{"data" => data} = KomkiMock.Server.state(mock)
      account = Map.put(data["account"], "token", "neues-token")
      {:ok, _} = KomkiMock.Server.put_data(mock, Map.put(data, "account", account))

      assert {:error, %{"code" => "credential-missing"}} = show(path, "1001-1")
      auth_calls = mock |> KomkiMock.Server.log() |> Enum.count(&(&1["path"] == "/auth"))
      assert auth_calls == 1
    end

    test "Passwort und Token erscheinen weder im Zustand noch im Log" do
      {_mock, port} = RisMock.start(:ok)

      log =
        capture_log(fn ->
          {:ok, cfg} =
            KomkiConnectorRis.init(%{
              base_url: "http://127.0.0.1:#{port}/",
              credentials: %{"RIS_ZUGANG" => @zugang}
            })

          refute inspect(cfg) =~ "mock-ris-token"
          refute inspect(cfg) =~ "mock-passwort"
          assert {:ok, _} = KomkiConnectorRis.handle_op("show", %{"top_id" => "1001-1"}, %{}, cfg)
        end)

      refute log =~ "mock-ris-token"
      refute log =~ "mock-passwort"
    end

    test "Anmeldung nur ueber https oder Loopback; sonst geht keine Anfrage raus" do
      {cfg, log} = failed_sign_in("http://ris.example.org/web/", @zugang)
      assert log =~ "nur über https"
      refute log =~ "mock-passwort"

      assert {:error, "credential-missing", _} =
               KomkiConnectorRis.handle_op("show", %{"top_id" => "1001-1"}, %{}, cfg)
    end

    test "expires_at liest den exp-Claim, ohne Claim nil" do
      segment = fn map -> map |> JSON.encode!() |> Base.url_encode64(padding: false) end

      jwt = fn claims ->
        token = Enum.join([segment.(%{"alg" => "none"}), segment.(claims), "signatur"], ".")
        fn -> token end
      end

      assert KomkiConnectorRis.Api.expires_at(jwt.(%{"exp" => 1_794_700_000})) ==
               DateTime.from_unix!(1_794_700_000)

      assert KomkiConnectorRis.Api.expires_at(jwt.(%{"sub" => "x"})) == nil
      assert KomkiConnectorRis.Api.expires_at(fn -> "mock-ris-token" end) == nil
    end
  end
end
