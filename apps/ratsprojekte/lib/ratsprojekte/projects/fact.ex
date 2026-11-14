defmodule Ratsprojekte.Projects.Fact do
  @moduledoc """
  A fact („Fakt“): a statement with citation, date and check status.
  What a machine found stays unverified until a person looked up the
  source; `verified` says a person did.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.Projects.Project
  alias Ratsprojekte.Text

  @type t :: %__MODULE__{}

  schema "facts" do
    belongs_to(:project, Project)
    field(:statement, :string)
    field(:citation, :string)
    field(:url, :string)
    field(:fetched_on, :date)
    field(:verified, :boolean, default: false)

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(fact, attrs) do
    fact
    |> cast(attrs, [:statement, :citation, :url, :fetched_on, :verified])
    |> Text.clean_fields([:statement, :citation, :url])
    |> validate_required([:statement, :citation, :fetched_on])
    |> validate_length(:statement, max: 2000)
    |> validate_length(:citation, max: 500)
    |> validate_format(:url, ~r{\Ahttps?://\S+\z},
      message: "muss mit http:// oder https:// beginnen"
    )
  end
end
