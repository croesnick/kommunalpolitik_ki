defmodule Ratsprojekte.Repo.Migrations.CreateHubModel do
  use Ecto.Migration

  # The small model of ADR 0004 (#436). Enum atoms are stored as text;
  # next_step, value and prerequisites are embedded as JSON.
  def change do
    create table(:projects) do
      add(:slug, :string, null: false)
      add(:title, :string, null: false)
      add(:short, :text)
      add(:origin, :string)
      add(:phase, :string, null: false, default: "idea")
      add(:disposition, :string)
      add(:disposed_on, :date)
      add(:next_step, :map)
      add(:value, :map)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:projects, [:slug]))

    create table(:surveys) do
      add(:public_id, :string, null: false)
      add(:title, :string, null: false)
      add(:question, :text, null: false)
      add(:circle, :string, null: false)
      add(:due_on, :date, null: false)
      add(:status, :string, null: false, default: "preparing")
      add(:running_since, :date)
      add(:results_as_of, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:surveys, [:public_id]))

    create table(:survey_topics) do
      add(:survey_id, references(:surveys, on_delete: :delete_all), null: false)
      add(:project_id, references(:projects, on_delete: :nilify_all))
      add(:topic_id, :string, null: false)
      add(:ignored, :boolean, null: false, default: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:survey_topics, [:survey_id, :topic_id]))

    create table(:timeline_entries) do
      add(:project_id, references(:projects, on_delete: :delete_all), null: false)
      add(:kind, :string, null: false)
      add(:text, :text, null: false)
      add(:on, :date, null: false)
      add(:by, :string)
      add(:in_briefing, :boolean, null: false, default: true)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create(index(:timeline_entries, [:project_id]))

    create table(:opinions) do
      add(:project_id, references(:projects, on_delete: :delete_all), null: false)
      add(:survey_id, references(:surveys, on_delete: :nilify_all))
      add(:on, :date, null: false)
      add(:circle, :string, null: false)
      add(:question, :text)
      add(:statement, :text)
      add(:tally, {:array, :integer})
      add(:arguments, {:array, :map})

      timestamps(type: :utc_datetime)
    end

    create(index(:opinions, [:project_id]))

    create table(:facts) do
      add(:project_id, references(:projects, on_delete: :delete_all), null: false)
      add(:statement, :text, null: false)
      add(:citation, :string, null: false)
      add(:url, :string)
      add(:fetched_on, :date, null: false)
      add(:verified, :boolean, null: false, default: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:facts, [:project_id]))

    create table(:variants) do
      add(:project_id, references(:projects, on_delete: :delete_all), null: false)
      add(:label, :string, null: false)
      add(:title, :string, null: false)
      add(:description, :text)
      add(:status, :string, null: false, default: "open")
      add(:reason, :text)
      add(:prerequisites, {:array, :map})

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:variants, [:project_id, :label]))

    create table(:motions) do
      add(:project_id, references(:projects, on_delete: :delete_all), null: false)
      add(:kind, :string, null: false)
      add(:title, :string, null: false)
      add(:status, :string, null: false, default: "draft")
      add(:motion_text, :text)
      add(:addressee, :string)
      add(:document_ref, :string)
      add(:ris, :string)
      add(:submitted_on, :date)
      add(:outcome, :string)
      add(:report_due_on, :date)

      timestamps(type: :utc_datetime)
    end

    create(index(:motions, [:project_id]))

    create table(:cross_references) do
      add(:project_id, references(:projects, on_delete: :delete_all), null: false)
      add(:kind, :string, null: false)
      add(:target, :string, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:cross_references, [:project_id]))
  end
end
