defmodule Ratsprojekte.MCP.Tools.ListProjekte do
  @moduledoc """
  Liste alle Stadtratsprojekte mit Status, Priorität und Anzahl Realisierungsstränge.

  Nützlich für einen ersten Überblick über alle Projekte im Tracker.
  Für Details zu einem einzelnen Projekt, verwende show_projekt.

  ## Filter

  - `status` — Filter nach Status: 'idee', 'aktiv', 'abgeschlossen' oder 'verworfen'.
  - `seit` — Datum (ISO 8601, z.B. '2025-01-01'). Liefert nur Projekte, die seit
    diesem Datum abgeschlossen oder verworfen wurden. In Kombination mit
    `status: "abgeschlossen"` wird `abgeschlossen_am >= seit` geprüft, mit
    `status: "verworfen"` entsprechend `verworfen_am >= seit`. Ohne `status`
    werden beide Spalten geprüft (Projekt gilt als passend, wenn entweder
    `abgeschlossen_am` oder `verworfen_am` ab dem Datum liegt).
  - `blockiert` — Wenn `true`, werden nur Projekte geliefert, bei denen KEIN
    Realisierungsstrang `bedingung_erfuellt: true` hat. Das sind Projekte, die
    festhängen — kein gangbarer Weg offen. Projekte ohne jegliche Stränge
    gelten ebenfalls als blockiert.
  - `limit` — Maximale Anzahl Ergebnisse.

  Beispiele: „Welche Projekte haben wir abgeschlossen?" (nur `status`),
  „Was wurde im Jahr 2025 abgeschlossen?" (`status` + `seit`),
  „Bei welchen Projekten hängen wir fest?" (`blockiert: true`).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.Projekt
  import Ecto.Query

  schema do
    field(:status, :string,
      description: "Filter nach Status: 'idee', 'aktiv', 'abgeschlossen' oder 'verworfen'"
    )

    field(:seit, :date,
      description:
        "Datum (ISO 8601, z.B. '2025-01-01'). Projekte, die ab diesem Datum " <>
          "abgeschlossen oder verworfen wurden. In Kombination mit `status` " <>
          "wird nur die entsprechende Datumsspalte geprüft."
    )

    field(:blockiert, :boolean,
      description:
        "Wenn true, nur Projekte bei denen kein Realisierungsstrang " <>
          "`bedingung_erfuellt: true` hat (Projekt kommt nicht voran). " <>
          "Projekte ohne Stränge gelten ebenfalls als blockiert."
    )

    field(:limit, :integer, default: 50, description: "Maximale Anzahl Ergebnisse")
  end

  @impl true
  def execute(params, frame) do
    status = params[:status]
    seit = params[:seit]
    blockiert = params[:blockiert]
    limit = params[:limit] || 50

    query =
      from(p in Projekt,
        order_by: [desc: p.prioritaet, desc: p.inserted_at],
        limit: ^limit,
        preload: [realisierungsstraenge: []]
      )

    query = apply_status(query, status)
    query = apply_seit(query, status, seit)

    projekte = Repo.all(query)

    projekte =
      if blockiert do
        Enum.filter(projekte, &blockiert?/1)
      else
        projekte
      end

    formatted = Enum.map(projekte, &format/1)

    {:reply, Response.json(Response.tool(), formatted), frame}
  end

  defp apply_status(query, nil), do: query

  defp apply_status(query, status) do
    from(p in query, where: p.status == ^status)
  end

  defp apply_seit(query, _status, nil), do: query

  defp apply_seit(query, "abgeschlossen", seit) do
    from(p in query, where: p.abgeschlossen_am >= ^seit)
  end

  defp apply_seit(query, "verworfen", seit) do
    from(p in query, where: p.verworfen_am >= ^seit)
  end

  defp apply_seit(query, _status, seit) do
    from(p in query,
      where: p.abgeschlossen_am >= ^seit or p.verworfen_am >= ^seit
    )
  end

  defp blockiert?(projekt) do
    not Enum.any?(projekt.realisierungsstraenge, & &1.bedingung_erfuellt)
  end

  defp format(projekt) do
    %{
      slug: projekt.slug,
      titel: projekt.titel,
      beschreibung: projekt.beschreibung,
      status: projekt.status,
      prioritaet: projekt.prioritaet,
      anzahl_straenge: length(projekt.realisierungsstraenge),
      abgeschlossen_am: projekt.abgeschlossen_am,
      verworfen_am: projekt.verworfen_am,
      url: "http://localhost:4000/projekte/#{projekt.slug}"
    }
  end
end
