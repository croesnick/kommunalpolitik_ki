defmodule Ratsprojekte.Seeds do
  @moduledoc """
  Seed: 3 Beispielprojekte mit Realisierungssträngen aus Carstens Vault.
  """

  alias Ratsprojekte.Schemas.{Projekt, Quelle, Realisierungsstrang, Schritt, Vorbedingung}

  def run do
    # Repo muss bereits laufen (mix run ohne --no-start, oder manuell gestartet)
    Ratsprojekte.Repo.delete_all(Quelle)
    Ratsprojekte.Repo.delete_all(Schritt)
    Ratsprojekte.Repo.delete_all(Vorbedingung)
    Ratsprojekte.Repo.delete_all(Realisierungsstrang)
    Ratsprojekte.Repo.delete_all(Projekt)

    _bahnhof = create_bahnhofstr()
    _gennach = create_gennachpark()
    _freibad = create_freibad()

    IO.puts("Seeds erstellt: Bahnhofstraße, Gennachpark, Freibad")
  end

  defp create_bahnhofstr do
    {:ok, projekt} =
      Ratsprojekte.Repo.insert(%Projekt{
        titel: "Bahnhofstraße umgestalten",
        beschreibung:
          "Boulevard Bahnhofstraße — Tempo 30, Begrünung, Sitzgelegenheiten, autofreie Tage.",
        status: :aktiv,
        prioritaet: :hoch
      })

    strang_a =
      create_strang(
        projekt,
        "A",
        "Westtangente als Ortsumgehung bauen",
        "Westtangente als OU qualifizieren → Staatsstraße wird dorthin verlegt → Bahnhofstraße wird Gemeindestraße. Stadt bekommt volle Gestaltungshoheit.",
        "Art. 13f BayFAG (Sonderbaulast)",
        "Westtangente muss als OU im Sinne des Art. 13f BayFAG qualifizieren",
        false
      )

    create_vorbedingung(
      strang_a,
      "Westtangente muss als Ortsumgehung (OU) im Sinne des Art. 13f BayFAG qualifizieren",
      false,
      "Art. 13f BayFAG"
    )

    create_vorbedingung(
      strang_a,
      "Verkehrsgutachten muss belegen, dass die Westtangente die Verkehrslast übernehmen kann",
      false
    )

    create_vorbedingung(
      strang_a,
      "Finanzierung der Sonderbaulast muss geklärt sein (70-80% Freistaat)",
      false,
      "Art. 13f BayFAG"
    )

    create_schritt(
      strang_a,
      "Verkehrsgutachten zur Westtangente erstellen oder aktualisieren (VEP von 2014 liegt vor)"
    )

    create_schritt(strang_a, "Staatliches Bauamt zur Qualifizierung als OU anfragen")
    create_schritt(strang_a, "Finanzierungsvereinbarung mit Freistaat verhandeln")

    create_quelle(strang_a, :gesetz, "Art. 13f BayFAG — Sonderbaulast-Modell",
      paragraf: "Art. 13f BayFAG"
    )

    strang_b =
      create_strang(
        projekt,
        "B",
        "Direkte Umstufung ohne Ortsumgehung",
        "Staatsstraße direkt umstufen, weil der Verkehrsrückgang seit 2005 die Widmung nicht mehr rechtfertigt. Keine OU nötig.",
        "Art. 7 BayStrWG (Umstufung)",
        "Verkehrsrückgang muss belegt werden. Kein Präzedenzfall für Gemeinden <25.000 ohne OU.",
        false
      )

    create_vorbedingung(
      strang_b,
      "Verkehrsrückgang muss mit Daten belegt werden (VEP 2014 zeigt Rückgang seit 2005)",
      true,
      "Art. 7 BayStrWG"
    )

    create_vorbedingung(
      strang_b,
      "Es gibt keinen Präzedenzfall für Gemeinden <25.000 ohne OU — Risiko der Ablehnung",
      false
    )

    create_vorbedingung(strang_b, "Staatliches Bauamt muss zustimmen", false, "Art. 7 BayStrWG")

    create_schritt(strang_b, "VEP-Daten (2005-2023) als Argumentationsgrundlage aufbereiten")
    create_schritt(strang_b, "Staatliches Bauamt anfragen — Präzedenzfälle recherchieren")

    create_schritt(
      strang_b,
      "Bei Ablehnung: politischer Druck über Bürgerbegehren (wie 2019 durch UBI)"
    )

    create_quelle(strang_b, :gesetz, "BayStrWG — Umstufung", paragraf: "Art. 7 BayStrWG")

    strang_c =
      create_strang(
        projekt,
        "C",
        "Freiwillige Baulastübernahme",
        "Stadt übernimmt freiwillig die Baulast für die Bahnhofstraße vom Freistaat. Sofort machbar, aber Stadt trägt dauerhaft die Unterhaltungskosten.",
        "Art. 42 Abs. 1 Satz 6 BayStrWG",
        "Stadt muss bereit sein, Unterhaltungskosten dauerhaft zu tragen",
        true
      )

    create_vorbedingung(
      strang_c,
      "Stadt muss bereit sein, Unterhaltungskosten dauerhaft zu tragen",
      true,
      "Art. 42 Abs. 1 Satz 6 BayStrWG"
    )

    create_vorbedingung(strang_c, "Gemeinderatsbeschluss über Baulastübernahme", false)

    create_schritt(strang_c, "Unterhaltungskosten pro Jahr schätzen lassen (Bauamt)")
    create_schritt(strang_c, "Gemeinderatsbeschluss vorbereiten und einbringen")

    create_quelle(strang_c, :gesetz, "BayStrWG — Freiwillige Baulastübernahme",
      paragraf: "Art. 42 Abs. 1 Satz 6"
    )

    projekt
  end

  defp create_gennachpark do
    {:ok, projekt} =
      Ratsprojekte.Repo.insert(%Projekt{
        titel: "Gennachpark / Moorpark",
        beschreibung:
          "Mehrgenerationen-Moorpark im Süden Buchloes. Im FNP verankert (02/2025). Haushaltsansatz existiert laut UBI.",
        status: :aktiv,
        prioritaet: :hoch
      })

    strang_a =
      create_strang(
        projekt,
        "A",
        "Über Städtebauförderung (Umweltbeitrag)",
        "Städtebauförderung mit Umweltbeitrag wegen Moor-Revitalisierung. Bis 90% Förderung. Der klassische Weg für grüne Infrastruktur.",
        "Bayerische Städtebauförderungsrichtlinien",
        "Bebauungsplan muss vorhanden sein und Umweltbeitrag muss anerkannt werden",
        false
      )

    create_vorbedingung(
      strang_a,
      "Bebauungsplan muss vorhanden sein (FNP allein reicht nicht)",
      false,
      "§ 9 BauGB"
    )

    create_vorbedingung(
      strang_a,
      "Erneuerungsgebiet muss förmlich festgelegt sein",
      false,
      "§ 136 BauGB"
    )

    create_vorbedingung(
      strang_a,
      "Umweltbeitrag muss von Bezirksregierung anerkannt werden",
      false
    )

    create_schritt(strang_a, "Bebauungsplan aufstellen (Gemeinderatsbeschluss zur Aufstellung)")
    create_schritt(strang_a, "Erneuerungsgebiet förmlich festlegen")

    create_schritt(
      strang_a,
      "Bedarfsmitteilung bei Bezirksregierung Schwaben einreichen",
      ~D[2026-12-01]
    )

    create_schritt(strang_a, "Umweltbeitrag beantragen (Moor-Revitalisierung als Begründung)")

    strang_b =
      create_strang(
        projekt,
        "B",
        "Über BMUV 'Natürlicher Klimaschutz in Kommunen'",
        "Bundesprogramm für naturnahe Grünflächen, Pikoparks, Baumpflanzung. Bis 80% Förderung. Schneller als Städtebauförderung, kein B-Plan nötig.",
        "BMUV Förderprogramm FG44",
        "Antragsfrist 31.12.2026. Finanzschwacher Status und Eigentumsfrage offen.",
        true
      )

    create_vorbedingung(strang_b, "Antragsfrist 31.12.2026", true)

    create_vorbedingung(
      strang_b,
      "Buchloe muss als finanzschwache Kommune eingestuft sein (50% vs 80% Förderung)",
      false
    )

    create_vorbedingung(
      strang_b,
      "Fläche muss im Eigentum der Stadt sein (Wasserturm-Wiese — Klärung nötig)",
      false
    )

    create_schritt(
      strang_b,
      "Klären: Ist die Wiese unter dem Wasserturm im Stadt- oder Verbandseigentum?"
    )

    create_schritt(strang_b, "Finanzschwachen-Status bei KfW prüfen")
    create_schritt(strang_b, "Antrag über KfW Programm 444 vorbereiten", ~D[2026-12-31])

    create_quelle(strang_b, :foerderprogramm, "BMUV FG44", url: "https://www.bmuv.de/FG44")

    projekt
  end

  defp create_freibad do
    {:ok, projekt} =
      Ratsprojekte.Repo.insert(%Projekt{
        titel: "Freibad Digitalisierung",
        beschreibung:
          "Smart Metering + Kartenzahlung im Freibad. Leck im Technikraum tagelang unbemerkt geblieben.",
        status: :idee,
        prioritaet: :mittel
      })

    strang_a =
      create_strang(
        projekt,
        "A",
        "Bündel-Antrag Smart Metering + Kartenzahlung",
        "Beide Themen über dieselbe Infrastruktur (Netz, Strom, Datenleitung). Ein Antrag für beides — effizienter als zwei Einzelanträge.",
        nil,
        "Stadtratsbeschluss und Kosten-Nutzen-Analyse nötig",
        false
      )

    create_vorbedingung(strang_a, "Stadtratsbeschluss zur Prüfung und Beauftragung", false)

    create_vorbedingung(
      strang_a,
      "Kosten-Nutzen-Analyse für Kartenterminals muss vorliegen",
      false
    )

    create_schritt(strang_a, "Kosten-Nutzen-Analyse Kartenterminals von Verwaltung anfordern")
    create_schritt(strang_a, "Bündel-Antrag im Stadtrat einbringen")
    create_schritt(strang_a, "Bei Beschluss: Umsetzung durch Bauamt/Stadtwerke")

    projekt
  end

  defp create_strang(
         projekt,
         label,
         titel,
         beschreibung,
         rechtliche_grundlage,
         bedingung,
         bedingung_erfuellt
       ) do
    {:ok, strang} =
      Ratsprojekte.Repo.insert(%Realisierungsstrang{
        label: label,
        titel: titel,
        beschreibung: beschreibung,
        rechtliche_grundlage: rechtliche_grundlage,
        bedingung: bedingung,
        bedingung_erfuellt: bedingung_erfuellt,
        projekt_id: projekt.id
      })

    strang
  end

  defp create_vorbedingung(strang, text, erfuellt, rechtliche_grundlage \\ nil) do
    {:ok, _} =
      Ratsprojekte.Repo.insert(%Vorbedingung{
        text: text,
        erfuellt: erfuellt,
        rechtliche_grundlage: rechtliche_grundlage,
        realisierungsstrang_id: strang.id
      })
  end

  defp create_schritt(strang, text, frist \\ nil) do
    {:ok, _} =
      Ratsprojekte.Repo.insert(%Schritt{
        text: text,
        frist: frist,
        realisierungsstrang_id: strang.id
      })
  end

  defp create_quelle(strang, typ, titel, opts \\ []) do
    {:ok, _} =
      Ratsprojekte.Repo.insert(%Quelle{
        typ: typ,
        titel: titel,
        url: Keyword.get(opts, :url),
        paragraf: Keyword.get(opts, :paragraf),
        realisierungsstrang_id: strang.id
      })
  end
end

# Repo starten (für --no-start mode)
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

case Ratsprojekte.Repo.start_link(
       config: [database: System.user_home!() <> "/.local/share/ratsinfo/ratsinfo.db"]
     ) do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

Ratsprojekte.Seeds.run()
