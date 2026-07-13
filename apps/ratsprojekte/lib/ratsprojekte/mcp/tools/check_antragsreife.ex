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

  Verwende list_projekte, um die Projekt-ID zu finden.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{Projekt, Realisierungsstrang}
  import Ecto.Query

  @beschlussvorschlag_min_length 20

  schema do
    field :id, :integer,
      required: true,
      description: "Projekt-ID (von list_projekte)"
  end

  @impl true
  def execute(%{id: id}, frame) do
    projekt =
      Repo.one(
        from(p in Projekt,
          where: p.id == ^id,
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
        {:reply, Response.error(Response.tool(), "Projekt #{id} nicht gefunden"), frame}

      projekt ->
        {:reply, Response.json(Response.tool(), build_report(projekt)), frame}
    end
  end

  defp build_report(projekt) do
    hard_gates = hard_gates(projekt)
    empfehlung = empfehlung(hard_gates)

    %{
      projekt_id: projekt.id,
      projekt_titel: projekt.titel,
      check_datum: DateTime.to_iso8601(DateTime.utc_now()),
      hard_gates: hard_gates,
      soft_gates: soft_gates(),
      politische_kriterien: politische_kriterien(),
      empfehlung: empfehlung,
      quelle: "ratsprojekte Projekt ##{projekt.id}, Stand #{Date.to_iso8601(Date.utc_today())}"
    }
  end

  # --- Hard Gates ---

  defp hard_gates(projekt) do
    [
      gate_quellen_vorhanden(projekt),
      gate_adressat_gesetzt(projekt),
      gate_beschlussvorschlag_konkret(projekt),
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

  defp gate_beschlussvorschlag_konkret(projekt) do
    cond do
      blank?(projekt.beschlussvorschlag) ->
        gate(:beschlussvorschlag_konkret, :fail, "Feld 'beschlussvorschlag' ist nicht gesetzt")

      String.length(projekt.beschlussvorschlag) <= @beschlussvorschlag_min_length ->
        gate(
          :beschlussvorschlag_konkret,
          :fail,
          "Beschlussvorschlag zu kurz (<= #{@beschlussvorschlag_min_length} Zeichen)"
        )

      true ->
        gate(
          :beschlussvorschlag_konkret,
          :pass,
          "Beschlussvorschlag gesetzt (#{String.length(projekt.beschlussvorschlag)} Zeichen)"
        )
    end
  end

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
          {strang.label, erfuellt, offen, length(vorb)}
        end)

      vorbedingungen_report(per_strang)
    end
  end

  defp vorbedingungen_report(per_strang) do
    gesamt_offen = Enum.reduce(per_strang, 0, fn {_, _, offen, _}, acc -> acc + offen end)

    if gesamt_offen == 0 do
      gate(:vorbedingungen_erfuellt, :pass, "Alle Stränge: alle Vorbedingungen erfüllt")
    else
      details =
        Enum.map_join(per_strang, "; ", fn {label, erfuellt, _offen, gesamt} ->
          "Strang #{label}: #{erfuellt} von #{gesamt} erfüllt"
        end)

      gate(:vorbedingungen_erfuellt, :warn, details)
    end
  end

  defp gate(kriterium, status, detail) do
    %{kriterium: kriterium, status: status, detail: detail}
  end

  # --- Empfehlung ---

  defp empfehlung(hard_gates) do
    statuses = Enum.map(hard_gates, & &1.status)

    cond do
      :fail in statuses -> "nicht_antragsreif"
      :warn in statuses -> "antragsreif_mit_vorbehalten"
      true -> "antragsreif"
    end
  end

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

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: true

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
