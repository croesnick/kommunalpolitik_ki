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

  test "keine Anfragen" do
    assert {"keine offenen GO-Anfragen\n", 0} = GoSteps.run("/nonexistent", ui(true))
  end
end
