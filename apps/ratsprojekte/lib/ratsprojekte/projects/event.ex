defmodule Ratsprojekte.Projects.Event do
  @moduledoc """
  The main flow „Was ist passiert?“ (ADR 0004): one entry that can carry
  a phase change and a new next step along, instead of three dialogs.
  Only the text is required; who may read it is always part of it.

  The next step changes only when the event carries the step fields
  (`step_text`, `step_assignee`, `step_due_on`); an empty `step_text`
  removes the step.

  At a motion the same event carries its status and outcome, its dates
  and the session (`status` … `ris`); at a project they are ignored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Ratsprojekte.{Labels, Text}
  alias Ratsprojekte.Projects.NextStep

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:text, :string)
    field(:by, Ecto.Enum, values: Labels.keys(Labels.actors()))
    field(:in_briefing, :boolean)
    field(:phase, Ecto.Enum, values: Labels.keys(Labels.phases()))
    field(:on, :date)
    field(:step_text, :string)
    field(:step_assignee, :string)
    field(:step_due_on, :date)

    field(:status, Ecto.Enum, values: Labels.keys(Labels.motion_statuses()))
    field(:outcome, Ecto.Enum, values: Labels.keys(Labels.outcomes()))
    field(:submitted_on, :date)
    field(:report_due_on, :date)
    field(:ris, :string)
  end

  @step_fields [:step_text, :step_assignee, :step_due_on]
  @motion_fields [:status, :outcome, :submitted_on, :report_due_on, :ris]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:text, :by, :in_briefing, :phase, :on] ++ @step_fields ++ @motion_fields)
    |> Text.clean_fields([:text, :step_text, :step_assignee, :ris])
    |> update_change(:step_assignee, &NextStep.normalize_assignee/1)
    |> validate_required([:text])
    |> validate_length(:text, max: 5000)
    |> validate_length(:step_text, max: 300)
    |> validate_length(:step_assignee, max: 80)
    |> validate_length(:ris, max: 200)
  end

  @doc "The motion fields of an applied event, for `Motion.progress_changeset/2`."
  @spec motion_attrs(t()) :: map()
  def motion_attrs(event), do: Map.take(event, @motion_fields)

  @doc "Does the event carry the next-step fields at all?"
  @spec step_given?(map()) :: boolean()
  def step_given?(attrs) do
    Enum.any?(@step_fields, &(Map.has_key?(attrs, &1) or Map.has_key?(attrs, Atom.to_string(&1))))
  end
end
