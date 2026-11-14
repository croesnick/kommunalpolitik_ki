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

  # #516: sessions as a hit list, agenda as an object with a list of items.
  test "ris sessions und agenda haben geschlossene Formen" do
    session = %{
      "sitzung_id" => "1",
      "sitzung" => "S",
      "gremium" => "G",
      "datum" => "2026-06-02",
      "uhrzeit" => "18:00",
      "url" => "u"
    }

    assert :ok =
             ResultShape.check("ris", "sessions", %{"results" => [session], "abrufdatum" => "d"})

    assert {:error, _} =
             ResultShape.check("ris", "sessions", %{
               "results" => [Map.put(session, "nicht_oeffentlich", "3")],
               "abrufdatum" => "d"
             })

    agenda =
      session
      |> Map.put("abrufdatum", "d")
      |> Map.put("tops", [%{"top_id" => "1-1", "nummer" => "1", "titel" => "T"}])

    assert :ok = ResultShape.check("ris", "agenda", agenda)
    assert :ok = ResultShape.check("ris", "agenda", %{agenda | "tops" => []})

    # No hidden count, no extra item field, no missing list.
    assert {:error, _} = ResultShape.check("ris", "agenda", Map.put(agenda, "verborgen", "2"))

    assert {:error, _} =
             ResultShape.check("ris", "agenda", %{
               agenda
               | "tops" => [%{"top_id" => "1-1", "nummer" => "1", "titel" => "T", "text" => "x"}]
             })

    assert {:error, _} = ResultShape.check("ris", "agenda", Map.delete(agenda, "tops"))
  end
end
