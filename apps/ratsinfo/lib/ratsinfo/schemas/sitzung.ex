defmodule Ratsinfo.Schemas.Sitzung do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  schema "sitzungen" do
    field(:name, :string)
    field(:gremium, :string)
    field(:datum, :string)
    field(:ort, :string)
    field(:status, :integer, default: 0)
    field(:client_id, :integer)
    field(:client_name, :string)
    field(:raw_json, :string)

    has_many(:tops, Ratsinfo.Schemas.TOP)

    timestamps(updated_at: :synced_at, inserted_at: false)
  end

  def changeset(sitzung, attrs) do
    sitzung
    |> cast(attrs, [
      :id,
      :name,
      :gremium,
      :datum,
      :ort,
      :status,
      :client_id,
      :client_name,
      :raw_json
    ])
    |> validate_required([:id, :name])
  end
end
