defmodule Ratsprojekte.BetriebRepo.Migrations.Probe3 do
  use Ecto.Migration

  def change do
    create table(:probe_3) do
      add(:text, :string)
    end
  end
end
