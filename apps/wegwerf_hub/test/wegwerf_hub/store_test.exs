defmodule WegwerfHub.StoreTest do
  # #419: Der Stand entsteht aus einer Liste erlaubter Felder.
  use ExUnit.Case, async: true

  alias KomkiPolicy.JSON
  alias WegwerfHub.Store

  @moduletag :tmp_dir

  defp vorschlag(dir, titel) do
    {:ok, id} =
      Store.annehmen(dir, %{
        "titel" => titel,
        "projekt_hinweis" => "radweg",
        "labels" => ["web-oeffentlich@1"],
        "teile" => [%{"aussage" => "Aussage zu " <> titel, "quelle" => "antwort-1"}]
      })

    id
  end

  defp stand(dir) do
    {:ok, path} = Store.stand_ausgeben(dir)
    {:ok, stand} = JSON.parse(File.read!(path))
    stand
  end

  test "nur angenommene Vorschläge, nur erlaubte Felder", %{tmp_dir: dir} do
    angenommen = vorschlag(dir, "Zählung")
    _offen = vorschlag(dir, "Offener Vorschlag")
    :ok = Store.entscheiden(dir, angenommen, [1])

    assert %{"vorschlaege" => [eintrag]} = stand(dir)
    assert eintrag["titel"] == "Zählung"
    assert Map.keys(eintrag) == ["teile", "titel"]

    assert eintrag["teile"] == [
             %{
               "aussage" => "Aussage zu Zählung",
               "fundstelle" => nil,
               "pruefstatus" => "nicht-verifiziert",
               "quelle" => "antwort-1"
             }
           ]
  end

  # Gegenprobe 12.7: ein neues Feld im Bestand bleibt unsichtbar.
  test "ein neues Feld im Bestand erscheint nicht im Stand", %{tmp_dir: dir} do
    id = vorschlag(dir, "Zählung")
    :ok = Store.entscheiden(dir, id, [1])
    vorher = Map.delete(stand(dir), "ausgegeben")

    path = Path.join(dir, "vorschlaege.json")
    {:ok, bestand} = JSON.parse(File.read!(path))
    bestand = put_in(bestand, [id, "privat"], "Notiz nur für die Redaktion")
    File.write!(path, JSON.canonical(bestand))

    assert Map.delete(stand(dir), "ausgegeben") == vorher
  end
end
