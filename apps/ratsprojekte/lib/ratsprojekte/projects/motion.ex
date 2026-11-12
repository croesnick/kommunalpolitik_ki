defmodule Ratsprojekte.Projects.Motion do
  @moduledoc """
  A motion („Antrag“, also Anfrage or Dringlichkeitsantrag): its own
  object, several per project, with the proposed resolution
  (`motion_text`, „Beschlussvorschlag“), addressee, status and outcome.
  The text itself does not live in the hub; `document_ref` points to
  where it lies (slot for #33 and #34: `document_ref`, `report_due_on`,
  without logic of their own yet).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.{Labels, Text}
  alias Ratsprojekte.Projects.Project

  @type t :: %__MODULE__{}

  schema "motions" do
    belongs_to(:project, Project)
    field(:kind, Ecto.Enum, values: Labels.keys(Labels.motion_kinds()), default: :motion)
    field(:title, :string)
    field(:status, Ecto.Enum, values: Labels.keys(Labels.motion_statuses()), default: :draft)
    field(:motion_text, :string)
    field(:addressee, :string)
    field(:document_ref, :string)
    field(:ris, :string)
    field(:submitted_on, :date)
    field(:outcome, Ecto.Enum, values: Labels.keys(Labels.outcomes()))
    field(:report_due_on, :date)

    timestamps(type: :utc_datetime)
  end

  @doc "A new motion: kind, title, proposed resolution, addressee, where the text lies."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(motion, attrs) do
    motion
    |> cast(attrs, [:kind, :title, :motion_text, :addressee, :document_ref])
    |> clean_and_validate()
    |> validate_required([:kind, :title])
  end

  @doc "Status, outcome, dates and session of a motion under way."
  @spec progress_changeset(t(), map()) :: Ecto.Changeset.t()
  def progress_changeset(motion, attrs) do
    motion
    |> cast(attrs, [:status, :outcome, :submitted_on, :report_due_on, :ris])
    |> clean_and_validate()
    |> validate_required([:status])
  end

  defp clean_and_validate(changeset) do
    changeset
    |> Text.clean_fields([:title, :motion_text, :addressee, :document_ref, :ris])
    |> validate_length(:title, max: 200)
    |> validate_length(:motion_text, max: 5000)
    |> validate_length(:addressee, max: 200)
    |> validate_length(:document_ref, max: 500)
    |> validate_length(:ris, max: 200)
  end
end
