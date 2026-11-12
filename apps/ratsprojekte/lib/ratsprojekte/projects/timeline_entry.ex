defmodule Ratsprojekte.Projects.TimelineEntry do
  @moduledoc """
  One line of a project's timeline („Verlauf“). Append-only: text, date
  and kind never change. Only the visibility of a note can be switched
  (`in_briefing`), because a private entry may later go into the
  briefing and back.

  Kinds: what someone noted (`:note`, `:opinion`), what was decided
  (`:decision`), and the lines the hub writes itself for what the
  editor did in it (`:created`, `:next_step`, `:fact`, `:variant`,
  `:value`, `:cross_reference`, `:motion`, `:survey`, `:return`).
  """

  use Ecto.Schema

  alias Ratsprojekte.Labels
  alias Ratsprojekte.Projects.Project

  @type t :: %__MODULE__{}

  @kinds [
    :created,
    :note,
    :opinion,
    :decision,
    :next_step,
    :fact,
    :variant,
    :value,
    :cross_reference,
    :motion,
    :survey,
    :return
  ]

  schema "timeline_entries" do
    belongs_to(:project, Project)
    field(:kind, Ecto.Enum, values: @kinds)
    field(:text, :string)
    field(:on, :date)
    field(:by, Ecto.Enum, values: Labels.keys(Labels.actors()))
    field(:in_briefing, :boolean, default: true)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The kinds of entries."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds
end
