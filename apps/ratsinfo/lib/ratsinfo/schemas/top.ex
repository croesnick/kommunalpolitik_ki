defmodule Ratsinfo.Schemas.TOP do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "tops" do
    field(:sitzung_id, :integer)
    field(:nummer, :string)
    field(:titel, :string)
    field(:restricted, :boolean, default: false)
    field(:raw_json, :string)

    belongs_to(:sitzung, Ratsinfo.Schemas.Sitzung, define_field: false)
    has_many(:dokumente, Ratsinfo.Schemas.Dokument)
    has_many(:textbloecke, Ratsinfo.Schemas.Textblock)

    timestamps(updated_at: false, inserted_at: false)
  end

  def changeset(top, attrs) do
    top
    |> cast(attrs, [:id, :sitzung_id, :nummer, :titel, :restricted, :raw_json])
    |> validate_required([:id, :sitzung_id])
  end
end
