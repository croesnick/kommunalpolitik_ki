defmodule Ratsprojekte.MCP.Tools.ListProjekte do
  @moduledoc """
  Liste alle Stadtratsprojekte mit Status, Priorität und Anzahl Realisierungsstränge.

  Nützlich für einen ersten Überblick über alle Projekte im Tracker.
  Für Details zu einem einzelnen Projekt, verwende show_projekt.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  import Ecto.Query

  schema do
    field(:status, :string,
      description: "Filter nach Status: 'idee', 'aktiv' oder 'abgeschlossen'"
    )

    field(:limit, :integer, default: 50, description: "Maximale Anzahl Ergebnisse")
  end

  @impl true
  def execute(params, frame) do
    status = params[:status]
    limit = params[:limit] || 50

    query =
      from(p in Projekt,
        order_by: [desc: p.prioritaet, desc: p.inserted_at],
        limit: ^limit,
        preload: [realisierungsstraenge: []]
      )

    query =
      if status do
        from(p in query, where: p.status == ^status)
      else
        query
      end

    projekte = Repo.all(query)

    formatted = Enum.map(projekte, &format/1)

    {:reply, Response.json(Response.tool(), formatted), frame}
  end

  defp format(projekt) do
    %{
      id: projekt.id,
      titel: projekt.titel,
      beschreibung: projekt.beschreibung,
      status: projekt.status,
      prioritaet: projekt.prioritaet,
      anzahl_straenge: length(projekt.realisierungsstraenge),
      url: "http://localhost:4000/projekte/#{projekt.id}"
    }
  end
end
