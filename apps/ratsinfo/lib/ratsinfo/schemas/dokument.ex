defmodule Ratsinfo.Schemas.Dokument do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "dokumente" do
    field(:top_id, :string)
    field(:sitzung_id, :integer)
    field(:name, :string)
    field(:fileext, :string)
    field(:lokaler_pfad, :string)
    field(:downloaded, :boolean, default: false)

    timestamps(updated_at: false, inserted_at: false)
  end

  def changeset(dokument, attrs) do
    dokument
    |> cast(attrs, [:id, :top_id, :sitzung_id, :name, :fileext, :lokaler_pfad, :downloaded])
    |> validate_required([:id, :top_id])
  end
end
