defmodule Ratsinfo.GartenstadtReplayTest do
  # Nicht async: RIS_BASE_URL ist knotenweit, MockRis bindet einen Port.
  use ExUnit.Case, async: false

  # Der RIS-Mock ist ein eigenstaendiges Nur-OTP-Skript der Connector-App.
  # Im Monorepo liegt es nebenan und wird hier per require_file geladen, ohne
  # eine mix-Abhaengigkeit: ratsinfo spricht HTTP gegen denselben Loopback
  # und kennt keine Interna der Connector-App (Unix-Prinzip).
  @mock Path.expand("../../../komki_connector_ris/priv/mock_ris.exs", __DIR__)
  @fixtures Path.expand("../../../komki_connector_ris/test/fixtures/gartenstadt", __DIR__)

  Code.require_file(@mock, __DIR__)

  alias Ratsinfo.ApiClient

  test "Gartenstadt-Replay: Login, Sitzungen, Suche, Details und Download" do
    {:ok, mock, port} = KomkiConnectorRis.MockRis.start(mode: {:replay, @fixtures})
    on_exit(fn -> KomkiConnectorRis.MockRis.stop(mock) end)

    System.put_env("RIS_BASE_URL", "http://127.0.0.1:#{port}/")
    on_exit(fn -> System.delete_env("RIS_BASE_URL") end)

    token = "gartenstadt-synthese-token"

    # Login liefert das synthetische Token aus der Kassette.
    assert {:ok, ^token} = ApiClient.login("gartenstadt", "synthetisch")

    # Gast-Liste: alle 33 Sitzungen des Strukturprofils.
    assert {:ok, sitzungen} = ApiClient.list_sitzungen()
    assert length(sitzungen) == 33

    # Gremienliste: neun Eintraege wie im echten Format.
    assert {:ok, gremien} = ApiClient.list_gremien(token)
    assert length(gremien) == 9

    # TOP-Details im authentifizierten Format; Kassetten gibt es nur fuer die
    # Auswahl nach Abdeckung, die TOP-ID kommt deshalb aus dem Fixture-Satz.
    [sitzung_id, top_id] =
      @fixtures
      |> File.ls!()
      |> Enum.sort()
      |> Enum.find_value(
        &Regex.run(~r/^\d+-get-agendaitems-(\d+)-(\d+)\.json$/, &1, capture: :all_but_first)
      )

    assert {:ok, top} = ApiClient.get_top(String.to_integer(sitzung_id), top_id, token)
    assert is_binary(top["name"]) and is_list(top["textblocks"])

    # Volltextsuche: Alle vier Lindenallee-TOPs, mit restricted-Flags — als
    # Angemeldete sieht ratsinfo mehr als der Connector (zwei Treffer).
    assert {:ok, volltext} = ApiClient.fulltext_search("Lindenallee", token: token)
    assert length(volltext["agendaitems"]) == 4
    assert Enum.count(volltext["agendaitems"], & &1["restricted"]) == 2

    assert {:ok, breit} = ApiClient.fulltext_search("Beschluss", token: token)
    assert length(breit["agendaitems"]) == 98

    assert {:ok, leer} = ApiClient.fulltext_search("qqxsichtbar", token: token)
    assert leer["agendaitems"] == []

    # Download: octet-stream (wie das echte RIS, Fund 2026-11-05), PDF-Body.
    [erste | _] =
      @fixtures
      |> File.ls!()
      |> Enum.filter(&String.contains?(&1, "-get-agendaitems-documents-"))
      |> Enum.sort()

    doc_id =
      erste
      |> String.replace_suffix(".json", "")
      |> String.replace(~r/^\d+-get-agendaitems-documents-/, "")

    assert {:ok, pdf} = ApiClient.download_dokument(doc_id, token)
    assert String.starts_with?(pdf, "%PDF-")
  end
end
