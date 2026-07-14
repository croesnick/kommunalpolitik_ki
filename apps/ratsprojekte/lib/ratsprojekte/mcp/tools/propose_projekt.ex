defmodule Ratsprojekte.MCP.Tools.ProposeProjekt do
  @moduledoc """
  Schlage ein neues Stadtratsprojekt vor.

  **GO-Prinzip**: Dieses Tool schreibt NUR in die Staging-Tabelle
  `pending_proposals` (typ: :add_projekt) — nicht in `projekte`. Der Vorschlag
  muss vom Stadtrat in der LiveView bestätigt werden, bevor ein echtes Projekt
  angelegt wird. Approve/Reject ist bewusst KEIN MCP-Tool — das ist das
  disziplinarische GO-Gate.

  Die `begruendung` ist Pflichtfeld (Quellenpflicht): die AI muss
  nachvollziehbar begründen, warum sie dieses Projekt vorschlägt.

  Nach dem Aufruf liefert das Tool eine `review_url`, unter der der
  Stadtrat den Vorschlag prüfen kann.

  Der `slug` ist der zukünftige Slug des Projekts (kebab-case, z.B.
  'freibad-digitalisierung'). Wird nach Accept als Projekt-Slug gespeichert
  und in der URL sowie als Vault-Tag `#ratsprojekt/<slug>` verwendet.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.PendingProposal

  schema do
    field(:titel, :string,
      required: true,
      description: "Titel des neuen Projekts"
    )

    field(:slug, :string,
      description:
        "Projekt-Slug (kebab-case, z.B. 'freibad-digitalisierung'). " <>
          "Wird in der URL und als Vault-Tag #ratsprojekt/<slug> verwendet."
    )

    field(:beschreibung, :string, description: "Beschreibung des Projekts (optional)")

    field(:prioritaet, :string,
      description: "Priorität: 'hoch', 'mittel' (default) oder 'niedrig' (optional)"
    )

    field(:begruendung, :string,
      required: true,
      description:
        "Warum wird dieses Projekt vorgeschlagen? (Pflichtfeld, min 10 Zeichen, " <>
          "Quellenpflicht — optionale URLs/Paragrafen in `quellen`)"
    )

    field(:quellen, :string,
      description: "Komma-getrennte URLs/Paragrafen, z.B. 'https://..., Art. 28 BayGO' (optional)"
    )
  end

  @impl true
  def execute(params, frame) do
    payload = %{
      "titel" => params[:titel],
      "slug" => params[:slug],
      "beschreibung" => params[:beschreibung],
      "prioritaet" => params[:prioritaet] || "mittel"
    }

    attrs = %{
      typ: :add_projekt,
      payload: payload,
      begruendung: params[:begruendung],
      quellen: params[:quellen],
      projekt_id: nil,
      vorgeschlagen_von: "ai-harness",
      vorgeschlagen_am: DateTime.utc_now()
    }

    changeset = PendingProposal.propose_changeset(%PendingProposal{}, attrs)

    case Repo.insert(changeset) do
      {:ok, proposal} ->
        body = %{
          id: proposal.id,
          typ: :add_projekt,
          status: proposal.status,
          review_url: "http://localhost:4000/proposals/#{proposal.id}",
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
