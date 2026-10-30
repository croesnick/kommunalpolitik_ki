defmodule Ratsprojekte.Repo.Migrations.AddValuePropositionSuccessMetrics do
  use Ecto.Migration

  def change do
    alter table(:projekte) do
      add(:value_proposition, :text)
      add(:success_metrics, :text)
    end
  end
end
