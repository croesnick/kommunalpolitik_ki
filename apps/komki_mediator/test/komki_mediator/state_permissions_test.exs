defmodule KomkiMediator.StatePermissionsTest do
  # Ticket #485 (Fund F13): die Zustandsverzeichnisse des Vermittlers
  # (go/, journal/) entstehen wie ihre Schwestern run/ und documents/
  # mit 0700, die Dateien darin mit 0600 — GO-Anfragen tragen den vollen
  # Text abgelehnter Ausgaben, das Journal die ganze Auditkette.
  use ExUnit.Case, async: false

  alias KomkiMediator.{Go, GoStand, Journal, Templates, TestHelpers}

  setup do
    base = TestHelpers.tmp_base("state-perms-")
    TestHelpers.stop_named(GoStand)
    TestHelpers.stop_named(Journal)
    on_exit(fn -> TestHelpers.stop_named(GoStand) end)
    on_exit(fn -> TestHelpers.stop_named(Journal) end)
    %{base: base}
  end

  describe "GO-Verzeichnis und GO-Dateien" do
    test "await legt go/ mit 0700 an, write_atomic schreibt 0600 (#485)", %{base: base} do
      go_dir = Path.join([base, "mediator", "go"])
      request = Path.join(go_dir, "ab.request.json")

      assert :timeout = Go.await(%{dir: go_dir, timeout_ms: 1}, %{"call_hash" => "ab"})
      assert mode(go_dir) == 0o700
      refute File.exists?(request)

      :ok = Go.write_atomic(request, %{"call_hash" => "ab"})
      assert mode(request) == 0o600

      :ok =
        Go.answer(
          go_dir,
          %{"call_hash" => "ab", "operation" => "emit", "authority" => "nutzende-person"},
          true
        )

      assert mode(Path.join(go_dir, "ab.answer.json")) == 0o600
    end
  end

  describe "Offenlegungsstand (stand.json)" do
    test "GoStand legt go/ mit 0700 an, stand.json entsteht mit 0600 (#485)", %{base: base} do
      go_dir = Path.join([base, "mediator", "go"])
      start_supervised!({GoStand, %{dir: go_dir, scope: "go-perms-test"}})

      assert mode(go_dir) == 0o700

      proposal = %{
        "release_id" => "go-perms-test",
        "nonce" => "n-" <> String.duplicate("a", 16),
        "stand_ref" => "go-stand@0",
        "stand_version_after" => 1,
        "call_hash" => String.duplicate("c", 64)
      }

      assert {:ok, _} = GoStand.advance(proposal)
      assert mode(GoStand.path(go_dir)) == 0o600
    end
  end

  describe "PDR-Journal" do
    test "Journal legt journal/ mit 0700 an, pdr.jsonl entsteht mit 0600 (#485)", %{base: base} do
      path = Path.join([base, "mediator", "journal", "pdr.jsonl"])

      {:ok, _} = Journal.start_link(path)

      assert mode(Path.dirname(path)) == 0o700
      assert mode(path) == 0o600

      :ok = Journal.append(KomkiMediator.Journal, %{"schema" => "komki-pdr/2", "tool" => "ping"})
      assert mode(path) == 0o600
    end
  end

  describe "Vorlagen des Vermittlers" do
    test "registry.json und room.json entstehen mit 0600 (#485)", %{base: base} do
      assert Templates.provision!(base) == :ok

      mediator = Path.join(base, "mediator")
      assert mode(mediator) == 0o700
      assert mode(Path.join(mediator, "registry.json")) == 0o600
      assert mode(Path.join(mediator, "room.json")) == 0o600
      # Dokumente haerten bereits seit #498.
      assert mode(Path.join([mediator, "documents", "doc-oeffentlich.md"])) == 0o600
    end
  end

  defp mode(path) do
    {:ok, stat} = File.stat(path)
    Bitwise.band(stat.mode, 0o777)
  end
end
