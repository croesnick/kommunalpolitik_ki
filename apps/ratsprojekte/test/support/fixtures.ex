defmodule Ratsprojekte.Fixtures do
  @moduledoc """
  Kompakte Test-Fixtures für LiveView-Tests. Fiktive Beispieldaten, keine
  realen Projekte.

  Baut einen deterministischen Satz an Projekten auf:
    * `marktplatz()` — aktiv, Strang A (nicht erfüllt) + Strang B (erfüllt), nicht blockiert
    * `nordumgehung()` — verworfen, verworfen_am 2025-03-15
    * `sportplatz()` — idee, blockiert (kein erfüllter Strang)
    * `bibliothek()` — abgeschlossen, abgeschlossen_am 2025-02-01, blockiert
    * `freibad(attrs \\ %{})` — idee, Strang A erfüllt, Projekt-Quelle mit
      URL+Abrufdatum; die Antragsreife-Hard-Gate-Felder
      (`beschlussvorschlag`, `adressat`) sind bewusst ungesetzt — Tests
      können sie per `attrs` vorbelegen
  """

  alias Ratsprojekte.Repo

  alias Ratsprojekte.Schemas.{
    PendingProposal,
    Projekt,
    Quelle,
    Realisierungsstrang,
    Schritt,
    Vorbedingung
  }

  def marktplatz do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Marktplatz umgestalten",
        beschreibung: "Marktplatz aufwerten — Aufenthaltsqualität, Begrünung, Sitzgelegenheiten.",
        status: :aktiv,
        prioritaet: :hoch,
        slug: "marktplatz"
      })

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Über Städtebauförderung",
        beschreibung: "Erneuerungsgebiet förmlich festlegen und Städtebauförderung beantragen.",
        rechtliche_grundlage: "§ 136 BauGB",
        bedingung: "Erneuerungsgebiet muss förmlich festgelegt sein",
        bedingung_erfuellt: false
      })

    vorbedingung(strang_a, %{
      text: "Erneuerungsgebiet muss förmlich festgelegt sein",
      erfuellt: false,
      rechtliche_grundlage: "§ 136 BauGB"
    })

    vorbedingung(strang_a, %{
      text: "Mittelfristige Finanzierung muss gesichert sein",
      erfuellt: false
    })

    schritt(strang_a, %{text: "Gebietsfestlegung vorbereiten"})
    schritt(strang_a, %{text: "Bürgerbeteiligung durchführen"})

    quelle(strang_a, %{
      typ: :foerderprogramm,
      titel: "Städtebauförderungsrichtlinien — Zuschussmodul",
      paragraf: "§ 136 BauGB"
    })

    strang_b =
      strang(projekt, %{
        label: "B",
        titel: "Über Eigenleistung",
        beschreibung: "Umbau aus regulärem Haushalt ohne Förderverfahren.",
        rechtliche_grundlage: "Art. 61 BayGO",
        bedingung: "Haushaltsmittel müssen eingeplant sein",
        bedingung_erfuellt: true
      })

    vorbedingung(strang_b, %{
      text: "Haushaltsmittel müssen eingeplant sein",
      erfuellt: true,
      rechtliche_grundlage: "Art. 61 BayGO"
    })

    schritt(strang_b, %{text: "Haushaltsantrag vorbereiten"})

    projekt
  end

  def freibad(attrs \\ %{}) do
    defaults = %{
      titel: "Freibad: Kartenzahlung einführen",
      beschreibung: "Bargeldlose Zahlung an allen Freibad-Kassen.",
      status: :idee,
      prioritaet: :mittel,
      slug: "freibad-kartenzahlung-test"
    }

    {:ok, projekt} = Repo.insert(struct(Projekt, Map.merge(defaults, Map.new(attrs))))

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Kartenzahlung über den Bäderbetrieb beschaffen",
        beschreibung: "Terminalmiete und Kartengebühren über den Bäderhaushalt.",
        rechtliche_grundlage: "Art. 61 BayGO",
        bedingung: "Haushaltsmittel müssen eingeplant sein",
        bedingung_erfuellt: true
      })

    vorbedingung(strang_a, %{
      text: "Haushaltsmittel müssen eingeplant sein",
      erfuellt: true,
      rechtliche_grundlage: "Art. 61 BayGO"
    })

    quelle(projekt, %{
      typ: :sitzung,
      titel: "Finanz- und Werksausschuss: Haushaltsansatz Bäderbetrieb",
      url: "https://example.org/sitzung/2026-07-01",
      abrufdatum: ~D[2026-07-01]
    })

    projekt
  end

  def nordumgehung do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Nordumgehung prüfen",
        beschreibung: "Prüfung, ob eine Nordumgehung den Innenstadtverkehr entlasten kann.",
        status: :verworfen,
        prioritaet: :niedrig,
        verworfen_am: ~D[2025-03-15],
        verworfen_grund: "Keine politische Mehrheit im Gremium.",
        slug: "nordumgehung-test"
      })

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Nordumgehung als Entlastung der Innenstadt",
        beschreibung: "Ortsumgehung Nord.",
        rechtliche_grundlage: "Art. 13f BayFAG",
        bedingung: "Verkehrsgutachten muss Entlastungswirkung belegen",
        bedingung_erfuellt: false
      })

    vorbedingung(strang_a, %{
      text: "Verkehrsgutachten muss Entlastungswirkung belegen",
      erfuellt: false,
      rechtliche_grundlage: "Art. 13f BayFAG"
    })

    projekt
  end

  def sportplatz do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Sportplatz-Beleuchtung umstellen",
        beschreibung: "LED-Umrüstung mit Präsenzsteuerung auf dem Sportplatz.",
        status: :idee,
        prioritaet: :mittel,
        slug: "sportplatzbeleuchtung-test"
      })

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Bündel-Antrag LED-Umrüstung + Steuerung",
        beschreibung: "Beide Themen über dieselbe Infrastruktur.",
        rechtliche_grundlage: nil,
        bedingung: "Stadtratsbeschluss und Kosten-Nutzen-Analyse nötig",
        bedingung_erfuellt: false
      })

    vorbedingung(strang_a, %{
      text: "Stadtratsbeschluss zur Prüfung und Beauftragung",
      erfuellt: false
    })

    vorbedingung(strang_a, %{
      text: "Kosten-Nutzen-Analyse für das Steuerungssystem muss vorliegen",
      erfuellt: false,
      typ: :wissen_fehlt
    })

    projekt
  end

  def bibliothek do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Bibliothek modernisieren",
        beschreibung: "Umbau der Stadtbibliothek mit Medienarbeit und Lernorten.",
        status: :abgeschlossen,
        prioritaet: :hoch,
        abgeschlossen_am: ~D[2025-02-01],
        slug: "bibliothek-test"
      })

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Über Investpauschale",
        beschreibung: "Modernisierung über die investive Pauschale des Freistaats.",
        rechtliche_grundlage: "BayFAG (Investpauschale)",
        bedingung: "Mittelfreigabe muss vorliegen",
        bedingung_erfuellt: false
      })

    vorbedingung(strang_a, %{
      text: "Mittelfreigabe muss vorliegen",
      erfuellt: false,
      rechtliche_grundlage: "BayFAG (Investpauschale)"
    })

    projekt
  end

  def seed_all do
    marktplatz()
    nordumgehung()
    sportplatz()
    bibliothek()
    :ok
  end

  def proposal(projekt, attrs \\ %{}) do
    defaults = %{
      typ: :add_realisierungsstrang,
      payload: %{
        "label" => "D",
        "titel" => "Neuer Realisierungsstrang per Vorschlag",
        "beschreibung" => "Per Proposal angelegt — AI-Vorschlag.",
        "rechtliche_grundlage" => "§ 1 BeispielG",
        "bedingung" => "Beschluss des Stadtrats",
        "bedingung_erfuellt" => false
      },
      begruendung: "Ein Vorschlag, der die Argumente verbessert — mindestens 10 Zeichen lang.",
      quellen: "https://example.org/beleg",
      vorgeschlagen_von: "ai-harness",
      vorgeschlagen_am: DateTime.truncate(DateTime.utc_now(), :second),
      projekt_id: projekt.id
    }

    merged = Map.merge(defaults, attrs)

    # Status / Entscheidungsfelder gehen über decision_changeset, der Rest über propose_changeset.
    decision_fields = %{
      status: merged[:status],
      entschieden_am: merged[:entschieden_am],
      entschieden_von: merged[:entschieden_von],
      entscheidungskommentar: merged[:entscheidungskommentar]
    }

    base_attrs =
      Map.drop(merged, [:status, :entschieden_am, :entschieden_von, :entscheidungskommentar])

    changeset =
      %PendingProposal{}
      |> PendingProposal.propose_changeset(base_attrs)
      |> then(fn cs ->
        if decision_fields[:status] do
          PendingProposal.decision_changeset(cs, decision_fields)
        else
          cs
        end
      end)

    {:ok, proposal} = Repo.insert(changeset)

    proposal
  end

  defp strang(projekt, attrs) do
    {:ok, strang} =
      Repo.insert(%Realisierungsstrang{
        projekt_id: projekt.id,
        label: attrs[:label],
        titel: attrs[:titel],
        beschreibung: attrs[:beschreibung],
        rechtliche_grundlage: attrs[:rechtliche_grundlage],
        bedingung: attrs[:bedingung],
        bedingung_erfuellt: attrs[:bedingung_erfuellt]
      })

    strang
  end

  defp vorbedingung(strang, attrs) do
    {:ok, _} =
      Repo.insert(%Vorbedingung{
        realisierungsstrang_id: strang.id,
        text: attrs[:text],
        erfuellt: attrs[:erfuellt],
        rechtliche_grundlage: attrs[:rechtliche_grundlage],
        typ: attrs[:typ] || :rechtlich
      })

    :ok
  end

  defp schritt(strang, attrs) do
    {:ok, _} =
      Repo.insert(%Schritt{
        realisierungsstrang_id: strang.id,
        text: attrs[:text]
      })

    :ok
  end

  @doc """
  Legt eine Quelle an — am Projekt oder am Realisierungsstrang. Sitzungs-Quellen
  können die strukturierte RIS-Referenz tragen (Ticket #32):
  `ris_sitzung_id`, `ris_top`, `beschluss_nr`.
  """
  def quelle(%Realisierungsstrang{} = strang, attrs) do
    insert_quelle(Map.put(Map.new(attrs), :realisierungsstrang_id, strang.id))
  end

  def quelle(%Projekt{} = projekt, attrs) do
    insert_quelle(Map.put(Map.new(attrs), :projekt_id, projekt.id))
  end

  defp insert_quelle(attrs) do
    {:ok, _} =
      Repo.insert(%Quelle{
        projekt_id: attrs[:projekt_id],
        realisierungsstrang_id: attrs[:realisierungsstrang_id],
        typ: attrs[:typ],
        titel: attrs[:titel],
        url: attrs[:url],
        paragraf: attrs[:paragraf],
        abrufdatum: attrs[:abrufdatum],
        ris_sitzung_id: attrs[:ris_sitzung_id],
        ris_top: attrs[:ris_top],
        beschluss_nr: attrs[:beschluss_nr]
      })

    :ok
  end
end
