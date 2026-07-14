defmodule Ratsprojekte.MCP.Tools.ProposeStrangUpdate do
  @moduledoc """
  Schlage eine Aktualisierung eines bestehenden Realisierungsstrangs vor
  (titel, beschreibung, rechtliche_grundlage, bedingung).

  **GO-Prinzip**: Dieses Tool schreibt NUR in die Staging-Tabelle
  `pending_proposals` — nicht in `realisierungsstraenge`. Der Vorschlag
  muss vom Stadtrat in der LiveView bestätigt werden, bevor der echte
  Realisierungsstrang aktualisiert wird. Approve/Reject ist bewusst KEIN
  MCP-Tool — das ist das disziplinarische GO-Gate.

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
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt, Realisierungsstrang}
  import Ecto.Query

  schema do
    field(:projekt_slug, :string,
      required: true,
      description: "Projekt-Slug (von list_projekte / search_projekte)"
    )

    field(:strang_label, :string,
      required: true,
      description: "Label des Realisierungsstrangs, z.B. 'A', 'B', 'C'"
    )

    field(:titel, :string, description: "Neuer Titel (optional)")

    field(:beschreibung, :string, description: "Neue Beschreibung (optional)")

    field(:rechtliche_grundlage, :string,
      description: "Neue rechtliche Grundlage, z.B. 'Art. 28 BayGO' (optional)"
    )

    field(:bedingung, :string, description: "Neue Bedingung (optional)")

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
    strang_label = params[:strang_label]

    projekt = Repo.one(from(p in Projekt, where: p.slug == ^projekt_slug))

    strang =
      if projekt,
        do:
          Repo.one(
            from(rs in Realisierungsstrang,
              where: rs.projekt_id == ^projekt.id and rs.label == ^strang_label
            )
          ),
        else: nil

    cond do
      projekt == nil ->
        {:reply, Response.error(Response.tool(), "Projekt '#{projekt_slug}' nicht gefunden"),
         frame}

      strang == nil ->
        {:reply,
         Response.error(
           Response.tool(),
           "Realisierungsstrang mit Label '#{strang_label}' in Projekt '#{projekt_slug}' nicht gefunden"
         ), frame}

      true ->
        insert_proposal(projekt, strang, strang_label, params, frame)
    end
  end

  defp insert_proposal(projekt, strang, strang_label, params, frame) do
    # Plausibilität: wenn kein einziges Update-Feld gesetzt ist, ist der
    # Vorschlag sinnlos — direkt ablehnen (Quellenpflicht/Idempotenz).
    if proposal_empty?(params) do
      {:reply,
       Response.error(
         Response.tool(),
         "Mindestens eines von titel/beschreibung/rechtliche_grundlage/bedingung muss gesetzt sein"
       ), frame}
    else
      payload =
        %{
          "label" => strang_label,
          "titel" => params[:titel],
          "beschreibung" => params[:beschreibung],
          "rechtliche_grundlage" => params[:rechtliche_grundlage],
          "bedingung" => params[:bedingung]
        }
        # Nur Felder aufnehmen, die die AI tatsächlich setzen will — keine
        # nil-Werte im Payload, sonst würde die Apply-Logik Felder aktiv
        # leeren. Das `label` wird immer gebraucht, um den Strang zu finden.
        |> Enum.reject(fn
          {_k, nil} -> true
          {"label", _} -> false
          _ -> false
        end)
        |> Map.new()

      attrs = %{
        typ: :update_strang,
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
            projekt_slug: projekt.slug,
            strang_label: strang_label,
            status: proposal.status,
            review_url: "http://localhost:4000/projekte/#{projekt.slug}/proposals/#{proposal.id}",
            hinweis: "Vorschlag angelegt. Stadtrat muss in der LiveView bestätigen (GO-Prinzip)."
          }

          # strang wird nicht im Response gebraucht, aber wir validieren
          # durch den Lookup oben, dass es ihn gibt.
          _ = strang

          {:reply, Response.json(Response.tool(), body), frame}

        {:error, changeset} ->
          errors = format_errors(changeset)
          {:reply, Response.error(Response.tool(), "Vorschlag ungültig: #{errors}"), frame}
      end
    end
  end

  defp proposal_empty?(params) do
    params[:titel] == nil and params[:beschreibung] == nil and
      params[:rechtliche_grundlage] == nil and params[:bedingung] == nil
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
