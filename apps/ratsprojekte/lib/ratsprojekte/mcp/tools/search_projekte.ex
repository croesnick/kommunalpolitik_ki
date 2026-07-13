defmodule Ratsprojekte.MCP.Tools.SearchProjekte do
  @moduledoc """
  Durchsuche Stadtratsprojekte nach einem Suchbegriff.

  Sucht in Projekt-Titeln und -Beschreibungen. Nützlich wenn man nach
  einem bestimmten Thema fragt (z.B. 'Bahnhof', 'Park', 'Digitalisierung').

  Gibt passende Projekte mit ID, Titel, Status und Priorität zurück.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  import Ecto.Query

  schema do
    field :query, :string,
      required: true,
      description: "Suchbegriff (wird in Titel und Beschreibung gesucht)"

    field :limit, :integer, default: 20, description: "Maximale Anzahl Ergebnisse"
  end

  @impl true
  def execute(%{query: query} = params, frame) do
    limit = params[:limit] || 20
    pattern = "%#{String.downcase(query)}%"

    projekte =
      Repo.all(
        from(p in Projekt,
          where:
            like(fragment("lower(?)", p.titel), ^pattern) or
              like(fragment("lower(?)", p.beschreibung), ^pattern),
          order_by: [desc: p.prioritaet, desc: p.inserted_at],
          limit: ^limit
        )
      )

    formatted =
      Enum.map(projekte, fn p ->
        %{
          id: p.id,
          titel: p.titel,
          beschreibung: p.beschreibung,
          status: p.status,
          prioritaet: p.prioritaet,
          url: "http://localhost:4000/projekte/#{p.id}"
        }
      end)

    {:reply, Response.json(Response.tool(), formatted), frame}
  end
end
