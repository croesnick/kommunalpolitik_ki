defmodule Ratsprojekte.Briefings.IssuedBriefing do
  @moduledoc """
  An issued briefing („ausgegebener Stand“): exactly the document the
  editor saw and gave out, with the time. It never changes; from its
  time on „Neu seit“ counts.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "issued_briefings" do
    field(:issued_at, :utc_datetime)
    field(:html, :string)
  end
end
