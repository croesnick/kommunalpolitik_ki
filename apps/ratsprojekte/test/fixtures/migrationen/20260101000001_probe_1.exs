defmodule Ratsprojekte.BetriebRepo.Migrations.Probe1 do
  use Ecto.Migration

  def change do
    create table(:probe_1) do
      add(:text, :string)
    end
  end
end
