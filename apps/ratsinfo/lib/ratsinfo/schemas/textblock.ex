defmodule Ratsinfo.Schemas.Textblock do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "texte" do
    field(:top_id, :string)
    field(:caption, :string)
    field(:content, :string)
    field(:sitzung_id, :integer)

    timestamps(updated_at: false, inserted_at: false)
  end

  def changeset(textblock, attrs) do
    textblock
    |> cast(attrs, [:id, :top_id, :caption, :content, :sitzung_id])
    |> validate_required([:id, :top_id])
  end
end
