defmodule KomkiCli.RaumbildTest do
  use ExUnit.Case, async: true

  alias KomkiCli.Raumbild
  alias KomkiMediator.Templates

  # Γ-Export und Raum aus den Vorlagen: dieselben Daten, die komki up
  # schreibt und der Vermittler liest.
  defp registry, do: JSON.decode!(JSON.encode!(Templates.registry()))
  defp room(bindings), do: Map.put(Templates.room(), "workspace_bindings", bindings)
  defp names(id), do: "Bezeichnung " <> id

  test "Raum recherche: Name, Zweck, Labels, nach draußen offen" do
    bild = Raumbild.build(room(Templates.recherche_bindings()), registry(), &names/1)

    assert bild["schema"] == "komki-raum/1"
    assert bild["raum"] == "recherche"
    assert bild["zweck"] == "offene-recherche"
    assert Enum.map(bild["labels"], & &1["id"]) == Enum.sort(Templates.recherche_bindings())
    assert Enum.all?(bild["labels"], &(&1["intern"] == false))
    assert hd(bild["labels"])["bezeichnung"] == "Bezeichnung doc-oeffentlich@2"

    assert bild["nach_draussen"] == [
             %{"empfaenger" => "brave-search", "offen" => true},
             %{"empfaenger" => "ris-betreiber", "offen" => true}
           ]
  end

  test "Raum vertraulich: das vertrauliche Label schließt jeden Weg nach draußen" do
    bild = Raumbild.build(room(Templates.vertraulich_bindings()), registry(), &names/1)

    assert bild["raum"] == "vertraulich"
    assert %{"intern" => true} = Enum.find(bild["labels"], &(&1["id"] == "vault-vertraulich@1"))
    assert Enum.all?(bild["nach_draussen"], &(&1["offen"] == false))
  end

  test "eigener Raum ohne Namen; ohne B_W ist nichts offen" do
    assert Raumbild.build(room(["ris-oeffentlich@1"]), registry(), &names/1)["raum"] == nil

    leer =
      Raumbild.build(Map.delete(Templates.room(), "workspace_bindings"), registry(), &names/1)

    assert leer["labels"] == []
    assert Enum.all?(leer["nach_draussen"], &(&1["offen"] == false))
  end

  test "fehlende Dateien: leeres Raumbild statt Absturz" do
    bild = Raumbild.build(nil, nil, fn _ -> nil end)

    assert bild == %{
             "schema" => "komki-raum/1",
             "raum" => nil,
             "zweck" => nil,
             "labels" => [],
             "nach_draussen" => []
           }

    assert Raumbild.encode(bild) =~ ~r/\A\{.*\}\n\z/
  end
end
