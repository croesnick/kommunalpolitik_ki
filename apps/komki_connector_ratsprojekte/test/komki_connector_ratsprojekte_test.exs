defmodule KomkiConnectorRatsprojekteTest do
  # Ticket #419, Szene 12: stand_lesen reads exactly the stand file. The hub
  # sees no request: these tests run without any hub socket.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  defp state(stand), do: %{hub_socket: nil, hub_token: nil, stand: stand}

  test "liest die Stand-Datei unverändert, ohne Hub", %{tmp_dir: dir} do
    path = Path.join(dir, "stand.json")
    File.write!(path, ~s({"projekte": [{"titel": "Radweg Bahnhofstraße"}]}))

    assert {:ok, %{"stand" => content}} =
             KomkiConnectorRatsprojekte.handle_op("stand_lesen", %{}, %{}, state(path))

    assert content == File.read!(path)
  end

  test "noch kein Stand ausgegeben: not-found", %{tmp_dir: dir} do
    assert {:error, "not-found", _} =
             KomkiConnectorRatsprojekte.handle_op(
               "stand_lesen",
               %{},
               %{},
               state(Path.join(dir, "fehlt.json"))
             )
  end

  test "ein Symlink statt der Datei wird nicht gelesen", %{tmp_dir: dir} do
    target = Path.join(dir, "anderes.json")
    File.write!(target, "{}")
    link = Path.join(dir, "stand.json")
    File.ln_s!(target, link)

    assert {:error, "forbidden-path", _} =
             KomkiConnectorRatsprojekte.handle_op("stand_lesen", %{}, %{}, state(link))
  end

  test "zu groß oder kein UTF-8: abgewiesen", %{tmp_dir: dir} do
    big = Path.join(dir, "gross.json")
    File.write!(big, :binary.copy("a", 1_048_577))

    assert {:error, "too-large", _} =
             KomkiConnectorRatsprojekte.handle_op("stand_lesen", %{}, %{}, state(big))

    binary = Path.join(dir, "binaer.json")
    File.write!(binary, <<0xFF, 0xFE>>)

    assert {:error, "invalid-content", _} =
             KomkiConnectorRatsprojekte.handle_op("stand_lesen", %{}, %{}, state(binary))
  end

  test "init: Stand allein reicht, ohne Hub-Token" do
    assert {:ok, %{stand: "/x/stand.json", hub_socket: nil}} =
             KomkiConnectorRatsprojekte.init(%{stand: "/x/stand.json", credentials: %{}})
  end

  test "init: ohne Hub-Socket und ohne Stand startet nichts" do
    assert {:error, _} = KomkiConnectorRatsprojekte.init(%{credentials: %{}})
  end

  test "init: Hub-Socket verlangt das Hub-Token" do
    assert {:error, "KOMKI_HUB_TOKEN" <> _} =
             KomkiConnectorRatsprojekte.init(%{hub_socket: "/x/hub.sock", credentials: %{}})
  end

  test "ohne Stand-Datei: stand_lesen ist nicht eingerichtet" do
    assert {:error, "not-configured", _} =
             KomkiConnectorRatsprojekte.handle_op("stand_lesen", %{}, %{}, state(nil))
  end
end
