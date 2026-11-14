defmodule Ratsprojekte.Projects.NextStep do
  @moduledoc """
  The one next step of a project: what, who, by when. It goes into the
  briefing.

  The person who runs the hub is stored as `"ich"`, whether they typed
  „du“ or „ich“: the work view says „Du“, outputs for others name the
  person (#407).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.Text

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:text, :string)
    field(:assignee, :string)
    field(:due_on, :date)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(step, attrs) do
    step
    |> cast(attrs, [:text, :assignee, :due_on])
    |> Text.clean_fields([:text, :assignee])
    |> update_change(:assignee, &normalize_assignee/1)
    |> validate_required([:text])
    |> validate_length(:text, max: 300)
    |> validate_length(:assignee, max: 80)
  end

  @editor "ich"

  @doc "The editor's own marker: „du“ and „ich“ both mean the person who runs the hub."
  @spec normalize_assignee(String.t() | nil) :: String.t() | nil
  def normalize_assignee(nil), do: nil

  def normalize_assignee(name),
    do: if(String.downcase(name) in ["du", "ich"], do: @editor, else: name)

  @doc "Is the assignee the person who runs the hub?"
  @spec editor?(String.t() | nil) :: boolean()
  def editor?(name), do: name == @editor
end
