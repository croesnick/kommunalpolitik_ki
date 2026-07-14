defmodule Ratsprojekte.Schemas.PendingProposal do
  use Ecto.Schema
  import Ecto.Changeset

  @typen [:add_realisierungsstrang, :add_projekt, :change_status, :update_projekt, :update_strang]
  @statuses [:pending, :approved, :rejected]

  schema "pending_proposals" do
    field(:typ, Ecto.Enum, values: @typen)
    field(:payload, :map)
    field(:begruendung, :string)
    field(:quellen, :string)

    field(:vorgeschlagen_von, :string, default: "ai-harness")
    field(:vorgeschlagen_am, :utc_datetime)
    field(:status, Ecto.Enum, values: @statuses, default: :pending)
    field(:entschieden_am, :utc_datetime)
    field(:entschieden_von, :string)
    field(:entscheidungskommentar, :string)

    belongs_to(:projekt, Ratsprojekte.Schemas.Projekt)

    timestamps(type: :utc_datetime)
  end

  # Changeset fuer neuen Vorschlag (von AI).
  # Schreibt nur in die Staging-Tabelle, nicht in realisierungsstraenge.
  # projekt_id ist fuer :add_realisierungsstrang, :change_status,
  # :update_projekt und :update_strang Pflicht, fuer :add_projekt optional
  # (neues Projekt ohne Eltern-Projekt).
  def propose_changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [
      :typ,
      :payload,
      :begruendung,
      :quellen,
      :projekt_id,
      :vorgeschlagen_von,
      :vorgeschlagen_am
    ])
    |> validate_required([:typ, :payload, :begruendung, :vorgeschlagen_am])
    |> validate_length(:begruendung, min: 10, max: 1000)
    |> validate_projekt_id_required_for_typed()
  end

  defp validate_projekt_id_required_for_typed(changeset) do
    typ = get_field(changeset, :typ)
    projekt_id = get_field(changeset, :projekt_id)

    case {typ, projekt_id} do
      {:add_realisierungsstrang, nil} ->
        add_error(changeset, :projekt_id, "ist für Realisierungsstrang-Vorschläge erforderlich")

      {:change_status, nil} ->
        add_error(changeset, :projekt_id, "ist für Statusänderungs-Vorschläge erforderlich")

      {:update_projekt, nil} ->
        add_error(
          changeset,
          :projekt_id,
          "ist für Projektaktualisierungs-Vorschläge erforderlich"
        )

      {:update_strang, nil} ->
        add_error(
          changeset,
          :projekt_id,
          "ist für Strang-Aktualisierungs-Vorschläge erforderlich"
        )

      _ ->
        changeset
    end
  end

  # Changeset fuer Entscheidung (von LiveView/Mensch).
  def decision_changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [:status, :entschieden_am, :entschieden_von, :entscheidungskommentar])
    |> validate_required([:status, :entschieden_am, :entschieden_von])
    |> validate_inclusion(:status, [:approved, :rejected])
  end

  # Changeset fuer manuelle Begründungs-Korrektur durch den Stadtrat (LiveView).
  # Erlaubt das Anpassen der AI-Begründung vor der Entscheidung — GO-Prinzip:
  # der Mensch kontrolliert und formuliert die öffentliche Begründung.
  def update_begruendung_changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [:begruendung])
    |> validate_required([:begruendung])
    |> validate_length(:begruendung, min: 10, max: 1000)
  end
end
