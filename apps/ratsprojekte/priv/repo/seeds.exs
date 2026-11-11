# Seeds für den Hub.
#
# Regel aus #435: Seeds zeigen ausschließlich erfundene Gartenstadt-Projekte —
# das Universum des Referenzszenarios (docs/szenarien/radweg-bahnhofstrasse.md,
# „Daten: ausschließlich erfunden; Personen, Beträge, Flurstücke und
# Verhandlungen gibt es nicht“). Echte Ratsarbeit gehört nie in diese Datei
# und nie in das Repo.
#
# Die Felder folgen dem kleinen Modell aus ADR 0004. Verbindlich benannt
# aus #414 ist Antrag = `motion` (dazu proposal, briefing, filing, die
# #436 setzt); dieser Schlüssel heißt hier entsprechend `motions`. Die
# übrigen Schlüssel bleiben in der Domänensprache, bis #436 die Feldnamen
# des Schemas festlegt. Das Eintragen gegen Schema und Kontext baut
# Ticket #436 — bis dahin zeigt run/0 den Datensatz nur an und trägt
# nichts in die Datenbank ein. Der Hub startet leer (ADR 0004: „Es gibt
# keinen Import und keine geregelte Übernahme“).

defmodule Ratsprojekte.Seeds do
  @moduledoc """
  Erfundene Gartenstadt-Projekte als Demo-Bestand. Nur lesen und anzeigen —
  das Eintragen kommt mit dem Schema (Ticket #436).
  """

  @projects [
    %{
      titel: "Radweg Bahnhofstraße",
      phase: :ausarbeitung,
      naechster_schritt: "Antrag zur Sitzung am 17.11.2026 vorbereiten",
      ablage: nil,
      verlauf: [
        %{datum: ~D[2026-09-18], kreis: :redaktion,
          text: "Idee aus der Fraktionssitzung aufgenommen: Engstelle Bahnhofstraße angehen."},
        %{datum: ~D[2026-10-05], kreis: :redaktion,
          text: "Bauausschuss vertagt das Radverkehrskonzept für die Bahnhofstraße."},
        %{datum: ~D[2026-11-03], kreis: :engerer_kreis,
          text: "Zeitungsbericht eingeordnet: Händler wehren sich gegen den Wegfall der Parkplätze."}
      ],
      meinungsbilder: [
        %{kreis: :basis, datum: ~D[2026-10-20],
          satz: "Sicherer Schulweg entlang der Bahnhofstraße ist der Basis am wichtigsten.",
          verteilung: %{dafür: 12, offen: 3, dagegen: 1}}
      ],
      fakten: [
        %{aussage: "Die Sanierung der Bahnhofstraße läuft in zwei Bauabschnitten (Baukosten 1,2 Mio. Euro).",
          beleg: "RIS, TOP 1001-1 „Sanierung der Bahnhofstraße“, September 2026",
          datum: ~D[2026-11-02], pruefstatus: :verifiziert},
        %{aussage: "Bayerische Kommunen bekommen Fördermittel für Radwege in Ortsdurchfahrten.",
          beleg: "Öffentliche Recherche (komki-Raum), Fundstelle im Förderprogramm-Steckbrief",
          datum: ~D[2026-11-09], pruefstatus: :nicht_verifiziert}
      ],
      varianten: [
        %{titel: "Einbahnregelung mit Schutzstreifen", status: :offen},
        %{titel: "Wegfall des Parkstreifens Nord", status: :offen},
        %{titel: "Umleitung über die Gartenstraße", status: :offen}
      ],
      motions: []
    },
    %{
      titel: "Sanierung Bahnhofstraße, 1. Bauabschnitt",
      phase: :im_rat,
      naechster_schritt: "Beschluss in der Sitzung am 17.11.2026",
      ablage: nil,
      verlauf: [
        %{datum: ~D[2026-09-18], kreis: :redaktion,
          text: "Stadtrat beschließt die Sanierung in zwei Bauabschnitten."},
        %{datum: ~D[2026-11-10], kreis: :redaktion,
          text: "Antrag der Fraktion eingereicht: Radverkehrsführung mit Förderung im 1. Bauabschnitt."}
      ],
      meinungsbilder: [],
      fakten: [],
      varianten: [],
      motions: [
        %{adressat: "Stadtrat",
          beschlussvorschlag: "Ausführungsplanung des 1. Bauabschnitts zustimmen und die Radverkehrsführung festlegen",
          status: :eingereicht, ergebnis: nil,
          querverweis: "Ratsinformationssystem, Sitzung 1003, TOP 1"}
      ]
    },
    %{
      titel: "Radweg Nord",
      phase: :idee,
      naechster_schritt: "Idee im Vorstand vorstellen",
      ablage: nil,
      verlauf: [
        %{datum: ~D[2026-11-08], kreis: :engerer_kreis,
          text: "Vom Ortsverband als Projektidee eingebracht (Vault-Notiz „Projektidee Radweg Nord“)."}
      ],
      meinungsbilder: [],
      fakten: [],
      varianten: [],
      motions: []
    }
  ]

  def projects, do: @projects

  def run do
    IO.puts("Seeds: #{length(@projects)} erfundene Gartenstadt-Projekte.\n")

    for project <- @projects do
      IO.puts([
        "- ", project.titel, " (", "Phase: ", phase_label(project.phase), ")\n",
        "  Nächster Schritt: ", project.naechster_schritt, "\n",
        "  Verlauf: ", Integer.to_string(length(project.verlauf)), " Einträge, ",
        "Varianten: ", Integer.to_string(length(project.varianten)), ", ",
        "Anträge: ", Integer.to_string(length(project.motions)), "\n"
      ])
    end

    IO.puts("""

    Diese Datei zeigt den Demo-Bestand nur an. Das Eintragen in die Datenbank \
    baut Ticket #436 (Schema und Kontext) — der Hub startet leer (ADR 0004).
    """)
  end

  defp phase_label(:idee), do: "Idee"
  defp phase_label(:meinungsbildung), do: "Meinungsbildung"
  defp phase_label(:ausarbeitung), do: "Ausarbeitung"
  defp phase_label(:im_rat), do: "Im Rat"
  defp phase_label(:umsetzung), do: "Umsetzung"
end

Ratsprojekte.Seeds.run()
