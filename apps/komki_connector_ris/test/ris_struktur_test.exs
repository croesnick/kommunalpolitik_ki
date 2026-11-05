defmodule KomkiConnectorRis.RisStrukturTest do
  use ExUnit.Case, async: true

  alias KomkiConnectorRis.RisStruktur

  test "extrahiert Belegung je Sitzung und TOP ohne Inhalte" do
    dir = tmp_dir()
    write_fixtures(dir)

    profil = RisStruktur.extract(dir)

    # Sitzungen: sortiert nach Id, Gremien als anonyme Indizes (c1 = Bau, c2 =
    # Rat nach alphabetischer Ordnung der echten Namen — nie die Namen selbst).
    assert profil["gremien"] == 2
    [bau, rat] = profil["sitzungen"]
    assert bau["id"] == 50 and bau["gremium"] == "c1"
    assert rat["id"] == 100 and rat["gremium"] == "c2"

    # Teile und Tagesordnungs-TOPs: Flags und Zaehler; Titellaengen nur bei
    # nachweislich oeffentlichen TOPs.
    [oeffentlich, geschuetzt] = rat["teile"]
    refute oeffentlich["protectedpart"]
    assert geschuetzt["protectedpart"]

    [top1, top2] = oeffentlich["tops"]
    assert top1["numbering"] == "1" and top1["documentcount"] == 2
    assert top1["titellaenge"] == String.length("Oeffentlicher Beispiel-Titel")
    assert top2["restricted"]
    refute Map.has_key?(top2, "titellaenge")

    [top3] = geschuetzt["tops"]
    assert top3["restricted"] == false
    refute Map.has_key?(top3, "titellaenge")

    assert rat["dokumente"] == [%{"fileext" => "pdf", "isprotected" => true}]

    # TOP-Details: Zaehler und Gast-Sichtbarkeit, keine Abstimmungsergebnisse.
    details = Map.new(profil["tops"], &{&1["id"], &1})

    assert details["100-1"]["textbloecke"] == 2
    assert details["100-1"]["abstimmungen"] == 1
    assert details["100-1"]["conorderitems"] == 0
    assert details["100-1"]["dokumente"] == [%{"fileext" => "pdf", "guestvisible" => false}]
    assert details["100-1"]["titellaenge"] == String.length("Oeffentlicher Beispiel-Titel")

    assert details["100-2"]["restricted"]
    assert details["100-3"]["textsanddocsvisible"]
    refute Map.has_key?(details["100-2"], "titellaenge")
    refute Map.has_key?(details["100-3"], "titellaenge")

    # TOP ohne belegte Tagesordnung: fail-closed, keine Titellaenge.
    refute Map.has_key?(details["100-9"], "titellaenge")

    # Downloads nach Content-Type, nicht verstandene Endpunkte nur gezaehlt.
    assert profil["downloads"] == ["pdf"]
    assert profil["uebersprungen"]["GET /fulltextsearch"] == 1
    assert profil["uebersprungen"]["GET /meetings/{id}"] == 1

    # Das Profil ist inhaltsfrei: keine Titel, Gremien-, Dokumentnamen, keine
    # Suchterme, keine Abstimmungsfelder.
    json = profil |> :json.encode() |> IO.iodata_to_binary()

    refute json =~ "Beispiel-Titel"
    refute json =~ "Verraterischer"
    refute json =~ "Schutzteil"
    refute json =~ "ohne Tagesordnung"
    refute json =~ "Stadtrat"
    refute json =~ "Bauausschuss"
    refute json =~ "Sitzungsmappe"
    refute json =~ "Anlage-Dateiname"
    refute json =~ "Bahnhofswunde"
    refute json =~ "supergeheim"
    refute json =~ "Sachverhalt"
    refute json =~ "resultyes"
  end

  test "Nicht-JSON-Bodies und unbekannte Download-Typen werden gezaehlt" do
    dir = tmp_dir()

    write_cassette(dir, "1.json", "/meetings/300", "<html>kein JSON</html>")

    write_cassette(dir, "2.json", "/agendaitems/documents/1-2-3", "ROHDATEN",
      headers: [["content-type", "application/octet-stream"]]
    )

    profil = RisStruktur.extract(dir)

    assert profil["sitzungen"] == []
    assert profil["uebersprungen"]["GET /meetings/{id}"] == 1
    assert profil["downloads"] == ["unbekannt"]
  end

  test "Extraktion ist deterministisch" do
    dir = tmp_dir()
    write_fixtures(dir)

    assert RisStruktur.extract(dir) == RisStruktur.extract(dir)
  end

  test "parse_cli meldet fehlende Argumente und Verzeichnisse" do
    assert {:error, usage} = RisStruktur.parse_cli(["--out", "/tmp/x"])
    assert usage =~ "Aufruf"

    assert {:error, missing} = RisStruktur.parse_cli(["--cassette", "/gibt-es-nicht"])
    assert missing =~ "existiert nicht"

    assert {:ok, opts} =
             RisStruktur.parse_cli(["--cassette", System.tmp_dir!(), "--out", "/tmp/p"])

    assert opts[:cassette] == System.tmp_dir!()
  end

  # --- Fixtures -----------------------------------------------------------------

  defp write_fixtures(dir) do
    write_cassette(dir, "1.json", "/meetings/100", meeting_rat())
    write_cassette(dir, "2.json", "/meetings/50", meeting_bau())
    write_cassette(dir, "3.json", "/agendaitems/100-1", top_oeffentlich())
    write_cassette(dir, "4.json", "/agendaitems/100-2", top_restricted())
    write_cassette(dir, "5.json", "/agendaitems/100-3", top_im_schutzteil())
    write_cassette(dir, "6.json", "/agendaitems/100-9", top_ohne_tagesordnung())

    write_cassette(dir, "7.json", "/agendaitems/documents/100-1-9", "ROHDATEN",
      headers: [
        ["content-type", "application/pdf"],
        ["content-disposition", "attachment; filename=\"supergeheim.pdf\""]
      ]
    )

    write_cassette(dir, "8.json", "/fulltextsearch", fulltextsearch_treffer(),
      query: "client=32&searchterm=Bahnhofswunde"
    )

    write_cassette(dir, "9.json", "/meetings/300", "{}", status: 500)
  end

  defp meeting_rat do
    ~s({"id": 100, "meetingdate": "2026-07-21T00:00:00", "num": "3.", "state": 1,
        "committeename": "Gartenstadt Stadtrat",
        "parts": [
          {"protectedpart": false, "agendaitems": [
            {"id": "100-1", "numbering": "1", "restricted": false, "documentcount": 2,
             "downloadallowed": true, "name": "Oeffentlicher Beispiel-Titel"},
            {"id": "100-2", "numbering": "2", "restricted": true, "documentcount": 0,
             "downloadallowed": true, "name": "Verraterischer Geheimtitel"}
          ]},
          {"protectedpart": true, "agendaitems": [
            {"id": "100-3", "numbering": "3", "restricted": false, "documentcount": 1,
             "downloadallowed": false, "name": "Titel im Schutzteil"}
          ]}
        ],
        "documents": [{"fileext": "pdf", "isprotected": true, "id": "77-1",
                       "name": "Sitzungsmappe.pdf"}]})
  end

  defp meeting_bau do
    ~s({"id": 50, "meetingdate": "2026-06-23T00:00:00", "num": "2.", "state": 1,
        "committeename": "Gartenstadt Bauausschuss", "parts": [], "documents": []})
  end

  defp top_oeffentlich do
    ~s({"id": "100-1", "numbering": "1", "restricted": false,
        "textsanddocsvisible": false, "downloadallowed": true,
        "name": "Oeffentlicher Beispiel-Titel",
        "textblocks": [
          {"caption": "Sachverhalt", "content": "PHA+VGV4dGJsb2NrIDE8L3A+", "mmsdataid2": "1"},
          {"caption": "Beschlussvorschlag", "content": "PHA+VGV4dGJsb2NrIDI8L3A+", "mmsdataid2": "2"}
        ],
        "votings": [{"resultyes": 14, "resultno": 2, "resultnone": null, "votingkind": 1,
                     "description": null, "textblocks": [], "attendeecount": null,
                     "consultantscount": null, "entitledtovotecount": null}],
        "conorderitems": [],
        "documents": [{"fileext": "pdf", "guestvisible": false, "id": "100-1-9",
                       "name": "Anlage-Dateiname.pdf", "clientname": "Gartenstadt"}]})
  end

  defp top_restricted do
    ~s({"id": "100-2", "numbering": "2", "restricted": true,
        "textsanddocsvisible": false, "downloadallowed": true,
        "name": "Verraterischer Geheimtitel",
        "textblocks": [], "votings": [], "conorderitems": [], "documents": []})
  end

  defp top_im_schutzteil do
    ~s({"id": "100-3", "numbering": "3", "restricted": false,
        "textsanddocsvisible": true, "downloadallowed": false,
        "name": "Titel im Schutzteil",
        "textblocks": [{"caption": "Sachverhalt", "content": "eA==", "mmsdataid2": "3"}],
        "votings": [], "conorderitems": [], "documents": []})
  end

  defp top_ohne_tagesordnung do
    ~s({"id": "100-9", "numbering": "9", "restricted": false,
        "textsanddocsvisible": false, "downloadallowed": true,
        "name": "Titel ohne Tagesordnung",
        "textblocks": [], "votings": [], "conorderitems": [], "documents": []})
  end

  defp fulltextsearch_treffer do
    ~s({"agendaitems": [{"name": "Bahnhofswunde-Treffer", "restricted": false}],
        "documents": [], "meetingdocuments": []})
  end

  # --- Hilfsgross ----------------------------------------------------------------

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "ris-struktur-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp write_cassette(dir, name, path, body, opts \\ []) do
    cassette = %{
      "request" => %{
        "method" => "GET",
        "path" => path,
        "query" => Keyword.get(opts, :query, :null),
        "headers" => [["accept", "application/json"]]
      },
      "response" => %{
        "status" => Keyword.get(opts, :status, 200),
        "headers" => Keyword.get(opts, :headers, [["content-type", "application/json"]]),
        "body" => body
      }
    }

    File.write!(Path.join(dir, name), IO.iodata_to_binary(:json.encode(cassette)))
  end
end
