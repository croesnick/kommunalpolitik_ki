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
  # mehr als 20 bzw. mehr als 10 Zeichen konkret genug.
  @value_proposition_min_chars 21
  @success_metrics_min_chars 11
  # Reines „Digitalisierung von X" = kurze Nominalphrase ohne Aussage über
  # Problem oder Veränderung. Deterministisch trennbar ist nur die Kurzform
  # (maximal fünf Wörter nach „Digitalisierung", ohne Nebensatz); alles
  # Längere lässt die Heuristik durch — die inhaltliche Qualität bewertet
  # der AI-Harness über die Soft Gates.
  @pure_digitalisierung ~r/^\s*digitalisierung(\s+von)?\s+\S+(?:\s+\S+){0,4}\s*[.!]?\s*$/i

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
    |> validate_value_proposition_inhaltlich()
    |> unique_constraint(:slug)
    |> validate_status_dates()
  end

  # Ein reines „Digitalisierung von X“ nennt kein konkretes Problem und keine
  # messbare Veränderung — die Querschnitts-Regel im Lifecycle-Dokument
  # verlangt mehr. Nur prüfen, wenn das Feld gesetzt ist (nil bleibt erlaubt:
  # Felder werden per Proposal + GO gesetzt, die Antragsreife prüft das Gate).
  defp validate_value_proposition_inhaltlich(changeset) do
    case get_field(changeset, :value_proposition) do
      value when is_binary(value) ->
        if String.trim(value) =~ @pure_digitalisierung do
          add_error(
            changeset,
            :value_proposition,
            "darf kein reines „Digitalisierung von X“ sein — es muss das konkrete Problem nennen"
          )
        else
          changeset
        end

      _ ->
        changeset
    end
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
