defmodule KomkiMediator.ResultShapeTest do
  use ExUnit.Case, async: true

  alias KomkiMediator.ResultShape

  test "gueltige Formen nach Connector-Vertrag §5.2" do
    hit = %{"title" => "T", "url" => "https://x.example", "snippet" => "s"}
    assert :ok = ResultShape.check("web", "search", %{"results" => [hit], "abrufdatum" => "d"})
    assert :ok = ResultShape.check("vault", "search", %{"results" => []})

    assert :ok =
             ResultShape.check("vault", "write_test", %{"note_id" => "n", "labels" => ["a@1"]})
  end

  test "Treffer mit fehlendem oder zusaetzlichem Feld ist ein Verstoss" do
    assert {:error, _} =
             ResultShape.check("web", "search", %{
               "results" => [%{"title" => "T", "url" => "u"}],
               "abrufdatum" => "d"
             })

    assert {:error, _} =
             ResultShape.check("vault", "search", %{
               "results" => [
                 %{"note_id" => "n", "title" => "T", "labels" => [], "content" => "c"}
               ]
             })
  end

  test "falsche Typen und fehlende Trefferliste sind Verstoesse" do
    assert {:error, _} =
             ResultShape.check("vault", "write_test", %{"note_id" => "n", "labels" => "a@1"})

    assert {:error, _} = ResultShape.check("ris", "search", %{"abrufdatum" => "d"})
    assert {:error, _} = ResultShape.check("ris", "unbekannt", %{})
  end
end
