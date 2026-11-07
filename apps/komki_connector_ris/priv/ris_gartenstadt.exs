# Gartenstadt generator (ticket #313): synthetic cassettes built from a
# structure profile and a skeleton report.
#
#     elixir apps/komki_connector_ris/priv/ris_gartenstadt.exs \
#       [--out <directory>] [--struktur <file>]
#
# Generates cassettes in the recorder's format (priv/ris_recorder.exs),
# playable with mock_ris.exs --mode replay. The template is the structure
# profile of session 20261101T112819Z: the transcription adopts every
# observed occupancy - protected parts, restricted flags, counters for text
# blocks, votes and documents - and fills them with content from the
# "Gartenstadt" universe (priv/gartenstadt_daten.exs). Real content never
# enters: the generator reads only committable, content-free reports. Every
# array length in the synthetic set is thus a length observed in the real
# RIS, and ris_skeleton --compare stays cardinality-compatible.
#
# Cassettes per meeting exist only for a (coverage) selection (auswahl/2):
# so few meetings that every observed occupancy occurs once. The guest list
# and the searches contain all meetings of the profile, because their
# length is part of the observed format; agendas and TOPs outside the
# selection answer with 404 in replay.
#
# The output directory must be empty (clear it before regenerating), so
# that no leftovers from earlier runs remain.
#
# OTP only, no deps - like the sibling scripts.

Code.require_file("./gartenstadt_daten.exs", __DIR__)
Code.require_file("./ris_http.exs", __DIR__)

