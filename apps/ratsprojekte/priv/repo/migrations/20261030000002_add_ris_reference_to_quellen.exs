defmodule Ratsprojekte.Repo.Migrations.AddRisReferenceToQuellen do
  use Ecto.Migration

  def change do
    alter table(:quellen) do
      add(:ris_sitzung_id, :string)
      add(:ris_top, :string)
      add(:beschluss_nr, :string)
    end
  end
end
