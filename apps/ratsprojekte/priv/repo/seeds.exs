# Seeds für den Hub: `mix run priv/repo/seeds.exs` (Teil von `mix ecto.setup`).
#
# Regel aus #435: Seeds zeigen ausschließlich erfundene Gartenstadt-Projekte —
# das Universum des Referenzszenarios (docs/szenarien/radweg-bahnhofstrasse.md,
# „Daten: ausschließlich erfunden; Personen, Beträge, Flurstücke und
# Verhandlungen gibt es nicht“). Echte Ratsarbeit gehört nie in diese Datei
# und nie in das Repo.
#
# Eingetragen wird nur über die Kontextfunktionen (#436), so wie die
# Oberfläche es tut; der Verlauf schreibt sich dabei selbst. Nur für Dev
# und Tests: Der Hub im Release startet leer (ADR 0004: „Es gibt keinen
# Import und keine geregelte Übernahme“). Ein zweiter Lauf trägt nichts
# doppelt ein.

defmodule Ratsprojekte.Seeds do
  @moduledoc false

  alias Ratsprojekte.Projects

  def run do
    if Projects.list_projects() == [] do
      radweg()
      sanierung()
      radweg_nord()
      sitzbaenke()
      IO.puts("Seeds: #{length(Projects.list_projects())} erfundene Gartenstadt-Projekte eingetragen.")
    else
      IO.puts("Seeds: Der Hub hat schon Projekte, nichts eingetragen.")
    end
  end

  defp radweg do
    p =
      new(%{
        title: "Radweg Bahnhofstraße",
        short: "Sichere Radverkehrsführung im 1. Bauabschnitt, möglichst mit Förderung.",
        origin: "Fraktion",
        on: ~D[2026-09-18]
      })

    p =
      ok(
        Projects.record_event(p, %{
          text: "Fraktion will die Engstelle Bahnhofstraße angehen.",
          by: :fraction,
          phase: :drafting,
          on: ~D[2026-10-05]
        })
      )

    p =
      ok(
        Projects.record_event(p, %{
          text: "Sicherer Schulweg entlang der Bahnhofstraße ist der Basis am wichtigsten.",
          by: :base,
          on: ~D[2026-10-20]
        })
      )

    p =
      ok(
        Projects.record_event(p, %{
          text: "Händler wehren sich laut Zeitung gegen den Wegfall der Parkplätze.",
          on: ~D[2026-11-03],
          step_text: "Antrag zur Sitzung am 17.11.2026 vorbereiten",
          step_assignee: "ich",
          step_due_on: ~D[2026-11-13]
        })
      )

    p =
      ok(
        Projects.add_fact(p, %{
          statement:
            "Die Sanierung der Bahnhofstraße läuft in zwei Bauabschnitten (Baukosten 1,2 Mio. Euro).",
          citation: "RIS, TOP 1001-1 „Sanierung der Bahnhofstraße“, September 2026",
          fetched_on: ~D[2026-11-02],
          verified: true,
          on: ~D[2026-11-02]
        })
      )

    p =
      ok(
        Projects.add_fact(p, %{
          statement: "Bayerische Kommunen bekommen Fördermittel für Radwege in Ortsdurchfahrten.",
          citation: "Öffentliche Recherche (komki-Raum), Fundstelle im Förderprogramm-Steckbrief",
          fetched_on: ~D[2026-11-09],
          on: ~D[2026-11-09]
        })
      )

    p =
      Enum.reduce(
        ["Einbahnregelung mit Schutzstreifen", "Wegfall des Parkstreifens Nord", "Umleitung über die Gartenstraße"],
        p,
        &ok(Projects.add_variant(&2, %{title: &1, on: ~D[2026-11-04]}))
      )

    ok(Projects.add_cross_reference(p, %{kind: :komki_room, target: "r-gartenstadt-7f3a"}))
  end

  defp sanierung do
    p =
      new(%{
        title: "Sanierung Bahnhofstraße, 1. Bauabschnitt",
        short: "Ausführungsplanung mit Radverkehrsführung.",
        origin: "Stadtrat",
        on: ~D[2026-09-18]
      })

    p =
      ok(
        Projects.record_event(p, %{
          text: "Stadtrat beschließt die Sanierung in zwei Bauabschnitten.",
          by: :council,
          phase: :at_council,
          on: ~D[2026-09-18]
        })
      )

    p =
      ok(
        Projects.create_motion(p, %{
          title: "Radverkehrsführung im 1. Bauabschnitt",
          motion_text:
            "Ausführungsplanung des 1. Bauabschnitts zustimmen und die Radverkehrsführung festlegen",
          addressee: "Stadtrat",
          document_ref: "Nextcloud, Ordner Anträge",
          on: ~D[2026-11-05]
        })
      )

    ok(
      Projects.record_motion_event(p, hd(p.motions), %{
        status: :submitted,
        submitted_on: ~D[2026-11-10],
        ris: "Sitzung 1003, TOP 1",
        text: "Antrag der Fraktion eingereicht.",
        by: :fraction,
        step_text: "Beschluss in der Sitzung am 17.11.2026",
        step_assignee: "Selin",
        step_due_on: ~D[2026-11-17],
        on: ~D[2026-11-10]
      })
    )
  end

  defp radweg_nord do
    p =
      new(%{
        title: "Radweg Nord",
        short: "Lückenschluss zwischen Gartenstadt-Nord und dem Bahnhof.",
        origin: "Ortsverband",
        on: ~D[2026-11-08]
      })

    ok(Projects.set_next_step(p, %{text: "Idee im Vorstand vorstellen", assignee: "ich", on: ~D[2026-11-08]}))
  end

  defp sitzbaenke do
    p =
      new(%{
        title: "Sitzbänke am Stadtweiher",
        short: "Rund um den Weiher fehlen Bänke für ältere Menschen.",
        origin: "Seniorenbeirat",
        on: ~D[2026-04-14]
      })

    ok(
      Projects.dispose(p, %{
        disposition: "resting",
        reason: "Erst nach dem Haushalt 2027 wieder aufgreifen.",
        by: "fraction",
        on: ~D[2026-06-02]
      })
    )
  end

  defp new(attrs), do: ok(Projects.create_project(attrs))

  defp ok({:ok, value}), do: value
end

Ratsprojekte.Seeds.run()
