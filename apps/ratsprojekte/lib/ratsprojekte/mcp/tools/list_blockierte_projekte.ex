defmodule Ratsprojekte.MCP.Tools.ListBlockierteProjekte do
  @moduledoc """
  Liste alle Stadtratsprojekte, die festhängen — bei denen kein gangbarer
  Realisierungsstrang offen ist.

  Ein Projekt gilt als **blockiert**, wenn KEIN seiner Realisierungsstränge
  `bedingung_erfuellt: true` hat. Das heißt alle Stränge sind blockiert → das
  Projekt kommt nicht voran. Projekte ohne jegliche Stränge gelten ebenfalls
  als blockiert (kein Weg gangbar).

  Nützlich für die Frage: „Bei welchen Projekten hängen wir fest?"

  Der Output enthält pro Projekt `anzahl_straenge_erfuellt` — bei blockierten
  Projekten ist dieser Wert `0`. Für Details zu einem einzelnen Projekt
  verwende show_projekt, für frei filterbare Listen list_projekte.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  import Ecto.Query

  schema do
    field(:limit, :integer, default: 50, description: "Maximale Anzahl Ergebnisse")
  end

  @impl true
  def execute(params, frame) do
    limit = params[:limit] || 50

    projekte =
      Repo.all(
        from(p in Projekt,
          order_by: [desc: p.prioritaet, desc: p.inserted_at],
          limit: ^limit,
          preload: [realisierungsstraenge: []]
        )
      )

    blockierte =
      projekte
      |> Enum.filter(&blockiert?/1)
      |> Enum.map(&format/1)

    {:reply, Response.json(Response.tool(), blockierte), frame}
  end

  defp blockiert?(projekt) do
    not Enum.any?(projekt.realisierungsstraenge, & &1.bedingung_erfuellt)
  end

  defp format(projekt) do
    straenge = projekt.realisierungsstraenge
    erfuellt = Enum.count(straenge, & &1.bedingung_erfuellt)

    %{
      id: projekt.id,
      titel: projekt.titel,
      status: projekt.status,
      prioritaet: projekt.prioritaet,
      anzahl_straenge: length(straenge),
      anzahl_straenge_erfuellt: erfuellt,
      url: "http://localhost:4000/projekte/#{projekt.id}"
    }
  end
end
