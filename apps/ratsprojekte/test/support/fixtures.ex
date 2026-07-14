defmodule Ratsprojekte.Fixtures do
  @moduledoc """
  Kompakte Test-Fixtures für LiveView-Tests.

  Baut einen deterministischen Satz an Projekten auf:
    * `bahnhofstr()` — aktiv, Strang A (nicht erfüllt) + Strang B (erfüllt), nicht blockiert
    * `westtangente()` — verworfen, verworfen_am 2025-03-15
    * `freibad()` — idee, blockiert (kein erfüllter Strang)
    * `gennachpark()` — abgeschlossen, abgeschlossen_am 2025-02-01, blockiert
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

  def bahnhofstr do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Bahnhofstraße umgestalten",
        beschreibung: "Boulevard Bahnhofstraße — Tempo 30, Begrünung, Sitzgelegenheiten.",
        status: :aktiv,
        prioritaet: :hoch
      })

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Westtangente als Ortsumgehung bauen",
        beschreibung: "Westtangente als OU → Bahnhofstraße wird Gemeindestraße.",
        rechtliche_grundlage: "Art. 13f BayFAG",
        bedingung: "Westtangente muss als OU qualifizieren",
        bedingung_erfuellt: false
      })

    vorbedingung(strang_a, %{
      text: "Westtangente muss als OU im Sinne des Art. 13f BayFAG qualifizieren",
      erfuellt: false,
      rechtliche_grundlage: "Art. 13f BayFAG"
    })

    vorbedingung(strang_a, %{
      text:
        "Verkehrsgutachten muss belegen, dass die Westtangente die Verkehrslast übernehmen kann",
      erfuellt: false
    })

    schritt(strang_a, %{text: "Verkehrsgutachten erstellen"})
    schritt(strang_a, %{text: "Staatliches Bauamt anfragen"})

    quelle(strang_a, %{
      typ: :gesetz,
      titel: "Art. 13f BayFAG — Sonderbaulast-Modell",
      paragraf: "Art. 13f BayFAG"
    })

    strang_b =
      strang(projekt, %{
        label: "B",
        titel: "Direkte Umstufung ohne Ortsumgehung",
        beschreibung: "Staatsstraße direkt umstufen.",
        rechtliche_grundlage: "Art. 7 BayStrWG",
        bedingung: "Verkehrsrückgang muss belegt werden.",
        bedingung_erfuellt: true
      })

    vorbedingung(strang_b, %{
      text: "Verkehrsrückgang muss mit Daten belegt werden",
      erfuellt: true,
      rechtliche_grundlage: "Art. 7 BayStrWG"
    })

    schritt(strang_b, %{text: "VEP-Daten aufbereiten"})

    projekt
  end

  def westtangente do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Westtangente prüfen",
        beschreibung: "Prüfung, ob eine Westtangente die Bahnhofstraße entlasten kann.",
        status: :verworfen,
        prioritaet: :niedrig,
        verworfen_am: ~D[2025-03-15],
        verworfen_grund: "Keine politische Mehrheit im Bauausschuss 03/2025."
      })

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Westtangente als Entlastung der Bahnhofstraße",
        beschreibung: "Ortsumgehung West.",
        rechtliche_grundlage: "Art. 13f BayFAG",
        bedingung: "Verkehrsgutachten muss Entlastung belegen",
        bedingung_erfuellt: false
      })

    vorbedingung(strang_a, %{
      text: "Verkehrsgutachten muss Entlastung der Bahnhofstraße belegen",
      erfuellt: false,
      rechtliche_grundlage: "Art. 13f BayFAG"
    })

    projekt
  end

  def freibad do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Freibad Digitalisierung",
        beschreibung: "Smart Metering + Kartenzahlung im Freibad.",
        status: :idee,
        prioritaet: :mittel
      })

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Bündel-Antrag Smart Metering + Kartenzahlung",
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
      text: "Kosten-Nutzen-Analyse für Kartenterminals muss vorliegen",
      erfuellt: false,
      typ: :wissen_fehlt
    })

    projekt
  end

  def gennachpark do
    {:ok, projekt} =
      Repo.insert(%Projekt{
        titel: "Gennachpark / Moorpark",
        beschreibung: "Mehrgenerationen-Moorpark im Süden Buchloes.",
        status: :abgeschlossen,
        prioritaet: :hoch,
        abgeschlossen_am: ~D[2025-02-01]
      })

    strang_a =
      strang(projekt, %{
        label: "A",
        titel: "Über Städtebauförderung (Umweltbeitrag)",
        beschreibung: "Städtebauförderung mit Umweltbeitrag wegen Moor-Revitalisierung.",
        rechtliche_grundlage: "Bayerische Städtebauförderungsrichtlinien",
        bedingung: "Bebauungsplan muss vorhanden sein und Umweltbeitrag muss anerkannt werden",
        bedingung_erfuellt: false
      })

    vorbedingung(strang_a, %{
      text: "Bebauungsplan muss vorhanden sein (FNP allein reicht nicht)",
      erfuellt: false,
      rechtliche_grundlage: "§ 9 BauGB"
    })

    projekt
  end

  def seed_all do
    bahnhofstr()
    westtangente()
    freibad()
    gennachpark()
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

  defp quelle(strang, attrs) do
    {:ok, _} =
      Repo.insert(%Quelle{
        realisierungsstrang_id: strang.id,
        typ: attrs[:typ],
        titel: attrs[:titel],
        url: attrs[:url],
        paragraf: attrs[:paragraf]
      })

    :ok
  end
end
