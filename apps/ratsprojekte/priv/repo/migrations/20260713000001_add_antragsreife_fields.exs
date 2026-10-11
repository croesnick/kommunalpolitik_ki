defmodule Ratsprojekte.Repo.Migrations.AddAntragsreifeFields do
  use Ecto.Migration

  def change do
    alter table(:projekte) do
      add(:beschlussvorschlag, :text)
      add(:adressat, :string)
    end
  end
end
