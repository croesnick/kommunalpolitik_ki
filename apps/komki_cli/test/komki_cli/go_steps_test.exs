defmodule KomkiCli.GoStepsTest do
  # Ticket #98: komki go zeigt die Anfrage und schreibt nur auf ein
  # ausdrueckliches Ja eine Freigabe.
  use ExUnit.Case, async: true

  alias KomkiCli.GoSteps
  alias KomkiMediator.Go

  setup do
    base = Path.join(System.tmp_dir!(), "komki-go-#{System.unique_integer([:positive])}")
    dir = Path.join([base, "mediator", "go"])
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(base) end)

    request = %{
      "schema" => "komki-go-request/1",
      "call_hash" => String.duplicate("a", 64),
      "decision_id" => "pdr-1",
      "operation" => "emit",
      "tool" => "web_search",
      "params" => %{"query" => "Radweg Buchloe", "count" => 5},
      "blockers" => ["recipient_not_allowed"],
      "object" => "out-abc@v1",
      "workspace" => "ws-test",
      "content_digest" => String.duplicate("b", 64),
      "scope" => "go-ws-test",
      "authority" => "nutzende-person",
      "expires_at" => System.os_time(:second) + 60
    }

    Go.write_atomic(Path.join(dir, request["call_hash"] <> ".request.json"), request)
    %{base: base, dir: dir, request: request}
  end

  defp ui(answer) do
    test = self()
    %{say: &send(test, {:said, &1}), confirm: fn _question, false -> answer end}
  end

  defp answer_file(dir, request), do: Path.join(dir, request["call_hash"] <> ".answer.json")

  test "Ja: Vorschau gezeigt, Freigabe fuer genau diesen Call", %{base: base, dir: dir} = ctx do
    assert {"1 von 1 Anfragen freigegeben\n", 0} = GoSteps.run(base, ui(true))

    assert_received {:said, preview}
    assert preview =~ "web_search"
    assert preview =~ ~s(query: "Radweg Buchloe")
    assert preview =~ "recipient_not_allowed"

    {:ok, release} = KomkiPolicy.JSON.parse(File.read!(answer_file(dir, ctx.request)))
    assert {:ok, _} = KomkiPolicy.Release.validate(release)
    assert release["call_hash"] == ctx.request["call_hash"]
    assert release["valid_until"] - release["valid_from"] == 300
  end

  test "Nein (Default): keine Freigabe", %{base: base, dir: dir} = ctx do
    assert {"0 von 1 Anfragen freigegeben\n", 0} = GoSteps.run(base, ui(false))

    assert {:ok, %{"go" => false}} =
             KomkiPolicy.JSON.parse(File.read!(answer_file(dir, ctx.request)))
  end

  # Ticket #217: Auch ein harmlos aussehender Aufruf verrät den Empfängern,
  # dass und wann aus dem Raum gefragt wird.
  test "Vorschau nennt Empfaenger und warnt vor dem Existenz-Leck", %{base: base} do
    File.write!(
      Path.join([base, "mediator", "registry.json"]),
      JSON.encode!(KomkiMediator.Templates.registry())
    )

    GoSteps.run(base, ui(false))
    assert_received {:said, preview}

    assert preview =~ "Sichtbar für: Brave (Websuche)"
    assert preview =~ "Schon der Aufruf selbst zeigt Brave (Websuche), dass und wann"
    assert preview =~ "auch wenn die Parameter harmlos aussehen"
    assert preview =~ ~r/aussehen\.\n  Ein GO gilt nur/
  end

  test "Empfaenger je Tool aus Γ; lokale Werkzeuge und fehlendes Γ ohne Warnung" do
    envs = KomkiMediator.Templates.registry()["environments"]

    assert GoSteps.recipients("web_search", envs) == ["brave-search"]
    assert GoSteps.recipients("ris_search", envs) == ["ris-betreiber"]
    assert GoSteps.recipients("vault_read", envs) == []
    assert GoSteps.recipients("web_search", %{}) == []

    refute GoSteps.describe(%{
             "decision_id" => "d",
             "tool" => "x",
             "params" => %{},
             "blockers" => []
           }) =~
             "Sichtbar"
  end

  test "keine Anfragen" do
    assert {"keine offenen GO-Anfragen\n", 0} = GoSteps.run("/nonexistent", ui(true))
  end

  test "store (#205): die Vorschau sagt, dass gespeichert wird", %{request: request} do
    store = Map.merge(request, %{"operation" => "store", "tool" => "vault_write_test"})

    assert GoSteps.describe(store) =~ "Aktion:    speichern — jedes Schreiben braucht dein GO"
    refute GoSteps.describe(request) =~ "Aktion:"
    assert Go.release_for(store, 1)["operation"] == "store"
  end
end
