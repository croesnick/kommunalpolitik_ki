defmodule Ratsprojekte.BetriebRepo.Migrations.Probe2 do
  use Ecto.Migration

  def change do
    create table(:probe_2) do
      add(:text, :string)
    end
  end
end
