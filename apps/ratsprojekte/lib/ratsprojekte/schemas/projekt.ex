defmodule Ratsprojekte.Schemas.Projekt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projekte" do
    field(:titel, :string)
    field(:beschreibung, :string)
    field(:status, Ecto.Enum, values: [:idee, :aktiv, :abgeschlossen, :verworfen], default: :idee)
    field(:prioritaet, Ecto.Enum, values: [:hoch, :mittel, :niedrig], default: :mittel)
    field(:beschlussvorschlag, :string)
    field(:adressat, :string)
    field(:abgeschlossen_am, :date)
    field(:verworfen_am, :date)
    field(:verworfen_grund, :string)

    has_many(:realisierungsstraenge, Ratsprojekte.Schemas.Realisierungsstrang)
    has_many(:quellen, Ratsprojekte.Schemas.Quelle, where: [realisierungsstrang_id: nil])

    timestamps(type: :utc_datetime)
  end

  def changeset(projekt, attrs) do
    projekt
    |> cast(attrs, [
      :titel,
      :beschreibung,
      :status,
      :prioritaet,
      :beschlussvorschlag,
      :adressat,
      :abgeschlossen_am,
      :verworfen_am,
      :verworfen_grund
    ])
    |> validate_required([:titel])
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

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: true
end
