defmodule Ratsprojekte.MCP.Tools.ProposeStatusChange do
  @moduledoc """
  Schlage eine Statusänderung für ein bestehendes Projekt vor.

  **GO-Prinzip**: Dieses Tool schreibt NUR in die Staging-Tabelle
  `pending_proposals` (typ: :change_status) — nicht in `projekte`. Der Vorschlag
  muss vom Stadtrat in der LiveView bestätigt werden, bevor der Projektstatus
  tatsächlich geändert wird. Approve/Reject ist bewusst KEIN MCP-Tool — das ist
  das disziplinarische GO-Gate.

  Die `begruendung` ist Pflichtfeld (Quellenpflicht): die AI muss
  nachvollziehbar begründen, warum sie diese Statusänderung vorschlägt.

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

  @status_werte ~w(idee aktiv abgeschlossen verworfen)

  schema do
    field(:projekt_slug, :string,
      required: true,
      description: "Projekt-Slug des Projekts, dessen Status geändert werden soll"
    )

    field(:status, :string,
      required: true,
      description: "Neuer Status: 'idee', 'aktiv', 'abgeschlossen' oder 'verworfen'"
    )

    field(:begruendung_fuer_aenderung, :string,
      required: true,
      description:
        "Warum wird diese Statusänderung vorgeschlagen? (Pflichtfeld, min 10 Zeichen, " <>
          "Quellenpflicht — optionale URLs/Paragrafen in `quellen`)"
    )

    field(:datum, :string,
      description:
        "ISO-Datum (YYYY-MM-DD). Pflicht bei 'abgeschlossen' (abgeschlossen_am) " <>
          "bzw. 'verworfen' (verworfen_am). Optional sonst."
    )

    field(:verworfen_grund, :string,
      description: "Verworfungsgrund bei Status 'verworfen' (optional, aber empfohlen)"
    )

    field(:quellen, :string,
      description: "Komma-getrennte URLs/Paragrafen, z.B. 'https://..., Art. 28 BayGO' (optional)"
    )
  end

  @impl true
  def execute(params, frame) do
    projekt_slug = params[:projekt_slug]
    status = params[:status]
    projekt = Repo.one(from(p in Projekt, where: p.slug == ^projekt_slug))

    cond do
      projekt == nil ->
        {:reply, Response.error(Response.tool(), "Projekt '#{projekt_slug}' nicht gefunden"),
         frame}

      status not in @status_werte ->
        {:reply,
         Response.error(
           Response.tool(),
           "Ungültiger Status '#{status}'. Erlaubt: #{Enum.join(@status_werte, ", ")}"
         ), frame}

      true ->
        build_and_insert(params, projekt, frame)
    end
  end

  defp build_and_insert(params, projekt, frame) do
    projekt_id = projekt.id
    status = params[:status]

    payload = %{
      "status" => status,
      "begruendung_fuer_aenderung" => params[:begruendung_fuer_aenderung],
      "datum" => params[:datum],
      "verworfen_grund" => params[:verworfen_grund]
    }

    attrs = %{
      typ: :change_status,
      payload: payload,
      begruendung: params[:begruendung_fuer_aenderung],
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
          projekt_slug: projekt.slug,
          typ: :change_status,
          neuer_status: status,
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
