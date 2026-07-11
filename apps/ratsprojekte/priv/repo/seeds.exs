defmodule Ratsprojekte.Seeds do
  @moduledoc """
  Seed: 3 Beispielprojekte aus Carstens Vault.
  """

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{Blocker, Projekt, Quelle}

  def run do
    # Bestehende Daten löschen (nur in dev!)
    Repo.delete_all(Quelle)
    Repo.delete_all(Blocker)
    Repo.delete_all(Projekt)

    bahnhof = create_bahnhofstr()
    gennach = create_gennachpark()
    _freibad = create_freibad()

    IO.puts("Seeds erstellt: Bahnhofstraße, Gennachpark, Freibad")
  end

  defp create_bahnhofstr do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Bahnhofstraße umgestalten",
        beschreibung:
          "Boulevard Bahnhofstraße — Tempo 30, Begrünung, Sitzgelegenheiten, autofreie Tage. Wahlprogramm-Punkt.",
        status: :aktiv,
        prioritaet: :hoch
      })

    b_strassenbaulast =
      create_blocker(
        projekt,
        "Staatsstraße umwidmen",
        "Die St 2035 ist eine Staatsstraße. Solange sie das ist, hat die Stadt keine Gestaltungshoheit. Alles hängt am Staatlichen Bauamt.",
        :rechtlich,
        :offen
      )

    create_quelle(b_strassenbaulast, :gesetz, "BayStrWG Art. 7 — Umstufung von Straßen",
      paragraf: "Art. 7 BayStrWG"
    )

    b_westtangente =
      create_blocker(
        projekt,
        "Westtangente als OU qualifizieren",
        "Die Westtangente muss als Ortsumgehung (OU) im Sinne des Art. 13f BayFAG qualifizieren, damit die Staatsstraße dorthin verlegt werden kann und die Bahnhofstraße zur Gemeindestraße wird.",
        :infrastruktur,
        :offen
      )

    create_quelle(b_westtangente, :gesetz, "Art. 13f BayFAG — Sonderbaulast-Modell",
      paragraf: "Art. 13f BayFAG"
    )

    b_verkehrskonzept =
      create_blocker(
        projekt,
        "Verkehrskonzept fehlt",
        "2023 von Hessel gefordert, nie richtig gekommen. SUMP-Förderung (Frist 1.6.2026) verstrichen. Alternative: KommKlimaFöR oder Städtebauförderung für Konzepterstellung.",
        :organisatorisch,
        :offen
      )

    b_foerderkulisse =
      create_blocker(
        projekt,
        "Förderkulisse unklar",
        "Städtebauförderung (60-90%), KommKlimaFöR (Subsidiaritätsklausel prüfen!), BayGVFG (30-80%). Kumulierung möglich aber Eigenanteil bleibt mind. 10%.",
        :finanziell,
        :in_arbeit
      )

    create_quelle(b_foerderkulisse, :foerderprogramm, "Bayerische Städtebauförderung",
      url: "https://www.stmb.bayern.de/buw/staedtebaufoerderung/"
    )

    create_quelle(
      b_foerderkulisse,
      :foerderprogramm,
      "KommKlimaFöR — Subsidiaritätsklausel Nr. 5.4",
      url: "https://www.verkuendung-bayern.de/baymbl/2022-740/"
    )

    b_beschluss =
      create_blocker(
        projekt,
        "Gemeinderatsbeschluss fehlt",
        "Antrag auf Beauftragung eines Verkehrskonzepts/ISEK muss im Stadtrat eingebracht werden. Fraktion muss abstimmen.",
        :politisch,
        :offen
      )

    b_erneuerungsgebiet =
      create_blocker(
        projekt,
        "Erneuerungsgebiet förmlich festlegen",
        "Voraussetzung für Städtebauförderung. Ohne förmlich festgelegtes Sanierungsgebiet keine Förderung. Gemeinderatsbeschluss nötig.",
        :rechtlich,
        :offen
      )

    create_quelle(b_erneuerungsgebiet, :gesetz, "§ 136 BauGB — Besonderes Städtebaurecht",
      paragraf: "§ 136 BauGB"
    )

    # DAG Dependencies
    create_dependency(b_strassenbaulast, b_westtangente)
    create_dependency(b_strassenbaulast, b_verkehrskonzept)
    create_dependency(b_foerderkulisse, b_erneuerungsgebiet)
    create_dependency(b_beschluss, b_verkehrskonzept)

    # Projekt-Quelle
    create_projekt_quelle(projekt, :sitzung, "93. Sitzung des Stadtrates Buchloe (2026-04-28)",
      url: "ris.komuna.net/vgbuchloe/app/sitzungen/113535630"
    )

    projekt
  end

  defp create_gennachpark do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Gennachpark / Moorpark",
        beschreibung:
          "Mehrgenerationen-Moorpark im Süden Buchloes. Im FNP verankert (02/2025). Grüne haben 2020 den Antrag gestellt. Haushaltsansatz existiert laut UBI.",
        status: :aktiv,
        prioritaet: :hoch
      })

    b_bplan =
      create_blocker(
        projekt,
        "Bebauungsplan fehlt",
        "Der FNP ist nur die grobe Flächenwidmung. Ohne B-Plan keine Bebaubarkeit. FNP ist keine bindende Rechtsnorm.",
        :rechtlich,
        :offen
      )

    create_quelle(b_bplan, :gesetz, "BauGB — Bebauungsplanverfahren", paragraf: "§ 9 ff. BauGB")

    b_konzept =
      create_blocker(
        projekt,
        "Konzept & Beteiligung fehlen",
        "Anwohner:innen, Jugendbeirat, Vereine, Kitas müssen früh eingebunden werden. Konzeptwerkstatt nötig.",
        :organisatorisch,
        :offen
      )

    b_traegerschaft =
      create_blocker(
        projekt,
        "Trägerschaft/Pflege unklar",
        "Wer unterhält den Park? Stadt? Verein? Genossenschaft? Muss vor Baubeginn geklärt sein.",
        :politisch,
        :offen
      )

    b_finanzierung =
      create_blocker(
        projekt,
        "Finanzierung unklar",
        "Grieb (UBI): 'Seit Jahren ist eine Summe im Haushalt eingestellt'. Wie viel? Reicht das? Förderanträge gestellt? Städtebauförderung wegen Umweltbeitrag möglich.",
        :finanziell,
        :in_arbeit
      )

    create_quelle(
      b_finanzierung,
      :zeitungsartikel,
      "BZ: Bekommt Buchloe statt neuer Häuser einen Moorpark? (27.02.2025)"
    )

    create_projekt_quelle(projekt, :url, "FNP-Eintrag als Moorpark (02/2025)")

    # DAG
    create_dependency(b_finanzierung, b_bplan)

    projekt
  end

  defp create_freibad do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Freibad Digitalisierung",
        beschreibung:
          "Smart Metering + Kartenzahlung im Freibad. Leck im Technikraum tagelang unbemerkt geblieben — hätte mit digitalen Wasserzählern sofort erkannt werden können.",
        status: :idee,
        prioritaet: :mittel
      })

    b_smart_metering =
      create_blocker(
        projekt,
        "Smart Metering einführen",
        "Leck im Technikraum lief tagelang unbemerkt. Digitale Wasserzähler hätten das sofort erkannt. Gleiche Infrastruktur wie Kartenzahlung.",
        :infrastruktur,
        :offen
      )

    b_kartenzahlung =
      create_blocker(
        projekt,
        "Kartenzahlung im Freibad + Kiosk",
        "Bar-only ist 2026 nicht mehr zeitgemäß. Kosten-Nutzen für Kartenterminals prüfen lassen.",
        :finanziell,
        :offen
      )

    b_beschluss =
      create_blocker(
        projekt,
        "Stadtratsbeschluss nötig",
        "Antrag auf Prüfung von Smart Metering + Kartenzahlung. Bündel-Antrag möglich (gleiche Infrastruktur).",
        :politisch,
        :offen
      )

    create_quelle(
      b_smart_metering,
      :url,
      "Kommunal Digital Podcast — Smart Metering als Türöffner"
    )

    create_dependency(b_beschluss, b_smart_metering)
    create_dependency(b_beschluss, b_kartenzahlung)

    projekt
  end

  # --- Helpers ---

  defp create_blocker(projekt, titel, beschreibung, typ, status) do
    {:ok, blocker} =
      Repo.insert(%Blocker{
        titel: titel,
        beschreibung: beschreibung,
        typ: typ,
        status: status,
        projekt_id: projekt.id
      })

    blocker
  end

  defp create_quelle(blocker, typ, titel, opts \\ [])
       when is_atom(typ) do
    {:ok, _} =
      Repo.insert(%Quelle{
        typ: typ,
        titel: titel,
        url: Keyword.get(opts, :url),
        paragraf: Keyword.get(opts, :paragraf),
        projekt_id: blocker.projekt_id,
        blocker_id: blocker.id
      })

    :ok
  end

  defp create_projekt_quelle(projekt, typ, titel, opts \\ []) do
    {:ok, _} =
      Repo.insert(%Quelle{
        typ: typ,
        titel: titel,
        url: Keyword.get(opts, :url),
        paragraf: Keyword.get(opts, :paragraf),
        projekt_id: projekt.id
      })

    :ok
  end

  defp create_dependency(blocker, depends_on) do
    Repo.insert_all("blocker_dependencies", [
      [blocker_id: blocker.id, depends_on_blocker_id: depends_on.id]
    ])
  end
end

Ratsprojekte.Seeds.run()
