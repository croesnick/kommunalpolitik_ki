defmodule Ratsprojekte.MCP.Tools.CheckAntragsreife do
  @moduledoc """
  Prüfe ein Projekt auf Antragsreife und liefere einen strukturierten Report.

  Der Report enthält drei Klassen von Kriterien:

  - **Hard Gates**: strukturelle Muss-Kriterien, deterministisch in Elixir geprüft.
    Ein `fail` blockiert die Antragsreife.
  - **Soft Gates**: inhaltliche Kriterien, als `pending` markiert. Der
    AI-Harness bewertet diese per LLM anhand der Projektdaten.
  - **Politische Kriterien**: vom Stadtrat persönlich zu prüfen, als `unchecked`
    markiert. Die KI bewertet diese nicht (GO-Prinzip).

  Keine LLM-Calls in diesem Tool — es liefert nur strukturelle Fakten.
  Der Report ist transient und wird nicht in der DB persistiert.

  ## Prüf-Stufen

  Das Tool unterstützt zwei Stufen mit unterschiedlichen Schwellen:

  - `stufe: "fraktion"` — Fraktionsreife. Der Entwurf ist gut genug, um ihn
    in der Fraktion zu diskutieren. Hard Gates müssen `pass` sein, aber
    `warn` (offene Vorbedingungen) führt zu `fraktionsreif_mit_vorbehalten`
    statt zu harter Blockade. Politische Kriterien dürfen `unchecked` sein.
  - `stufe: "stadtrat"` (Default) — Stadtratsreife. Höchste Schwelle, alle
    Kriterien geprüft. `warn` führt zu `antragsreif_mit_vorbehalten`.

  Die Kriterien-Listen sind für beide Stufen identisch. Die Stufe beeinflusst
  nur die Empfehlung, nicht die Kriterien selbst.

  Verwende list_projekte, um den Slug zu finden.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{Projekt, Realisierungsstrang}
  import Ecto.Query
  import Ratsprojekte.Present

  @beschlussvorschlag_min_length 20
  @value_proposition_min_length 20
  @success_metrics_min_length 10

  # Reines „Digitalisierung von X" = kurze Nominalphrase ohne Aussage über
  # Problem oder Veränderung. Deterministisch trennbar ist nur die Kurzform
  # (maximal fünf Wörter nach „Digitalisierung", ohne Nebensatz) — als
  # :warn am Gate, nicht als Changeset-Veto: die inhaltliche Qualität
  # bewertet der AI-Harness (Soft Gates), und ein GO des Stadtrats darf
  # nicht an einer Regex scheitern.
  @pure_digitalisierung ~r/^\s*digitalisierung(\s+von)?\s+\S+(?:\s+\S+){0,4}\s*[.!]?\s*$/i

  schema do
    field(:slug, :string,
      required: true,
      description: "Projekt-Slug (von list_projekte)"
    )

    field(:stufe, :string,
      default: "stadtrat",
      description:
        "Prüfstufe: 'fraktion' (niedrigere Schwelle, politische Kriterien offen erlaubt) oder 'stadtrat' (höchste Schwelle, alle Kriterien geprüft). Default: 'stadtrat'."
    )
  end

  @impl true
  def execute(%{slug: slug, stufe: stufe}, frame) do
    projekt =
      Repo.one(
        from(p in Projekt,
          where: p.slug == ^slug,
          preload: [
            realisierungsstraenge:
              ^from(rs in Realisierungsstrang,
                order_by: rs.label,
                preload: [:vorbedingungen, :schritte, :quellen]
              ),
            quellen: []
          ]
        )
      )

    case projekt do
      nil ->
        {:reply, Response.error(Response.tool(), "Projekt '#{slug}' nicht gefunden"), frame}

      projekt ->
        {:reply, Response.json(Response.tool(), build_report(projekt, stufe)), frame}
    end
  end

  defp build_report(projekt, stufe) do
    hard_gates = hard_gates(projekt)
    empfehlung = empfehlung(hard_gates, stufe)

    %{
      projekt_slug: projekt.slug,
      projekt_titel: projekt.titel,
      stufe: stufe,
      check_datum: DateTime.to_iso8601(DateTime.utc_now()),
      hard_gates: hard_gates,
      soft_gates: soft_gates(),
      politische_kriterien: politische_kriterien(),
      empfehlung: empfehlung,
      quelle: "ratsprojekte Projekt '#{projekt.slug}', Stand #{Date.to_iso8601(Date.utc_today())}"
    }
  end

  # --- Hard Gates ---

  defp hard_gates(projekt) do
    [
      gate_quellen_vorhanden(projekt),
      gate_adressat_gesetzt(projekt),
      gate_beschlussvorschlag_konkret(projekt),
      gate_value_proposition_vorhanden(projekt),
      gate_success_metrics_vorhanden(projekt),
      gate_realisierungsstrang_vorhanden(projekt),
      gate_vorbedingungen_erfuellt(projekt)
    ]
  end

  defp gate_quellen_vorhanden(projekt) do
    projekt_quellen = projekt.quellen
    strang_quellen = Enum.flat_map(projekt.realisierungsstraenge, & &1.quellen)
    alle_quellen = projekt_quellen ++ strang_quellen

    mit_url_abrufdatum =
      Enum.count(alle_quellen, fn q ->
        present?(q.url) and present?(q.abrufdatum)
      end)

    cond do
      alle_quellen == [] ->
        gate(:quellen_vorhanden, :fail, "Keine Quellen vorhanden")

      mit_url_abrufdatum == 0 ->
        gate(
          :quellen_vorhanden,
          :fail,
          "#{length(alle_quellen)} Quellen, aber keine mit URL+abrufdatum"
        )

      true ->
        gate(
          :quellen_vorhanden,
          :pass,
          "#{length(alle_quellen)} Quellen, #{mit_url_abrufdatum} mit URL+abrufdatum"
        )
    end
  end

  defp gate_adressat_gesetzt(projekt) do
    if present?(projekt.adressat) do
      gate(:adressat_gesetzt, :pass, "Adressat: #{projekt.adressat}")
    else
      gate(:adressat_gesetzt, :fail, "Feld 'adressat' ist nicht gesetzt")
    end
  end

  # Gemeinsame Struktur der Feld-Gates: gesetzt, nicht leer, länger als die
  # Schwellen aus priv/antragsreife_kriterien.md.
  defp gate_feld_konkret(projekt, kriterium, field, min_length, label) do
    value = Map.get(projekt, field)

    cond do
      blank?(value) ->
        gate(kriterium, :fail, "Feld '#{field}' ist nicht gesetzt")

      String.length(value) <= min_length ->
        gate(kriterium, :fail, "#{label} zu kurz (<= #{min_length} Zeichen)")

      true ->
        gate(kriterium, :pass, "#{label} gesetzt (#{String.length(value)} Zeichen)")
    end
  end

  defp gate_beschlussvorschlag_konkret(projekt) do
    gate_feld_konkret(
      projekt,
      :beschlussvorschlag_konkret,
      :beschlussvorschlag,
      @beschlussvorschlag_min_length,
      "Beschlussvorschlag"
    )
  end

  defp gate_value_proposition_vorhanden(projekt) do
    base =
      gate_feld_konkret(
        projekt,
        :value_proposition_vorhanden,
        :value_proposition,
        @value_proposition_min_length,
        "Value Proposition"
      )

    if base.status == :pass and pure_digitalisierung?(projekt.value_proposition) do
      %{
        base
        | status: :warn,
          detail:
            base.detail <> " — wirkt wie ein reines „Digitalisierung von X“ (Soft Gate prüfen)"
      }
    else
      base
    end
  end

  defp gate_success_metrics_vorhanden(projekt) do
    gate_feld_konkret(
      projekt,
      :success_metrics_vorhanden,
      :success_metrics,
      @success_metrics_min_length,
      "Success Metrics"
    )
  end

  defp pure_digitalisierung?(value) when is_binary(value),
    do: String.trim(value) =~ @pure_digitalisierung

  defp pure_digitalisierung?(_), do: false

  defp gate_realisierungsstrang_vorhanden(projekt) do
    straenge = projekt.realisierungsstraenge

    if straenge == [] do
      gate(:realisierungsstrang_vorhanden, :fail, "Keine Realisierungsstränge vorhanden")
    else
      labels = Enum.reject(Enum.map(straenge, & &1.label), &blank?/1)

      gate(
        :realisierungsstrang_vorhanden,
        :pass,
        "#{length(straenge)} Realisierungsstränge (#{Enum.join(labels, ", ")})"
      )
    end
  end

  defp gate_vorbedingungen_erfuellt(projekt) do
    straenge = projekt.realisierungsstraenge

    if straenge == [] do
      gate(:vorbedingungen_erfuellt, :warn, "Keine Stränge — Vorbedingungen nicht prüfbar")
    else
      per_strang =
        Enum.map(straenge, fn strang ->
          vorb = strang.vorbedingungen
          erfuellt = Enum.count(vorb, & &1.erfuellt)
          offen = length(vorb) - erfuellt
          {strang.label, erfuellt, offen, length(vorb), vorb}
        end)

      vorbedingungen_report(per_strang)
    end
  end

  defp vorbedingungen_report(per_strang) do
    gesamt_offen = Enum.reduce(per_strang, 0, fn {_, _, offen, _, _}, acc -> acc + offen end)

    if gesamt_offen == 0 do
      gate(:vorbedingungen_erfuellt, :pass, "Alle Stränge: alle Vorbedingungen erfüllt")
    else
      details = Enum.map_join(per_strang, "; ", &format_strang_report/1)
      gate(:vorbedingungen_erfuellt, :warn, details)
    end
  end

  defp format_strang_report({label, _erfuellt, _offen, _gesamt, vorb}) do
    by_typ =
      vorb
      |> Enum.group_by(& &1.typ)
      |> Enum.map_join(", ", fn {typ, items} ->
        erfuellt_typ = Enum.count(items, & &1.erfuellt)
        "#{erfuellt_typ}/#{length(items)} #{typ}"
      end)

    "Strang #{label}: #{by_typ} erfüllt"
  end

  defp gate(kriterium, status, detail) do
    %{kriterium: kriterium, status: status, detail: detail}
  end

  # --- Empfehlung ---

  defp empfehlung(hard_gates, stufe) do
    statuses = Enum.map(hard_gates, & &1.status)

    cond do
      :fail in statuses -> empfehlung_fail(stufe)
      :warn in statuses -> empfehlung_warn(stufe)
      true -> empfehlung_pass(stufe)
    end
  end

  defp empfehlung_fail("fraktion"), do: "nicht_fraktionsreif"
  defp empfehlung_fail(_stufe), do: "nicht_antragsreif"

  defp empfehlung_warn("fraktion"), do: "fraktionsreif_mit_vorbehalten"
  defp empfehlung_warn(_stufe), do: "antragsreif_mit_vorbehalten"

  defp empfehlung_pass("fraktion"), do: "fraktionsreif"
  defp empfehlung_pass(_stufe), do: "antragsreif"

  # --- Soft Gates (LLM-bewertet durch AI-Harness) ---

  defp soft_gates do
    [
      %{
        kriterium: :finanzierung_angesprochen,
        status: :pending,
        hinweis: "Prüfe, ob Beschlussvorschlag oder Beschreibung Finanzierung erwähnt"
      },
      %{
        kriterium: :rechtliche_grundlagen_genannt,
        status: :pending,
        hinweis: "Prüfe strang.rechtliche_grundlage und vorbedingungen.rechtliche_grundlage"
      },
      %{
        kriterium: :fristen_gesetzt,
        status: :pending,
        hinweis: "Prüfe schritt.frist auf Vorhandensein und Realismus"
      }
    ]
  end

  # --- Politische Kriterien (vom Stadtrat zu prüfen) ---

  defp politische_kriterien do
    [
      %{
        kriterium: :tonalitaet_sachlich,
        status: :unchecked,
        hinweis: "Vom Stadtrat zu prüfen"
      },
      %{
        kriterium: :konsensfaehigkeit,
        status: :unchecked,
        hinweis: "Vom Stadtrat zu prüfen"
      },
      %{
        kriterium: :widerspruch_fraktionsposition,
        status: :unchecked,
        hinweis: "Vom Stadtrat zu prüfen"
      }
    ]
  end

  # --- Helpers ---
end
