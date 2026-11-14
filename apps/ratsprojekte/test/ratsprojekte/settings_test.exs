defmodule Ratsprojekte.SettingsTest do
  use Ratsprojekte.DataCase, async: false

  alias Ratsprojekte.Settings

  test "the editor's name is stored without invisible characters and can be removed" do
    assert Settings.editor_name() == nil

    assert {:ok, "Miriam Haas"} = Settings.set_editor_name(%{"name" => " Miriam​ Haas "})
    assert Settings.editor_name() == "Miriam Haas"

    assert {:ok, "Selin"} = Settings.set_editor_name(%{"name" => "Selin"})
    assert Settings.editor_name() == "Selin"

    assert {:ok, nil} = Settings.set_editor_name(%{"name" => ""})
    assert Settings.editor_name() == nil
  end

  test "a name longer than 80 characters is refused" do
    assert {:error, changeset} = Settings.set_editor_name(%{"name" => String.duplicate("a", 81)})
    assert %{name: [_]} = errors_on(changeset)
  end
end
