defmodule Ratsprojekte.Schemas.Projekt do
  use Ecto.Schema
  import Ecto.Changeset
  import Ratsprojekte.Present

  schema "projekte" do
    field(:titel, :string)
    field(:beschreibung, :string)
    field(:status, Ecto.Enum, values: [:idee, :aktiv, :abgeschlossen, :verworfen], default: :idee)
    field(:prioritaet, Ecto.Enum, values: [:hoch, :mittel, :niedrig], default: :mittel)
    field(:beschlussvorschlag, :string)
    field(:adressat, :string)
    field(:value_proposition, :string)
    field(:success_metrics, :string)
    field(:abgeschlossen_am, :date)
    field(:verworfen_am, :date)
    field(:verworfen_grund, :string)
    field(:slug, :string)

    has_many(:realisierungsstraenge, Ratsprojekte.Schemas.Realisierungsstrang)
    has_many(:quellen, Ratsprojekte.Schemas.Quelle, where: [realisierungsstrang_id: nil])

    timestamps(type: :utc_datetime)
  end

  # Schwellen spiegeln die Hard Gates in check_antragsreife bzw.
  # priv/antragsreife_kriterien.md: VP und SM sind dort erst ab
  # mehr als 20 bzw. mehr als 10 Zeichen konkret genug. Die inhaltliche
  # Qualität (kein reines „Digitalisierung von X") prüft das Gate als
  # :warn — ein Changeset-Veto am GO des Stadtrats wäre der falsche Ort.
  @value_proposition_min_chars 21
  @success_metrics_min_chars 11

  def changeset(projekt, attrs) do
    projekt
    |> cast(attrs, [
      :titel,
      :beschreibung,
      :status,
      :prioritaet,
      :beschlussvorschlag,
      :adressat,
      :value_proposition,
      :success_metrics,
      :abgeschlossen_am,
      :verworfen_am,
      :verworfen_grund,
      :slug
    ])
    |> validate_required([:titel, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_length(:value_proposition, min: @value_proposition_min_chars)
    |> validate_length(:success_metrics, min: @success_metrics_min_chars)
    |> unique_constraint(:slug)
    |> validate_status_dates()
  end

  defp validate_status_dates(changeset) do
    case get_field(changeset, :status) do
      :abgeschlossen ->
        if present?(get_field(changeset, :abgeschlossen_am)) do
          changeset
        else
          add_error(
            changeset,
            :abgeschlossen_am,
            "sollte bei Status 'abgeschlossen' gesetzt sein"
          )
        end

      :verworfen ->
        if present?(get_field(changeset, :verworfen_am)) do
          changeset
        else
          add_error(changeset, :verworfen_am, "sollte bei Status 'verworfen' gesetzt sein")
        end

      _ ->
        changeset
    end
  end
end
