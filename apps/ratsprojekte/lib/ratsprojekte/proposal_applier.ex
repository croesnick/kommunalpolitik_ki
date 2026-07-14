defmodule Ratsprojekte.ProposalApplier do
  @moduledoc """
  Single Source of Truth für das Anwenden eines PendingProposal (Accept/Reject).

  Wird von zwei Stellen aus aufgerufen:
  - `RatsprojekteWeb.ProposalLive.Show` — Browser-GO (Button in der LiveView)
  - `Ratsprojekte.MCP.Tools.DecideProposal` — Chat-GO (AI führt GO aus)

  Beide Wege laufen hier zusammen — dieselbe Transaktion, dieselbe Logik.
  Die einzige Differenz ist `entschieden_von`: "stadtrat" (Browser) vs.
  "stadtrat-via-ai" (Chat). Das wird vom Aufrufer als opts gesetzt.

  ## Idempotenz

  Alle Mutationen laufen in einer `Repo.transaction`. Schlägt das Anlegen
  bzw. Aktualisieren des Records fehl, bleibt das Proposal `pending`.

  ## Rückgabe

      {:ok, result} | {:error, changeset | :strang_not_found}
  """

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt, Realisierungsstrang}
  import Ecto.Query

  @type apply_opt :: {:entschieden_von, String.t()} | {:entscheidungskommentar, String.t() | nil}

  @doc """
  Wendet ein PendingProposal an (Accept).

  `projekt` ist das Projekt, das zum Proposal gehört. Für `:add_projekt`
  ohne Eltern-Projekt darf es `nil` sein, sonst sollte es das zum
  `proposal.projekt_id` gehörende Projekt sein. Der Aufrufer ist für das
  Laden verantwortlich.

  ## Opts

  - `:entschieden_von` (Pflicht) — "stadtrat" (Browser) oder
    "stadtrat-via-ai" (Chat-GO). Dient dem Audit-Trail.
  - `:entscheidungskommentar` (optional) — Kommentar des Stadtrats.
  """
  @spec apply_proposal(PendingProposal.t(), Projekt.t() | nil, [apply_opt()]) ::
          {:ok, term()} | {:error, Ecto.Changeset.t() | :strang_not_found}
  def apply_proposal(proposal, projekt \\ nil, opts \\ [])

  def apply_proposal(%PendingProposal{typ: :add_projekt} = proposal, _projekt, opts) do
    decision_attrs = decision_attrs(:approved, opts)

    Repo.transaction(fn ->
      record = Repo.insert!(Projekt.changeset(struct(Projekt), proposal.payload))
      _ = record

      Repo.update!(PendingProposal.decision_changeset(proposal, decision_attrs))
    end)
  end

  def apply_proposal(%PendingProposal{typ: :add_realisierungsstrang} = proposal, _projekt, opts) do
    strang_attrs = Map.put(proposal.payload, "projekt_id", proposal.projekt_id)
    decision_attrs = decision_attrs(:approved, opts)

    Repo.transaction(fn ->
      record =
        Repo.insert!(Realisierungsstrang.changeset(struct(Realisierungsstrang), strang_attrs))

      _ = record

      Repo.update!(PendingProposal.decision_changeset(proposal, decision_attrs))
    end)
  end

  def apply_proposal(%PendingProposal{typ: :change_status} = proposal, projekt, opts) do
    status = String.to_existing_atom(proposal.payload["status"])
    datum = parse_date(proposal.payload["datum"])
    verworfen_grund = proposal.payload["verworfen_grund"]

    update_attrs = %{status: status}

    update_attrs =
      if datum, do: put_date_field(update_attrs, status, datum), else: update_attrs

    update_attrs =
      if verworfen_grund,
        do: Map.put(update_attrs, :verworfen_grund, verworfen_grund),
        else: update_attrs

    decision_attrs = decision_attrs(:approved, opts)

    Repo.transaction(fn ->
      Repo.update!(Projekt.changeset(projekt, update_attrs))
      Repo.update!(PendingProposal.decision_changeset(proposal, decision_attrs))
    end)
  end

  def apply_proposal(%PendingProposal{typ: :update_projekt} = proposal, projekt, opts) do
    update_attrs =
      Enum.reduce(proposal.payload, %{}, fn
        {"titel", v}, acc when is_binary(v) ->
          Map.put(acc, :titel, v)

        {"beschreibung", v}, acc when is_binary(v) ->
          Map.put(acc, :beschreibung, v)

        {"prioritaet", v}, acc when is_binary(v) ->
          Map.put(acc, :prioritaet, String.to_existing_atom(v))

        _, acc ->
          acc
      end)

    decision_attrs = decision_attrs(:approved, opts)

    Repo.transaction(fn ->
      Repo.update!(Projekt.changeset(projekt, update_attrs))
      Repo.update!(PendingProposal.decision_changeset(proposal, decision_attrs))
    end)
  end

  def apply_proposal(%PendingProposal{typ: :update_strang} = proposal, _projekt, opts) do
    label = proposal.payload["label"]

    strang =
      Repo.one(
        from(rs in Realisierungsstrang,
          where: rs.projekt_id == ^proposal.projekt_id and rs.label == ^label
        )
      )

    if strang == nil do
      {:error, :strang_not_found}
    else
      update_attrs =
        Enum.reduce(proposal.payload, %{}, fn
          {"titel", v}, acc when is_binary(v) ->
            Map.put(acc, :titel, v)

          {"beschreibung", v}, acc when is_binary(v) ->
            Map.put(acc, :beschreibung, v)

          {"rechtliche_grundlage", v}, acc when is_binary(v) ->
            Map.put(acc, :rechtliche_grundlage, v)

          {"bedingung", v}, acc when is_binary(v) ->
            Map.put(acc, :bedingung, v)

          _, acc ->
            acc
        end)

      decision_attrs = decision_attrs(:approved, opts)

      Repo.transaction(fn ->
        Repo.update!(Realisierungsstrang.changeset(strang, update_attrs))
        Repo.update!(PendingProposal.decision_changeset(proposal, decision_attrs))
      end)
    end
  end

  @doc """
  Lehnt ein PendingProposal ab (Reject). Nur Status-Update mit Kommentar,
  keine weiteren Mutationen.

  ## Opts

  - `:entschieden_von` (Pflicht) — "stadtrat" (Browser) oder
    "stadtrat-via-ai" (Chat-GO).
  - `:entscheidungskommentar` (optional).
  """
  @spec reject_proposal(PendingProposal.t(), [apply_opt()]) ::
          {:ok, PendingProposal.t()} | {:error, Ecto.Changeset.t()}
  def reject_proposal(%PendingProposal{} = proposal, opts) do
    decision_attrs = decision_attrs(:rejected, opts)
    proposal |> PendingProposal.decision_changeset(decision_attrs) |> Repo.update()
  end

  # --- Helpers (entsprechend der bisherigen LiveView-Logik) ---

  defp decision_attrs(status, opts) do
    %{
      status: status,
      entschieden_am: DateTime.utc_now(),
      entschieden_von: Keyword.fetch!(opts, :entschieden_von),
      entscheidungskommentar: blank_to_nil(Keyword.get(opts, :entscheidungskommentar))
    }
  end

  defp put_date_field(attrs, :abgeschlossen, datum),
    do: Map.put(attrs, :abgeschlossen_am, datum)

  defp put_date_field(attrs, :verworfen, datum), do: Map.put(attrs, :verworfen_am, datum)
  defp put_date_field(attrs, _, _), do: attrs

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
