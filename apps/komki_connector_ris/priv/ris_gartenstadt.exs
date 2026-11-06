# Gartenstadt-Generator (Ticket #313): synthetische Kassetten aus
# Strukturprofil und Skelett-Bericht.
#
#     elixir apps/komki_connector_ris/priv/ris_gartenstadt.exs \
#       [--out <verzeichnis>] [--struktur <datei>]
#
# Erzeugt Kassetten im Format des Recorders (priv/ris_recorder.exs), spielbar
# mit mock_ris.exs --mode replay. Vorlage ist das Strukturprofil der Session
# 20261101T112819Z: Die Transkription uebernimmt jede beobachtete Belegung —
# geschuetzte Teile, restricted-Flags, Zaehler fuer Textbloecke, Abstimmungen
# und Dokumente — und fuellt sie mit Inhalten aus dem Universum "Gartenstadt"
# (priv/gartenstadt_daten.exs). Echte Inhalte fliessen nie ein: Der Generator
# liest nur committbare, inhaltsfreie Berichte. Jede Array-Laenge der
# synthetischen Menge ist damit eine im echten RIS beobachtete Laenge, und
# ris_skeleton --compare bleibt kardinalitaetskompatibel.
#
# Kassetten pro Sitzung gibt es nur fuer eine Auswahl nach Abdeckung
# (auswahl/2): so wenige Sitzungen, dass jede beobachtete Belegung einmal
# vorkommt. Gast-Liste und Suchen fuehren alle Sitzungen des Profils, weil
# ihre Laenge Teil des beobachteten Formats ist; Tagesordnungen und TOPs
# ausserhalb der Auswahl antworten im Replay mit 404.
#
# Das Ausgabeverzeichnis muss leer sein (bei Regeneration vorher leeren),
# damit keine Reste frueherer Laeufe liegenbleiben.
#
# Nur OTP, keine Deps — wie die Geschwister-Skripte.

