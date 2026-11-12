defmodule Ratsprojekte.Settings do
  @moduledoc """
  Settings of the hub, kept in its encrypted database. So far only the
  name of the person who runs the hub: the work view says „Du“, but the
  briefing is read by others and names the person (#407, #438).
  """

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Ratsprojekte.{Repo, Text}
  alias Ratsprojekte.Settings.Setting

  @editor_name "editor_name"

  @doc "The editor's name, or nil while none is entered."
  @spec editor_name() :: String.t() | nil
  def editor_name do
    case Repo.get(Setting, @editor_name) do
      nil -> nil
      setting -> setting.value
    end
  end

  @doc "Changeset for the form of the editor's name."
  @spec change_editor_name(map()) :: Ecto.Changeset.t()
  def change_editor_name(attrs \\ %{}) do
    {%{}, %{name: :string}}
    |> cast(attrs, [:name])
    |> Text.clean_fields([:name])
    |> validate_length(:name, max: 80)
  end

  @doc "Stores the editor's name; an empty name removes it."
  @spec set_editor_name(map()) :: {:ok, String.t() | nil} | {:error, Ecto.Changeset.t()}
  def set_editor_name(attrs) do
    with {:ok, %{} = input} <- apply_action(change_editor_name(attrs), :update) do
      case input[:name] do
        name when name in [nil, ""] ->
          Repo.delete_all(from(s in Setting, where: s.key == @editor_name))
          {:ok, nil}

        name ->
          Repo.insert!(%Setting{key: @editor_name, value: name},
            on_conflict: {:replace, [:value, :updated_at]},
            conflict_target: :key
          )

          {:ok, name}
      end
    end
  end
end
