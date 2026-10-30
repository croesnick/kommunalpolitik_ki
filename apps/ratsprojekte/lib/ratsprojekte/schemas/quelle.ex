defmodule Ratsprojekte.Schemas.Quelle do
  use Ecto.Schema
  import Ecto.Changeset
  import Ratsprojekte.Present

  @ris_fields [:ris_sitzung_id, :ris_top, :beschluss_nr]

  schema "quellen" do
    field(:typ, Ecto.Enum, values: [:sitzung, :foerderprogramm, :gesetz, :url, :zeitungsartikel])
    field(:titel, :string)
    field(:url, :string)
    field(:paragraf, :string)
    field(:abrufdatum, :date)

    # Strukturierte RIS-Referenz (Ticket #32) — nur am Quellentyp :sitzung
    # sinnvoll (Unix-Prinzip: ratsprojekte kennt nur die IDs, kein ratsinfo-Interna).
    field(:ris_sitzung_id, :string)
    field(:ris_top, :string)
    field(:beschluss_nr, :string)

    belongs_to(:projekt, Ratsprojekte.Schemas.Projekt)
    belongs_to(:realisierungsstrang, Ratsprojekte.Schemas.Realisierungsstrang)

    timestamps(type: :utc_datetime)
  end

  def changeset(quelle, attrs) do
    quelle
    |> cast(attrs, [
      :typ,
      :titel,
      :url,
      :paragraf,
      :abrufdatum,
      :ris_sitzung_id,
      :ris_top,
      :beschluss_nr,
      :projekt_id,
      :realisierungsstrang_id
    ])
    |> validate_required([:typ, :titel])
    |> validate_ris_reference_nur_fuer_sitzung()
  end

  # Die RIS-Referenz ist die Struktur hinter „welcher Beschluss gehört zu
  # Projekt X?“ (WF 4) — sie gehört an die Sitzungs-Quelle, nicht an
  # Förderprogramme oder Zeitungsartikel.
  defp validate_ris_reference_nur_fuer_sitzung(changeset) do
    ris_gesetzt? =
      Enum.any?(@ris_fields, fn field -> present?(get_field(changeset, field)) end)

    if ris_gesetzt? and get_field(changeset, :typ) != :sitzung do
      add_error(
        changeset,
        :ris_sitzung_id,
        "RIS-Referenz (ris_sitzung_id/ris_top/beschluss_nr) ist nur für Quellen vom Typ 'sitzung' erlaubt"
      )
    else
      changeset
    end
  end
end
