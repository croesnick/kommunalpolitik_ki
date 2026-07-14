defmodule Ratsprojekte.MCP.Tools.ProposeRealisierungsstrang do
  @moduledoc """
  Schlage einen neuen Realisierungsstrang für ein Projekt vor.

  **GO-Prinzip**: Dieses Tool schreibt NUR in die Staging-Tabelle
  `pending_proposals` — nicht in `realisierungsstraenge`. Der Vorschlag
  muss vom Stadtrat in der LiveView bestätigt werden, bevor ein echter
  Realisierungsstrang angelegt wird. Approve/Reject ist bewusst KEIN
  MCP-Tool — das ist das disziplinarische GO-Gate.

  Die `begruendung` ist Pflichtfeld (Quellenpflicht): die AI muss
  nachvollziehbar begründen, warum sie diesen Strang vorschlägt.

  Nach dem Aufruf liefert das Tool eine `review_url`, unter der der
  Stadtrat den Vorschlag prüfen kann. Folge-Aufrufe:
  - `list_pending_proposals` — alle offenen Vorschläge für ein Projekt
  - `show_pending_proposal` — Details zu einem konkreten Vorschlag

  Verwende list_projekte oder search_projekte, um die `projekt_id` zu finden.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}

  schema do
    field(:projekt_id, :integer,
      required: true,
      description: "Projekt-ID (von list_projekte / search_projekte)"
    )

    field(:label, :string,
      required: true,
      description: "Strang-Label, z.B. 'A', 'B', 'C'"
    )

    field(:titel, :string, required: true, description: "Titel des Realisierungsstrangs")

    field(:beschreibung, :string, description: "Beschreibung des Strangs (optional)")

    field(:rechtliche_grundlage, :string,
      description: "Rechtliche Grundlage, z.B. 'Art. 28 BayGO' (optional)"
    )

    field(:bedingung, :string, description: "Wann kann dieser Weg gezogen werden? (optional)")

    field(:begruendung, :string,
      required: true,
      description:
        "Warum wird dieser Strang vorgeschlagen? (Pflichtfeld, min 10 Zeichen, " <>
          "Quellenpflicht — optionale URLs/Paragrafen in `quellen`)"
    )

    field(:quellen, :string,
      description: "Komma-getrennte URLs/Paragrafen, z.B. 'https://..., Art. 28 BayGO' (optional)"
    )
  end

  @impl true
  def execute(params, frame) do
    projekt_id = params[:projekt_id]

    if Repo.get(Projekt, projekt_id) == nil do
      {:reply, Response.error(Response.tool(), "Projekt #{projekt_id} nicht gefunden"), frame}
    else
      payload = %{
        "label" => params[:label],
        "titel" => params[:titel],
        "beschreibung" => params[:beschreibung],
        "rechtliche_grundlage" => params[:rechtliche_grundlage],
        "bedingung" => params[:bedingung]
      }

      attrs = %{
        typ: :add_realisierungsstrang,
        payload: payload,
        begruendung: params[:begruendung],
        quellen: params[:quellen],
        projekt_id: projekt_id,
        vorgeschlagen_von: "ai-harness",
        vorgeschlagen_am: DateTime.utc_now()
      }

      changeset = PendingProposal.propose_changeset(%PendingProposal{}, attrs)

      case Repo.insert(changeset) do
        {:ok, proposal} ->
          body = %{
            id: proposal.id,
            projekt_id: projekt_id,
            status: proposal.status,
            review_url: "http://localhost:4000/projekte/#{projekt_id}/proposals/#{proposal.id}",
            hinweis: "Vorschlag angelegt. Stadtrat muss in der LiveView bestätigen (GO-Prinzip)."
          }

          {:reply, Response.json(Response.tool(), body), frame}

        {:error, changeset} ->
          errors = format_errors(changeset)
          {:reply, Response.error(Response.tool(), "Vorschlag ungültig: #{errors}"), frame}
      end
    end
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end