defmodule KomkiConnectorRis.RisGartenstadt do
  @moduledoc false

  alias KomkiConnectorRis.GartenstadtDaten, as: Daten
  alias KomkiConnectorRis.RisHttp

  @usage "Aufruf: [--out <verzeichnis>] [--struktur <datei>]"

  @client 32
  @clientname "Gartenstadt"
  @sitzungs_basis 300_000_000
  @top_basis 400_000_000
  @dokument_basis 500_000

  # Header names as in the skeleton reports; all values invented.
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

  # Download response like the real RIS (finding 2026-11-05, #313):
  # application/octet-stream, not application/pdf; file name in
  # content-disposition. Header names follow the real skeleton report.
  @download_kopf [
    ["content-disposition", "attachment; filename=\"Gartenstadt_Anlage.pdf\""],
    ["content-type", "application/octet-stream"],
    ["date", "Thu, 05 Nov 2026 10:00:00 GMT"],
    ["server", "RIS-Mock"],
    ["strict-transport-security", "max-age=31536000"],
    ["x-powered-by", "Gartenstadt"]
  ]

  # Small structured PDF as the download body: storable byte-for-byte,
  # entirely invented.
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
    case RisHttp.parse_flags(argv, out: :string, struktur: :string) do
      {:ok, opts} -> {:ok, opts}
      :error -> {:error, @usage}
    end
  end

  # --- Template ------------------------------------------------------------------

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

  # --- Selection by coverage ----------------------------------------------------------
  #
  # Greedy set cover: always the meeting with the most still-missing
  # markers, on a tie the one with fewer TOPs, then the earlier one in the
  # profile. Stop as soon as no meeting contributes a new marker.

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

  # Markers that shape format or behavior: part layout and meeting state;
  # per TOP visibility, numbering form (the compare distinguishes "digits"
  # from "text") and whether a field is empty or occupied - text blocks
  # with the exact count, because they cover the length in the compare.
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

  # --- Transcription ----------------------------------------------------------------

  defp sitzung_uebersetzen(s, nr, details, aktive) do
    id = @sitzungs_basis + nr
    gremium = Enum.at(aktive, gremium_index(s) - 1) || hd(aktive)

    {teile, _bisher} =
      Enum.map_reduce(s["teile"], 0, fn teil, bisher ->
        {tops, lauf} =
          Enum.map_reduce(teil["tops"], bisher, fn top, l ->
            {top_uebersetzen(top, teil["protectedpart"], l + 1, id, nr, details), l + 1}
          end)

        {%{protectedpart: teil["protectedpart"], tops: tops}, lauf}
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

  # The number and naming pattern are invented: the real meeting number next
  # to the real date, with the real naming pattern, would yield the same word
  # sequence as in the RIS (n-gram finding, #313).
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

  # Own phrasing instead of the real RIS formulas: earlier templates carried
  # real wording and stood out in the n-gram comparison (#313). The word
  # "Beschlussfassung" stays; the broad search filters on it.
  @beschluss " – Vorlage zur Beschlussfassung im Gartenstadt-Gremium"

  defp titel(index) do
    thema = Daten.nth_cyclic(Daten.themen(), index)
    strasse = Daten.nth_cyclic(Daten.strassen(), index)
    # Plot and house number cycle via div instead of rem: the building
    # template only hits indices with rem(index, 6) == 2, otherwise the same
    # pair would come up every time.
    flur = Daten.nth_cyclic(Daten.flurstuecke(), div(index, 6))
    hnr = Daten.nth_cyclic(Daten.hausnummern(), div(index, 6))
    vorname = Daten.nth_cyclic(Daten.vornamen(), index)
    nachname = Daten.nth_cyclic(Daten.nachnamen(), index)

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
        "Neufassung der Ortsregel: " <> thema <> @beschluss

      4 ->
        "Mitteilungen der Gartenstadt-Verwaltung (zur Kenntnis)"

      _ ->
        "Fragen aus der Gartenstadt-Bürgerrunde: " <> thema <> " (zur Kenntnis)"
    end
  end

  # --- Entries ------------------------------------------------------------------------

  defp auth_eintrag do
    anfrage =
      :json.encode(%{"login" => "rathaus@gartenstadt.example", "password" => "gartenschluessel"})

    body = IO.iodata_to_binary(anfrage)

    # The login posts a body (content-type, content-length) and naturally
    # carries no authorization header yet - the names follow the real
    # skeleton report.
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

  # Guest view of the meeting (inferred, deliberately open in #313): frame
  # like the real guest endpoint, agenda like meetings/{id} - exactly the
  # fields the connector reads according to the README (protectedpart,
  # restricted, name, numbering, id).
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

  # --- Special cases (deliberate test cases, mirror of the previous mock) ------------
  #
  # "Lindenallee" appears in two public TOPs (once in the title, once only
  # in the text) and in two non-public ones: once as a restricted TOP in the
  # unprotected part - the fail-closed case the real data never shows - and
  # once in the protected part. This is the counting test: the connector's
  # hit count must not give anything away. "Rosenhang-West" appears in only
  # one non-public TOP, the prompt injection only in the public text.

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

    # Date-descending, within a meeting in agenda order: the connector reads
    # the newest meetings first, and after 33 agenda fetches (the 404s
    # outside the selection also cost budget) its leftover budget has room
    # for only a few text queries. The special cases must therefore sit in
    # the newest selected meetings, so the counting test actually reaches
    # them.
    sortiert = Enum.sort_by(paare, fn {s, _top} -> s.datum end, :desc)

    oeffentliche =
      Enum.reject(sortiert, fn {_s, top} -> top.geschuetzt or top.vorlage["restricted"] end)

    # A zusatz_satz reaches the cassette only through a text block; a TOP
    # without blocks would silently drop the sentence. Text carriers are
    # therefore chosen from public TOPs WITH blocks, so that the text
    # special case and the injection are preserved for future profiles too.
    # Both sit as early as possible in the newest-first order - the
    # connector's leftover budget reaches them.
    texttraeger =
      Enum.filter(oeffentliche, fn {_s, top} -> (top.detail["textbloecke"] || 0) > 0 end)

    # Title carriers take the remaining public TOPs: no TOP carries two
    # cases, and all four sit among the newest public ones.
    titeltraeger =
      Enum.reject(oeffentliche, fn {_s, top} ->
        top.id_paar in Enum.map(Enum.take(texttraeger, 2), &paar_id/1)
      end)

    geschuetzte =
      Enum.filter(sortiert, fn {_s, top} -> top.geschuetzt and top.vorlage["restricted"] end)

    [
      {traeger!(titeltraeger, 0, "Lindenallee im Titel"),
       %{
         titel:
           "Antrag auf Verlegung der Lindenallee in die Tempo-30-Zone" <> @beschluss
       }},
      {traeger!(texttraeger, 0, "Lindenallee im Text"),
       %{zusatz_satz: "Anwohner der Lindenallee regen eine Prüfung der Tempo-30-Zone an."}},
      {traeger!(titeltraeger, 1, "restricted im ungeschuetzten Teil"),
       %{
         titel:
           "Antrag auf Sperrung der Lindenallee für den Durchgangsverkehr" <> @beschluss,
         restricted_override: true
       }},
      {traeger!(texttraeger, 1, "Prompt-Injection"), %{zusatz_satz: Daten.injection()}},
      {traeger!(geschuetzte, 0, "Rosenhang-West"),
       %{
         titel:
           "Antrag auf Erwerb des Grundstücks Rosenhang-West" <> @beschluss
       }},
      {traeger!(geschuetzte, 1, "Lindenallee im geschuetzten Teil"),
       %{
         titel:
           "Bebauungsplan Lindenallee 12; Aufstellung" <> @beschluss
       }}
    ]
    |> Map.new(fn {{_s, top}, aenderung} -> {top.id_paar, aenderung} end)
  end

  # Carriers are mandatory, not best-effort: a missing selection would
  # silently drop a planned test case from the fixture set - better to fail
  # loudly at generation time (review #313).
  defp traeger!(list, n, zweck) do
    case Enum.at(list, n) do
      nil -> raise "ris_gartenstadt: kein TOP als Traeger fuer #{zweck} im Strukturprofil"
      paar -> paar
    end
  end

  defp paar_id({_s, top}), do: top.id_paar

  # --- Search cassettes --------------------------------------------------------------
  #
  # Three search terms: "Beschluss" as a broad search with 98 hits (mirror
  # of the only real observation - this keeps the cardinality inside the
  # compare window, and as there, all hits carry purely numeric numbers),
  # "Lindenallee" for the counting test, and a zero-hit term for the empty
  # response form.

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

  # --- Download cassettes --------------------------------------------------------------

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

  # --- Meeting and TOP bodies -----------------------------------------------------------

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
      # Neutral zip code with no reference to a real region.
      "locationzip" => "00000",
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

  # unreadop is sometimes a counter, sometimes null in the real RIS
  # (skeleton: mixed).
  defp ungelesen(n), do: if(rem(n, 2) == 0, do: 0)

  defp top_art(top) do
    if restricted?(top), do: "beratend", else: "beschliessend"
  end

  # Effective visibility: a deliberate special case (the connector's
  # fail-closed test) may set a TOP in the unprotected part to restricted -
  # the real data never shows that, but the connector filter must still
  # throw it away (sonderfaelle/1 sets exactly one).
  defp restricted?(%{restricted_override: true}), do: true
  defp restricted?(top), do: top.vorlage["restricted"]

  # The third block stays empty: in the real RIS, content is sometimes
  # Base64-HTML, sometimes plain text (skeleton: formats base64-html and text).
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
      |> Enum.map(&Daten.nth_cyclic(Daten.saetze(), saat_index + &1))
      |> Enum.join(" ")

    inhalt = if zusatz, do: inhalt <> " " <> zusatz, else: inhalt

    %{
      "caption" => caption,
      "content" => Base.encode64("<p>" <> inhalt <> "</p>"),
      "mmsdataid2" => mms_id(saat_index)
    }
  end

  # Votes alternate between recorded (result, description, one text block)
  # and open (everything null, no text blocks) - the real RIS shows both
  # forms (skeleton: mixed with null, textblocks 0..1).
  defp abstimmungen(top) do
    # Range.new with step 1: a count of 0 stays empty (1..0 would be
    # descending in Elixir 1.20 and would yield two elements).
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
        "name" => Daten.nth_cyclic(Daten.dokumentnamen(), top.lauf + i)
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

  # --- Writing ---------------------------------------------------------------------------

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

  # OTP :json writes the atom nil as the string "nil"; the RIS returns null.
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
