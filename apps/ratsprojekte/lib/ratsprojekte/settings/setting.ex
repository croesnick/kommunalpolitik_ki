defmodule Ratsprojekte.Settings.Setting do
  @moduledoc "One stored setting of the hub: a key and its value."

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:key, :string, autogenerate: false}
  schema "settings" do
    field(:value, :string)

    timestamps(type: :utc_datetime)
  end
end