Code.require_file("./gartenstadt_daten.exs", __DIR__)
Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisGartenstadt do
  @moduledoc false

  alias KomkiConnectorRis.GartenstadtDaten, as: Daten

  @usage "Aufruf: [--out <verzeichnis>] [--struktur <datei>]"

  @client 32
  @clientname "Gartenstadt"
  @sitzungs_basis 300_000_000
  @top_basis 400_000_000
  @dokument_basis 500_000

  # Kopfzeilen-Namen wie in den Skelett-Berichten; alle Werte erfunden.
  @anfrage_kopf [
    ["accept", "application/json"],
    ["user-agent", "gartenstadt/1.0"],
    ["x-customname", "gastschnittstelle"],
    ["x-orgkey", "synthetisch"],
    ["x-uniqueid", "00000000-0000-0000-0000-000000000000"]
  ]
  @host_kopfzeile ["host", "ris.gartenstadt.local"]
  @auth_kopfzeile ["authorization", "Bearer gartenstadt-synthese"]

  @antwort_kopf [
    ["content-type", "application/json"],
    ["date", "Thu, 05 Nov 2026 10:00:00 GMT"],
    ["server", "RIS-Mock"],
    ["strict-transport-security", "max-age=31536000"],
    ["x-powered-by", "Gartenstadt"]
  ]

  # Download-Antwort wie das echte RIS (Fund 2026-11-05, #313):
  # application/octet-stream, nicht application/pdf; Dateiname in
  # content-disposition. Kopfnamen folgen dem echten Skelett-Bericht.
  @download_kopf [
    ["content-disposition", "attachment; filename=\"Gartenstadt_Anlage.pdf\""],
    ["content-type", "application/octet-stream"],
    ["date", "Thu, 05 Nov 2026 10:00:00 GMT"],
    ["server", "RIS-Mock"],
    ["strict-transport-security", "max-age=31536000"],
    ["x-powered-by", "Gartenstadt"]
  ]

  # Kleines strukturiertes PDF als Download-Body: bytetreu speicherbar,
  # vollstaendig erfunden.
  @pdf """
  %PDF-1.4
  1 0 obj
  << /Type /Catalog /Pages 2 0 R >>
  endobj
  2 0 obj
  << /Type /Pages /Kids [3 0 R] /Count 1 >>
  endobj
  3 0 obj
  << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
  endobj
  4 0 obj
  << /Length 76 >>
  stream
  BT /F1 12 Tf 72 720 Td (Synthetische Testanlage der Stadt Gartenstadt) Tj ET
  endstream
  endobj
  5 0 obj
  << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
  endobj
  trailer
  << /Size 6 /Root 1 0 R >>
  %%EOF
  """

  @spec generate(keyword()) :: {:ok, Path.t(), non_neg_integer()} | {:error, String.t()}
  def generate(opts \\ []) do
    out = Path.expand(Keyword.get(opts, :out, default_out()))
    struktur = Path.expand(Keyword.get(opts, :struktur, default_struktur()))

    with :ok <- leeres_verzeichnis(out),
         {:ok, vorlage} <- vorlage_laden(struktur) do
      File.mkdir_p!(out)

      details = Map.new(vorlage["tops"], &{&1["id"], &1})
      aktive = gremien_aktiv()

      ausgewaehlt = auswahl(vorlage["sitzungen"], details)

      sitzungen =
        vorlage["sitzungen"]
        |> Enum.with_index(1)
        |> Enum.map(fn {s, nr} -> sitzung_uebersetzen(s, nr, details, aktive) end)
        |> sonderfaelle(ausgewaehlt)

      abgedeckt = Enum.filter(sitzungen, &(&1.vorlage["id"] in ausgewaehlt))

      eintraege =
        [
          auth_eintrag(),
          committees_eintrag(),
          guestmeetings_eintrag(sitzungen)
        ] ++
          Enum.flat_map(abgedeckt, &sitzungs_eintraege/1) ++
          such_eintraege(sitzungen) ++
          download_eintraege(abgedeckt)

      eintraege
      |> Enum.with_index(1)
      |> Enum.each(fn {eintrag, n} -> schreibe(out, n, eintrag) end)

      {:ok, out, length(eintraege)}
    end
  end

  @doc false
  @spec parse_cli([String.t()]) :: {:ok, keyword()} | {:error, String.t()}
  def parse_cli(argv) do
    case parse_flags(argv, []) do
      {:ok, opts} -> {:ok, opts}
      {:error, _} -> {:error, @usage}
    end
  end

  defp parse_flags([], acc), do: {:ok, acc}

  defp parse_flags(["--out", value | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :out, value))

  defp parse_flags(["--struktur", value | rest], acc),
    do: parse_flags(rest, Keyword.put(acc, :struktur, value))

  defp parse_flags(_other, _acc), do: {:error, @usage}

  # --- Vorlage -------------------------------------------------------------------

  defp vorlage_laden(datei) do
    {:ok, :json.decode(File.read!(datei))}
  rescue
    _ -> {:error, "Strukturprofil nicht lesbar: #{datei}"}
  end

  defp leeres_verzeichnis(out) do
    cond do
      not File.exists?(out) -> :ok
      not File.dir?(out) -> {:error, "Ausgabepfad ist keine Verzeichnis: #{out}"}
      File.ls!(out) == [] -> :ok
      true -> {:error, "Ausgabeverzeichnis ist nicht leer: #{out} — vorher leeren"}
    end
  end

  defp gremien_aktiv do
    Daten.gremien()
    |> Enum.with_index(1)
    |> Enum.filter(fn {{_name, aktiv}, _i} -> aktiv end)
    |> Enum.map(fn {{name, _aktiv}, i} -> %{id: i, name: name} end)
  end

  # --- Auswahl nach Abdeckung ---------------------------------------------------------
  #
  # Greedy-Mengenueberdeckung: Immer die Sitzung mit den meisten noch fehlenden
  # Merkmalen, bei Gleichstand die mit weniger TOPs, dann die fruehere im
  # Profil. Schluss, sobald keine Sitzung mehr ein neues Merkmal bringt.

  defp auswahl(vorlagen, details) do
    kandidaten = Enum.map(vorlagen, &{&1["id"], merkmale(&1, details), top_zahl(&1)})
    waehle(kandidaten, MapSet.new(), [])
  end

  defp waehle([], _gedeckt, gewaehlt), do: gewaehlt

  defp waehle(kandidaten, gedeckt, gewaehlt) do
    {id, merkmale, _tops} =
      kandidaten
      |> Enum.with_index()
      |> Enum.max_by(fn {{_id, m, tops}, i} -> {neue(m, gedeckt), -tops, -i} end)
      |> elem(0)

    if neue(merkmale, gedeckt) == 0 do
      gewaehlt
    else
      kandidaten
      |> List.keydelete(id, 0)
      |> waehle(MapSet.union(gedeckt, merkmale), [id | gewaehlt])
    end
  end

  defp neue(merkmale, gedeckt), do: MapSet.size(MapSet.difference(merkmale, gedeckt))

  # Merkmale, die Format oder Verhalten praegen: Teil-Layout und Status der
  # Sitzung; je TOP Sichtbarkeit, Nummernform (der Compare unterscheidet
  # "digits" von "text") und ob ein Feld leer oder belegt ist — Textbloecke
  # mit genauer Zahl, weil sie die Laenge im Compare abdecken.
  defp merkmale(s, details) do
    sitzung = [{:teile, Enum.map(s["teile"], & &1["protectedpart"])}, {:state, s["state"]}]

    tops =
      Enum.flat_map(s["teile"], fn teil ->
        Enum.flat_map(teil["tops"], fn top ->
          d = Map.get(details, top["id"]) || leeres_detail()

          [
            {:restricted, top["restricted"]},
            {:numerisch, Regex.match?(~r/^\d+$/, top["numbering"])},
            {:downloadallowed, top["downloadallowed"]},
            {:documentcount, top["documentcount"] > 0},
            {:textbloecke, d["textbloecke"]},
            {:abstimmungen, d["abstimmungen"] > 0},
            {:conorderitems, d["conorderitems"] > 0},
            {:dokumente, d["dokumente"] != []},
            {:textsanddocsvisible, d["textsanddocsvisible"]}
          ]
        end)
      end)

    MapSet.new(sitzung ++ tops)
  end

  defp top_zahl(s), do: s["teile"] |> Enum.map(&length(&1["tops"])) |> Enum.sum()

  # --- Transkription ----------------------------------------------------------------

  defp sitzung_uebersetzen(s, nr, details, aktive) do
    id = @sitzungs_basis + nr
    gremium = Enum.at(aktive, gremium_index(s) - 1) || hd(aktive)

    {teile, _lauf} =
      Enum.map_reduce(s["teile"], 0, fn teil, lauf ->
        {tops, laauf} =
          Enum.map_reduce(teil["tops"], lauf, fn top, l ->
            {top_uebersetzen(top, teil["protectedpart"], l + 1, id, nr, details), l + 1}
          end)

        {%{protectedpart: teil["protectedpart"], tops: tops}, laauf}
      end)

    %{
      id: id,
      vorlage: s,
      gremium: gremium,
      teile: teile,
      datum: s["datum"],
      nummer: Integer.to_string(nr) <> ".",
      name: sitzungsname(gremium, nr)
    }
  end

  defp gremium_index(s) do
    case s["gremium"] do
      "c" <> ziffer -> max(String.to_integer(ziffer), 1)
      _other -> 1
    end
  end

  # Nummer und Namensmuster sind erfunden: Die echte Sitzungsnummer neben dem
  # echten Datum ergaebe mit dem echten Namensmuster dieselbe Wortfolge wie im
  # RIS (N-Gramm-Fund, #313).
  defp sitzungsname(gremium, nr) do
    kurz = Daten.gremium_kurz(gremium.name)
    "Gartenstadt-" <> kurz <> ", Zusammenkunft Nr. " <> Integer.to_string(nr)
  end

  defp top_uebersetzen(vorlage, geschuetzt, lauf, sitzungs_id, sitzungs_nr, details) do
    detail = Map.get(details, vorlage["id"]) || leeres_detail()

    %{
      vorlage: vorlage,
      detail: detail,
      geschuetzt: geschuetzt,
      lauf: lauf,
      id_paar: "#{sitzungs_id}-#{@top_basis + (sitzungs_nr - 1) * 1000 + lauf}",
      titel: titel(sitzungs_nr * 100 + lauf),
      zusatz_satz: nil,
      restricted_override: false
    }
  end

  defp leeres_detail do
    %{
      "textbloecke" => 0,
      "abstimmungen" => 0,
      "dokumente" => [],
      "conorderitems" => 0,
      "textsanddocsvisible" => false
    }
  end

  # Eigene Wendungen statt der Formeln des echten RIS: Die frueheren Vorlagen
  # trugen echten Wortlaut und fielen im N-Gramm-Abgleich auf (#313). Das Wort
  # Beschlussfassung bleibt, die Breitensuche filtert danach.
  @beschluss " – Vorlage zur Beschlussfassung im Gartenstadt-Gremium"

  defp titel(index) do
    thema = Daten.dreher(Daten.themen(), index)
    strasse = Daten.dreher(Daten.strassen(), index)
    flur = Daten.dreher(Daten.flurstuecke(), index)
    hnr = Daten.dreher(Daten.hausnummern(), index)
    vorname = Daten.dreher(Daten.vornamen(), index)
    nachname = Daten.dreher(Daten.nachnamen(), index)

    case rem(index, 6) do
      0 ->
        "Antrag auf " <> thema

      1 ->
        thema <> @beschluss

      2 ->
        "Gartenhaus-Anfrage von " <>
          vorname <>
          " " <>
          nachname <>
          " zu Flurstück " <>
          flur <>
          ", " <>
          strasse <>
          " " <>
          hnr <>
          @beschluss

      3 ->
        "Neufassung der Ortsregel zur " <> thema <> @beschluss

      4 ->
        "Mitteilungen der Gartenstadt-Verwaltung (zur Kenntnis)"

      _ ->
        "Fragen aus der Gartenstadt-Bürgerrunde: " <> thema <> " (zur Kenntnis)"
    end
  end

  # --- Eintraege ----------------------------------------------------------------------

  defp auth_eintrag do
    anfrage =
      :json.encode(%{"login" => "rathaus@gartenstadt.example", "password" => "gartenschluessel"})

    body = IO.iodata_to_binary(anfrage)

    # Der Login postet einen Body (content-type, content-length) und traegt
    # natuerlich noch keinen authorization-Kopf — die Namen folgen dem echten
    # Skelett-Bericht.
    kopf = [
      ["accept", "application/json"],
      ["content-length", Integer.to_string(byte_size(body))],
      ["content-type", "application/json"],
      @host_kopfzeile,
      ["user-agent", "gartenstadt/1.0"],
      ["x-customname", "gastschnittstelle"],
      ["x-orgkey", "synthetisch"],
      ["x-uniqueid", "00000000-0000-0000-0000-000000000000"]
    ]

    %{
      "method" => "POST",
      "path" => "/auth",
      "query" => nil,
      "anfrage_kopf" => kopf,
      "anfrage_body" => body,
      "antwort_body" => %{"token" => "gartenstadt-synthese-token"}
    }
  end

  defp committees_eintrag do
    items =
      Daten.gremien()
      |> Enum.with_index(1)
      |> Enum.map(fn {{name, _aktiv}, i} ->
        %{
          "clientid" => @client,
          "clientname" => @clientname,
          "id" => i,
          "name" => name,
          "printorder" => Integer.to_string(i)
        }
      end)

    %{
      "method" => "GET",
      "path" => "/committees",
      "query" => "client=" <> Integer.to_string(@client),
      "gast" => false,
      "anfrage_body" => "",
      "antwort_body" => %{"items" => items}
    }
  end

  defp guestmeetings_eintrag(sitzungen) do
    %{
      "method" => "GET",
      "path" => "/guestmeetings",
      "query" => "client=32&from=2026-01-01&until=2026-12-31",
      "gast" => true,
      "anfrage_body" => "",
      "antwort_body" => %{"items" => Enum.map(sitzungen, &gast_sitzung/1)}
    }
  end

  defp gast_sitzung(s) do
    tag = String.slice(s.datum, 0, 10)

    dokumente =
      s.teile
      |> Enum.flat_map(& &1.tops)
      |> Enum.map(& &1.vorlage["documentcount"])
      |> Enum.sum()

    %{
      "absoluteendtime" => tag <> "T20:15:00",
      "absolutestarttime" => tag <> "T18:00:00",
      "calendarshortname" => gremium_kurzform(s.gremium.name),
      "candownloadsummonspdf" => true,
      "clientname" => @clientname,
      "committeename" => s.gremium.name,
      "documentcount" => dokumente,
      "id" => s.id,
      "loc_name" => "Rathaussaal",
      "meetingdate" => s.datum,
      "name" => s.name,
      "opdatetime" => s.datum,
      "state" => s.vorlage["state"],
      "unreadop" => nil,
      "visibility" => 1
    }
  end

  defp gremium_kurzform(name) do
    name |> Daten.gremium_kurz() |> String.slice(0, 2) |> String.upcase()
  end

  defp sitzungs_eintraege(s) do
    [
      %{
        "method" => "GET",
        "path" => "/meetings/#{s.id}",
        "query" => nil,
        "gast" => false,
        "anfrage_body" => "",
        "antwort_body" => sitzungs_body(s)
      },
      %{
        "method" => "GET",
        "path" => "/guestmeetings/#{s.id}",
        "query" => nil,
        "gast" => true,
        "anfrage_body" => "",
        "antwort_body" => sitzungs_gast_body(s)
      }
    ] ++
      Enum.flat_map(alle_tops(s), fn top ->
        [
          %{
            "method" => "GET",
            "path" => "/guestagendaitems/#{top.id_paar}",
            "query" => nil,
            "gast" => true,
            "anfrage_body" => "",
            "antwort_body" => top_body(s, top)
          },
          %{
            "method" => "GET",
            "path" => "/agendaitems/#{top.id_paar}",
            "query" => nil,
            "gast" => false,
            "anfrage_body" => "",
            "antwort_body" => top_body(s, top)
          }
        ]
      end)
  end

  defp alle_tops(s), do: Enum.flat_map(s.teile, & &1.tops)

  # Gast-Sicht der Sitzung (inferiert, Bewusst-offen in #313): Rahmen wie der
  # echte Gast-Endpunkt, Tagesordnung wie meetings/{id} — genau die Felder,
  # die der Connector laut README liest (protectedpart, restricted, name,
  # numbering, id).
  defp sitzungs_gast_body(s) do
    %{
      "id" => s.id,
      "name" => s.name,
      "meetingdate" => s.datum,
      "committeename" => s.gremium.name,
      "state" => s.vorlage["state"],
      "opdatetime" => s.datum,
      "parts" => Enum.map(s.teile, &teil_body/1)
    }
  end

  # --- Sonderfaelle (bewusste Testfaelle, Spiegel des bisherigen Mocks) --------------
  #
  # "Lindenallee" steht in zwei oeffentlichen TOPs (einmal Titel, einmal nur
  # im Text) und in zwei nicht-oeffentlichen: einmal als restricted-TOP im
  # ungeschuetzten Teil — der Fail-closed-Fall, den die reale Datenlage nie
  # zeigt — und einmal im geschuetzten Teil. Das ist der Zaehltest: Die
  # Trefferzahl des Connectors darf nichts verraten. "Rosenhang-West" steht
  # nur in einem nicht-oeffentlichen TOP, die Prompt-Injection nur im
  # oeffentlichen Text.

  defp sonderfaelle(sitzungen, ausgewaehlt) do
    updates =
      sitzungen
      |> Enum.filter(&(&1.vorlage["id"] in ausgewaehlt))
      |> sonderfall_updates()

    Enum.map(sitzungen, fn s ->
      teile =
        Enum.map(s.teile, fn teil ->
          tops =
            Enum.map(teil.tops, fn top ->
              case Map.get(updates, top.id_paar) do
                nil -> top
                aenderung -> Map.merge(top, aenderung)
              end
            end)

          %{teil | tops: tops}
        end)

      %{s | teile: teile}
    end)
  end

  defp sonderfall_updates(sitzungen) do
    paare = Enum.flat_map(sitzungen, fn s -> Enum.map(alle_tops(s), &{s, &1}) end)

    # Datum-absteigend, innerhalb der Sitzung in Tagesordnungs-Reihenfolge:
    # Der Connector liest die neuesten Sitzungen zuerst, und nach 33
    # Tagesordnungsabrufen (auch die 404 ausserhalb der Auswahl kosten
    # Budget) bleibt seinem Restbudget nur Platz fuer wenige Textabfragen.
    # Die Sonderfaelle muessen deshalb in den neuesten ausgewaehlten
    # Sitzungen liegen, damit der Zaehltest sie wirklich erreicht.
    sortiert = Enum.sort_by(paare, fn {s, _top} -> s.datum end, :desc)

    oeffentliche =
      Enum.reject(sortiert, fn {_s, top} -> top.geschuetzt or top.vorlage["restricted"] end)

    geschuetzte =
      Enum.filter(sortiert, fn {_s, top} -> top.geschuetzt and top.vorlage["restricted"] end)

    [
      {Enum.at(oeffentliche, 0),
       %{
         titel:
           "Antrag auf Verlegung der Lindenallee in die Tempo-30-Zone" <> @beschluss
       }},
      {Enum.at(oeffentliche, 1),
       %{zusatz_satz: "Anwohner der Lindenallee regen eine Prüfung der Tempo-30-Zone an."}},
      {Enum.at(oeffentliche, 2),
       %{
         titel:
           "Antrag auf Sperrung der Lindenallee für den Durchgangsverkehr" <> @beschluss,
         restricted_override: true
       }},
      {Enum.at(oeffentliche, 3), %{zusatz_satz: Daten.injection()}},
      {Enum.at(geschuetzte, 0),
       %{
         titel:
           "Antrag auf Erwerb des Grundstücks Rosenhang-West" <> @beschluss
       }},
      {Enum.at(geschuetzte, 1),
       %{
         titel:
           "Bebauungsplan Lindenallee 12; Aufstellung" <> @beschluss
       }}
    ]
    |> Enum.reject(fn {paar, _aenderung} -> is_nil(paar) end)
    |> Map.new(fn {{_s, top}, aenderung} -> {top.id_paar, aenderung} end)
  end

  # --- Suchkassetten -----------------------------------------------------------------
  #
  # Drei Suchbegriffe: "Beschluss" als Breitensuche mit 98 Treffern (Spiegel
  # der einzigen echten Beobachtung — damit bleibt die Kardinalitaet im
  # Compare-Fenster, und wie dort tragen alle Treffer rein numerische
  # Nummern), "Lindenallee" fuer den Zaehltest und ein trefferloser Begriff
  # fuer die leere Antwortform.

  defp such_eintraege(sitzungen) do
    paare = Enum.flat_map(sitzungen, fn s -> Enum.map(alle_tops(s), &{s, &1}) end)

    breit =
      paare
      |> Enum.reject(fn {_s, top} -> top.geschuetzt or restricted?(top) end)
      |> Enum.filter(fn {_s, top} -> String.contains?(top.titel, "Beschlussfassung") end)
      |> Enum.filter(fn {_s, top} -> Regex.match?(~r/^\d+$/, top.vorlage["numbering"]) end)
      |> Enum.take(98)

    lindenallee = Enum.filter(paare, fn {_s, top} -> lindenallee_top?(top) end)

    [
      such_eintrag("Beschluss", breit),
      such_eintrag("Lindenallee", lindenallee),
      such_eintrag("qqxsichtbar", [])
    ]
  end

  defp lindenallee_top?(top) do
    im_titel = String.contains?(top.titel, "Lindenallee")
    im_text = (top.zusatz_satz || "") |> String.contains?("Lindenallee")
    im_titel or im_text
  end

  defp such_eintrag(begriff, paare) do
    %{
      "method" => "GET",
      "path" => "/fulltextsearch",
      "query" => "client=32&committee=0&searchterm=" <> URI.encode(begriff),
      "gast" => false,
      "anfrage_body" => "",
      "antwort_body" => %{
        "agendaitems" => Enum.map(paare, fn {s, top} -> such_treffer(s, top) end),
        "documents" => [],
        "meetingdocuments" => []
      }
    }
  end

  defp such_treffer(s, top) do
    %{
      "clientid" => @client,
      "clientname" => @clientname,
      "committeeid" => s.gremium.id,
      "conorderid" => top.lauf,
      "globalid" => "g-#{top.id_paar}",
      "id" => top.id_paar,
      "meetingdate" => s.datum,
      "meetingid" => s.id,
      "meetingname" => s.name,
      "meetingnum" => s.nummer,
      "name" => top.titel,
      "nameguest" => nameguest(top),
      "numbering" => top.vorlage["numbering"],
      "orderinmeeting" => top.lauf,
      "restricted" => restricted?(top)
    }
  end

  defp nameguest(top) do
    if restricted?(top) or top.geschuetzt,
      do: "Von der Veröffentlichung ausgenommen",
      else: top.titel
  end

  # --- Download-Kassetten --------------------------------------------------------------

  defp download_eintraege(sitzungen) do
    sitzungen
    |> Enum.flat_map(&alle_tops/1)
    |> Enum.filter(&(length(&1.detail["dokumente"] || []) > 0))
    |> Enum.take(3)
    |> Enum.map(fn top ->
      laenge = [["content-length", Integer.to_string(byte_size(@pdf))] | @download_kopf]

      %{
        "method" => "GET",
        "path" => "/agendaitems/documents/#{dokument_id(top, 1)}",
        "query" => nil,
        "gast" => false,
        "anfrage_body" => "",
        "antwort_kopf" => laenge,
        "roh" => true,
        "antwort_body" => @pdf
      }
    end)
  end

  # --- Sitzungs- und TOP-Koerper --------------------------------------------------------

  defp sitzungs_body(s) do
    tag = String.slice(s.datum, 0, 10)
    uhr = fn zeit -> tag <> zeit end

    %{
      "absolutestarttime" => uhr.("T18:00:00"),
      "absoluteendtime" => uhr.("T20:15:00"),
      "candownloadsummonspdf" => true,
      "clientid" => @client,
      "clientname" => @clientname,
      "committeename" => s.gremium.name,
      "committeeid" => s.gremium.id,
      "committeename2" => nil,
      "committeeid2" => nil,
      "committeename3" => nil,
      "committeeid3" => nil,
      "documents" => [],
      "expirationdate" => faellig(tag, 14),
      "freetextsafterfirstprotectedpart" => [],
      "freetextsafterfirstpublicpart" => [],
      "freetextsaftermeeting" => [],
      "freetextsbeforefirstprotectedpart" => [],
      "freetextsbeforefirstpublicpart" => [],
      "freetextsbeforemeeting" => [],
      "freetextsbeforeparts" => [],
      "id" => s.id,
      "locationcity" => @clientname,
      "locationdescription" => "Rathaussaal im Rathausgarten",
      "locationdistrict" => "Kernstadt",
      "locationname" => "Rathaus",
      "locationprintname" => "Rathaus Gartenstadt, Rathausgarten 1",
      "locationshortname" => "Rathaus",
      "locationstreet" => "Rathausgarten",
      "locationzip" => "87654",
      "meetingdate" => s.datum,
      "name" => s.name,
      "nonepublicendtime" => uhr.("T21:00:00"),
      "nonepublicendtime2" => uhr.("T21:00:00"),
      "nonepublicpart" => Enum.any?(s.teile, & &1.protectedpart),
      "nonepublicstarttime" => uhr.("T20:15:00"),
      "nonepublicstarttime2" => uhr.("T20:15:00"),
      "num" => s.nummer,
      "op" => 0,
      "opdatetime" => s.datum,
      "parts" => Enum.map(s.teile, &teil_body/1),
      "publicendtime" => uhr.("T20:15:00"),
      "publicendtime2" => uhr.("T20:15:00"),
      "publicpart" => true,
      "publicstarttime" => uhr.("T18:00:00"),
      "publicstarttime2" => uhr.("T17:30:00"),
      "snapdatetime" => s.datum,
      "state" => s.vorlage["state"],
      "unreadop" => ungelesen(s.id),
      "visibilitynoe" => 1,
      "visibilityoe" => 2
    }
  end

  defp faellig(tag, tage) do
    datum = tag |> Date.from_iso8601!() |> Date.add(tage) |> Date.to_string()
    datum <> "T12:00:00"
  end

  defp teil_body(teil) do
    %{
      "protectedpart" => teil.protectedpart,
      "agendaitems" =>
        Enum.map(teil.tops, fn top ->
          %{
            "id" => top.id_paar,
            "name" => top.titel,
            "numbering" => top.vorlage["numbering"],
            "restricted" => restricted?(top),
            "documentcount" => top.vorlage["documentcount"],
            "downloadallowed" => top.vorlage["downloadallowed"],
            "globalid" => "g-#{top.id_paar}",
            "unreadop" => ungelesen(top.lauf)
          }
        end)
    }
  end

  defp top_body(s, top) do
    %{
      "agendaitemtype" => top_art(top),
      "attendee" => nil,
      "bereitstellungsumfang" => true,
      "clientname" => @clientname,
      "committeeid" => s.gremium.id,
      "committeename" => s.gremium.name,
      "conorderid" => top.lauf,
      "conorder_order" => top.lauf,
      "conorderitems" => conorderitems(top, s),
      "conordertype" => "Beschlussvorlage",
      "consultants" => nil,
      "documents" => dokumente(top),
      "downloadallowed" => top.vorlage["downloadallowed"],
      "editor" => nil,
      "entitledToVote" => nil,
      "globalid" => "g-#{top.id_paar}",
      "id" => top.id_paar,
      "inpart" => if(top.geschuetzt, do: 2, else: 1),
      "meetingdate" => s.datum,
      "meetingid" => s.id,
      "meetingname" => s.name,
      "meetingnum" => s.nummer,
      "meetingstate" => 1,
      "name" => top.titel,
      "nameadditional" => "",
      "numbering" => top.vorlage["numbering"],
      "numberingsnapshot" => "TOP " <> top.vorlage["numbering"],
      "numberingsnapshotorder" => top.lauf,
      "op" => 0,
      "opdatetime" => s.datum,
      "orderinmeeting" => top.lauf,
      "pageno" => "S. " <> Integer.to_string(rem(top.lauf, 250) + 1),
      "publizierungsumfang" => 1,
      "restricted" => restricted?(top),
      "textblocks" => textbloecke(top),
      "textsanddocsvisible" => top.detail["textsanddocsvisible"],
      "unreadop" => ungelesen(top.lauf),
      "votings" => abstimmungen(top)
    }
  end

  # unreadop ist im echten RIS mal Zaehler, mal null (Skelett: mixed).
  defp ungelesen(n), do: if(rem(n, 2) == 0, do: 0)

  defp top_art(top) do
    if restricted?(top), do: "beratend", else: "beschliessend"
  end

  # Effektive Sichtbarkeit: Ein bewusster Sonderfall (Fail-closed-Test des
  # Connectors) darf einen TOP im ungeschuetzten Teil auf restricted setzen —
  # die reale Datenlage kennt das nicht, der Connector-Filter muss es trotzdem
  # wegwerfen (sonderfaelle/1 setzt genau einen).
  defp restricted?(%{restricted_override: true}), do: true
  defp restricted?(top), do: top.vorlage["restricted"]

  # Der dritte Block bleibt leer: Im echten RIS ist content mal Base64-HTML,
  # mal schlichter Text (Skelett: Formate base64-html und text).
  defp textbloecke(top) do
    ["Sachverhalt", "Beschlussvorschlag", "Abwaegung"]
    |> Enum.take(top.detail["textbloecke"] || 0)
    |> Enum.with_index(1)
    |> Enum.map(fn
      {caption, 3} -> leerer_textblock(caption, top.lauf * 10 + 3)
      {caption, i} -> textblock(caption, top.lauf * 10 + i, top.zusatz_satz)
    end)
  end

  defp leerer_textblock(caption, saat_index) do
    %{"caption" => caption, "content" => "", "mmsdataid2" => mms_id(saat_index)}
  end

  defp mms_id(saat_index), do: "mms-" <> Integer.to_string(saat_index)

  defp textblock(caption, saat_index, zusatz) do
    inhalt =
      1..3
      |> Enum.map(&Daten.dreher(Daten.saetze(), saat_index + &1))
      |> Enum.join(" ")

    inhalt = if zusatz, do: inhalt <> " " <> zusatz, else: inhalt

    %{
      "caption" => caption,
      "content" => Base.encode64("<p>" <> inhalt <> "</p>"),
      "mmsdataid2" => mms_id(saat_index)
    }
  end

  # Abstimmungen wechseln zwischen erfasster (Ergebnis, Beschreibung, ein
  # Textblock) und offener (alles null, keine Textbloecke) — beide Formen
  # zeigt das echte RIS (Skelett: mixed mit null, textblocks 0..1).
  defp abstimmungen(top) do
    # Range.new mit Schritt 1: Zaehler 0 bleibt leer (1..0 waere in Elixir
    # 1.20 absteigend und wuerde zwei Elemente liefern).
    Enum.map(Range.new(1, top.detail["abstimmungen"] || 0, 1), fn i ->
      leer = %{
        "attendeecount" => nil,
        "consultantscount" => nil,
        "description" => nil,
        "entitledtovotecount" => nil,
        "resultno" => nil,
        "resultnone" => nil,
        "resultyes" => nil,
        "textblocks" => [],
        "votingkind" => nil
      }

      if rem(top.lauf + i, 2) == 0 do
        %{
          leer
          | "description" => "Abstimmung über den Beschlussvorschlag",
            "resultno" => rem(top.lauf + i, 3),
            "resultyes" => 8 + rem(top.lauf + i, 7),
            "textblocks" => [textblock("Beschluss", top.lauf * 10 + 5, nil)],
            "votingkind" => 1
        }
      else
        leer
      end
    end)
  end

  defp dokumente(top) do
    (top.detail["dokumente"] || [])
    |> Enum.with_index(1)
    |> Enum.map(fn {vorlage, i} ->
      %{
        "clientname" => @clientname,
        "fileext" => vorlage["fileext"],
        "guestvisible" => vorlage["guestvisible"],
        "id" => dokument_id(top, i),
        "name" => Daten.dreher(Daten.dokumentnamen(), top.lauf + i)
      }
    end)
  end

  defp dokument_id(top, i), do: "#{top.id_paar}-#{@dokument_basis + top.lauf * 100 + i}"

  defp conorderitems(top, s) do
    Enum.map(Range.new(1, top.detail["conorderitems"] || 0, 1), fn _i ->
      %{
        "agendaitemid" => top.id_paar,
        "clientname" => @clientname,
        "committeeid" => s.gremium.id,
        "committeename" => s.gremium.name,
        "conordertypename" => "Beschluss",
        "meetingdate" => s.datum,
        "meetingid" => s.id,
        "meetingname" => s.name,
        "numbering" => top.vorlage["numbering"],
        "restricted" => "false"
      }
    end)
  end

  # --- Schreiben -------------------------------------------------------------------------

  defp schreibe(out, n, eintrag) do
    body =
      if eintrag["roh"],
        do: eintrag["antwort_body"],
        else: eintrag["antwort_body"] |> :json.encode(&json_wert/2) |> IO.iodata_to_binary()

    kopf =
      eintrag["antwort_kopf"] ||
        [["content-length", Integer.to_string(byte_size(body))] | @antwort_kopf]

    cassette = %{
      "request" => %{
        "method" => eintrag["method"],
        "path" => eintrag["path"],
        "query" => eintrag["query"] || :null,
        "headers" => eintrag["anfrage_kopf"] || standard_kopf(eintrag),
        "body_b64" => Base.encode64(eintrag["anfrage_body"])
      },
      "response" => %{
        "status" => 200,
        "headers" => kopf,
        "body_b64" => Base.encode64(body)
      }
    }

    datei = Path.join(out, dateiname(n, eintrag["method"], eintrag["path"]))
    File.write!(datei, IO.iodata_to_binary(:json.encode(cassette)) <> "\n")
  end

  # OTP :json schreibt das Atom nil als String "nil"; das RIS liefert null.
  defp json_wert(nil, _encode), do: "null"
  defp json_wert(wert, encode), do: :json.encode_value(wert, encode)

  defp standard_kopf(%{"gast" => true}), do: [@host_kopfzeile | @anfrage_kopf]
  defp standard_kopf(_eintrag), do: [@host_kopfzeile, @auth_kopfzeile | @anfrage_kopf]

  defp dateiname(n, method, path) do
    pfad = path |> String.trim_leading("/") |> String.replace("/", "-")

    String.pad_leading(Integer.to_string(n), 4, "0") <>
      "-" <> String.downcase(method) <> "-" <> pfad <> ".json"
  end

  defp default_out, do: Path.expand("../test/fixtures/gartenstadt", __DIR__)
  defp default_struktur, do: Path.expand("strukturen/20261101T112819Z.json", __DIR__)
end

KomkiConnectorRis.RisHttp.cli(System.argv(), fn argv ->
  case KomkiConnectorRis.RisGartenstadt.parse_cli(argv) do
    {:ok, opts} ->
      case KomkiConnectorRis.RisGartenstadt.generate(opts) do
        {:ok, out, anzahl} ->
          IO.puts("ris_gartenstadt: #{anzahl} Kassetten nach #{out}")

        {:error, meldung} ->
          IO.puts(:stderr, "ris_gartenstadt: #{meldung}")
          exit({:shutdown, 1})
      end

    {:error, usage} ->
      IO.puts(:stderr, "ris_gartenstadt: #{usage}")
      exit({:shutdown, 1})
  end
end)
