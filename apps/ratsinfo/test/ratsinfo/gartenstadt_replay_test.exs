defmodule Ratsinfo.GartenstadtReplayTest do
  # Not async: RIS_BASE_URL is node-global, and MockRis binds a port.
  use ExUnit.Case, async: false

  # The RIS mock is a standalone OTP-only script of the connector app.
  # In the monorepo it lives next door and is loaded here via require_file,
  # without a mix dependency: ratsinfo speaks plain HTTP to the same
  # loopback and knows no internals of the connector app (Unix principle).
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

    # Login returns the synthetic token from the cassette.
    assert {:ok, ^token} = ApiClient.login("gartenstadt", "synthetisch")

    # Guest list: all 33 meetings of the structure profile.
    assert {:ok, sitzungen} = ApiClient.list_sitzungen()
    assert length(sitzungen) == 33

    # Committee list: nine entries as in the real format.
    assert {:ok, gremien} = ApiClient.list_gremien(token)
    assert length(gremien) == 9

    # TOP details in the authenticated format; cassettes exist only for the
    # coverage selection, so the TOP ID comes from the fixture set.
    [sitzung_id, top_id] =
      @fixtures
      |> File.ls!()
      |> Enum.sort()
      |> Enum.find_value(
        &Regex.run(~r/^\d+-get-agendaitems-(\d+)-(\d+)\.json$/, &1, capture: :all_but_first)
      )

    assert {:ok, top} = ApiClient.get_top(String.to_integer(sitzung_id), top_id, token)
    assert is_binary(top["name"]) and is_list(top["textblocks"])

    # Full-text search: all four Lindenallee TOPs, with restricted flags -
    # logged in, ratsinfo sees more than the connector (two hits).
    assert {:ok, volltext} = ApiClient.fulltext_search("Lindenallee", token: token)
    assert length(volltext["agendaitems"]) == 4
    assert Enum.count(volltext["agendaitems"], & &1["restricted"]) == 2

    assert {:ok, breit} = ApiClient.fulltext_search("Beschluss", token: token)
    assert length(breit["agendaitems"]) == 98

    assert {:ok, leer} = ApiClient.fulltext_search("qqxsichtbar", token: token)
    assert leer["agendaitems"] == []

    # Download: octet-stream (like the real RIS, finding 2026-11-05), PDF body.
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
