defmodule Ratsprojekte.MCP.Tools.ShowProjekt do
  @moduledoc """
  Zeige ein einzelnes Projekt mit allen Realisierungssträngen, Vorbedingungen,
  Schritten und Quellen.

  Liefert die vollständige rechtlich-inhaltliche Standortbestimmung:
  - Alle Realisierungsstränge (A/B/C) mit Bedingung und Erfüllt-Status
  - Vorbedingungen mit rechtlicher Grundlage und Erfüllt-Status
  - Geordnete Schritte mit optionalen Fristen
  - Quellen mit URL, Paragraf und Typ

  Verwende list_projekte, um die Projekt-ID zu finden.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{Projekt, Realisierungsstrang}
  import Ecto.Query

  schema do
    field(:id, :integer,
      required: true,
      description: "Projekt-ID (von list_projekte)"
    )
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
        {:reply, Response.json(Response.tool(), format(projekt)), frame}
    end
  end

  defp format(projekt) do
    %{
      id: projekt.id,
      titel: projekt.titel,
      beschreibung: projekt.beschreibung,
      status: projekt.status,
      prioritaet: projekt.prioritaet,
      realisierungsstraenge: Enum.map(projekt.realisierungsstraenge, &format_strang/1),
      projekt_quellen: Enum.map(projekt.quellen, &format_quelle/1)
    }
  end

  defp format_strang(strang) do
    vorbedingungen = Enum.sort_by(strang.vorbedingungen, & &1.position)
    schritte = Enum.sort_by(strang.schritte, & &1.position)

    erfuellt = Enum.count(vorbedingungen, & &1.erfuellt)
    offen = length(vorbedingungen) - erfuellt

    %{
      label: strang.label,
      titel: strang.titel,
      beschreibung: strang.beschreibung,
      rechtliche_grundlage: strang.rechtliche_grundlage,
      bedingung: strang.bedingung,
      bedingung_erfuellt: strang.bedingung_erfuellt,
      vorbedingungen_erfuellt: erfuellt,
      vorbedingungen_offen: offen,
      vorbedingungen: Enum.map(vorbedingungen, &format_vorbedingung/1),
      schritte: Enum.map(schritte, &format_schritt/1),
      quellen: Enum.map(strang.quellen, &format_quelle/1)
    }
  end

  defp format_vorbedingung(vorb) do
    %{
      text: vorb.text,
      erfuellt: vorb.erfuellt,
      rechtliche_grundlage: vorb.rechtliche_grundlage
    }
  end

  defp format_schritt(schritt) do
    %{
      text: schritt.text,
      frist: schritt.frist
    }
  end

  defp format_quelle(quelle) do
    %{
      typ: quelle.typ,
      titel: quelle.titel,
      url: quelle.url,
      paragraf: quelle.paragraf,
      abrufdatum: quelle.abrufdatum
    }
  end
end
