defmodule Ratsprojekte.Repo.Migrations.AddProjektSlug do
  use Ecto.Migration

  def change do
    alter table("projekte") do
      add :slug, :string
    end

    create unique_index("projekte", [:slug])
  end
end
