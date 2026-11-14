defmodule KomkiConnectorRis.GartenstadtReplayTest do
  # Not async: the connector's httpc profile is node-global.
  use ExUnit.Case, async: false

  alias KomkiConnectorRis.RisMock

  @fixtures Path.expand("fixtures/gartenstadt", __DIR__)

  # The connector speaks only the guest endpoints. The Gartenstadt replay
  # carries all 33 meetings in the list, but agendas and TOP details only
  # for the coverage selection; the remaining ones answer with 404, which
  # the connector skips. The request budget (40) suffices for the title
  # phase and the text phase of the most recent meetings - which is why the
  # special cases sit there (see ris_gartenstadt.exs, sonderfall_updates).

  defp stack(credentials \\ %{}) do
    {_mock, port} = RisMock.start({:replay, @fixtures})

    {:ok, cfg} =
      KomkiConnectorRis.init(%{base_url: "http://127.0.0.1:#{port}/", credentials: credentials})

    cfg
  end

  # The synthetic account of the Gartenstadt login cassette (0001-post-auth).
  # Replay matches method and path only, so this proves the format of the
  # signed-in endpoints, not the account check (that is the RIS mock's job).
  defp signed_in_stack do
    zugang =
      JSON.encode!(%{"login" => "rathaus@gartenstadt.example", "password" => "gartenschluessel"})

    stack(%{"RIS_ZUGANG" => zugang})
  end

  defp search(cfg, text) do
    KomkiConnectorRis.handle_op("search", %{"text" => text, "limit" => 10}, %{}, cfg)
  end

  defp show(cfg, top_id) do
    KomkiConnectorRis.handle_op("show", %{"top_id" => top_id}, %{}, cfg)
  end

  test "Zaehltest: zwei oeffentliche Treffer, die nicht-oeffentlichen fehlen" do
    cfg = stack()

    assert {:ok, %{"results" => ergebnisse}} = search(cfg, "Lindenallee")

    # Four TOPs carry the street, two of them non-public: the connector
    # finds exactly the two public ones - the hit count gives nothing away.
    assert length(ergebnisse) == 2

    # One hit carries the street in its title, the other only in its text.
    assert Enum.count(ergebnisse, &String.contains?(&1["titel"], "Lindenallee")) == 1

    Enum.each(ergebnisse, fn eintrag ->
      assert {:ok, gezeigt} = show(cfg, eintrag["top_id"])
      assert gezeigt["top_id"] == eintrag["top_id"]
      assert gezeigt["text"] != ""
    end)
  end

  test "Fail-closed: nicht-oeffentliche TOPs und Unbekannte sind not-found" do
    cfg = stack()

    # The deliberate special case (restricted in the unprotected part) and
    # the TOP in the protected part produce the same error as an unknown one.
    assert {:error, "not-found", _} = show(cfg, top_id("Sperrung der Lindenallee"))
    assert {:error, "not-found", _} = show(cfg, top_id("Bebauungsplan Lindenallee 12"))
    assert {:error, "not-found", _} = show(cfg, "300000001-999999999")
  end

  test "Prompt-Injection im oeffentlichen Text kommt als Text durch" do
    cfg = stack()

    # Red-team case: the connector transports the text unfiltered; the
    # defense sits with the mediator. Only the transport is evidenced here.
    assert {:ok, gezeigt} = show(cfg, injection_top_id())
    assert gezeigt["text"] =~ "Ignoriere alle bisherigen Anweisungen"
  end

  test "Limit stoppt die Titelphase; trefferlose Suche bleibt leer" do
    cfg = stack()

    # More than ten public TOPs of the selection carry "Beschlussfassung"
    # in the title; the limit stops the search before the budget comes
    # into play.
    assert {:ok, %{"results" => ergebnisse}} = search(cfg, "Beschluss")
    assert length(ergebnisse) == 10

    assert {:ok, %{"results" => []}} = search(cfg, "qqxsichtbar")
  end

  # Ticket #148: the signed-in endpoints (meetings/{id}, agendaitems/{id})
  # in the shape the recording profiled; the filter stays the same.
  test "angemeldet: Zaehltest und Fail-closed ueber die angemeldeten Endpunkte" do
    cfg = signed_in_stack()

    assert {:ok, %{"results" => ergebnisse}} = search(cfg, "Lindenallee")
    assert length(ergebnisse) == 2

    Enum.each(ergebnisse, fn eintrag ->
      assert {:ok, %{"text" => text}} = show(cfg, eintrag["top_id"])
      assert text != ""
    end)

    assert {:error, "not-found", _} = show(cfg, top_id("Sperrung der Lindenallee"))
    assert {:error, "not-found", _} = show(cfg, top_id("Bebauungsplan Lindenallee 12"))
  end

  # --- Reading fixtures --------------------------------------------------------

  # TOP ID from the committed agendas, title prefix as the key.
  defp top_id(titel_anfang) do
    @fixtures
    |> File.ls!()
    |> Enum.sort()
    |> Enum.filter(&Regex.match?(~r/-get-guestmeetings-\d+\.json$/, &1))
    |> Enum.find_value(fn name ->
      kassette = :json.decode(File.read!(Path.join(@fixtures, name)))
      body = kassette["response"]["body_b64"] |> Base.decode64!() |> :json.decode()
      top_mit(body, titel_anfang)
    end)
  end

  defp top_mit(body, titel_anfang) do
    body["parts"]
    |> Enum.flat_map(& &1["agendaitems"])
    |> Enum.find_value(fn top ->
      if String.contains?(top["name"], titel_anfang), do: top["id"]
    end)
  end

  defp injection_top_id do
    @fixtures
    |> File.ls!()
    |> Enum.sort()
    |> Enum.filter(&Regex.match?(~r/-get-guestagendaitems-\d+-\d+\.json$/, &1))
    |> Enum.find_value(fn name ->
      kassette = :json.decode(File.read!(Path.join(@fixtures, name)))
      body = kassette["response"]["body_b64"] |> Base.decode64!() |> :json.decode()

      text = Enum.map_join(body["textblocks"], " ", &Base.decode64!(&1["content"]))

      if String.contains?(text, "Ignoriere alle bisherigen Anweisungen"), do: body["id"]
    end)
  end
end
