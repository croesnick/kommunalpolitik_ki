defmodule Ratsprojekte.MCP.Tools.ProposeProjektUpdate do
  @moduledoc """
  Schlage eine Aktualisierung eines bestehenden Projekts vor (titel,
  beschreibung, prioritaet).

  **GO-Prinzip**: Dieses Tool schreibt NUR in die Staging-Tabelle
  `pending_proposals` — nicht in `projekte`. Der Vorschlag muss vom
  Stadtrat in der LiveView bestätigt werden, bevor das echte Projekt
  aktualisiert wird. Approve/Reject ist bewusst KEIN MCP-Tool — das
  ist das disziplinarische GO-Gate.

  Die `begruendung` ist Pflichtfeld (Quellenpflicht): die AI muss
  nachvollziehbar begründen, warum sie diese Aktualisierung vorschlägt.

  Nach dem Aufruf liefert das Tool eine `review_url`, unter der der
  Stadtrat den Vorschlag prüfen kann. Folge-Aufrufe:
  - `list_pending_proposals` — alle offenen Vorschläge für ein Projekt
  - `show_pending_proposal` — Details zu einem konkreten Vorschlag

  Verwende list_projekte oder search_projekte, um den Projekt-Slug zu finden.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}
  import Ecto.Query

  schema do
    field(:projekt_slug, :string,
      required: true,
      description: "Projekt-Slug (von list_projekte / search_projekte)"
    )

    field(:titel, :string, description: "Neuer Titel (optional)")

    field(:beschreibung, :string, description: "Neue Beschreibung (optional)")

    field(:prioritaet, :string,
      description: "Neue Priorität: 'hoch', 'mittel' oder 'niedrig' (optional)"
    )

    field(:begruendung, :string,
      required: true,
      description:
        "Warum wird diese Aktualisierung vorgeschlagen? (Pflichtfeld, min 10 Zeichen, " <>
          "Quellenpflicht — optionale URLs/Paragrafen in `quellen`)"
    )

    field(:quellen, :string,
      description: "Komma-getrennte URLs/Paragrafen, z.B. 'https://..., Art. 28 BayGO' (optional)"
    )
  end

  @impl true
  def execute(params, frame) do
    projekt_slug = params[:projekt_slug]

    projekt = Repo.one(from(p in Projekt, where: p.slug == ^projekt_slug))

    if projekt == nil do
      {:reply, Response.error(Response.tool(), "Projekt '#{projekt_slug}' nicht gefunden"), frame}
    else
      payload =
        %{
          "titel" => params[:titel],
          "beschreibung" => params[:beschreibung],
          "prioritaet" => params[:prioritaet]
        }
        # Nur Felder aufnehmen, die die AI tatsächlich setzen will — keine
        # nil-Werte im Payload, sonst würde apply_projekt_update/3 Felder
        # aktiv leeren.
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      attrs = %{
        typ: :update_projekt,
        payload: payload,
        begruendung: params[:begruendung],
        quellen: params[:quellen],
        projekt_id: projekt.id,
        vorgeschlagen_von: "ai-harness",
        vorgeschlagen_am: DateTime.utc_now()
      }

      changeset = PendingProposal.propose_changeset(%PendingProposal{}, attrs)

      case Repo.insert(changeset) do
        {:ok, proposal} ->
          body = %{
            id: proposal.id,
            projekt_slug: projekt_slug,
            status: proposal.status,
            review_url: "http://localhost:4000/projekte/#{projekt.slug}/proposals/#{proposal.id}",
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
