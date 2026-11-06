defmodule KomkiConnectorRis.RisGartenstadtTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorRis.GartenstadtDaten
  alias KomkiConnectorRis.RisGartenstadt
  alias KomkiConnectorRis.RisSkeleton

  @realbericht Path.expand("../priv/skeletons/20261101T112819Z.json", __DIR__)
  @fixtures Path.expand("../test/fixtures/gartenstadt", __DIR__)
  @gast_detail_endpunkte [
    "GET /guestagendaitems/{meetingId-agendaId}",
    "GET /guestmeetings/{id}"
  ]

  test "Auswahl nach Abdeckung: fuenf Sitzungen mit Kassetten, Liste mit allen" do
    dir = tmp_dir()
    assert {:ok, ^dir, 97} = RisGartenstadt.generate(out: dir)
    assert length(File.ls!(dir)) == 97

    # Agendas only for the selection, in both guest and auth views.
    assert length(tops_aus(dir, ~r/-get-meetings-\d+\.json$/)) == 39
    assert dir |> File.ls!() |> Enum.count(&Regex.match?(~r/-get-meetings-\d+\.json$/, &1)) == 5

    # The guest list carries all 33 meetings of the profile (observed length).
    [liste] = dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, "-get-guestmeetings.json"))
    kassette = liste |> Path.expand(dir) |> File.read!() |> :json.decode()
    body = kassette["response"]["body_b64"] |> Base.decode64!() |> :json.decode()
    assert length(body["items"]) == 33
  end

  test "zwei Laeufe erzeugen byteidentische Kassetten" do
    a = tmp_dir()
    b = tmp_dir()

    {:ok, _, _} = RisGartenstadt.generate(out: a)
    {:ok, _, _} = RisGartenstadt.generate(out: b)

    dateien = a |> File.ls!() |> Enum.sort()
    assert dateien == b |> File.ls!() |> Enum.sort()

    Enum.each(dateien, fn name ->
      assert File.read!(Path.join(a, name)) == File.read!(Path.join(b, name))
    end)
  end

  test "der committete Fixture-Satz ist regenerierbar" do
    dir = tmp_dir()
    {:ok, _dir, _n} = RisGartenstadt.generate(out: dir)

    dateien = dir |> File.ls!() |> Enum.sort()
    assert dateien == @fixtures |> File.ls!() |> Enum.sort()

    Enum.each(dateien, fn name ->
      assert File.read!(Path.join(dir, name)) == File.read!(Path.join(@fixtures, name)), name
    end)
  end

  test "Formate stimmen mit dem echten Skelett-Bericht ueberein" do
    dir = tmp_dir()
    {:ok, _dir, _n} = RisGartenstadt.generate(out: dir)

    synth = RisSkeleton.extract(dir)
    real = @realbericht |> File.read!() |> :json.decode()

    assert Enum.sort(Map.keys(synth["endpoints"]) -- @gast_detail_endpunkte) == [
             "GET /agendaitems/documents/{meetingId-agendaId-docId}",
             "GET /agendaitems/{meetingId-agendaId}",
             "GET /committees",
             "GET /fulltextsearch",
             "GET /guestmeetings",
             "GET /meetings/{id}",
             "POST /auth"
           ]

    assert Enum.sort(@gast_detail_endpunkte -- Map.keys(synth["endpoints"])) == []

    # The real report is the contract for every endpoint it knows: query
    # keys, header names, and the key set of the response body must match.
    vertrag = Map.keys(real["endpoints"])

    Enum.each(Map.keys(synth["endpoints"]), fn name ->
      if name in vertrag do
        s = synth["endpoints"][name]
        r = real["endpoints"][name]

        assert s["query_keys"] == r["query_keys"], name
        assert Enum.sort(s["request_headers"]) == Enum.sort(r["request_headers"]), name
        assert Enum.sort(s["response_headers"]) == Enum.sort(r["response_headers"]), name

        assert MapSet.equal?(schluessel(s["response_body"]), schluessel(r["response_body"])),
               name
      end
    end)

    # Inferred guest detail endpoints (deliberately open, #313): header
    # names as in the real guest list, without authorization.
    gast = real["endpoints"]["GET /guestmeetings"]

    Enum.each(@gast_detail_endpunkte, fn name ->
      s = synth["endpoints"][name]

      assert Enum.sort(s["request_headers"]) == Enum.sort(gast["request_headers"]), name
      assert Enum.sort(s["response_headers"]) == Enum.sort(gast["response_headers"]), name
    end)

    # Text blocks are base64-HTML or empty, as in the real RIS.
    top = synth["endpoints"]["GET /agendaitems/{meetingId-agendaId}"]["response_body"]

    assert top["keys"]["textblocks"]["items"]["keys"]["content"]["formats"] == [
             "base64-html",
             "text"
           ]
  end

  test "Compare gegen den echten Skelett-Bericht: kein Drift" do
    dir = tmp_dir()
    {:ok, _dir, _n} = RisGartenstadt.generate(out: dir)

    real = @realbericht |> File.read!() |> :json.decode()

    # Expected are only the endpoints this recording does not know: the
    # inferred guest details and the download (session 20261105).
    assert RisSkeleton.compare(real, RisSkeleton.extract(dir)) == [
             "Endpunkt nur in rechts: GET /agendaitems/documents/{meetingId-agendaId-docId}",
             "Endpunkt nur in rechts: GET /guestagendaitems/{meetingId-agendaId}",
             "Endpunkt nur in rechts: GET /guestmeetings/{id}"
           ]
  end

  test "Inhalte sind Gartenstadt, nie Buchloe" do
    dir = tmp_dir()
    {:ok, _dir, _n} = RisGartenstadt.generate(out: dir)

    korpus =
      dir
      |> File.ls!()
      |> Enum.map_join(&File.read!(Path.join(dir, &1)))

    assert korpus =~ "Gartenstadt"
    refute korpus =~ "Buchloe"
    refute korpus =~ "Gansbichl"
    refute korpus =~ "Bauturbo"
  end

  test "Sonderfaelle: Zaehltest, Fail-closed und Injection" do
    dir = tmp_dir()
    {:ok, _dir, _n} = RisGartenstadt.generate(out: dir)

    # Guest and auth views of the agendas are consistent.
    gast_tops = tops_aus(dir, ~r/-get-guestmeetings-\d+\.json$/)
    auth_tops = tops_aus(dir, ~r/-get-meetings-\d+\.json$/)

    assert Enum.map(gast_tops, &{&1["name"], &1["restricted"]}) ==
             Enum.map(auth_tops, &{&1["name"], &1["restricted"]})

    # Three TOPs carry the test street in their title: one public and two
    # non-public (protected part and the deliberate
    # restricted-in-unprotected-part case); a fourth, public one carries it
    # only in the text - four search hits in total.
    lindenalle = Enum.filter(gast_tops, &String.contains?(&1["name"], "Lindenallee"))

    assert length(lindenalle) == 3
    assert Enum.count(lindenalle, & &1["restricted"]) == 2
    assert Enum.count(lindenalle, &(!&1["geschuetzt"] and &1["restricted"])) == 1

    # Rosenhang-West appears only in one non-public TOP.
    rosenhang = Enum.filter(gast_tops, &String.contains?(&1["name"], "Rosenhang-West"))

    assert length(rosenhang) == 1
    assert hd(rosenhang)["geschuetzt"]

    # Prompt injection exactly once, in the public text.
    injectionen = injection_tops(dir)

    assert length(injectionen) == 1
    assert hd(injectionen)["restricted"] == false
  end

  test "Suchkassetten: breite Suche, Zaehltest, leere Trefferform" do
    dir = tmp_dir()
    {:ok, _dir, _n} = RisGartenstadt.generate(out: dir)

    suchen =
      dir
      |> File.ls!()
      |> Enum.filter(&Regex.match?(~r/-get-fulltextsearch\.json$/, &1))
      |> Map.new(fn name ->
        kassette = name |> Path.expand(dir) |> File.read!() |> :json.decode()
        body = kassette["response"]["body_b64"] |> Base.decode64!() |> :json.decode()
        {kassette["request"]["query"], length(body["agendaitems"])}
      end)

    assert map_size(suchen) == 3
    assert suchen["client=32&committee=0&searchterm=Beschluss"] == 98
    assert suchen["client=32&committee=0&searchterm=Lindenallee"] == 4
    assert suchen["client=32&committee=0&searchterm=qqxsichtbar"] == 0
  end

  test "Downloads: octet-stream mit PDF-Body und content-disposition" do
    dir = tmp_dir()
    {:ok, _dir, _n} = RisGartenstadt.generate(out: dir)

    dateien =
      dir |> File.ls!() |> Enum.filter(&String.contains?(&1, "-get-agendaitems-documents-"))

    assert length(dateien) == 3

    Enum.each(dateien, fn name ->
      kassette = name |> Path.expand(dir) |> File.read!() |> :json.decode()
      kopf = kassette["response"]["headers"]

      assert Enum.any?(kopf, &(&1 == ["content-type", "application/octet-stream"])), name
      assert Enum.any?(kopf, fn [feld, _wert] -> feld == "content-disposition" end), name

      body = Base.decode64!(kassette["response"]["body_b64"])
      assert String.starts_with?(body, "%PDF-"), name
    end)
  end

  test "restricted-TOPs liegen in geschuetzten Teilen, ein bewusster Fall ausser" do
    dir = tmp_dir()
    {:ok, _dir, _n} = RisGartenstadt.generate(out: dir)
    tops = tops_aus(dir, ~r/-get-meetings-\d+\.json$/)

    # The connector's fail-closed case: exactly one TOP in the unprotected
    # part carries restricted - with the test street in its name.
    uebertritte = Enum.filter(tops, &(!&1["geschuetzt"] and &1["restricted"]))

    assert length(uebertritte) == 1
    assert String.contains?(hd(uebertritte)["name"], "Lindenallee")

    Enum.each(Enum.filter(tops, & &1["restricted"]) -- uebertritte, fn top ->
      assert top["geschuetzt"]
    end)
  end

  test "weigert sich bei nicht leerem Ausgabeverzeichnis" do
    dir = tmp_dir()
    File.write!(Path.join(dir, "rest.json"), "{}")

    assert {:error, meldung} = RisGartenstadt.generate(out: dir)
    assert meldung =~ "nicht leer"
  end

  test "parse_cli prueft die Argumente" do
    assert {:ok, _opts} = RisGartenstadt.parse_cli([])
    assert {:ok, _opts} = RisGartenstadt.parse_cli(["--out", "/tmp/g", "--struktur", "/tmp/s"])
    assert {:error, usage} = RisGartenstadt.parse_cli(["--sitzungen", "5"])
    assert usage =~ "Aufruf"
    assert {:error, _usage} = RisGartenstadt.parse_cli(["--kein-flag"])
  end

  # --- Helpers -----------------------------------------------------------------

  defp schluessel(%{"keys" => keys}), do: keys |> Map.keys() |> MapSet.new()

  # Agenda TOPs from the cassettes that match the pattern: name, restricted
  # flag, and meeting part context.
  defp tops_aus(dir, muster) do
    dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.filter(&Regex.match?(muster, &1))
    |> Enum.flat_map(fn name ->
      kassette = name |> Path.expand(dir) |> File.read!() |> :json.decode()
      body = kassette["response"]["body_b64"] |> Base.decode64!() |> :json.decode()

      Enum.flat_map(body["parts"], fn teil ->
        Enum.map(teil["agendaitems"], &Map.put(&1, "geschuetzt", teil["protectedpart"]))
      end)
    end)
  end

  defp injection_tops(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&Regex.match?(~r/-get-guestagendaitems-\d+-\d+\.json$/, &1))
    |> Enum.flat_map(fn name ->
      kassette = name |> Path.expand(dir) |> File.read!() |> :json.decode()
      body = kassette["response"]["body_b64"] |> Base.decode64!() |> :json.decode()

      text =
        Enum.map_join(body["textblocks"], " ", fn block -> Base.decode64!(block["content"]) end)

      if String.contains?(text, GartenstadtDaten.injection()), do: [body], else: []
    end)
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "ris-gartenstadt-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
