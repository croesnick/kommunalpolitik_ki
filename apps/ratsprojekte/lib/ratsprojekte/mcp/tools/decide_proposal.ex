defmodule Ratsprojekte.MCP.Tools.DecideProposal do
  @moduledoc """
  Führt ein GO (Go-Ahead) des Stadtrats aus, das im Chat gegeben wurde.

  **GO-Execution**: Dieses Tool ersetzt den Accept/Reject-Button der
  LiveView für den Chat-basierten Workflow. Der Stadtrat gibt GO im Chat
  (z.B. „Vorschlag 42 annehmen, Kommentar: ..."), die AI führt es hiermit
  atomar aus.

  **Dürfen-Pflicht**: Die AI darf dieses Tool NIEMALS ohne explizites,
  unmissverständliches GO des Stadtrats aufrufen. Kein stillschweigendes
  Accept, kein „ich dachte, das ist gewollt". Nur weil der Vorschlag
  sinngemäß passt, ist das kein GO. Das GO muss vom Menschen kommen.

  **Audit-Trail**: `entschieden_von` wird auf `"stadtrat-via-ai"` gesetzt —
  nicht `"stadtrat"` (das reserviert für Browser-GO über die LiveView).
  So bleibt im Audit-Trail klar unterscheidbar, welches GO aus dem Chat
  und welches aus der LiveView kam.

  **Idempotenz**: Alle Mutationen laufen in einer Transaktion. Schlägt das
  Anwenden fehl, bleibt das Proposal `pending`.

  ## Parameter

  - `proposal_id` — ID des PendingProposal (von list_pending_proposals /
    show_pending_proposal).
  - `aktion` — `"accept"` oder `"reject"`.
  - `kommentar` (optional) — Entscheidungskommentar des Stadtrats.
    Bei Reject empfohlen (Lern-Effekt für die AI).
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ratsprojekte.{ProposalApplier, Repo}
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt}
  import Ecto.Query

  schema do
    field(:proposal_id, :string,
      required: true,
      description: "ID des PendingProposal (von list_pending_proposals / show_pending_proposal)"
    )

    field(:aktion, :string,
      required: true,
      description: "Entscheidung: 'accept' oder 'reject'"
    )

    field(:kommentar, :string,
      description:
        "Kommentar des Stadtrats (optional bei Accept, empfohlen bei Reject — " <>
          "Lern-Effekt für die AI)"
    )
  end

  @impl true
  def execute(params, frame) do
    proposal_id = params[:proposal_id]
    aktion = params[:aktion]
    kommentar = params[:kommentar]

    cond do
      proposal_id == nil ->
        {:reply, Response.error(Response.tool(), "proposal_id fehlt"), frame}

      aktion not in ["accept", "reject"] ->
        {:reply, Response.error(Response.tool(), "aktion muss 'accept' oder 'reject' sein"),
         frame}

      true ->
        execute_decision(proposal_id, aktion, kommentar, frame)
    end
  end

  defp execute_decision(proposal_id, aktion, kommentar, frame) do
    proposal =
      Repo.one(
        from(pp in PendingProposal,
          where: pp.id == ^proposal_id,
          preload: [:projekt]
        )
      )

    cond do
      proposal == nil ->
        {:reply, Response.error(Response.tool(), "Vorschlag #{proposal_id} nicht gefunden"),
         frame}

      proposal.status != :pending ->
        {:reply,
         Response.error(
           Response.tool(),
           "Vorschlag #{proposal_id} ist bereits #{proposal.status} — keine erneute Entscheidung möglich"
         ), frame}

      aktion == "accept" ->
        accept(proposal, kommentar, frame)

      aktion == "reject" ->
        reject(proposal, kommentar, frame)
    end
  end

  defp accept(proposal, kommentar, frame) do
    opts = [entschieden_von: "stadtrat-via-ai", entscheidungskommentar: blank_to_nil(kommentar)]

    case ProposalApplier.apply_proposal(proposal, proposal.projekt, opts) do
      {:ok, _} ->
        body = %{
          id: proposal.id,
          typ: proposal.typ,
          aktion: "accept",
          status: :approved,
          projekt_slug: projekt_slug(proposal),
          hinweis: "GO ausgeführt — Vorschlag angenommen (stadtrat-via-ai)."
        }

        {:reply, Response.json(Response.tool(), body), frame}

      {:error, :strang_not_found} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Strang mit Label #{proposal.payload["label"]} nicht gefunden"
         ), frame}

      {:error, changeset} ->
        errors = format_errors(changeset)
        {:reply, Response.error(Response.tool(), "Anwenden fehlgeschlagen: #{errors}"), frame}
    end
  end

  defp reject(proposal, kommentar, frame) do
    opts = [entschieden_von: "stadtrat-via-ai", entscheidungskommentar: blank_to_nil(kommentar)]

    case ProposalApplier.reject_proposal(proposal, opts) do
      {:ok, _updated} ->
        body = %{
          id: proposal.id,
          typ: proposal.typ,
          aktion: "reject",
          status: :rejected,
          projekt_slug: projekt_slug(proposal),
          hinweis: "GO ausgeführt — Vorschlag abgelehnt (stadtrat-via-ai)."
        }

        {:reply, Response.json(Response.tool(), body), frame}

      {:error, changeset} ->
        errors = format_errors(changeset)
        {:reply, Response.error(Response.tool(), "Ablehnen fehlgeschlagen: #{errors}"), frame}
    end
  end

  defp projekt_slug(%{projekt: %Projekt{} = projekt}), do: projekt.slug
  defp projekt_slug(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

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
